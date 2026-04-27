import 'dart:convert';
import 'dart:async';
import '../routes/app_routes.dart';
import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../services/auth_service.dart';
import 'student_profile_view.dart';
import 'trainer_workout_organizer_view.dart';
import 'trainer_chat_view.dart';
import 'diet_control_view.dart';
import '../widgets/fitmatch_logo.dart';

// ─── Estado dos horários ──────────────────────────────────────────────────────
// O personal GERENCIA os próprios horários.
// available  → disponível para alunos solicitarem
// unavailable → bloqueado pelo próprio personal
// requested  → aluno fez uma solicitação (aguardando confirmação do personal)

enum _SlotState { available, requested, unavailable }

class _Slot {
  final String time;
  _SlotState state;
  String? studentName;
  _Slot(this.time) : state = _SlotState.available;
}

// ─── Dashboard do Personal Trainer ───────────────────────────────────────────

class TrainerDashboardView extends StatefulWidget {
  final String name;
  final String? cref;
  final String? cidade;
  final String? especialidade;
  final String? valorHora;
  final String? bio;
  final int? trainerId;
  final String? horasPorSessao;

  const TrainerDashboardView({
    super.key,
    required this.name,
    this.cref,
    this.cidade,
    this.especialidade,
    this.valorHora,
    this.bio,
    this.trainerId,
    this.horasPorSessao,
  });

  @override
  State<TrainerDashboardView> createState() => _TrainerDashboardViewState();
}

class _TrainerDashboardViewState extends State<TrainerDashboardView> {
  int _selectedDay = 0;
  int _agendaWeekOffset = 0;
  bool _initialAgendaPositioned = false;
  bool _applyingBlockRange = false;
  bool _applyingCloneDay = false;
  bool _clearingDayBlocks = false;
  final ScrollController _pageScrollController = ScrollController();

  List<Map<String, dynamic>> _allTrainerRequests = [];
  final Set<int> _hiddenRequestIds = <int>{};
  bool _loadingRequests = false;
  late String _horasPorSessao;
  late String _editCidade;
  late String _editValorHora;

  List<Map<String, dynamic>> _myStudents = [];
  List<Map<String, dynamic>> _allStudents = [];
  Set<int> _blockedStudentIds = {};
  Map<int, String> _blockedStudentNames = {};
  String _studentSearch = '';
  bool _loadingStudents = false;
  Timer? _dashboardRefreshTimer;
  final ScrollController _studentsScrollController = ScrollController();
  List<Map<String, String>> _oneTimeManualBlocks = [];
  List<Map<String, String>> _oneTimeManualUnblocks = [];
  final Set<String> _weeklyManualBlockKeys = <String>{};

  List<Map<String, dynamic>> _ratings = [];
  bool _loadingRatings = false;
  double _avgRating = 0;

  static const List<String> _days = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
  ];
  static const List<String> _dayLabels = [
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
    'Dom',
  ];

  late final Map<String, List<_Slot>> _schedule;

  void _onGlobalRefresh() {
    if (!mounted) return;
    setState(() {
      _selectedDay = DateTime.now().weekday - 1;
      _agendaWeekOffset = 0;
      _studentSearch = '';
      _initialAgendaPositioned = false;
    });
    _loadAll();
  }

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_onGlobalRefresh);
    _horasPorSessao = widget.horasPorSessao?.trim().isNotEmpty == true
        ? widget.horasPorSessao!
        : '1h por sessão';
    _editCidade = widget.cidade ?? '';
    _editValorHora = widget.valorHora ?? '';
    final allSlots = [
      for (int h = 0; h < 24; h++) '${h.toString().padLeft(2, '0')}:00',
    ];
    _schedule = {
      for (final d in _days) d: allSlots.map((t) => _Slot(t)).toList(),
    };
    if (widget.trainerId != null) {
      _loadAll();
      _dashboardRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!mounted) return;
        _loadRequests(silent: true);
      });
    }
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_onGlobalRefresh);
    _dashboardRefreshTimer?.cancel();
    _studentsScrollController.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadMyStudents(),
      _loadBlockedStudents(),
      _loadAllStudents(),
      _loadRatings(),
    ]);
    await _loadSlots();
    await _loadRequests();
    _positionAgendaForTrainer();
  }

  DateTime? _parseIsoDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String? _resolveRequestChatLockAtIso(Map<String, dynamic> currentReq) {
    final trainerId = (currentReq['trainerId'] ?? widget.trainerId)?.toString();
    final studentId = currentReq['studentId']?.toString();
    final currentCreatedAt = _parseIsoDateTime(currentReq['createdAt']);

    if (trainerId == null || studentId == null || currentCreatedAt == null) {
      return null;
    }

    DateTime? nextNewerCreatedAt;
    for (final req in _allTrainerRequests) {
      final reqTrainerId = (req['trainerId'] ?? widget.trainerId)?.toString();
      final reqStudentId = req['studentId']?.toString();
      if (reqTrainerId != trainerId || reqStudentId != studentId) continue;

      final reqCreatedAt = _parseIsoDateTime(req['createdAt']);
      if (reqCreatedAt == null || !reqCreatedAt.isAfter(currentCreatedAt)) {
        continue;
      }

      if (nextNewerCreatedAt == null || reqCreatedAt.isBefore(nextNewerCreatedAt)) {
        nextNewerCreatedAt = reqCreatedAt;
      }
    }

    if (nextNewerCreatedAt == null) {
      // Solicitação mais recente do par: sem ciclo seguinte para limitar janela.
      return null;
    }

    // Isola pelo início da próxima solicitação mais nova do mesmo par.
    return nextNewerCreatedAt.toIso8601String();
  }

  Future<void> _loadAllStudents() async {
    try {
      final all = await AuthService.fetchStudents();
      if (!mounted) return;
      setState(() {
        _allStudents = all;
      });
    } catch (_) {
      // silently ignore
    }
  }

  Future<void> _loadRatings() async {
    if (widget.trainerId == null) return;
    setState(() => _loadingRatings = true);
    try {
      final ratings = await AuthService.getTrainerRatings(widget.trainerId!);
      if (!mounted) return;
      final avg = ratings.isEmpty
          ? 0.0
          : ratings
                    .map((r) => (r['stars'] ?? 0) as int)
                    .reduce((a, b) => a + b) /
                ratings.length;
      setState(() {
        _ratings = ratings;
        _avgRating = avg;
        _loadingRatings = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRatings = false);
    }
  }

  Future<void> _loadBlockedStudents() async {
    if (widget.trainerId == null) return;
    try {
      final blocked = await AuthService.getBlockedStudents(widget.trainerId!);
      final blockedIds = blocked
          .map((b) => int.tryParse((b['studentId'] ?? '').toString()))
          .whereType<int>()
          .toSet();

      final nameEntries = await Future.wait(
        blockedIds.map((id) async {
          try {
            final user = await AuthService.getUserById(id);
            return MapEntry(id, (user['name'] ?? 'Aluno #$id').toString());
          } catch (_) {
            return MapEntry(id, 'Aluno #$id');
          }
        }),
      );

      if (!mounted) return;
      setState(() {
        _blockedStudentIds = blockedIds;
        _blockedStudentNames = Map<int, String>.fromEntries(nameEntries);
      });
    } catch (_) {
      // silently ignore
    }
  }

  Future<void> _loadMyStudents() async {
    if (widget.trainerId == null) return;
    setState(() => _loadingStudents = true);
    try {
      final students = await AuthService.getTrainerApprovedConnections(
        widget.trainerId!,
      );
      if (!mounted) return;
      setState(() {
        _myStudents = students;
        _loadingStudents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStudents = false);
    }
  }

  Future<void> _loadRequests({bool silent = false}) async {
    if (widget.trainerId == null) return;
    final shouldShowLoader = !silent && _allTrainerRequests.isEmpty;
    if (shouldShowLoader) {
      setState(() => _loadingRequests = true);
    }
    try {
      final reqs = await AuthService.getAllTrainerRequests(widget.trainerId!);
      if (!mounted) return;
      setState(() {
        _allTrainerRequests = reqs;
        for (final daySlots in _schedule.values) {
          for (final slot in daySlots) {
            slot.studentName = null;
          }
        }
        // limpa estado de solicitados para recálculo
        for (final daySlots in _schedule.values) {
          for (final slot in daySlots) {
            if (slot.state == _SlotState.requested) {
              slot.state = _SlotState.available;
            }
          }
        }
        // Marca os slots de solicitações aprovadas com o nome do aluno
        final approvedRequests = _allTrainerRequests
            .where((r) => (r['status'] ?? '') == 'APPROVED')
            .toList();
        for (final req in approvedRequests) {
          final planType =
              (req['planType'] ?? 'DIARIO').toString().toUpperCase();
          if (planType == 'MENSAL' || planType == 'DIARIO' || planType == 'SEMANAL') {
            continue;
          }
          final studentName = (req['studentName'] ?? 'Aluno').toString().trim();
          final slots = _extractRequestSlots(req);
          for (final approvedSlot in slots) {
            final day = approvedSlot['dayName'] ?? '';
            final time = approvedSlot['time'] ?? '';
            if (day.isEmpty || time.isEmpty) continue;
            final daySlots = _schedule[day];
            if (daySlots == null) continue;
            for (final slot in daySlots) {
              if (slot.time == time) {
                slot.state = _SlotState.unavailable;
                slot.studentName = studentName.isNotEmpty ? studentName : 'Aluno';
                break;
              }
            }
          }
        }
        // Marca os slots com solicitações pendentes
        for (final req in _pendingRequests) {
          final planType =
              (req['planType'] ?? 'DIARIO').toString().toUpperCase();
          if (planType == 'MENSAL' || planType == 'DIARIO' || planType == 'SEMANAL') {
            continue;
          }
          final slots = _extractRequestSlots(req);
          for (final pendingSlot in slots) {
            final day = pendingSlot['dayName'] ?? '';
            final time = pendingSlot['time'] ?? '';
            final daySlots = _schedule[day];
            if (daySlots != null) {
              for (final slot in daySlots) {
                if (slot.time == time && slot.state != _SlotState.unavailable) {
                  slot.state = _SlotState.requested;
                }
              }
            }
          }
        }
      });
    } catch (_) {
      // silently ignore
    } finally {
      if (mounted && shouldShowLoader) setState(() => _loadingRequests = false);
    }
  }

  List<Map<String, String>> _extractRequestSlots(Map<String, dynamic> req) {
    final raw = req['daysJson']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final slots = decoded
            .whereType<Map>()
            .map(
              (s) => {
                'dayName': (s['dayName'] ?? '').toString(),
                'time': (s['time'] ?? '').toString(),
                'dateLabel': (s['dateLabel'] ?? '').toString(),
                'dateIso': (s['dateIso'] ?? '').toString(),
              },
            )
            .where((s) => s['dayName']!.isNotEmpty && s['time']!.isNotEmpty)
            .toList();
        if (slots.isNotEmpty) return slots;
      } catch (_) {}
    }
    return [
      {
        'dayName': (req['dayName'] ?? '').toString(),
        'time': (req['time'] ?? '').toString(),
        'dateLabel': '',
        'dateIso': '',
      },
    ];
  }

  void _releaseRequestSlotsFromSchedule(Map<String, dynamic> req) {
    final slots = _extractRequestSlots(req);
    for (final selected in slots) {
      final day = selected['dayName'] ?? '';
      final time = selected['time'] ?? '';
      if (day.isEmpty || time.isEmpty) continue;
      final daySlots = _schedule[day];
      if (daySlots == null) continue;
      for (final slot in daySlots) {
        if (slot.time == time && slot.state == _SlotState.requested) {
          slot.state = _SlotState.available;
          break;
        }
      }
    }
  }

  String _buildDecisionAutoMessage(
    Map<String, dynamic> req, {
    required bool approved,
  }) {
    final slots = _extractRequestSlots(req);
    final anchorIso = (req['approvedAt'] ?? req['createdAt'] ?? '').toString();
    final slotsText = slots
        .map((s) {
          final day = (s['dayName'] ?? '').toString().trim();
          final time = (s['time'] ?? '').toString().trim();
          if (day.isEmpty || time.isEmpty) return '';

          String dateLabel = (s['dateLabel'] ?? '').toString().trim();
          if (dateLabel.isEmpty) {
            final iso = (s['dateIso'] ?? '').toString().trim();
            if (iso.isNotEmpty) {
              final parsed = DateTime.tryParse(iso);
              if (parsed != null) {
                dateLabel = _formatDateLabel(parsed);
              }
            }
          }
          if (dateLabel.isEmpty) {
            dateLabel = _fallbackDateLabelForLegacySlot(
              dayName: day,
              time: time,
              anchorIso: anchorIso,
            );
          }

          return dateLabel.isEmpty
              ? '$day às $time'
              : '$day $dateLabel às $time';
        })
        .where((label) => label.isNotEmpty)
        .join(', ');

    final safeSlotsText = slotsText.isEmpty ? 'horário não informado' : slotsText;
    if (approved) {
      return '✅ Sua solicitação foi confirmada por ${widget.name}. '
          'Horário${slots.length > 1 ? 's' : ''}: $safeSlotsText. '
          'Nos vemos nos treinos!';
    }
    return '❌ Sua solicitação foi recusada por ${widget.name}. '
      'Horário: $safeSlotsText.';
  }

  Future<void> _sendDecisionAutoMessage(
    Map<String, dynamic> req, {
    required bool approved,
  }) async {
    if (widget.trainerId == null) return;
    final studentId = int.tryParse((req['studentId'] ?? '').toString());
    if (studentId == null) return;
    try {
      await AuthService.sendChatMessage(
        senderId: widget.trainerId!,
        receiverId: studentId,
        text: _buildDecisionAutoMessage(req, approved: approved),
      );
    } catch (_) {
      // Se falhar o chat automático, não bloqueia o fluxo principal.
    }
  }

  Future<void> _loadSlots() async {
    if (widget.trainerId == null) return;
    try {
      final slots = await AuthService.getTrainerSlots(widget.trainerId!);
      if (!mounted) return;
      setState(() {
        _oneTimeManualBlocks = [];
        _oneTimeManualUnblocks = [];
        _weeklyManualBlockKeys.clear();
        for (final daySlots in _schedule.values) {
          for (final slot in daySlots) {
            slot.state = _SlotState.available;
            slot.studentName = null;
          }
        }
        for (final s in slots) {
          final day = s['dayName']?.toString() ?? '';
          final time = s['time']?.toString() ?? '';
          final dateIso = (s['dateIso'] ?? '').toString().trim();
          final state = (s['state'] ?? '').toString().trim().toUpperCase();
          if (day.isEmpty || time.isEmpty) continue;

          // REQUEST (pendente/aprovado) deve ser calculado por request + data real,
          // não como bloqueio manual base.
          if (state == 'REQUEST') {
            continue;
          }

          if (dateIso.isNotEmpty) {
            final targetList = state == 'UNBLOCK_ONCE'
                ? _oneTimeManualUnblocks
                : _oneTimeManualBlocks;
            targetList.add({
              'dayName': day,
              'time': time,
              'dateIso': dateIso.length >= 10 ? dateIso.substring(0, 10) : dateIso,
            });
            continue;
          }

          // Mantem como indisponivel base apenas bloqueios manuais reais.
          final isManualState =
              state.isEmpty || state == 'MANUAL' || state == 'BLOCKED';
          if (!isManualState) {
            continue;
          }

          _weeklyManualBlockKeys.add(_weeklyManualBlockKey(day, time));

          final daySlots = _schedule[day];
          if (daySlots != null) {
            for (final slot in daySlots) {
              if (slot.time == time) {
                slot.state = _SlotState.unavailable;
                slot.studentName = null;
              }
            }
          }
        }
      });
    } catch (_) {
      // silently ignore
    }
  }

  Future<void> _showEditProfileDialog() async {
    final cidadeCtrl = TextEditingController(text: _editCidade);
    final valorHoraCtrl = TextEditingController(text: _editValorHora);
    final horasSessaoCtrl = TextEditingController(text: _horasPorSessao);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Editar Perfil',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cidadeCtrl,
              decoration: const InputDecoration(
                labelText: 'Cidade',
                prefixIcon: Icon(Icons.location_on_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valorHoraCtrl,
              decoration: const InputDecoration(
                labelText: 'Valor por hora (R\$)',
                prefixIcon: Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: horasSessaoCtrl,
              decoration: const InputDecoration(
                labelText: 'Horas por sessão',
                prefixIcon: Icon(Icons.access_time_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (widget.trainerId == null) return;
              try {
                await AuthService.updateTrainerProfile(
                  widget.trainerId!,
                  cidade: cidadeCtrl.text.trim(),
                  valorHora: valorHoraCtrl.text.trim(),
                  horasPorSessao: horasSessaoCtrl.text.trim(),
                );
                setState(() {
                  _editCidade = cidadeCtrl.text.trim();
                  _editValorHora = valorHoraCtrl.text.trim();
                  _horasPorSessao = horasSessaoCtrl.text.trim().isNotEmpty
                      ? horasSessaoCtrl.text.trim()
                      : '1h por sessão';
                });
                _showSnack(
                  'Perfil atualizado!',
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF059669),
                );
              } catch (e) {
                _showSnack(
                  e.toString().replaceFirst('Exception: ', ''),
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFEF4444),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B4DBA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Resumo de solicitações pendentes
  List<Map<String, dynamic>> get _pendingRequests => _allTrainerRequests
      .where((r) {
        final id = r['id'] is int
            ? r['id'] as int
            : int.tryParse((r['id'] ?? '').toString());
        final hiddenByDb = r['hiddenForTrainer'] == true;
        final hiddenLocally = id != null && _hiddenRequestIds.contains(id);
        return (r['status'] ?? '') == 'PENDING' && !hiddenByDb && !hiddenLocally;
      })
      .toList();

  int get _totalPending => _pendingRequests.length;

  DateTime _startOfWeek(DateTime baseDate) {
    final normalized = DateTime(baseDate.year, baseDate.month, baseDate.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  DateTime _dateForDayIndex(int dayIndex) {
    final weekStart = _startOfWeek(DateTime.now()).add(
      Duration(days: _agendaWeekOffset * 7),
    );
    return weekStart.add(Duration(days: dayIndex));
  }

  DateTime _dateForDayIndexWithOffset(int dayIndex, int weekOffset) {
    final weekStart = _startOfWeek(DateTime.now()).add(
      Duration(days: weekOffset * 7),
    );
    return weekStart.add(Duration(days: dayIndex));
  }

  String _formatDateLabel(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  String _dayDateLabel(int dayIndex) {
    return _formatDateLabel(_dateForDayIndex(dayIndex));
  }

  String _weekRangeLabel() {
    final start = _dateForDayIndex(0);
    final end = _dateForDayIndex(6);
    return '${_formatDateLabel(start)}-${_formatDateLabel(end)}';
  }

  DateTime? _slotDateTimeFor(int dayIndex, String time, {int? weekOffset}) {
    final parts = time.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;

    final dayDate = weekOffset == null
        ? _dateForDayIndex(dayIndex)
        : _dateForDayIndexWithOffset(dayIndex, weekOffset);
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      hour,
      minute,
    );
  }

  bool _isPastSlotFor(int dayIndex, String time, {int? weekOffset}) {
    final dt = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (dt == null) return false;
    return dt.isBefore(DateTime.now());
  }

  void _positionAgendaForTrainer() {
    if (_initialAgendaPositioned) return;

    final now = DateTime.now();
    final todayIndex = now.weekday - 1;
    const maxFutureWeeks = 8;

    for (int week = 0; week <= maxFutureWeeks; week++) {
      final startDay = week == 0 ? todayIndex : 0;
      for (int day = startDay; day < _days.length; day++) {
        final daySlots = _schedule[_days[day]] ?? const <_Slot>[];
        final hasAvailable = daySlots.any(
          (slot) =>
              _effectiveSlotState(slot, day, weekOffset: week) ==
              _SlotState.available,
        );
        if (hasAvailable) {
          if (!mounted) return;
          setState(() {
            _agendaWeekOffset = week;
            _selectedDay = day;
            _initialAgendaPositioned = true;
          });
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _agendaWeekOffset = 0;
      _selectedDay = todayIndex;
      _initialAgendaPositioned = true;
    });
  }

  String _normalizeDayForFallback(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .trim();
  }

  int? _weekdayFromPtForFallback(String dayName) {
    switch (_normalizeDayForFallback(dayName)) {
      case 'segunda':
        return DateTime.monday;
      case 'terca':
      case 'terça':
        return DateTime.tuesday;
      case 'quarta':
        return DateTime.wednesday;
      case 'quinta':
        return DateTime.thursday;
      case 'sexta':
        return DateTime.friday;
      case 'sabado':
      case 'sábado':
        return DateTime.saturday;
      case 'domingo':
        return DateTime.sunday;
      default:
        return null;
    }
  }

  (int hour, int minute)? _parseHourMinuteForFallback(String time) {
    final parts = time.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  DateTime _nextOccurrenceForFallback(DateTime base, int weekday, int hour, int minute) {
    final sameDayAtTime = DateTime(base.year, base.month, base.day, hour, minute);
    var deltaDays = weekday - base.weekday;
    if (deltaDays < 0) deltaDays += 7;
    var candidate = sameDayAtTime.add(Duration(days: deltaDays));
    if (candidate.isBefore(base)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  String _fallbackDateLabelForLegacySlot({
    required String dayName,
    required String time,
    String? anchorIso,
  }) {
    final weekday = _weekdayFromPtForFallback(dayName);
    final hm = _parseHourMinuteForFallback(time);
    if (weekday == null || hm == null) return '';

    final anchor = DateTime.tryParse((anchorIso ?? '').toString()) ?? DateTime.now();
    var candidate =
        _nextOccurrenceForFallback(anchor, weekday, hm.$1, hm.$2);
    if (weekday == anchor.weekday) {
      final sameDayScheduled = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        hm.$1,
        hm.$2,
      );
      if (sameDayScheduled.isBefore(anchor)) {
        candidate = sameDayScheduled;
      }
    }

    final dd = candidate.day.toString().padLeft(2, '0');
    final mm = candidate.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  String _normalizeTimeValue(String value) {
    final text = value.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return text;
    final hh = (int.tryParse(match.group(1) ?? '') ?? 0)
        .toString()
        .padLeft(2, '0');
    final mm = (int.tryParse(match.group(2) ?? '') ?? 0)
        .toString()
        .padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime _addOneMonthKeepingDay(DateTime date) {
    final nextMonth = date.month == 12 ? 1 : date.month + 1;
    final nextYear = date.month == 12 ? date.year + 1 : date.year;
    final maxDayNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
    final day = date.day <= maxDayNextMonth ? date.day : maxDayNextMonth;
    return DateTime(nextYear, nextMonth, day, date.hour, date.minute);
  }

  String _toDateIso(DateTime value) {
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  String _weeklyManualBlockKey(String dayName, String time) {
    final normalizedDay = _normalizeDayForFallback(dayName);
    final normalizedTime = _normalizeTimeValue(time);
    return '$normalizedDay|$normalizedTime';
  }

  bool _isWeeklyManualBlockFor(int dayIndex, String time) {
    if (dayIndex < 0 || dayIndex >= _days.length) return false;
    return _weeklyManualBlockKeys.contains(
      _weeklyManualBlockKey(_days[dayIndex], time),
    );
  }

  bool _hasOneTimeManualBlockFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final slotDate = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (slotDate == null) return false;

    final dayName = _days[dayIndex];
    final normalizedDay = _normalizeDayForFallback(dayName);
    final normalizedTime = _normalizeTimeValue(time);
    final dateIso = _toDateIso(slotDate);

    for (final blocked in _oneTimeManualBlocks) {
      final blockedDay = _normalizeDayForFallback(
        (blocked['dayName'] ?? '').toString(),
      );
      final blockedTime = _normalizeTimeValue((blocked['time'] ?? '').toString());
      final blockedDate = (blocked['dateIso'] ?? '').toString().trim();
      final dayMatches = blockedDay.isEmpty || blockedDay == normalizedDay;
      if (dayMatches && blockedTime == normalizedTime && blockedDate == dateIso) {
        return true;
      }
    }
    return false;
  }

  bool _hasOneTimeManualUnblockFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final slotDate = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (slotDate == null) return false;

    final dayName = _days[dayIndex];
    final normalizedDay = _normalizeDayForFallback(dayName);
    final normalizedTime = _normalizeTimeValue(time);
    final dateIso = _toDateIso(slotDate);

    for (final unblocked in _oneTimeManualUnblocks) {
      final unblockedDay = _normalizeDayForFallback(
        (unblocked['dayName'] ?? '').toString(),
      );
      final unblockedTime = _normalizeTimeValue((unblocked['time'] ?? '').toString());
      final unblockedDate = (unblocked['dateIso'] ?? '').toString().trim();
      final dayMatches = unblockedDay.isEmpty || unblockedDay == normalizedDay;
      if (dayMatches && unblockedTime == normalizedTime && unblockedDate == dateIso) {
        return true;
      }
    }
    return false;
  }

  DateTime? _parseSlotDateMeta(
    Map<String, String> slot,
    int hour,
    int minute,
    DateTime anchor,
  ) {
    final iso = (slot['dateIso'] ?? '').trim();
    if (iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
      }
    }

    final dateLabel = (slot['dateLabel'] ?? '').trim();
    final full = RegExp(r'^(\d{2})\/(\d{2})\/(\d{4})$').firstMatch(dateLabel);
    if (full != null) {
      final day = int.tryParse(full.group(1)!);
      final month = int.tryParse(full.group(2)!);
      final year = int.tryParse(full.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, hour, minute);
      }
    }

    final short = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(dateLabel);
    if (short != null) {
      final day = int.tryParse(short.group(1)!);
      final month = int.tryParse(short.group(2)!);
      if (day != null && month != null) {
        return DateTime(anchor.year, month, day, hour, minute);
      }
    }

    return null;
  }

  DateTime _requestAnchor(Map<String, dynamic> req) {
    return _parseIsoDateTime(req['approvedAt']) ??
        _parseIsoDateTime(req['createdAt']) ??
        DateTime.now();
  }

  DateTime _requestWindowAnchor(Map<String, dynamic> req) {
    return _parseIsoDateTime(req['createdAt']) ?? _requestAnchor(req);
  }

  DateTime _weeklyOverlayAnchor(Map<String, dynamic> req) {
    return _parseIsoDateTime(req['createdAt']) ??
      _parseIsoDateTime(req['approvedAt']) ??
      DateTime.now();
  }

  bool _sameMomentByMinute(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  DateTime? _slotStartAtForMonthly(
    Map<String, String> slot,
    DateTime anchor,
  ) {
    final weekday = _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
    final hm = _parseHourMinuteForFallback((slot['time'] ?? '').toString());
    if (weekday == null || hm == null) return null;

    final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
    if (fromMeta != null) return fromMeta;

    return _nextOccurrenceForFallback(anchor, weekday, hm.$1, hm.$2);
  }

  DateTime? _slotStartAtForWeekly(
    Map<String, String> slot,
    DateTime anchor,
  ) {
    final weekday = _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
    final hm = _parseHourMinuteForFallback((slot['time'] ?? '').toString());
    if (weekday == null || hm == null) return null;

    final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
    if (fromMeta != null) return fromMeta;

    final weekStart = _startOfWeek(anchor);
    final targetDate = weekStart.add(Duration(days: weekday - 1));
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hm.$1,
      hm.$2,
    );
  }

  DateTime? _monthlyFirstSessionAt(Map<String, dynamic> req) {
    final slots = _extractRequestSlots(req);
    if (slots.isEmpty) return null;
    final anchor = _requestAnchor(req);

    DateTime? first;
    for (final slot in slots) {
      final current = _slotStartAtForMonthly(slot, anchor);
      if (current == null) continue;
      if (first == null || current.isBefore(first)) {
        first = current;
      }
    }
    return first;
  }

  ( _SlotState state, String? studentName )? _monthlyRequestOverlayFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final candidate = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (candidate == null) return null;

    final normalizedCandidateTime = _normalizeTimeValue(time);
    final candidateWeekday = dayIndex + 1;

    final approvedRequests = _allTrainerRequests
        .where((r) {
          final status = (r['status'] ?? '').toString().toUpperCase();
          final plan = (r['planType'] ?? 'DIARIO').toString().toUpperCase();
          return status == 'APPROVED' && plan == 'MENSAL';
        })
        .toList();

    for (final req in approvedRequests) {
      final anchor = _requestWindowAnchor(req);
      final firstSession = _monthlyFirstSessionAt(req);
      if (firstSession == null) continue;
      final windowEnd = _addOneMonthKeepingDay(firstSession);
      final slots = _extractRequestSlots(req);
      for (final slot in slots) {
        final weekday = _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == null) continue;
        if (weekday != candidateWeekday || slotTime != normalizedCandidateTime) {
          continue;
        }

        final slotStart = _slotStartAtForMonthly(slot, anchor);
        if (slotStart == null || candidate.isBefore(slotStart)) continue;
        if (candidate.isAfter(windowEnd)) continue;

        final diffDays = candidate.difference(slotStart).inDays;
        if (diffDays % 7 != 0) continue;

        final studentName =
            (req['studentName'] ?? 'Aluno').toString().trim();
        return (_SlotState.unavailable, studentName.isNotEmpty ? studentName : 'Aluno');
      }
    }

    for (final req in _pendingRequests) {
      final plan = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      if (plan != 'MENSAL') continue;

      final anchor = _requestWindowAnchor(req);
      final firstSession = _monthlyFirstSessionAt(req);
      if (firstSession == null) continue;
      final windowEnd = _addOneMonthKeepingDay(firstSession);
      final slots = _extractRequestSlots(req);

      for (final slot in slots) {
        final weekday = _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == null) continue;
        if (weekday != candidateWeekday || slotTime != normalizedCandidateTime) {
          continue;
        }

        final slotStart = _slotStartAtForMonthly(slot, anchor);
        if (slotStart == null || candidate.isBefore(slotStart)) continue;
        if (candidate.isAfter(windowEnd)) continue;

        final diffDays = candidate.difference(slotStart).inDays;
        if (diffDays % 7 != 0) continue;

        return (_SlotState.requested, null);
      }
    }

    return null;
  }

  ( _SlotState state, String? studentName )? _weeklyRequestOverlayFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final candidate = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (candidate == null) return null;

    final normalizedCandidateTime = _normalizeTimeValue(time);
    final candidateWeekday = dayIndex + 1;

    for (final req in _allTrainerRequests) {
      final plan = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      final status = (req['status'] ?? '').toString().toUpperCase();
      if (plan != 'SEMANAL') continue;
      if (status != 'APPROVED' && status != 'PENDING') continue;

      final anchor = _weeklyOverlayAnchor(req);
      final slots = _extractRequestSlots(req);

      for (final slot in slots) {
        final weekday = _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == null) continue;
        if (weekday != candidateWeekday || slotTime != normalizedCandidateTime) {
          continue;
        }

        final slotStart = _slotStartAtForWeekly(slot, anchor);
        if (slotStart == null) continue;

        if (!_sameMomentByMinute(candidate, slotStart)) {
          continue;
        }

        if (status == 'APPROVED') {
          final studentName = (req['studentName'] ?? 'Aluno').toString().trim();
          return (_SlotState.unavailable, studentName.isNotEmpty ? studentName : 'Aluno');
        }
        return (_SlotState.requested, null);
      }
    }

    return null;
  }

  ( _SlotState state, String? studentName )? _dailyPendingOverlayFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final candidate = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (candidate == null) return null;

    final normalizedCandidateTime = _normalizeTimeValue(time);
    final candidateWeekday = dayIndex + 1;

    for (final req in _pendingRequests) {
      final plan = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      if (plan != 'DIARIO') continue;

      final slots = _extractRequestSlots(req);
      final anchor = _requestAnchor(req);
      for (final slot in slots) {
        final weekday =
            _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == null) continue;
        if (weekday != candidateWeekday || slotTime != normalizedCandidateTime) {
          continue;
        }

        final slotStart = _slotStartAtForMonthly(slot, anchor);
        if (slotStart == null) continue;

        final sameMoment =
            candidate.year == slotStart.year &&
            candidate.month == slotStart.month &&
            candidate.day == slotStart.day &&
            candidate.hour == slotStart.hour &&
            candidate.minute == slotStart.minute;
        if (sameMoment) {
          return (_SlotState.requested, null);
        }
      }
    }

    return null;
  }

  ( _SlotState state, String? studentName )? _dailyApprovedOverlayFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final candidate = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (candidate == null) return null;

    final normalizedCandidateTime = _normalizeTimeValue(time);
    final candidateWeekday = dayIndex + 1;

    for (final req in _allTrainerRequests) {
      final plan = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      final status = (req['status'] ?? '').toString().toUpperCase();
      if (plan != 'DIARIO' || status != 'APPROVED') continue;

      final slots = _extractRequestSlots(req);
      final anchor = _requestAnchor(req);
      for (final slot in slots) {
        final weekday =
            _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == null) continue;
        if (weekday != candidateWeekday || slotTime != normalizedCandidateTime) {
          continue;
        }

        final slotStart = _slotStartAtForMonthly(slot, anchor);
        if (slotStart == null) continue;

        final sameMoment =
            candidate.year == slotStart.year &&
            candidate.month == slotStart.month &&
            candidate.day == slotStart.day &&
            candidate.hour == slotStart.hour &&
            candidate.minute == slotStart.minute;
        if (!sameMoment) continue;

        final studentName = (req['studentName'] ?? 'Aluno').toString().trim();
        return (_SlotState.unavailable, studentName.isNotEmpty ? studentName : 'Aluno');
      }
    }

    return null;
  }

  bool _hasMonthlyPatternFor(int dayIndex, String time) {
    final candidateWeekday = dayIndex + 1;
    final normalizedTime = _normalizeTimeValue(time);

    for (final req in _allTrainerRequests) {
      final plan = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      final status = (req['status'] ?? '').toString().toUpperCase();
      if (plan != 'MENSAL') continue;
      if (status != 'APPROVED' && status != 'PENDING') continue;

      final slots = _extractRequestSlots(req);
      for (final slot in slots) {
        final weekday = _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == candidateWeekday && slotTime == normalizedTime) {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasDailyPatternFor(int dayIndex, String time) {
    final candidateWeekday = dayIndex + 1;
    final normalizedTime = _normalizeTimeValue(time);

    for (final req in _allTrainerRequests) {
      final plan = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      final status = (req['status'] ?? '').toString().toUpperCase();
      if (plan != 'DIARIO' || status != 'APPROVED') continue;

      final slots = _extractRequestSlots(req);
      for (final slot in slots) {
        final weekday =
            _weekdayFromPtForFallback((slot['dayName'] ?? '').toString());
        final slotTime = _normalizeTimeValue((slot['time'] ?? '').toString());
        if (weekday == candidateWeekday && slotTime == normalizedTime) {
          return true;
        }
      }
    }

    return false;
  }

  String _slotChipLabel({
    required String dayName,
    required String time,
    String? dateLabel,
  }) {
    final safeDay = dayName.trim();
    final safeTime = _normalizeTimeValue(time);
    final safeDate = (dateLabel ?? '').trim();
    if (safeDate.isNotEmpty) {
      return '$safeDay $safeDate · $safeTime';
    }
    return '$safeDay · $safeTime';
  }

  List<String> _requestSlotLabelsForAgenda(Map<String, dynamic> req) {
    final planType = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
    final slots = _extractRequestSlots(req);
    if (slots.isEmpty) return const [];

    if (planType != 'MENSAL') {
      return slots.map((slot) {
        final dayName = (slot['dayName'] ?? '').toString().trim();
        final time = (slot['time'] ?? '').toString().trim();
        final rawDate = (slot['dateLabel'] ?? '').toString().trim();
        final dateLabel = rawDate.isNotEmpty
            ? rawDate
            : _fallbackDateLabelForLegacySlot(
                dayName: dayName,
                time: time,
                anchorIso: req['updatedAt']?.toString() ?? req['createdAt']?.toString(),
              );
        return _slotChipLabel(
          dayName: dayName,
          time: time,
          dateLabel: dateLabel,
        );
      }).toList();
    }

    final anchor = _requestAnchor(req);
    final parsed = <Map<String, dynamic>>[];
    for (final slot in slots) {
      final dayName = (slot['dayName'] ?? '').toString().trim();
      final time = (slot['time'] ?? '').toString().trim();
      final weekday = _weekdayFromPtForFallback(dayName);
      final hm = _parseHourMinuteForFallback(time);
      final startAt = _slotStartAtForMonthly(slot, anchor);
      if (dayName.isEmpty || time.isEmpty || weekday == null || hm == null || startAt == null) {
        continue;
      }
      parsed.add({
        'dayName': dayName,
        'time': _normalizeTimeValue(time),
        'weekday': weekday,
        'hour': hm.$1,
        'minute': hm.$2,
        'startAt': startAt,
      });
    }

    if (parsed.isEmpty) {
      return slots
          .map((slot) => _slotChipLabel(
                dayName: (slot['dayName'] ?? '').toString(),
                time: (slot['time'] ?? '').toString(),
                dateLabel: (slot['dateLabel'] ?? '').toString(),
              ))
          .toList();
    }

    parsed.sort((a, b) =>
        (a['startAt'] as DateTime).compareTo(b['startAt'] as DateTime));
    final first = parsed.first;
    final firstAt = first['startAt'] as DateTime;
    final windowEnd = _addOneMonthKeepingDay(firstAt);

    final patterns = <String, Map<String, dynamic>>{};
    for (final item in parsed) {
      final key = '${item['weekday']}|${item['time']}';
      patterns.putIfAbsent(key, () => item);
    }

    final firstKey = '${first['weekday']}|${first['time']}';
    final middle = patterns.entries
        .where((e) => e.key != firstKey)
        .map((e) => e.value)
        .toList();
    middle.sort((a, b) {
      final aNext = _nextOccurrenceForFallback(
        firstAt,
        a['weekday'] as int,
        a['hour'] as int,
        a['minute'] as int,
      );
      final bNext = _nextOccurrenceForFallback(
        firstAt,
        b['weekday'] as int,
        b['hour'] as int,
        b['minute'] as int,
      );
      return aNext.compareTo(bNext);
    });

    DateTime? lastAt;
    Map<String, dynamic>? lastPattern;
    for (final pattern in patterns.values) {
      var candidate = pattern['startAt'] as DateTime;
      while (candidate.add(const Duration(days: 7)).isBefore(windowEnd) ||
          candidate.add(const Duration(days: 7)).isAtSameMomentAs(windowEnd)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      if (candidate.isAfter(windowEnd)) continue;

      if (lastAt == null || candidate.isAfter(lastAt)) {
        lastAt = candidate;
        lastPattern = pattern;
      }
    }

    final labels = <String>[
      _slotChipLabel(
        dayName: first['dayName'] as String,
        time: first['time'] as String,
        dateLabel: _formatDateLabel(firstAt),
      ),
    ];

    for (final pattern in middle) {
      labels.add(
        _slotChipLabel(
          dayName: pattern['dayName'] as String,
          time: pattern['time'] as String,
        ),
      );
    }

    if (lastAt != null && lastPattern != null && lastAt.isAfter(firstAt)) {
      labels.add(
        _slotChipLabel(
          dayName: lastPattern['dayName'] as String,
          time: lastPattern['time'] as String,
          dateLabel: _formatDateLabel(lastAt),
        ),
      );
    }

    return labels;
  }

  (_SlotState state, String? studentName) _effectiveSlotInfo(
    _Slot slot,
    int dayIndex, {
    int? weekOffset,
  }) {
    if (_isPastSlotFor(dayIndex, slot.time, weekOffset: weekOffset)) {
      return (_SlotState.unavailable, null);
    }

    if (_hasOneTimeManualBlockFor(dayIndex, slot.time, weekOffset: weekOffset)) {
      return (_SlotState.unavailable, null);
    }

    final monthlyOverlay = _monthlyRequestOverlayFor(
      dayIndex,
      slot.time,
      weekOffset: weekOffset,
    );
    if (monthlyOverlay != null) {
      return monthlyOverlay;
    }

    final weeklyOverlay = _weeklyRequestOverlayFor(
      dayIndex,
      slot.time,
      weekOffset: weekOffset,
    );
    if (weeklyOverlay != null) {
      return weeklyOverlay;
    }

    final dailyPendingOverlay = _dailyPendingOverlayFor(
      dayIndex,
      slot.time,
      weekOffset: weekOffset,
    );
    if (dailyPendingOverlay != null) {
      return dailyPendingOverlay;
    }

    final dailyApprovedOverlay = _dailyApprovedOverlayFor(
      dayIndex,
      slot.time,
      weekOffset: weekOffset,
    );
    if (dailyApprovedOverlay != null) {
      return dailyApprovedOverlay;
    }

    final isManualBlocked =
        slot.state == _SlotState.unavailable && (slot.studentName ?? '').trim().isEmpty;
    if (isManualBlocked) {
      if (_hasOneTimeManualUnblockFor(dayIndex, slot.time, weekOffset: weekOffset)) {
        return (_SlotState.available, null);
      }

      if (!_isWeeklyManualBlockFor(dayIndex, slot.time) &&
          (_hasMonthlyPatternFor(dayIndex, slot.time) ||
              _hasDailyPatternFor(dayIndex, slot.time))) {
        // Slot legado bloqueado por aprovação mensal antiga: fora da janela do plano,
        // volta a ficar disponível para não manter bloqueio indefinido.
        return (_SlotState.available, null);
      }
      return (_SlotState.unavailable, null);
    }

    return (slot.state, slot.studentName);
  }

  _SlotState _effectiveSlotState(
    _Slot slot,
    int dayIndex, {
    int? weekOffset,
  }) {
    return _effectiveSlotInfo(
      slot,
      dayIndex,
      weekOffset: weekOffset,
    ).$1;
  }

  String? _effectiveSlotStudentName(
    _Slot slot,
    int dayIndex, {
    int? weekOffset,
  }) {
    return _effectiveSlotInfo(
      slot,
      dayIndex,
      weekOffset: weekOffset,
    ).$2;
  }

  // ── Toque em horário (gerenciamento) ─────────────────────────────────────

  Future<void> _onSlotTap(
    _Slot slot,
    String dayName, {
    _SlotState? effectiveState,
  }) async {
    final dayIndex = _days.indexOf(dayName);
    if (dayIndex >= 0 && _isPastSlotFor(dayIndex, slot.time)) {
      _showSnack(
        '$dayName às ${slot.time} está bloqueado (horário passado).',
        icon: Icons.block_rounded,
        color: const Color(0xFFEF4444),
      );
      return;
    }

    final state = effectiveState ?? slot.state;

    switch (state) {
      case _SlotState.available:
        // Personal bloqueia o horário
        _showBlockDialog(slot, dayName);
        break;
      case _SlotState.unavailable:
        if (widget.trainerId == null) return;
        final slotDate = dayIndex >= 0
          ? _slotDateTimeFor(dayIndex, slot.time, weekOffset: _agendaWeekOffset)
          : null;
        final dateIso = slotDate != null ? _toDateIso(slotDate) : '';

        try {
          await AuthService.unblockSlot(
            widget.trainerId!,
            dayName,
            slot.time,
            repeatMode: 'ONCE',
            dateIso: dateIso,
          );
          await _loadSlots();
        } catch (_) {
          _showSnack(
            'Não foi possível desbloquear este horário.',
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFEF4444),
          );
          return;
        }

        _showSnack(
          '$dayName às ${slot.time} desbloqueado apenas para ${_dayDateLabel(dayIndex)}',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF22C55E),
        );
        break;
      case _SlotState.requested:
        // Personal vê a solicitação e decide
        _showRequestDialog(slot, dayName);
        break;
    }
  }

  void _showBlockDialog(_Slot slot, String dayName) {
    String repeatMode = 'ONCE';
    String fullDayRepeatMode = 'ONCE';
    bool blockFullDay = false;
    final dayIndex = _days.indexOf(dayName);
    final dateIso = dayIndex >= 0
        ? _toDateIso(_dateForDayIndex(dayIndex))
        : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Bloquear horário'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escolha como bloquear $dayName às ${slot.time}.',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              if (!blockFullDay)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(
                        dayIndex >= 0
                            ? 'Somente ${_dayDateLabel(dayIndex)}'
                            : 'Somente este dia',
                      ),
                      selected: repeatMode == 'ONCE',
                      onSelected: (_) => setDialogState(() => repeatMode = 'ONCE'),
                    ),
                    ChoiceChip(
                      label: Text('Toda semana em $dayName'),
                      selected: repeatMode == 'WEEKLY',
                      onSelected: (_) => setDialogState(() => repeatMode = 'WEEKLY'),
                    ),
                    ChoiceChip(
                      label: const Text('Todos os dias da semana'),
                      selected: repeatMode == 'ALL_DAYS',
                      onSelected: (_) => setDialogState(() => repeatMode = 'ALL_DAYS'),
                    ),
                  ],
                ),
              const Divider(height: 18),
              CheckboxListTile(
                value: blockFullDay,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Bloquear o dia inteiro (00:00 às 23:00)'),
                onChanged: (v) => setDialogState(() {
                  blockFullDay = v ?? false;
                  if (!blockFullDay) {
                    fullDayRepeatMode = 'ONCE';
                  }
                }),
              ),
              if (blockFullDay) ...[
                const SizedBox(height: 6),
                const Text(
                  'Aplicar o dia inteiro somente nesta data ou repetir toda semana?',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(
                        dayIndex >= 0
                            ? 'Só ${_dayDateLabel(dayIndex)}'
                            : 'Só este dia',
                      ),
                      selected: fullDayRepeatMode == 'ONCE',
                      onSelected: (_) =>
                          setDialogState(() => fullDayRepeatMode = 'ONCE'),
                    ),
                    ChoiceChip(
                      label: Text('Repetir toda semana em $dayName'),
                      selected: fullDayRepeatMode == 'WEEKLY',
                      onSelected: (_) =>
                          setDialogState(() => fullDayRepeatMode = 'WEEKLY'),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (widget.trainerId == null) return;

                try {
                  final selectedMode = blockFullDay ? fullDayRepeatMode : repeatMode;
                  await AuthService.blockSlot(
                    widget.trainerId!,
                    dayName,
                    slot.time,
                    repeatMode: selectedMode,
                    dateIso: selectedMode == 'ONCE' ? dateIso : null,
                    blockFullDay: blockFullDay,
                  );
                  await _loadSlots();
                } catch (_) {
                  if (!mounted) return;
                  _showSnack(
                    'Não foi possível bloquear o horário.',
                    icon: Icons.error_outline_rounded,
                    color: const Color(0xFFEF4444),
                  );
                  return;
                }

                if (!mounted) return;
                _showSnack(
                  blockFullDay
                    ? fullDayRepeatMode == 'ONCE'
                      ? 'Dia inteiro bloqueado apenas em ${_dayDateLabel(dayIndex)}'
                      : 'Dia inteiro bloqueado semanalmente em $dayName'
                      : repeatMode == 'ONCE'
                          ? '$dayName às ${slot.time} bloqueado apenas para ${_dayDateLabel(dayIndex)}'
                          : repeatMode == 'ALL_DAYS'
                              ? '${slot.time} bloqueado em todos os dias da semana'
                              : '$dayName às ${slot.time} bloqueado semanalmente',
                  icon: Icons.block_rounded,
                  color: const Color(0xFFEF4444),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: const Text('Bloquear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRepeatBlockedDialog() async {
    if (widget.trainerId == null) return;

    final dayName = _days[_selectedDay];
    final daySlots = _schedule[dayName] ?? [];
    if (daySlots.isEmpty) return;

    final times = daySlots.map((s) => s.time).toList();
    final defaultEndIndex = times.length > 8 ? 7 : times.length - 1;
    String startTime = times.first;
    String endTime = times[defaultEndIndex];
    String repeatMode = 'ONCE';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Bloquear faixa de horários'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escolha a faixa e como ela deve se repetir.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text('Apenas ${_dayDateLabel(_selectedDay)}'),
                      selected: repeatMode == 'ONCE',
                      onSelected: (_) => setDialogState(() => repeatMode = 'ONCE'),
                    ),
                    ChoiceChip(
                      label: Text('Toda semana em $dayName'),
                      selected: repeatMode == 'WEEKLY',
                      onSelected: (_) => setDialogState(() => repeatMode = 'WEEKLY'),
                    ),
                    const SizedBox(width: 2),
                    ChoiceChip(
                      label: const Text('Todos os dias da semana'),
                      selected: repeatMode == 'ALL_DAYS',
                      onSelected: (_) => setDialogState(() => repeatMode = 'ALL_DAYS'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Início da faixa'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: startTime,
                  items: times
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setDialogState(() => startTime = v);
                  },
                ),
                const SizedBox(height: 10),
                const Text('Fim da faixa'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: endTime,
                  items: times
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setDialogState(() => endTime = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  'startTime': startTime,
                  'endTime': endTime,
                  'repeatMode': repeatMode,
                }),
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;

    await _applyBlockRange(
      dayName: dayName,
      startTime: result['startTime'] as String,
      endTime: result['endTime'] as String,
      repeatMode: result['repeatMode'] as String,
    );
  }

  List<String> _manualBlockedTimesForDay(
    int dayIndex, {
    int? weekOffset,
  }) {
    if (dayIndex < 0 || dayIndex >= _days.length) return const [];

    final dayName = _days[dayIndex];
    final daySlots = _schedule[dayName] ?? const <_Slot>[];
    final blockedTimes = <String>[];

    for (final slot in daySlots) {
      final hasManualBlock =
          _isWeeklyManualBlockFor(dayIndex, slot.time) ||
              _hasOneTimeManualBlockFor(
                dayIndex,
                slot.time,
                weekOffset: weekOffset,
              );
      final hasManualUnblock = _hasOneTimeManualUnblockFor(
        dayIndex,
        slot.time,
        weekOffset: weekOffset,
      );

      if (hasManualBlock && !hasManualUnblock) {
        blockedTimes.add(slot.time);
      }
    }

    return blockedTimes;
  }

  Future<void> _showCloneDayDialog() async {
    if (widget.trainerId == null) return;

    final sourceDayIndex = _selectedDay;
    final sourceDayName = _days[sourceDayIndex];
    final blockedTimes = _manualBlockedTimesForDay(
      sourceDayIndex,
      weekOffset: _agendaWeekOffset,
    );

    if (blockedTimes.isEmpty) {
      _showSnack(
        'Não há horários manuais bloqueados em $sourceDayName para clonar.',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF64748B),
      );
      return;
    }

    bool cloneToAllDays = false;
    final selectedTargetDays = <int>{};

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Clonar bloqueios do dia'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dia base: $sourceDayName ${_dayDateLabel(sourceDayIndex)} (${blockedTimes.length} horário${blockedTimes.length > 1 ? 's' : ''} bloqueado${blockedTimes.length > 1 ? 's' : ''}).',
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Clonar para todos os dias'),
                      selected: cloneToAllDays,
                      onSelected: (_) => setDialogState(() {
                        cloneToAllDays = true;
                        selectedTargetDays.clear();
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Escolher dias específicos'),
                      selected: !cloneToAllDays,
                      onSelected: (_) => setDialogState(() => cloneToAllDays = false),
                    ),
                  ],
                ),
                if (!cloneToAllDays) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Selecione os dias que receberão o mesmo padrão:',
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Dica: os dias começam desmarcados.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black45),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = 0; i < _days.length; i++)
                        FilterChip(
                          label: Text(_days[i]),
                          selected: selectedTargetDays.contains(i),
                          onSelected: (value) {
                            setDialogState(() {
                              if (value) {
                                selectedTargetDays.add(i);
                              } else {
                                selectedTargetDays.remove(i);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: !cloneToAllDays && selectedTargetDays.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, {
                          'cloneToAllDays': cloneToAllDays,
                          'targetDays': cloneToAllDays
                              ? const <int>[]
                              : selectedTargetDays.toList(),
                        }),
                child: const Text('Aplicar clone'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;

    await _applyCloneDayPattern(
      sourceDayIndex: sourceDayIndex,
      blockedTimes: blockedTimes,
      cloneToAllDays: (result['cloneToAllDays'] as bool?) ?? true,
      targetDayIndexes: Set<int>.from(
        (result['targetDays'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e is int ? e : int.tryParse(e.toString()) ?? -1)
            .where((e) => e >= 0 && e < _days.length),
      ),
    );
  }

  Future<void> _applyCloneDayPattern({
    required int sourceDayIndex,
    required List<String> blockedTimes,
    required bool cloneToAllDays,
    required Set<int> targetDayIndexes,
  }) async {
    if (widget.trainerId == null || _applyingCloneDay) return;
    if (blockedTimes.isEmpty) return;

    final sourceDayName = _days[sourceDayIndex];
    final uniqueTimes = blockedTimes.toSet().toList()..sort();
    final effectiveCloneToAllDays = cloneToAllDays && targetDayIndexes.isEmpty;

    final targets = effectiveCloneToAllDays
        ? <int>{for (int i = 0; i < _days.length; i++) if (i != sourceDayIndex) i}
      : {...targetDayIndexes};

    if (!effectiveCloneToAllDays && targets.isEmpty) {
      _showSnack(
        'Selecione ao menos um dia para clonar o padrão.',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF64748B),
      );
      return;
    }

    var changedCount = 0;

    setState(() => _applyingCloneDay = true);
    try {
      if (effectiveCloneToAllDays) {
        for (final time in uniqueTimes) {
          await AuthService.blockSlot(
            widget.trainerId!,
            sourceDayName,
            time,
            repeatMode: 'ALL_DAYS',
          );
          changedCount += (_days.length - 1);
        }
      } else {
        for (final targetIndex in targets) {
          final targetDay = _days[targetIndex];
          for (final time in uniqueTimes) {
            await AuthService.blockSlot(
              widget.trainerId!,
              targetDay,
              time,
              repeatMode: 'WEEKLY',
            );
            changedCount++;
          }
        }
      }

      await _loadSlots();

      if (!mounted) return;
      final targetNames = targets.map((i) => _days[i]).toList()..sort();
      _showSnack(
        effectiveCloneToAllDays
            ? 'Padrão de $sourceDayName clonado para todos os dias da semana.'
        : 'Padrão de $sourceDayName clonado para ${targets.length} dia${targets.length > 1 ? 's' : ''} (${targetNames.join(', ')}). ${changedCount} bloqueio${changedCount > 1 ? 's' : ''} aplicado${changedCount > 1 ? 's' : ''}.',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), ''),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _applyingCloneDay = false);
    }
  }

  Future<void> _clearBlockedTimesForSelectedDate() async {
    if (widget.trainerId == null || _clearingDayBlocks) return;

    final dayIndex = _selectedDay;
    if (dayIndex < 0 || dayIndex >= _days.length) return;

    final dayName = _days[dayIndex];
    final selectedDate = _dateForDayIndex(dayIndex);
    final dateIso = _toDateIso(selectedDate);
    final dateLabel = _formatDateLabel(selectedDate);

    final blockedTimes = _manualBlockedTimesForDay(
      dayIndex,
      weekOffset: _agendaWeekOffset,
    ).toSet().toList()
      ..sort();

    if (blockedTimes.isEmpty) {
      _showSnack(
        'Não há bloqueios manuais em $dayName ($dateLabel) para limpar.',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF64748B),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar bloqueios do dia'),
        content: Text(
          'Deseja liberar ${blockedTimes.length} horário${blockedTimes.length > 1 ? 's' : ''} em $dayName ($dateLabel)?\n\nA limpeza será aplicada somente nesta data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Limpar dia'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    var clearedCount = 0;
    setState(() => _clearingDayBlocks = true);
    try {
      for (final time in blockedTimes) {
        await AuthService.unblockSlot(
          widget.trainerId!,
          dayName,
          time,
          repeatMode: 'ONCE',
          dateIso: dateIso,
        );
        clearedCount++;
      }

      await _loadSlots();

      if (!mounted) return;
      _showSnack(
        '$clearedCount horário${clearedCount > 1 ? 's' : ''} liberado${clearedCount > 1 ? 's' : ''} em $dayName ($dateLabel), somente nesta data.',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), ''),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _clearingDayBlocks = false);
    }
  }

  Future<void> _applyBlockRange({
    required String dayName,
    required String startTime,
    required String endTime,
    required String repeatMode,
  }) async {
    if (widget.trainerId == null || _applyingBlockRange) return;

    final baseSlots = _schedule[dayName] ?? [];
    if (baseSlots.isEmpty) return;

    final orderedTimes = baseSlots.map((s) => s.time).toList();
    var startIdx = orderedTimes.indexOf(startTime);
    var endIdx = orderedTimes.indexOf(endTime);
    if (startIdx < 0 || endIdx < 0) return;
    if (startIdx > endIdx) {
      final temp = startIdx;
      startIdx = endIdx;
      endIdx = temp;
    }

    final dayIndex = _days.indexOf(dayName);
    final dateIso = dayIndex >= 0 ? _toDateIso(_dateForDayIndex(dayIndex)) : '';

    if (repeatMode == 'ONCE' && dateIso.isEmpty) {
      _showSnack(
        'Não foi possível determinar a data da faixa selecionada.',
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
      return;
    }

    var changedCount = 0;

    setState(() => _applyingBlockRange = true);
    try {
      for (int i = startIdx; i <= endIdx && i < orderedTimes.length; i++) {
        final time = orderedTimes[i];
        await AuthService.blockSlot(
          widget.trainerId!,
          dayName,
          time,
          repeatMode: repeatMode,
          dateIso: repeatMode == 'ONCE' ? dateIso : null,
        );
        changedCount++;
      }

      await _loadSlots();

      if (!mounted) return;
      _showSnack(
        changedCount > 0
            ? repeatMode == 'ALL_DAYS'
                ? 'Faixa bloqueada em todos os dias da semana ($changedCount horário${changedCount > 1 ? 's' : ''}).'
                : repeatMode == 'WEEKLY'
                    ? 'Faixa bloqueada semanalmente em $dayName ($changedCount horário${changedCount > 1 ? 's' : ''}).'
                    : 'Faixa bloqueada apenas em ${_dayDateLabel(_selectedDay)} ($changedCount horário${changedCount > 1 ? 's' : ''}).'
            : 'Nenhum horário elegível para bloquear na faixa selecionada.',
        icon: changedCount > 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
        color: changedCount > 0 ? const Color(0xFF16A34A) : const Color(0xFF64748B),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), ''),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _applyingBlockRange = false);
    }
  }

  void _showRequestDialog(_Slot slot, String dayName) {
    // Busca a solicitação pendente correspondente
    Map<String, dynamic>? matchReq;
    for (final r in _pendingRequests) {
      if (r['dayName'].toString() == dayName &&
          r['time'].toString() == slot.time) {
        matchReq = r;
        break;
      }
    }
    final studentName = matchReq != null
        ? (matchReq['studentName'] ?? 'Aluno')
        : 'Aluno';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFDE68A), width: 2),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 26,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Solicitação de Aluno',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '$studentName solicitou $dayName às ${slot.time}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              // Botão Chat
              if (matchReq != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrainerChatView(
                              requestId: matchReq?['id'] != null
                                  ? int.tryParse(matchReq!['id'].toString())
                                  : null,
                              trainerName: studentName.toString(),
                              dayName: dayName,
                              time: slot.time,
                              isTrainerSide: true,
                              senderId: widget.trainerId,
                              receiverId:
                                  matchReq != null &&
                                      matchReq['studentId'] != null
                                  ? int.tryParse(
                                      matchReq['studentId'].toString(),
                                    )
                                  : null,
                              planType: matchReq?['planType']?.toString(),
                              daysJson: matchReq?['daysJson']?.toString(),
                              readOnlyStartAtIso:
                                  matchReq?['createdAt']?.toString(),
                              readOnlyLockAtIso:
                                  matchReq != null
                                      ? _resolveRequestChatLockAtIso(matchReq)
                                      : null,
                                requestUpdatedAtIso:
                                  matchReq?['updatedAt']?.toString(),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                      ),
                      label: const Text('Chat com Aluno'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0B4DBA),
                        side: const BorderSide(color: Color(0xFF0B4DBA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (matchReq == null) return;
                        try {
                          final targetReq = Map<String, dynamic>.from(matchReq);
                          await AuthService.updateRequestStatus(
                            (targetReq['id'] is int
                                ? targetReq['id'] as int
                                : int.parse(targetReq['id'].toString())),
                            'REJECTED',
                          );
                          await _sendDecisionAutoMessage(
                            targetReq,
                            approved: false,
                          );
                          setState(() => slot.state = _SlotState.available);
                          _showSnack(
                            'Solicitação recusada',
                            icon: Icons.cancel_rounded,
                            color: const Color(0xFFEF4444),
                          );
                          _loadRequests();
                        } catch (e) {
                          _showSnack(
                            e.toString().replaceFirst('Exception: ', ''),
                            icon: Icons.error_outline_rounded,
                            color: const Color(0xFFEF4444),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        foregroundColor: const Color(0xFFEF4444),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Recusar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (matchReq == null) return;
                        try {
                          final targetReq = Map<String, dynamic>.from(matchReq);
                          await AuthService.updateRequestStatus(
                            (targetReq['id'] is int
                                ? targetReq['id'] as int
                                : int.parse(targetReq['id'].toString())),
                            'APPROVED',
                          );
                          await _sendDecisionAutoMessage(
                            targetReq,
                            approved: true,
                          );
                          final approvedReq = matchReq;
                          setState(() {
                            // Atualização otimista: adiciona aluno imediatamente
                            final sid = approvedReq['studentId']?.toString();
                            final alreadyIn = _myStudents.any(
                              (s) => s['studentId']?.toString() == sid,
                            );
                            if (!alreadyIn) {
                              _myStudents = List.from(_myStudents)
                                ..add(Map<String, dynamic>.from(approvedReq));
                            }
                          });
                          _showSnack(
                            '$dayName às ${slot.time} confirmado!',
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF22C55E),
                          );
                          _loadRequests();
                          _loadMyStudents();
                        } catch (e) {
                          _showSnack(
                            e.toString().replaceFirst('Exception: ', ''),
                            icon: Icons.error_outline_rounded,
                            color: const Color(0xFFEF4444),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {required IconData icon, required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _blockStudentFromRequest(Map<String, dynamic> req) async {
    if (widget.trainerId == null) return;
    final studentId = int.tryParse((req['studentId'] ?? '').toString());
    final requestId = int.tryParse((req['id'] ?? '').toString());
    if (studentId == null) {
      _showSnack(
        'Aluno inválido para bloqueio',
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
      return;
    }

    try {
      await AuthService.blockStudent(
        widget.trainerId!,
        studentId,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _blockedStudentIds = {..._blockedStudentIds, studentId};
      });
      await _loadSlots();
      await _loadRequests();
      _loadMyStudents();
      _showSnack(
        'Aluno bloqueado e removido da sua lista',
        icon: Icons.block_rounded,
        color: const Color(0xFFEF4444),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
    }
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                controller: _pageScrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                child: Column(
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 20),
                    _buildMyStudentsCard(),
                    const SizedBox(height: 20),
                    _buildReviewsCard(),
                    const SizedBox(height: 20),
                    _buildScheduleCard(),
                    const SizedBox(height: 20),
                    _buildRequestsCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B4DBA), Color(0xFF1A62D4)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x330B4DBA),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              const FitMatchLogo(height: 38, onDarkBackground: true),
              const Spacer(),
              if (_totalPending > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.notifications_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$_totalPending nova${_totalPending > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 56),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  tooltip: 'Sair',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _topActionButton(
                  icon: Icons.person_rounded,
                  label: 'Meu perfil',
                  isActive: true,
                  onTap: _scrollToProfile,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _topActionButton(
                  icon: Icons.restaurant_menu_rounded,
                  label: 'Controle de dieta',
                  isActive: false,
                  onTap: _openDietControl,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDietControl() {
    final trainerId = widget.trainerId;
    if (trainerId == null) {
      _showSnack(
        'Não foi possível abrir o controle de dieta.',
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.dietControl),
        builder: (_) => DietControlView(
          userId: trainerId,
          userName: widget.name,
          isTrainerSide: true,
        ),
      ),
    );
  }

  void _scrollToProfile() {
    if (!_pageScrollController.hasClients) return;
    _pageScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _topActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isActive ? Colors.white : const Color(0xFF0B4DBA),
        backgroundColor:
            isActive ? const Color(0xFF3B82F6) : const Color(0xFFF8FBFF),
        side: BorderSide(
          color: isActive ? const Color(0xFF3B82F6) : const Color(0xFFBFD3F5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ── Card de perfil ────────────────────────────────────────────────────────

  ({int availableSlots, int activeDays}) _currentMonthAvailabilityStats() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(now.year, now.month + 1, 0);
    final baseWeekStart = _startOfWeek(now);

    var availableSlots = 0;
    var activeDays = 0;

    for (
      DateTime date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final dayIndex = date.weekday - 1;
      final weekOffset = date.difference(baseWeekStart).inDays ~/ 7;
      final dayName = _days[dayIndex];
      final slots = _schedule[dayName] ?? const <_Slot>[];

      var dayHasAvailable = false;
      for (final slot in slots) {
        final hm = _parseHourMinuteForFallback(slot.time);
        if (hm == null) continue;

        final slotDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          hm.$1,
          hm.$2,
        );
        if (slotDateTime.isBefore(now)) continue;

        final state = _effectiveSlotState(
          slot,
          dayIndex,
          weekOffset: weekOffset,
        );
        if (state == _SlotState.available) {
          availableSlots++;
          dayHasAvailable = true;
        }
      }

      if (dayHasAvailable) {
        activeDays++;
      }
    }

    return (availableSlots: availableSlots, activeDays: activeDays);
  }

  Widget _buildProfileCard() {
    final hasCref = widget.cref != null && widget.cref!.trim().isNotEmpty;
    final hasBio = widget.bio != null && widget.bio!.trim().isNotEmpty;
    final hasEsp =
        widget.especialidade != null && widget.especialidade!.trim().isNotEmpty;

    // Calcula stats considerando o mês atual.
    final monthlyStats = _currentMonthAvailabilityStats();
    final totalAvail = monthlyStats.availableSlots;
    final activeDays = monthlyStats.activeDays;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.1),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Banner ──────────────────────────────────────────────
          Container(
            height: 140,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0B4DBA),
                  Color(0xFF1D4ED8),
                  Color(0xFF3B82F6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Círculos decorativos
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: -20,
                  bottom: -40,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 80,
                  top: 20,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Ícone decorativo
                Positioned(
                  left: 20,
                  top: 16,
                  child: Icon(
                    Icons.fitness_center,
                    size: 32,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                // Badge CREF
                if (hasCref)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: _BadgeChip(
                      icon: Icons.verified_rounded,
                      label: 'CREF Verificado',
                      color: Color(0xFF22C55E),
                    ),
                  ),
              ],
            ),
          ),
          // ── Info do perfil ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar sobreposto + nome
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD9E8FB), Color(0xFFBDD5F5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0B4DBA,
                              ).withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: ClipOval(
                            child: widget.trainerId != null
                                ? Image.network(
                                    AuthService.getUserPhotoUrl(
                                      widget.trainerId!,
                                    ),
                                    fit: BoxFit.cover,
                                    width: 90,
                                    height: 90,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person_rounded,
                                      size: 40,
                                      color: Color(0xFF0B4DBA),
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 40,
                                    color: Color(0xFF0B4DBA),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.name.trim().isEmpty
                                        ? 'Personal Trainer'
                                        : widget.name,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                if (hasCref) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: Color(0xFF0B4DBA),
                                    size: 19,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasCref
                                  ? 'CREF ${widget.cref!.trim()}'
                                  : 'Personal Trainer',
                              style: const TextStyle(
                                color: Colors.black45,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Stats rápidas
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        value: '$totalAvail',
                        label: 'Disponíveis no mês',
                        icon: Icons.lock_open_rounded,
                        color: const Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        value: '$_totalPending',
                        label: 'Solicitações',
                        icon: Icons.hourglass_top_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        value: '$activeDays',
                        label: 'Dias ativos no mês',
                        icon: Icons.calendar_today_rounded,
                        color: const Color(0xFF0B4DBA),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Especialidades
                if (hasEsp) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s
                          in widget.especialidade!
                              .split(RegExp(r'[,;]'))
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty))
                        _SpecialtyChip(label: s),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                // Info chips + botão editar
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (_editCidade.isNotEmpty)
                            _InfoChip(
                              icon: Icons.location_on_rounded,
                              label: _editCidade,
                            ),
                          if (_editValorHora.isNotEmpty)
                            _InfoChip(
                              icon: Icons.attach_money_rounded,
                              label: 'R\$ $_editValorHora / hora',
                            ),
                          _InfoChip(
                            icon: Icons.access_time_rounded,
                            label: _horasPorSessao,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _showEditProfileDialog,
                      icon: const Icon(
                        Icons.edit_rounded,
                        size: 20,
                        color: Color(0xFF0B4DBA),
                      ),
                      tooltip: 'Editar perfil',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF4FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
                // Bio
                if (hasBio) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE7EBF3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0B4DBA,
                            ).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.bio!,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13.5,
                              height: 1.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Meus Alunos ──────────────────────────────────────────────────────────────

  Widget _buildMyStudentsCard() {
    const dayOrder = {
      'Segunda': 1,
      'Terça': 2,
      'Quarta': 3,
      'Quinta': 4,
      'Sexta': 5,
      'Sábado': 6,
      'Domingo': 7,
    };

    String planLabelFor(String? planType) {
      switch (planType?.toUpperCase()) {
        case 'DIARIO':
          return 'Plano Diário';
        case 'SEMANAL':
          return 'Plano Semanal';
        case 'MENSAL':
          return 'Plano Mensal';
        default:
          return 'Aluno';
      }
    }

    String scheduleLabelFor(Map<String, dynamic> row) {
      final rawDays = (row['daysJson'] ?? '').toString().trim();
      if (rawDays.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawDays) as List<dynamic>;
          final labels = <String>[];
          final seen = <String>{};
          for (final slot in decoded.whereType<Map>()) {
            final d = (slot['dayName'] ?? '').toString().trim();
            final t = (slot['time'] ?? '').toString().trim();
            if (d.isEmpty || t.isEmpty) continue;
            final label = '$d $t';
            if (seen.add(label)) {
              labels.add(label);
            }
          }
          if (labels.isNotEmpty) {
            return labels.join(', ');
          }
        } catch (_) {}
      }

      final day = (row['dayName'] ?? '').toString().trim();
      final hour = (row['time'] ?? '').toString().trim();
      if (day.isNotEmpty && hour.isNotEmpty) {
        return '$day $hour';
      }

      return '';
    }

    List<String> workoutDaysFor(Map<String, dynamic> row) {
      final days = <String>{};
      final rawDays = (row['daysJson'] ?? '').toString().trim();
      if (rawDays.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawDays) as List<dynamic>;
          for (final slot in decoded.whereType<Map>()) {
            final d = (slot['dayName'] ?? '').toString().trim();
            if (d.isNotEmpty) {
              days.add(d);
            }
          }
        } catch (_) {}
      }

      final singleDay = (row['dayName'] ?? '').toString().trim();
      if (singleDay.isNotEmpty) {
        days.add(singleDay);
      }

      final list = days.toList();
      list.sort((a, b) =>
          (dayOrder[a] ?? 99).compareTo(dayOrder[b] ?? 99));
      return list;
    }

    List<Map<String, String>> workoutSlotsFor(Map<String, dynamic> row) {
      final slots = <Map<String, String>>[];
      final seen = <String>{};

      final rawDays = (row['daysJson'] ?? '').toString().trim();
      if (rawDays.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawDays) as List<dynamic>;
          for (final slot in decoded.whereType<Map>()) {
            final day = (slot['dayName'] ?? '').toString().trim();
            final time = (slot['time'] ?? '').toString().trim();
            final dateLabel = (slot['dateLabel'] ?? '').toString().trim();
            final dateIso = (slot['dateIso'] ?? '').toString().trim();
            if (day.isEmpty || time.isEmpty) continue;
            final key = '$day|$time';
            if (!seen.add(key)) continue;
            slots.add({
              'dayName': day,
              'time': time,
              'dateLabel': dateLabel,
              'dateIso': dateIso,
            });
          }
        } catch (_) {}
      }

      if (slots.isEmpty) {
        final day = (row['dayName'] ?? '').toString().trim();
        final time = (row['time'] ?? '').toString().trim();
        if (day.isNotEmpty && time.isNotEmpty) {
          slots.add({
            'dayName': day,
            'time': time,
            'dateLabel': '',
            'dateIso': '',
          });
        }
      }

      slots.sort((a, b) {
        final dayCmp = (dayOrder[a['dayName']] ?? 99).compareTo(
          dayOrder[b['dayName']] ?? 99,
        );
        if (dayCmp != 0) return dayCmp;
        return (a['time'] ?? '').compareTo(b['time'] ?? '');
      });
      return slots;
    }

    final activeRows = _myStudents
        .map(
          (s) => {
            ...s,
            'studentId': s['studentId'] != null
                ? (s['studentId'] as num).toInt()
                : null,
            'studentName': (s['studentName'] ?? 'Aluno').toString(),
            'blocked': false,
            'isMyStudent': true,
          },
        )
        .toList();

    final groupedActive = <int, Map<String, dynamic>>{};
    for (final row in activeRows) {
      final sid = row['studentId'] as int?;
      if (sid == null) continue;

      final existing = groupedActive[sid];
      if (existing == null) {
        groupedActive[sid] = {
          ...row,
          'plansSummaryItems': <String>{},
          'allowedWorkoutDaysItems': <String>{},
          'allowedWorkoutSlotItems': <String>{},
          'allowedWorkoutSlots': <Map<String, String>>[],
          'latestPlanAt': null,
        };
      }

      final entry = groupedActive[sid]!;
      final plan = planLabelFor(row['planType']?.toString());
      final schedule = scheduleLabelFor(row);
      final item = schedule.isEmpty ? plan : '$plan $schedule';
      final items = entry['plansSummaryItems'] as Set<String>;
      if (item.trim().isNotEmpty) {
        items.add(item);
      }

      final allowedDays = entry['allowedWorkoutDaysItems'] as Set<String>;
      allowedDays.addAll(workoutDaysFor(row));

      final allowedSlotItems = entry['allowedWorkoutSlotItems'] as Set<String>;
      final allowedSlots = entry['allowedWorkoutSlots'] as List<Map<String, String>>;
      for (final slot in workoutSlotsFor(row)) {
        final key = '${slot['dayName']}|${slot['time']}';
        if (!allowedSlotItems.add(key)) continue;
        allowedSlots.add(slot);
      }

      final rowDate = _parseIsoDateTime(row['approvedAt']) ??
          _parseIsoDateTime(row['createdAt']);
      final latestPlanAt = entry['latestPlanAt'] as DateTime?;
      if (rowDate != null && (latestPlanAt == null || rowDate.isAfter(latestPlanAt))) {
        entry['latestPlanAt'] = rowDate;
      }
    }

    final activeStudents = groupedActive.values
        .map((row) {
          final items = (row['plansSummaryItems'] as Set<String>).toList();
          items.sort();
          final workoutDays = (row['allowedWorkoutDaysItems'] as Set<String>).toList()
            ..sort((a, b) => (dayOrder[a] ?? 99).compareTo(dayOrder[b] ?? 99));
          final workoutSlots = List<Map<String, String>>.from(
            row['allowedWorkoutSlots'] as List<Map<String, String>>,
          );
          workoutSlots.sort((a, b) {
            final dayCmp = (dayOrder[a['dayName']] ?? 99).compareTo(
              dayOrder[b['dayName']] ?? 99,
            );
            if (dayCmp != 0) return dayCmp;
            return (a['time'] ?? '').compareTo(b['time'] ?? '');
          });
          return {
            ...row,
            'plansSummary': items.join(' • '),
            'allowedWorkoutDays': workoutDays,
            'allowedWorkoutSlots': workoutSlots,
            'latestApprovedAtIso':
                (row['latestPlanAt'] as DateTime?)?.toIso8601String(),
          };
        })
        .toList();

    activeStudents.sort((a, b) {
      final da = a['latestPlanAt'] as DateTime?;
      final db = b['latestPlanAt'] as DateTime?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final activeIds = activeStudents
        .map((s) => s['studentId'])
        .whereType<int>()
        .toSet();

    final blockedOnly = _blockedStudentIds
        .where((id) => !activeIds.contains(id))
        .map(
          (id) => <String, dynamic>{
            'studentId': id,
            'studentName': _blockedStudentNames[id] ?? 'Aluno #$id',
            'blocked': true,
            'isMyStudent': false,
          },
        )
        .toList();

    final platformStudents = _allStudents
        .map(
          (s) => <String, dynamic>{
            'studentId': s['id'] != null ? (s['id'] as num).toInt() : null,
            'studentName': (s['name'] ?? 'Aluno').toString(),
            'blocked': _blockedStudentIds.contains(
              s['id'] != null ? (s['id'] as num).toInt() : -1,
            ),
            'isMyStudent': activeIds.contains(
              s['id'] != null ? (s['id'] as num).toInt() : -1,
            ),
          },
        )
        .where((s) => s['studentId'] != null)
        .toList();

    final query = _studentSearch.trim().toLowerCase();
    final searchable = query.isEmpty
        ? [...activeStudents, ...blockedOnly]
        : platformStudents;
    final visibleStudents = query.isEmpty
        ? activeStudents
        : searchable.where((s) {
            final sid = (s['studentId'] ?? '').toString();
            final name = (s['studentName'] ?? '').toString().toLowerCase();
            return name.contains(query) || sid.contains(query);
          }).toList();

    return _SectionCard(
      title: 'Meus Alunos',
      icon: Icons.people_rounded,
        trailing: activeStudents.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFBFD3F5)),
              ),
              child: Text(
                '${activeStudents.length} aluno${activeStudents.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Color(0xFF0B4DBA),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      child: _loadingStudents
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  color: Color(0xFF0B4DBA),
                  strokeWidth: 2.5,
                ),
              ),
            )
          : Column(
              children: [
                TextField(
                  onChanged: (value) {
                    setState(() => _studentSearch = value);
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar aluno (inclui bloqueados)',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF7F9FD),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE7EBF3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE7EBF3)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (visibleStudents.isEmpty && _studentSearch.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    alignment: Alignment.center,
                    child: const Text(
                      'Nenhum aluno encontrado na busca',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.black45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (visibleStudents.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFBFD3F5)),
                          ),
                          child: const Icon(
                            Icons.people_outline_rounded,
                            color: Color(0xFF0B4DBA),
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Nenhum aluno ainda',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Alunos com solicitações aprovadas aparecerão aqui',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black38,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _loadMyStudents,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Atualizar'),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: visibleStudents.length > 4
                        ? 392
                        : (visibleStudents.length * 98).toDouble(),
                    child: Scrollbar(
                      controller: _studentsScrollController,
                      thumbVisibility: visibleStudents.length > 4,
                      child: ListView.builder(
                        controller: _studentsScrollController,
                        itemExtent: 98,
                        itemCount: visibleStudents.length,
                        itemBuilder: (_, index) {
                          final student = visibleStudents[index];
                          return _StudentRow(
                            studentName: (student['studentName'] ?? 'Aluno')
                                .toString(),
                            studentId: student['studentId'] != null
                                ? (student['studentId'] as num).toInt()
                                : null,
                            trainerId: widget.trainerId,
                            planType: student['planType']?.toString(),
                            dayName: student['dayName']?.toString(),
                            time: student['time']?.toString(),
                            daysJson: student['daysJson']?.toString(),
                            plansSummary: student['plansSummary']?.toString(),
                            blocked: _blockedStudentIds.contains(
                              student['studentId'] != null
                                  ? (student['studentId'] as num).toInt()
                                  : -1,
                            ),
                            onChat: (student['isMyStudent'] == true)
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TrainerChatView(
                                          trainerName:
                                              (student['studentName'] ?? 'Aluno')
                                                  .toString(),
                                          isTrainerSide: true,
                                          senderId: widget.trainerId,
                                          receiverId: student['studentId'] != null
                                              ? int.tryParse(
                                                  student['studentId'].toString(),
                                                )
                                              : null,
                                          dayName: (student['dayName'] ?? '')
                                              .toString(),
                                          time: (student['time'] ?? '')
                                              .toString(),
                                          planType: student['planType']
                                              ?.toString(),
                                          daysJson: student['daysJson']
                                              ?.toString(),
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            onViewProfile: () {
                              final sid = student['studentId'] != null
                                  ? (student['studentId'] as num).toInt()
                                  : null;
                              if (sid == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentProfileView(
                                    studentId: sid,
                                    studentName:
                                        (student['studentName'] ?? 'Aluno')
                                            .toString(),
                                    trainerId: widget.trainerId,
                                    trainerName: widget.name,
                                  ),
                                ),
                              );
                            },
                            onBlock: () async {
                              if (widget.trainerId == null ||
                                  student['studentId'] == null) {
                                return;
                              }
                              final sid = (student['studentId'] as num).toInt();
                              final requestId = int.tryParse(
                                (student['id'] ?? student['requestId'] ?? '').toString(),
                              );
                              try {
                                await AuthService.blockStudent(
                                  widget.trainerId!,
                                  sid,
                                  requestId: requestId,
                                );
                                if (!mounted) return;
                                setState(() {
                                  _blockedStudentIds = {
                                    ..._blockedStudentIds,
                                    sid,
                                  };
                                });
                                await _loadAll();
                                _showSnack(
                                  'Aluno bloqueado e removido da sua lista',
                                  icon: Icons.block_rounded,
                                  color: const Color(0xFFEF4444),
                                );
                              } catch (e) {
                                _showSnack(
                                  e.toString().replaceFirst('Exception: ', ''),
                                  icon: Icons.error_outline_rounded,
                                  color: const Color(0xFFEF4444),
                                );
                              }
                            },
                            onUnblock: () async {
                              if (widget.trainerId == null ||
                                  student['studentId'] == null) {
                                return;
                              }
                              final sid = (student['studentId'] as num).toInt();
                              try {
                                await AuthService.unblockStudent(
                                  widget.trainerId!,
                                  sid,
                                );
                                if (!mounted) return;
                                setState(() {
                                  _blockedStudentIds = {..._blockedStudentIds}
                                    ..remove(sid);
                                });
                                _showSnack(
                                  'Aluno desbloqueado',
                                  icon: Icons.lock_open_rounded,
                                  color: const Color(0xFF22C55E),
                                );
                              } catch (e) {
                                _showSnack(
                                  e.toString().replaceFirst('Exception: ', ''),
                                  icon: Icons.error_outline_rounded,
                                  color: const Color(0xFFEF4444),
                                );
                              }
                            },
                            onRemove: (student['isMyStudent'] == true)
                                ? () async {
                                    if (widget.trainerId == null ||
                                        student['studentId'] == null) {
                                      return;
                                    }
                                    final myStudentIds = _myStudents
                                        .map((s) => s['studentId'])
                                        .whereType<int>()
                                        .toSet();
                                    if (!myStudentIds.contains(
                                      (student['studentId'] as num).toInt(),
                                    )) {
                                      _showSnack(
                                        'Esse aluno não está em Meus Alunos',
                                        icon: Icons.info_outline_rounded,
                                        color: const Color(0xFF0B4DBA),
                                      );
                                      return;
                                    }
                                    final sid = (student['studentId'] as num)
                                        .toInt();
                                    final requestId = int.tryParse(
                                      (student['id'] ?? student['requestId'] ?? '')
                                          .toString(),
                                    );
                                    try {
                                      await AuthService.removeTrainerStudent(
                                        widget.trainerId!,
                                        sid,
                                        requestId: requestId,
                                      );
                                      try {
                                        await AuthService.createConnection(
                                          studentId: sid,
                                          trainerId: widget.trainerId!,
                                          studentName:
                                              (student['studentName'] ?? 'Aluno')
                                                  .toString(),
                                          trainerName: widget.name,
                                        );
                                      } catch (_) {}
                                      if (!mounted) return;
                                      await _loadAll();
                                      _showSnack(
                                        'Aluno removido e horários liberados',
                                        icon: Icons.person_remove_rounded,
                                        color: const Color(0xFF0B4DBA),
                                      );
                                    } catch (e) {
                                      _showSnack(
                                        e.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                        icon: Icons.error_outline_rounded,
                                        color: const Color(0xFFEF4444),
                                      );
                                    }
                                  }
                                : null,
                            onOrganizeWorkout: (student['isMyStudent'] == true)
                                ? () {
                                    if (widget.trainerId == null || student['studentId'] == null) {
                                      return;
                                    }
                                    final sid = (student['studentId'] as num).toInt();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TrainerWorkoutOrganizerView(
                                          trainerId: widget.trainerId!,
                                          studentId: sid,
                                          studentName: (student['studentName'] ?? 'Aluno').toString(),
                                          allowedDays: (student['allowedWorkoutDays'] as List?)
                                                  ?.map((d) => d.toString())
                                                  .toList() ??
                                              const [],
                                          allowedSlots: (student['allowedWorkoutSlots'] as List?)
                                                  ?.whereType<Map>()
                                                  .map(
                                                    (slot) => {
                                                      'dayName': (slot['dayName'] ?? '').toString(),
                                                      'time': (slot['time'] ?? '').toString(),
                                                      'dateLabel': (slot['dateLabel'] ?? '').toString(),
                                                      'dateIso': (slot['dateIso'] ?? '').toString(),
                                                    },
                                                  )
                                                  .toList() ??
                                              const [],
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildReviewsCard() {
    return _SectionCard(
      title: 'Avaliações dos Alunos',
      icon: Icons.star_outline_rounded,
      trailing: _ratings.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 4),
                Text(
                  _avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                Text(
                  ' (${_ratings.length})',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            )
          : null,
      child: _loadingRatings
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(
                  color: Color(0xFF0B4DBA),
                  strokeWidth: 2.5,
                ),
              ),
            )
          : _ratings.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhuma avaliação recebida ainda.',
                style: TextStyle(fontSize: 12.5, color: Colors.black45),
              ),
            )
          : Column(
              children: [
                for (final rating in _ratings)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              (rating['studentName'] ?? 'Aluno').toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              (rating['stars'] ?? 0).toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                        if ((rating['comment'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            (rating['comment'] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ── Agenda do personal ────────────────────────────────────────────────────

  Widget _buildScheduleCard() {
    final slots = _schedule[_days[_selectedDay]] ?? [];
    final available = slots
      .where((s) => _effectiveSlotState(s, _selectedDay) == _SlotState.available)
      .length;
    final blocked = slots
      .where((s) => _effectiveSlotState(s, _selectedDay) == _SlotState.unavailable)
      .length;
    final requested = slots
      .where((s) => _effectiveSlotState(s, _selectedDay) == _SlotState.requested)
      .length;
    final canGoPrevWeek = _agendaWeekOffset > 0;

    return _SectionCard(
      title: 'Minha Agenda',
      icon: Icons.calendar_month_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (requested > 0)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                '$requested solicit.',
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: available > 0
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$available livres',
              style: TextStyle(
                color: available > 0 ? const Color(0xFF16A34A) : Colors.black45,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instrução contextual
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFBFD3F5)),
            ),
            child: Row(
              children: const [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Color(0xFF0B4DBA),
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Toque em um horário disponível para bloqueá-lo, ou em um bloqueado para liberar.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Resumo do dia
          if (slots.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _CountBadge(
                  value: available,
                  label: 'Disponíveis',
                  color: const Color(0xFF22C55E),
                ),
                if (requested > 0)
                  _CountBadge(
                    value: requested,
                    label: 'Solicitados',
                    color: const Color(0xFFF59E0B),
                  ),
                if (blocked > 0)
                  _CountBadge(
                    value: blocked,
                    label: 'Bloqueados',
                    color: const Color(0xFF9CA3AF),
                  ),
              ],
            ),
          if (slots.isNotEmpty) const SizedBox(height: 14),
          // Navegação de semana
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: canGoPrevWeek
                      ? () => setState(() => _agendaWeekOffset -= 1)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 22,
                      color: canGoPrevWeek
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _weekRangeLabel(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _agendaWeekOffset += 1),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Seletor de dia
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final isSelected = _selectedDay == i;
                final daySlots = _schedule[_days[i]] ?? [];
                final hasReq = daySlots.any(
                  (s) => _effectiveSlotState(s, i) == _SlotState.requested,
                );
                final hasAvail = daySlots.any(
                  (s) => _effectiveSlotState(s, i) == _SlotState.available,
                );
                final isEmpty = daySlots.isEmpty;

                Color? dotColor;
                if (!isSelected && !isEmpty) {
                  if (hasReq) {
                    dotColor = const Color(0xFFF59E0B);
                  } else if (hasAvail) {
                    dotColor = const Color(0xFF22C55E);
                  } else {
                    dotColor = const Color(0xFF9CA3AF);
                  }
                }

                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : const Color(0xFFE7EBF3),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF0B4DBA,
                                ).withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _dayLabels[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: dotColor != null
                                    ? (isSelected ? Colors.white : dotColor)
                                    : (isSelected
                                        ? Colors.white.withValues(alpha: 0.4)
                                        : Colors.transparent),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dayDateLabel(i),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          // Legenda
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: const [
              _LegendItem(
                color: Color(0xFF22C55E),
                label: 'Disponível – toque para bloquear',
              ),
              _LegendItem(
                color: Color(0xFFFDE68A),
                label: 'Solicitado por aluno',
              ),
              _LegendItem(
                color: Color(0xFFE5E7EB),
                label: 'Bloqueado – toque para liberar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _applyingBlockRange ? null : _showRepeatBlockedDialog,
                  icon: _applyingBlockRange
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.schedule_rounded, size: 16),
                  label: const Text('Bloquear faixa de horários'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: (_applyingCloneDay || _applyingBlockRange)
                      ? null
                      : _showCloneDayDialog,
                  icon: _applyingCloneDay
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.copy_all_rounded, size: 16),
                  label: const Text('Clonar bloqueios do dia'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      (_applyingCloneDay || _applyingBlockRange || _clearingDayBlocks)
                          ? null
                          : _clearBlockedTimesForSelectedDate,
                  icon: _clearingDayBlocks
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_delete_rounded, size: 16),
                  label: const Text('Limpar bloqueios do dia'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Grid de horários
          if (slots.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Icon(
                      Icons.event_busy_rounded,
                      color: Color(0xFF9CA3AF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sem atendimento neste dia',
                    style: TextStyle(
                      color: Colors.black45,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 2.5,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: slots.length,
              itemBuilder: (_, i) {
                final baseSlot = slots[i];
                final effectiveState = _effectiveSlotState(baseSlot, _selectedDay);
                final effectiveStudentName =
                    _effectiveSlotStudentName(baseSlot, _selectedDay);
                final viewSlot = _Slot(baseSlot.time)
                  ..state = effectiveState
                  ..studentName = effectiveStudentName;

                return _DashSlotTile(
                  slot: viewSlot,
                  forceUnavailable: _isPastSlotFor(_selectedDay, baseSlot.time),
                  onTap: () => _onSlotTap(
                    baseSlot,
                    _days[_selectedDay],
                    effectiveState: effectiveState,
                  ),
                );
              },
            ),
          // ── Solicitações em análise ───────────────────────────────────────
          if (_pendingRequests.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: Color(0xFFE7EBF3)),
            const SizedBox(height: 14),
            Row(
              children: const [
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 16,
                  color: Color(0xFFF59E0B),
                ),
                SizedBox(width: 8),
                Text(
                  'Horários em análise',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final req in _pendingRequests) _buildPendingAgendaItem(req),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingAgendaItem(Map<String, dynamic> req) {
    final studentName = (req['studentName'] ?? 'Aluno').toString();
    final studentId = req['studentId'] is num ? (req['studentId'] as num).toInt() : null;
    final slotLabels = _requestSlotLabelsForAgenda(req);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFEF9C3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: ClipOval(
                child: studentId != null
                    ? Image.network(
                        AuthService.getUserPhotoUrl(studentId),
                        fit: BoxFit.cover,
                        width: 36,
                        height: 36,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_rounded,
                          color: Color(0xFFB45309),
                          size: 18,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: Color(0xFFB45309),
                        size: 18,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: slotLabels
                      .map(
                        (label) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Em análise',
              style: TextStyle(
                fontSize: 10.5,
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Solicitações ──────────────────────────────────────────────────────────

  Widget _buildRequestsCard() {
    return _SectionCard(
      title: 'Solicitações de Alunos',
      icon: Icons.inbox_rounded,
      trailing: _allTrainerRequests.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                '${_pendingRequests.length} pendente${_pendingRequests.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      child: _loadingRequests
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  color: Color(0xFF0B4DBA),
                  strokeWidth: 2.5,
                ),
              ),
            )
          : (() {
              final visibleRequests = _allTrainerRequests.where((req) {
                final id = req['id'] is int
                    ? req['id'] as int
                    : int.tryParse((req['id'] ?? '').toString());
                final hiddenByDb = req['hiddenForTrainer'] == true;
                final hiddenLocally = id != null && _hiddenRequestIds.contains(id);
                return !hiddenByDb && !hiddenLocally;
              }).toList();

              if (visibleRequests.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFBFD3F5)),
                        ),
                        child: const Icon(
                          Icons.inbox_outlined,
                          color: Color(0xFF0B4DBA),
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhuma solicitação pendente',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'As solicitações dos alunos aparecerão aqui',
                        style: TextStyle(fontSize: 12.5, color: Colors.black38),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _loadRequests,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Atualizar'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (final req in visibleRequests)
                    _RequestRow(
                      studentName: (req['studentName'] ?? 'Aluno').toString(),
                      requestId: req['id'] is int
                          ? req['id'] as int
                          : int.tryParse(req['id'].toString()) ?? 0,
                      dayName: (req['dayName'] ?? '').toString(),
                      time: (req['time'] ?? '').toString(),
                      status: (req['status'] ?? 'PENDING').toString(),
                      studentBlocked: _blockedStudentIds.contains(
                        int.tryParse((req['studentId'] ?? '').toString()) ?? -1,
                      ),
                      planType: (req['planType'] ?? 'DIARIO').toString(),
                      daysJson: req['daysJson']?.toString(),
                      approvedAtIso: req['approvedAt']?.toString(),
                      createdAtIso: req['createdAt']?.toString(),
                      onChat: () {
                        final reqStatus = (req['status'] ?? 'PENDING').toString();
                        final requestStartAtIso = req['createdAt']?.toString();
                        final requestLockAtIso = _resolveRequestChatLockAtIso(req);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrainerChatView(
                              requestId: req['id'] != null
                                  ? int.tryParse(req['id'].toString())
                                  : null,
                              trainerName: (req['studentName'] ?? 'Aluno')
                                  .toString(),
                              dayName: (req['dayName'] ?? '').toString(),
                              time: (req['time'] ?? '').toString(),
                              isTrainerSide: true,
                              senderId: widget.trainerId,
                              receiverId: req['studentId'] != null
                                  ? int.tryParse(req['studentId'].toString())
                                  : null,
                              planType: (req['planType'] ?? 'DIARIO').toString(),
                              daysJson: req['daysJson']?.toString(),
                              readOnly: reqStatus == 'REJECTED',
                              readOnlyMessage: reqStatus == 'REJECTED'
                                  ? 'Este chat está em modo leitura porque esta solicitação foi encerrada. Para voltar a enviar mensagens, o aluno precisa criar uma nova solicitação.'
                                  : null,
                              readOnlyStartAtIso: requestStartAtIso,
                              readOnlyLockAtIso: requestLockAtIso,
                              requestUpdatedAtIso: req['updatedAt']?.toString(),
                            ),
                          ),
                        );
                      },
                      onBlockStudent: () => _blockStudentFromRequest(req),
                      onUnblockStudent: () async {
                        if (widget.trainerId == null) return;
                        final sid = int.tryParse(
                          (req['studentId'] ?? '').toString(),
                        );
                        if (sid == null) return;
                        try {
                          await AuthService.unblockStudent(
                            widget.trainerId!,
                            sid,
                          );
                          if (!mounted) return;
                          setState(() {
                            _blockedStudentIds = {..._blockedStudentIds}
                              ..remove(sid);
                          });
                          _showSnack(
                            'Aluno desbloqueado',
                            icon: Icons.lock_open_rounded,
                            color: const Color(0xFF22C55E),
                          );
                        } catch (e) {
                          _showSnack(
                            e.toString().replaceFirst('Exception: ', ''),
                            icon: Icons.error_outline_rounded,
                            color: const Color(0xFFEF4444),
                          );
                        }
                      },
                      onDelete: () async {
                        try {
                          final reqId = req['id'] is int
                              ? req['id'] as int
                              : int.parse(req['id'].toString());
                          final previousStatus = (req['status'] ?? '').toString();
                          if (previousStatus == 'PENDING') {
                            await _sendDecisionAutoMessage(
                              req,
                              approved: false,
                            );
                          }
                          await AuthService.hideRequestForTrainer(reqId);
                          if (!mounted) return;
                          setState(() {
                            _hiddenRequestIds.add(reqId);
                            if (previousStatus == 'PENDING') {
                              _releaseRequestSlotsFromSchedule(req);
                              _allTrainerRequests = _allTrainerRequests.where((r) {
                                final id = r['id'] is int
                                    ? r['id'] as int
                                    : int.tryParse((r['id'] ?? '').toString());
                                return id != reqId;
                              }).toList();
                            } else if (previousStatus == 'APPROVED') {
                              _allTrainerRequests = _allTrainerRequests.map((r) {
                                final id = r['id'] is int
                                    ? r['id'] as int
                                    : int.tryParse((r['id'] ?? '').toString());
                                if (id != reqId) return r;
                                return {
                                  ...r,
                                  'hiddenForTrainer': true,
                                };
                              }).toList();
                            } else {
                              _allTrainerRequests = _allTrainerRequests.where((r) {
                                final id = r['id'] is int
                                    ? r['id'] as int
                                    : int.tryParse((r['id'] ?? '').toString());
                                return id != reqId;
                              }).toList();
                            }
                          });
                          _showSnack(
                            'Solicitação removida da sua lista',
                            icon: Icons.visibility_off_rounded,
                            color: const Color(0xFF0B4DBA),
                          );
                        } catch (e) {
                          _showSnack(
                            e.toString().replaceFirst('Exception: ', ''),
                            icon: Icons.error_outline_rounded,
                            color: const Color(0xFFEF4444),
                          );
                        }
                      },
                      onConfirm: () async {
                        final status = (req['status'] ?? '').toString();
                        if (status != 'PENDING') return;
                        try {
                          final reqId = req['id'] is int
                              ? req['id'] as int
                              : int.parse(req['id'].toString());
                          await AuthService.updateRequestStatus(
                            reqId,
                            'APPROVED',
                          );
                          await _sendDecisionAutoMessage(
                            req,
                            approved: true,
                          );
                          // Atualização otimista (sem materializar bloqueio manual base)
                          setState(() {
                            // Adiciona aluno imediatamente em Meus Alunos
                            final sid = req['studentId']?.toString();
                            final alreadyIn = _myStudents.any(
                              (s) => s['studentId']?.toString() == sid,
                            );
                            if (!alreadyIn) {
                              _myStudents = List.from(_myStudents)
                                ..add(Map<String, dynamic>.from(req));
                            }
                          });
                          _showSnack(
                            'Solicitação aprovada!',
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF22C55E),
                          );
                          _loadRequests();
                          _loadMyStudents();
                        } catch (e) {
                          _showSnack(
                            e.toString().replaceFirst('Exception: ', ''),
                            icon: Icons.error_outline_rounded,
                            color: const Color(0xFFEF4444),
                          );
                        }
                      },
                      onReject: () async {
                        final status = (req['status'] ?? '').toString();
                        if (status != 'PENDING') return;
                        try {
                          final reqId = req['id'] is int
                              ? req['id'] as int
                              : int.parse(req['id'].toString());
                          await _sendDecisionAutoMessage(
                            req,
                            approved: false,
                          );
                          await AuthService.updateRequestStatus(
                            reqId,
                            'REJECTED',
                          );
                          if (mounted) {
                            setState(() {
                              _releaseRequestSlotsFromSchedule(req);
                            });
                          }
                          _showSnack(
                            'Solicitação recusada',
                            icon: Icons.cancel_rounded,
                            color: const Color(0xFFEF4444),
                          );
                          _loadRequests();
                        } catch (e) {
                          _showSnack(
                            e.toString().replaceFirst('Exception: ', ''),
                            icon: Icons.error_outline_rounded,
                            color: const Color(0xFFEF4444),
                          );
                        }
                      },
                    ),
                ],
              );
            })(),
    );
  }
}

// ─── _RequestRow ──────────────────────────────────────────────────────────────

class _RequestRow extends StatelessWidget {
  final String studentName;
  final int requestId;
  final String dayName;
  final String time;
  final String status;
  final bool studentBlocked;
  final String planType;
  final String? daysJson;
  final String? approvedAtIso;
  final String? createdAtIso;
  final VoidCallback onChat;
  final VoidCallback onBlockStudent;
  final VoidCallback? onUnblockStudent;
  final VoidCallback onDelete;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _RequestRow({
    required this.studentName,
    required this.requestId,
    required this.dayName,
    required this.time,
    this.status = 'PENDING',
    this.studentBlocked = false,
    this.planType = 'DIARIO',
    this.daysJson,
    this.approvedAtIso,
    this.createdAtIso,
    required this.onChat,
    required this.onBlockStudent,
    this.onUnblockStudent,
    required this.onDelete,
    required this.onConfirm,
    required this.onReject,
  });

  static (Color fg, Color bg, String label, IconData icon) _planStyle(
    String pt,
  ) {
    switch (pt) {
      case 'SEMANAL':
        return (
          const Color(0xFF1D4ED8),
          const Color(0xFFEFF6FF),
          'Plano Semanal',
          Icons.event_repeat_rounded,
        );
      case 'MENSAL':
        return (
          const Color(0xFF059669),
          const Color(0xFFECFDF3),
          'Plano Mensal',
          Icons.calendar_month_rounded,
        );
      default:
        return (
          const Color(0xFFB45309),
          const Color(0xFFFFFBEB),
          'Aula Avulsa',
          Icons.flash_on_rounded,
        );
    }
  }

  List<Map<String, String>> _parseDays() {
    if (daysJson == null || daysJson!.isEmpty) return [];
    try {
      final list = jsonDecode(daysJson!) as List;
      return list
          .map(
            (e) => {
              'dayName': e['dayName'].toString(),
              'time': e['time'].toString(),
              'dateLabel': (e['dateLabel'] ?? '').toString(),
              'dateIso': (e['dateIso'] ?? '').toString(),
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _normalizeDay(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .trim();
  }

  int? _weekdayFromPt(String dayName) {
    switch (_normalizeDay(dayName)) {
      case 'segunda':
        return DateTime.monday;
      case 'terca':
        return DateTime.tuesday;
      case 'quarta':
        return DateTime.wednesday;
      case 'quinta':
        return DateTime.thursday;
      case 'sexta':
        return DateTime.friday;
      case 'sabado':
        return DateTime.saturday;
      case 'domingo':
        return DateTime.sunday;
      default:
        return null;
    }
  }

  (int hour, int minute)? _parseHourMinute(String time) {
    final parts = time.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  String _normalizeTime(String value) {
    final text = value.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return text;
    final hh = (int.tryParse(match.group(1) ?? '') ?? 0)
        .toString()
        .padLeft(2, '0');
    final mm = (int.tryParse(match.group(2) ?? '') ?? 0)
        .toString()
        .padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime _nextOccurrence(DateTime base, int weekday, int hour, int minute) {
    final sameDayAtTime = DateTime(base.year, base.month, base.day, hour, minute);
    var deltaDays = weekday - base.weekday;
    if (deltaDays < 0) deltaDays += 7;
    var candidate = sameDayAtTime.add(Duration(days: deltaDays));
    if (candidate.isBefore(base)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  DateTime _addOneMonthKeepingDay(DateTime date) {
    final nextMonth = date.month == 12 ? 1 : date.month + 1;
    final nextYear = date.month == 12 ? date.year + 1 : date.year;
    final maxDayNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
    final day = date.day <= maxDayNextMonth ? date.day : maxDayNextMonth;
    return DateTime(nextYear, nextMonth, day, date.hour, date.minute);
  }

  DateTime? _parseSlotDateMeta(
    Map<String, String> slot,
    int hour,
    int minute,
    DateTime anchor,
  ) {
    final iso = (slot['dateIso'] ?? '').trim();
    if (iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
      }
    }

    final dateLabel = (slot['dateLabel'] ?? '').trim();
    final full = RegExp(r'^(\d{2})\/(\d{2})\/(\d{4})$').firstMatch(dateLabel);
    if (full != null) {
      final day = int.tryParse(full.group(1)!);
      final month = int.tryParse(full.group(2)!);
      final year = int.tryParse(full.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, hour, minute);
      }
    }

    final short = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(dateLabel);
    if (short != null) {
      final day = int.tryParse(short.group(1)!);
      final month = int.tryParse(short.group(2)!);
      if (day != null && month != null) {
        return DateTime(anchor.year, month, day, hour, minute);
      }
    }

    return null;
  }

  String _slotChipLabel({
    required String dayName,
    required String time,
    String? dateLabel,
  }) {
    final safeDate = (dateLabel ?? '').trim();
    final safeTime = _normalizeTime(time);
    if (safeDate.isNotEmpty) {
      return '$dayName $safeDate · $safeTime';
    }
    return '$dayName · $safeTime';
  }

  String _formatDateLabel(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  List<String> _displaySlotLabels() {
    final slots = _parseDays().isNotEmpty
        ? _parseDays()
        : [
            {'dayName': dayName, 'time': time},
          ];

    if (planType.toUpperCase() != 'MENSAL') {
      return slots.map((slot) {
        final d = (slot['dayName'] ?? '').toString().trim();
        final t = (slot['time'] ?? '').toString().trim();
        final rawDate = (slot['dateLabel'] ?? '').toString().trim();
        final date = rawDate.isNotEmpty ? rawDate : _fallbackDateLabelForSlot(d, t);
        return _slotChipLabel(dayName: d, time: t, dateLabel: date);
      }).toList();
    }

    final anchor = DateTime.tryParse((createdAtIso ?? approvedAtIso ?? '').toString()) ??
        DateTime.now();

    final parsed = <Map<String, dynamic>>[];
    for (final slot in slots) {
      final d = (slot['dayName'] ?? '').toString().trim();
      final t = (slot['time'] ?? '').toString().trim();
      final weekday = _weekdayFromPt(d);
      final hm = _parseHourMinute(t);
      if (weekday == null || hm == null || d.isEmpty || t.isEmpty) continue;

      final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
      final startAt = fromMeta ?? _nextOccurrence(anchor, weekday, hm.$1, hm.$2);
      parsed.add({
        'dayName': d,
        'time': _normalizeTime(t),
        'weekday': weekday,
        'hour': hm.$1,
        'minute': hm.$2,
        'startAt': startAt,
      });
    }

    if (parsed.isEmpty) {
      return slots
          .map((slot) => _slotChipLabel(
                dayName: (slot['dayName'] ?? '').toString(),
                time: (slot['time'] ?? '').toString(),
                dateLabel: (slot['dateLabel'] ?? '').toString(),
              ))
          .toList();
    }

    parsed.sort((a, b) =>
        (a['startAt'] as DateTime).compareTo(b['startAt'] as DateTime));
    final first = parsed.first;
    final firstAt = first['startAt'] as DateTime;
    final windowEnd = _addOneMonthKeepingDay(firstAt);

    final patterns = <String, Map<String, dynamic>>{};
    for (final item in parsed) {
      final key = '${item['weekday']}|${item['time']}';
      patterns.putIfAbsent(key, () => item);
    }

    final firstKey = '${first['weekday']}|${first['time']}';
    final middle = patterns.entries
        .where((e) => e.key != firstKey)
        .map((e) => e.value)
        .toList();
    middle.sort((a, b) {
      final aNext = _nextOccurrence(
        firstAt,
        a['weekday'] as int,
        a['hour'] as int,
        a['minute'] as int,
      );
      final bNext = _nextOccurrence(
        firstAt,
        b['weekday'] as int,
        b['hour'] as int,
        b['minute'] as int,
      );
      return aNext.compareTo(bNext);
    });

    DateTime? lastAt;
    Map<String, dynamic>? lastPattern;
    for (final pattern in patterns.values) {
      var candidate = pattern['startAt'] as DateTime;
      while (candidate.add(const Duration(days: 7)).isBefore(windowEnd) ||
          candidate.add(const Duration(days: 7)).isAtSameMomentAs(windowEnd)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      if (candidate.isAfter(windowEnd)) continue;
      if (lastAt == null || candidate.isAfter(lastAt)) {
        lastAt = candidate;
        lastPattern = pattern;
      }
    }

    final labels = <String>[
      _slotChipLabel(
        dayName: first['dayName'] as String,
        time: first['time'] as String,
        dateLabel: _formatDateLabel(firstAt),
      ),
    ];
    for (final pattern in middle) {
      labels.add(
        _slotChipLabel(
          dayName: pattern['dayName'] as String,
          time: pattern['time'] as String,
        ),
      );
    }
    if (lastAt != null && lastPattern != null && lastAt.isAfter(firstAt)) {
      labels.add(
        _slotChipLabel(
          dayName: lastPattern['dayName'] as String,
          time: lastPattern['time'] as String,
          dateLabel: _formatDateLabel(lastAt),
        ),
      );
    }

    return labels;
  }

  DateTime? _resolveDailyExpiresAt() {
    final base = DateTime.tryParse((approvedAtIso ?? createdAtIso ?? '').toString());
    if (base == null) return null;

    final slots = _parseDays().isNotEmpty
        ? _parseDays()
        : [
            {'dayName': dayName, 'time': time},
          ];

    DateTime? lastSession;
    for (final slot in slots) {
      final weekday = _weekdayFromPt(slot['dayName'] ?? '');
      final hm = _parseHourMinute(slot['time'] ?? '');
      if (weekday == null || hm == null) continue;

      final fromMeta = _parseSlotDateMeta(
        {
          'dayName': (slot['dayName'] ?? '').toString(),
          'time': (slot['time'] ?? '').toString(),
          'dateLabel': (slot['dateLabel'] ?? '').toString(),
          'dateIso': (slot['dateIso'] ?? '').toString(),
        },
        hm.$1,
        hm.$2,
        base,
      );

      DateTime candidate;
      if (fromMeta != null) {
        candidate = fromMeta;
      } else {
        candidate = _nextOccurrence(base, weekday, hm.$1, hm.$2);
        if (weekday == base.weekday) {
          final sameDayScheduled = DateTime(
            base.year,
            base.month,
            base.day,
            hm.$1,
            hm.$2,
          );
          if (sameDayScheduled.isBefore(base)) {
            candidate = sameDayScheduled;
          }
        }
      }

      if (lastSession == null || candidate.isAfter(lastSession)) {
        lastSession = candidate;
      }
    }

    if (lastSession == null) return null;
    return lastSession.add(const Duration(hours: 1));
  }

  String _fallbackDateLabelForSlot(String dayName, String time) {
    final weekday = _weekdayFromPt(dayName);
    final hm = _parseHourMinute(time);
    if (weekday == null || hm == null) return '';

    final anchor = DateTime.tryParse((createdAtIso ?? approvedAtIso ?? '').toString()) ??
        DateTime.now();
    var candidate = _nextOccurrence(anchor, weekday, hm.$1, hm.$2);
    if (weekday == anchor.weekday) {
      final sameDayScheduled = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        hm.$1,
        hm.$2,
      );
      if (sameDayScheduled.isBefore(anchor)) {
        candidate = sameDayScheduled;
      }
    }

    final dd = candidate.day.toString().padLeft(2, '0');
    final mm = candidate.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  @override
  Widget build(BuildContext context) {
    final (planFg, planBg, planLabel, planIcon) = _planStyle(planType);
    final displaySlotLabels = _displaySlotLabels();
    final isPending = status == 'PENDING';
    final isApproved = status == 'APPROVED';
    final showChat = !isApproved;
    final isDailyExpired =
        planType.toUpperCase() == 'DIARIO' &&
        status == 'APPROVED' &&
        (() {
          final expiresAt = _resolveDailyExpiresAt();
          return expiresAt != null && DateTime.now().isAfter(expiresAt);
        })();
    final statusUi = isDailyExpired
        ? (
            const Color(0xFF6B7280),
            const Color(0xFFF3F4F6),
            'Encerrado',
            Icons.stop_circle_rounded,
          )
        : switch (status) {
      'APPROVED' => (
        const Color(0xFF166534),
        const Color(0xFFDCFCE7),
        'Aprovada',
        Icons.check_circle_rounded,
      ),
      'REJECTED' => (
        const Color(0xFFB91C1C),
        const Color(0xFFFEE2E2),
        'Recusada',
        Icons.cancel_rounded,
      ),
      _ => (
        const Color(0xFFB45309),
        const Color(0xFFFFFBEB),
        'Pendente',
        Icons.hourglass_top_rounded,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusUi.$1.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: statusUi.$2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusUi.$4, size: 18, color: statusUi.$1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studentName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusUi.$1.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusUi.$3,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusUi.$1,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: planBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(planIcon, size: 11, color: planFg),
                                const SizedBox(width: 4),
                                Text(
                                  planLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: planFg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: studentBlocked ? onUnblockStudent : onBlockStudent,
                  icon: Icon(
                    studentBlocked ? Icons.lock_open_rounded : Icons.block_outlined,
                    size: 14,
                  ),
                  label: Text(
                    studentBlocked ? 'Desbloquear aluno' : 'Bloquear aluno',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: studentBlocked
                        ? const Color(0xFF0B4DBA)
                        : const Color(0xFFB91C1C),
                    backgroundColor: studentBlocked
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFFEF2F2),
                    side: BorderSide(
                      color: studentBlocked
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFFFCA5A5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: displaySlotLabels
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: planBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: planFg.withValues(alpha: 0.18)),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: planFg,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('Excluir', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    backgroundColor: const Color(0xFFFEF2F2),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (showChat)
                  OutlinedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text('Chat', style: TextStyle(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0B4DBA),
                      backgroundColor: const Color(0xFFF8FBFF),
                      side: const BorderSide(color: Color(0xFFBFD3F5)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                if (isPending)
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Recusar', style: TextStyle(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      backgroundColor: const Color(0xFFFEF2F2),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                if (isPending)
                  ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Confirmar', style: TextStyle(fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── _StudentRow ──────────────────────────────────────────────────────────────

class _StudentRow extends StatelessWidget {
  final String studentName;
  final int? studentId;
  final int? trainerId;
  final bool blocked;
  final String? plansSummary;
  final String? planType;
  final String? dayName;
  final String? time;
  final String? daysJson;
  final VoidCallback? onChat;
  final VoidCallback onViewProfile;
  final VoidCallback onBlock;
  final VoidCallback? onUnblock;
  final VoidCallback? onRemove;
  final VoidCallback? onOrganizeWorkout;

  const _StudentRow({
    required this.studentName,
    this.studentId,
    this.trainerId,
    this.blocked = false,
    this.plansSummary,
    this.planType,
    this.dayName,
    this.time,
    this.daysJson,
    this.onChat,
    required this.onViewProfile,
    required this.onBlock,
    this.onUnblock,
    this.onRemove,
    this.onOrganizeWorkout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFD3F5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: ClipOval(
                child: studentId != null
                    ? Image.network(
                        AuthService.getUserPhotoUrl(studentId!),
                        fit: BoxFit.cover,
                        width: 44,
                        height: 44,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: studentName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Colors.black87,
                        ),
                      ),
                      TextSpan(
                        text: ' • ${_buildPlanAndScheduleText()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRemove != null) ...[
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.person_remove_rounded, size: 14),
                  label: const Text(
                    'Remover',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0B4DBA),
                    side: const BorderSide(color: Color(0xFF0B4DBA)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (onOrganizeWorkout != null) ...[
                OutlinedButton.icon(
                  onPressed: onOrganizeWorkout,
                  icon: const Icon(Icons.fitness_center_rounded, size: 14),
                  label: const Text(
                    'Organizar treino',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF065F46),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: blocked ? onUnblock : onBlock,
                icon: Icon(
                  blocked ? Icons.lock_open_rounded : Icons.block_outlined,
                  size: 14,
                ),
                label: Text(
                  blocked ? 'Desbloquear' : 'Bloquear',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: blocked
                      ? const Color(0xFF0B4DBA)
                      : const Color(0xFFB91C1C),
                  side: BorderSide(
                    color: blocked
                        ? const Color(0xFF0B4DBA)
                        : const Color(0xFFEF4444),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onViewProfile,
                icon: const Icon(Icons.person_outline_rounded, size: 15),
                label: const Text('Ver perfil', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B4DBA),
                  side: const BorderSide(color: Color(0xFF0B4DBA)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (onChat != null) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  label: const Text('Chat', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4DBA),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatPlanType(String? planType) {
    switch (planType?.trim().toUpperCase()) {
      case 'DIARIO':
        return 'Plano Diário';
      case 'SEMANAL':
        return 'Plano Semanal';
      case 'MENSAL':
        return 'Plano Mensal';
      default:
        return 'Aluno';
    }
  }

  int? _weekdayFromPt(String day) {
    switch (day.trim().toLowerCase()) {
      case 'segunda':
      case 'segunda-feira':
        return DateTime.monday;
      case 'terça':
      case 'terca':
      case 'terça-feira':
      case 'terca-feira':
        return DateTime.tuesday;
      case 'quarta':
      case 'quarta-feira':
        return DateTime.wednesday;
      case 'quinta':
      case 'quinta-feira':
        return DateTime.thursday;
      case 'sexta':
      case 'sexta-feira':
        return DateTime.friday;
      case 'sábado':
      case 'sabado':
        return DateTime.saturday;
      case 'domingo':
        return DateTime.sunday;
      default:
        return null;
    }
  }

  (int hour, int minute)? _parseHourMinute(String value) {
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  DateTime _nextOccurrence(DateTime base, int weekday, int hour, int minute) {
    final sameDayAtTime = DateTime(base.year, base.month, base.day, hour, minute);
    var deltaDays = weekday - base.weekday;
    if (deltaDays < 0) deltaDays += 7;
    var candidate = sameDayAtTime.add(Duration(days: deltaDays));
    if (candidate.isBefore(base)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  String _dateLabelFromIso(String iso) {
    final parsed = DateTime.tryParse(iso.trim());
    if (parsed == null) return '';
    final dd = parsed.day.toString().padLeft(2, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  String _fallbackDateLabelForSlot(String dayName, String time) {
    final weekday = _weekdayFromPt(dayName);
    final hm = _parseHourMinute(time);
    if (weekday == null || hm == null) return '';

    final candidate = _nextOccurrence(DateTime.now(), weekday, hm.$1, hm.$2);
    final dd = candidate.day.toString().padLeft(2, '0');
    final mm = candidate.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  DateTime _addOneMonthKeepingDay(DateTime date) {
    final nextMonth = date.month == 12 ? 1 : date.month + 1;
    final nextYear = date.month == 12 ? date.year + 1 : date.year;
    final maxDayNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
    final day = date.day <= maxDayNextMonth ? date.day : maxDayNextMonth;
    return DateTime(nextYear, nextMonth, day, date.hour, date.minute);
  }

  String _formatDateLabel(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  DateTime? _parseSlotDateMeta(
    Map<String, String> slot,
    int hour,
    int minute,
    DateTime anchor,
  ) {
    final iso = (slot['dateIso'] ?? '').trim();
    if (iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
      }
    }

    final dateLabel = (slot['dateLabel'] ?? '').trim();
    final full = RegExp(r'^(\d{2})\/(\d{2})\/(\d{4})$').firstMatch(dateLabel);
    if (full != null) {
      final day = int.tryParse(full.group(1)!);
      final month = int.tryParse(full.group(2)!);
      final year = int.tryParse(full.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, hour, minute);
      }
    }

    final short = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(dateLabel);
    if (short != null) {
      final day = int.tryParse(short.group(1)!);
      final month = int.tryParse(short.group(2)!);
      if (day != null && month != null) {
        return DateTime(anchor.year, month, day, hour, minute);
      }
    }

    return null;
  }

  List<String> _monthlySummaryLabels(List<Map<String, String>> slots) {
    if (slots.isEmpty) return const [];

    final anchor = DateTime.now();
    final parsed = <Map<String, dynamic>>[];
    for (final slot in slots) {
      final slotDay = (slot['dayName'] ?? '').trim();
      final slotTime = (slot['time'] ?? '').trim();
      final weekday = _weekdayFromPt(slotDay);
      final hm = _parseHourMinute(slotTime);
      if (slotDay.isEmpty || slotTime.isEmpty || weekday == null || hm == null) {
        continue;
      }

      final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
      final startAt = fromMeta ?? _nextOccurrence(anchor, weekday, hm.$1, hm.$2);
      parsed.add({
        'dayName': slotDay,
        'time': slotTime,
        'weekday': weekday,
        'hour': hm.$1,
        'minute': hm.$2,
        'startAt': startAt,
      });
    }

    if (parsed.isEmpty) {
      return slots.map((slot) {
        final slotDay = (slot['dayName'] ?? '').trim();
        final slotTime = (slot['time'] ?? '').trim();
        final rawDateLabel = (slot['dateLabel'] ?? '').trim();
        final isoDateLabel = _dateLabelFromIso((slot['dateIso'] ?? '').trim());
        final dateLabel = rawDateLabel.isNotEmpty
            ? rawDateLabel
            : (isoDateLabel.isNotEmpty
                ? isoDateLabel
                : _fallbackDateLabelForSlot(slotDay, slotTime));
        return dateLabel.isEmpty
            ? '$slotDay $slotTime'
            : '$slotDay $dateLabel $slotTime';
      }).toList();
    }

    parsed.sort((a, b) =>
        (a['startAt'] as DateTime).compareTo(b['startAt'] as DateTime));
    final first = parsed.first;
    final firstAt = first['startAt'] as DateTime;
    final windowEnd = _addOneMonthKeepingDay(firstAt);

    final patterns = <String, Map<String, dynamic>>{};
    for (final item in parsed) {
      final key = '${item['weekday']}|${item['time']}';
      patterns.putIfAbsent(key, () => item);
    }

    final firstKey = '${first['weekday']}|${first['time']}';
    final middle = patterns.entries
        .where((entry) => entry.key != firstKey)
        .map((entry) => entry.value)
        .toList();
    middle.sort((a, b) {
      final aNext = _nextOccurrence(
        firstAt,
        a['weekday'] as int,
        a['hour'] as int,
        a['minute'] as int,
      );
      final bNext = _nextOccurrence(
        firstAt,
        b['weekday'] as int,
        b['hour'] as int,
        b['minute'] as int,
      );
      return aNext.compareTo(bNext);
    });

    DateTime? lastAt;
    Map<String, dynamic>? lastPattern;
    for (final pattern in patterns.values) {
      var candidate = pattern['startAt'] as DateTime;
      while (candidate
              .add(const Duration(days: 7))
              .isAtSameMomentAs(windowEnd) ||
          candidate.add(const Duration(days: 7)).isBefore(windowEnd)) {
        candidate = candidate.add(const Duration(days: 7));
      }

      if (candidate.isAfter(windowEnd)) {
        continue;
      }

      if (lastAt == null || candidate.isAfter(lastAt)) {
        lastAt = candidate;
        lastPattern = pattern;
      }
    }

    final labels = <String>[
      '${first['dayName']} ${_formatDateLabel(firstAt)} ${first['time']}',
    ];
    for (final pattern in middle) {
      labels.add('${pattern['dayName']} ${pattern['time']}');
    }
    if (lastAt != null && lastPattern != null && lastAt.isAfter(firstAt)) {
      labels.add(
        '${lastPattern['dayName']} ${_formatDateLabel(lastAt)} ${lastPattern['time']}',
      );
    }

    return labels;
  }

  String _buildPlanAndScheduleText() {
    final planLabel = _formatPlanType(planType);
    final normalizedPlanType = planType?.trim().toUpperCase();

    String scheduleLabel = '';

    final day = (dayName ?? '').trim();
    final hour = (time ?? '').trim();
    if ((daysJson ?? '').trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(daysJson!) as List<dynamic>;
        final slots = decoded
            .whereType<Map>()
            .map((slot) => {
                  'dayName': (slot['dayName'] ?? '').toString().trim(),
                  'time': (slot['time'] ?? '').toString().trim(),
                  'dateLabel': (slot['dateLabel'] ?? '').toString().trim(),
                  'dateIso': (slot['dateIso'] ?? '').toString().trim(),
                })
            .where((slot) => slot['dayName']!.isNotEmpty && slot['time']!.isNotEmpty)
            .toList();

        final labels = normalizedPlanType == 'MENSAL'
            ? _monthlySummaryLabels(slots)
            : slots.map((slot) {
                final slotDay = (slot['dayName'] ?? '').trim();
                final slotTime = (slot['time'] ?? '').trim();
                final rawDateLabel = (slot['dateLabel'] ?? '').trim();
                final isoDateLabel = _dateLabelFromIso((slot['dateIso'] ?? '').trim());
                final computedDate = rawDateLabel.isNotEmpty
                    ? rawDateLabel
                    : (isoDateLabel.isNotEmpty
                        ? isoDateLabel
                        : _fallbackDateLabelForSlot(slotDay, slotTime));
                return computedDate.isEmpty
                    ? '$slotDay $slotTime'
                    : '$slotDay $computedDate $slotTime';
              }).toList();

        if (labels.isNotEmpty) {
          scheduleLabel = labels.join(', ');
        }
      } catch (_) {}
    }

    if (scheduleLabel.isEmpty && day.isNotEmpty && hour.isNotEmpty) {
      final fallbackDate = _fallbackDateLabelForSlot(day, hour);
      scheduleLabel = fallbackDate.isEmpty
          ? '$day $hour'
          : '$day $fallbackDate $hour';
    }

    if (scheduleLabel.isEmpty) {
      final summary = (plansSummary ?? '').trim();
      if (summary.isNotEmpty) {
        return summary;
      }
    }

    if (scheduleLabel.isEmpty) {
      return planLabel;
    }
    return '$planLabel • $scheduleLabel';
  }
}

// ─── Widgets reutilizáveis ────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _BadgeChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  final String label;
  const _SpecialtyChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFD3F5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0B4DBA),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7EBF3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0B4DBA)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0B4DBA).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _DashSlotTile extends StatelessWidget {
  final _Slot slot;
  final VoidCallback onTap;
  final bool forceUnavailable;

  const _DashSlotTile({
    required this.slot,
    required this.onTap,
    this.forceUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final Color textColor;
    final IconData iconData;

    if (forceUnavailable) {
      bgColor = const Color(0xFFF9FAFB);
      borderColor = const Color(0xFFE5E7EB);
      iconColor = const Color(0xFFD1D5DB);
      textColor = const Color(0xFF9CA3AF);
      iconData = Icons.lock_rounded;
    } else {
      switch (slot.state) {
        case _SlotState.available:
          bgColor = const Color(0xFFF0FDF4);
          borderColor = const Color(0xFFBBF7D0);
          iconColor = const Color(0xFF22C55E);
          textColor = const Color(0xFF15803D);
          iconData = Icons.lock_open_rounded;
          break;
        case _SlotState.requested:
          bgColor = const Color(0xFFFFFBEB);
          borderColor = const Color(0xFFFDE68A);
          iconColor = const Color(0xFFF59E0B);
          textColor = const Color(0xFFB45309);
          iconData = Icons.hourglass_top_rounded;
          break;
        case _SlotState.unavailable:
          bgColor = const Color(0xFFF9FAFB);
          borderColor = const Color(0xFFE5E7EB);
          iconColor = const Color(0xFFD1D5DB);
          textColor = const Color(0xFF9CA3AF);
          iconData = Icons.lock_rounded;
          break;
      }
    }

    // Verifica se o slot está desabilitado
    final isDisabled = forceUnavailable ||
                       slot.state == _SlotState.requested || 
                       (slot.studentName ?? '').trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isDisabled ? 0.6 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconData, size: 17, color: iconColor),
                const SizedBox(height: 4),
                Text(
                  slot.time,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                if (slot.state == _SlotState.unavailable &&
                    (slot.studentName ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      slot.studentName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _CountBadge({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── _StatBox ─────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: color == const Color(0xFFE5E7EB)
                  ? const Color(0xFFD1D5DB)
                  : color.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
      ],
    );
  }
}
