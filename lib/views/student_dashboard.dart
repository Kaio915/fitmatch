import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'trainer_chat_view.dart';
import 'trainer_profile_view.dart';
import 'student_workout_view.dart';
import 'diet_control_view.dart';
import '../widgets/fitmatch_logo.dart';

// ─── Student Dashboard ────────────────────────────────────────────────────────

class StudentDashboard extends StatefulWidget {
  final int? studentId;
  final String userName;
  final String? email;
  final String? objetivos;
  final String? nivel;

  const StudentDashboard({
    super.key,
    this.studentId,
    required this.userName,
    this.email,
    this.objetivos,
    this.nivel,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _pageScrollController = ScrollController();

  final TextEditingController _searchCtrl = TextEditingController();
  String _filterMode = 'Todos';
  List<Map<String, dynamic>> _allTrainers = [];
  List<Map<String, dynamic>> _filteredTrainers = [];
  bool _loadingTrainers = false;
  String? _trainersError;
  bool _trainersFetched = false;
  bool _searchHasRun = false; // novo: só mostra resultados após pesquisar

  // Solicitações do aluno
  List<Map<String, dynamic>> _myRequests = [];
  final Set<String> _locallyHiddenRequestIds = <String>{};
  bool _loadingMyRequests = false;
  String? _myRequestsError;

  // Trainers que o aluno segue
  List<Map<String, dynamic>> _myConnections = [];
  final Map<int, double> _followingAvgRatings = {};
  final Map<int, int> _followingAvailableSlots = {};
  bool _loadingConnections = false;

  // Avaliações recebidas do aluno
  List<Map<String, dynamic>> _receivedRatings = [];
  bool _loadingReceivedRatings = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    // NÃO carrega trainers ao abrir (busca lazy)
    // Carrega solicitações do aluno
    if (widget.studentId != null) {
      _loadHiddenRequestIds().then((_) => _loadMyRequests());
      _loadConnections();
      _loadReceivedRatings();
    }
  }

  String get _hiddenRequestsStorageKey =>
      'student_hidden_requests_${widget.studentId ?? 0}';

  Future<void> _loadHiddenRequestIds() async {
    if (widget.studentId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_hiddenRequestsStorageKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _locallyHiddenRequestIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _persistHiddenRequestIds() async {
    if (widget.studentId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _hiddenRequestsStorageKey,
      _locallyHiddenRequestIds.toList(),
    );
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    // Recarrega sempre que o aluno abre as abas, para refletir mudanças recentes
    if (_tabController.index == 3 && widget.studentId != null) {
      _loadMyRequests();
    }
    if (_tabController.index == 2 && widget.studentId != null) {
      _loadConnections();
    }
    if (_tabController.index == 0 && widget.studentId != null) {
      _loadMyRequests();
      _loadConnections();
      _loadReceivedRatings();
    }
  }

  Future<void> _loadTrainers() async {
    setState(() {
      _loadingTrainers = true;
      _trainersError = null;
    });
    try {
      final trainers = await AuthService.fetchTrainers(
        studentId: widget.studentId,
      );
      final trainersWithAvailability = await _attachAvailableSlots(trainers);
      if (!mounted) return;
      setState(() {
        _allTrainers = trainersWithAvailability;
        _loadingTrainers = false;
        _trainersFetched = true;
      });
      // Após carregar, aplica o filtro já digitado
      _runSearch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trainersError = e.toString().replaceFirst('Exception: ', '');
        _loadingTrainers = false;
        _trainersFetched = true;
      });
    }
  }

  void _runSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _searchHasRun = false;
        _filteredTrainers = [];
      });
      return;
    }
    setState(() {
      _searchHasRun = true;
      _filteredTrainers = _allTrainers.where((t) {
        final name = (t['name'] ?? '').toString().toLowerCase();
        final city = (t['cidade'] ?? '').toString().toLowerCase();
        final spec = (t['especialidade'] ?? '').toString().toLowerCase();
        switch (_filterMode) {
          case 'Cidade':
            return city.contains(q);
          case 'Especialidade':
            return spec.contains(q);
          case 'Nome':
            return name.contains(q);
          default:
            return name.contains(q) || spec.contains(q) || city.contains(q);
        }
      }).toList();
    });
  }

  DateTime? _parseIsoDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  List<Map<String, dynamic>> _attachChatWindowToRequests(
    List<Map<String, dynamic>> requests,
  ) {
    final enriched = requests
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    for (final current in enriched) {
      final trainerId = current['trainerId']?.toString();
      final studentId = current['studentId']?.toString();
      final currentCreatedAt = _parseIsoDateTime(current['createdAt']);

      DateTime? nextNewerCreatedAt;
      if (trainerId != null && studentId != null && currentCreatedAt != null) {
        for (final other in enriched) {
          final otherTrainerId = other['trainerId']?.toString();
          final otherStudentId = other['studentId']?.toString();
          if (otherTrainerId != trainerId || otherStudentId != studentId) {
            continue;
          }

          final otherCreatedAt = _parseIsoDateTime(other['createdAt']);
          if (otherCreatedAt == null || !otherCreatedAt.isAfter(currentCreatedAt)) {
            continue;
          }

          if (nextNewerCreatedAt == null ||
              otherCreatedAt.isBefore(nextNewerCreatedAt)) {
            nextNewerCreatedAt = otherCreatedAt;
          }
        }
      }

      // Quando existe solicitação mais nova no mesmo par, encerra a janela
      // da solicitação atual exatamente no início do próximo ciclo.
      final lockAt = nextNewerCreatedAt;

      current['chatStartAtIso'] = current['createdAt']?.toString();
      current['chatLockAtIso'] = lockAt?.toIso8601String();
    }

    return enriched;
  }

  Future<void> _loadMyRequests() async {
    if (widget.studentId == null) return;
    setState(() {
      _loadingMyRequests = true;
      _myRequestsError = null;
    });
    try {
      final reqs = await AuthService.getStudentRequests(widget.studentId!);
      final reqsWithChatWindow = _attachChatWindowToRequests(reqs);
      if (!mounted) return;
      setState(() {
        _myRequests = reqsWithChatWindow
            .where(
              (r) => !_locallyHiddenRequestIds.contains(
                (r['id'] ?? '').toString(),
              ),
            )
            .toList();
        _loadingMyRequests = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _myRequestsError = e.toString().replaceFirst('Exception: ', '');
        _loadingMyRequests = false;
      });
    }
  }

  Future<void> _loadConnections() async {
    if (widget.studentId == null) return;
    setState(() => _loadingConnections = true);
    try {
      final conns = await AuthService.getStudentConnections(widget.studentId!);
      await _loadFollowingStats(conns);
      if (!mounted) return;
      setState(() {
        _myConnections = conns;
        _loadingConnections = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingConnections = false;
      });
    }
  }

  List<Map<String, String>> _requestSlotsFromData(Map<String, dynamic> req) {
    final raw = req['daysJson']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final parsed = decoded
            .whereType<Map>()
            .map((slot) => {
                  'dayName': (slot['dayName'] ?? '').toString(),
                  'time': (slot['time'] ?? '').toString(),
                  'dateLabel': (slot['dateLabel'] ?? '').toString(),
                  'dateIso': (slot['dateIso'] ?? '').toString(),
                })
            .where((slot) =>
                slot['dayName']!.isNotEmpty && slot['time']!.isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {}
    }

    final dayName = (req['dayName'] ?? '').toString();
    final time = (req['time'] ?? '').toString();
    if (dayName.isEmpty || time.isEmpty) return [];
    return [
      {'dayName': dayName, 'time': time, 'dateLabel': '', 'dateIso': ''}
    ];
  }

  String _normalizeDayName(String value) {
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

  int? _weekdayFromPt(String dayName) {
    switch (_normalizeDayName(dayName)) {
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

  String _dayNameFromWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Segunda';
      case DateTime.tuesday:
        return 'Terça';
      case DateTime.wednesday:
        return 'Quarta';
      case DateTime.thursday:
        return 'Quinta';
      case DateTime.friday:
        return 'Sexta';
      case DateTime.saturday:
        return 'Sábado';
      case DateTime.sunday:
        return 'Domingo';
      default:
        return '';
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

  DateTime _requestAnchor(Map<String, dynamic> req) {
    return DateTime.tryParse((req['createdAt'] ?? '').toString()) ?? DateTime.now();
  }

  DateTime? _firstSessionStartAt(Map<String, dynamic> req) {
    final slots = _requestSlotsFromData(req);
    if (slots.isEmpty) return null;
    final anchor = _requestAnchor(req);

    DateTime? first;
    for (final slot in slots) {
      final weekday = _weekdayFromPt((slot['dayName'] ?? '').toString());
      final hm = _parseHourMinute((slot['time'] ?? '').toString());
      if (weekday == null || hm == null) continue;

      final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
      var candidate = fromMeta ?? _nextOccurrence(anchor, weekday, hm.$1, hm.$2);
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

      if (first == null || candidate.isBefore(first)) {
        first = candidate;
      }
    }

    return first;
  }

  bool _isPendingOccupyingDateTime(
    Map<String, dynamic> req,
    DateTime candidate,
    String candidateDayName,
    String candidateTime,
  ) {
    final planType = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
    final slots = _requestSlotsFromData(req);
    if (slots.isEmpty) return false;

    final normalizedCandidateDay = _normalizeDayName(candidateDayName);
    final normalizedCandidateTime = _normalizeTimeValue(candidateTime);
    final anchor = _requestAnchor(req);
    final firstSession = _firstSessionStartAt(req);
    final monthlyEnd = firstSession != null ? _addOneMonthKeepingDay(firstSession) : null;

    for (final slot in slots) {
      final day = _normalizeDayName((slot['dayName'] ?? '').toString());
      final time = _normalizeTimeValue((slot['time'] ?? '').toString());
      if (day != normalizedCandidateDay || time != normalizedCandidateTime) {
        continue;
      }

      final weekday = _weekdayFromPt((slot['dayName'] ?? '').toString());
      final hm = _parseHourMinute((slot['time'] ?? '').toString());
      if (weekday == null || hm == null) continue;

      final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
      final slotStart = fromMeta ?? _nextOccurrence(anchor, weekday, hm.$1, hm.$2);

      if (planType == 'DIARIO') {
        final sameMoment =
            candidate.year == slotStart.year &&
            candidate.month == slotStart.month &&
            candidate.day == slotStart.day &&
            candidate.hour == slotStart.hour &&
            candidate.minute == slotStart.minute;
        if (sameMoment) return true;
        continue;
      }

      if (candidate.isBefore(slotStart)) continue;
      final diffDays = candidate.difference(slotStart).inDays;
      if (diffDays % 7 != 0) continue;

      if (planType == 'MENSAL') {
        if (monthlyEnd == null || candidate.isAfter(monthlyEnd)) continue;
      }

      return true;
    }

    return false;
  }

  int _countTrainerAvailableSlots(
    List<Map<String, dynamic>> blockedSlots,
    List<Map<String, dynamic>> activeRequests,
  ) {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(now.year, now.month + 1, 0);

    final blockedRecurring = <String>{};
    final blockedOneTime = <String>{};
    for (final slot in blockedSlots) {
      final state = (slot['state'] ?? '').toString().toUpperCase();
      if (state == 'REQUEST') {
        continue;
      }

      final day = _normalizeDayName((slot['dayName'] ?? '').toString());
      final time = _normalizeTimeValue((slot['time'] ?? '').toString());
      final dateIsoRaw = (slot['dateIso'] ?? '').toString().trim();
      final dateIso = dateIsoRaw.length >= 10
          ? dateIsoRaw.substring(0, 10)
          : dateIsoRaw;
      final repeatMode = (slot['repeatMode'] ?? '').toString().toUpperCase();

      if (day.isEmpty || time.isEmpty) continue;

      if (dateIso.isNotEmpty || repeatMode == 'ONCE') {
        if (dateIso.isNotEmpty) {
          blockedOneTime.add('$dateIso|$day|$time');
        }
      } else {
        blockedRecurring.add('$day|$time');
      }
    }

    var available = 0;
    for (
      DateTime date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final dayName = _dayNameFromWeekday(date.weekday);
      final normalizedDay = _normalizeDayName(dayName);
      final dateIso = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      for (int h = 0; h < 24; h++) {
        final time = '${h.toString().padLeft(2, '0')}:00';
        final candidate = DateTime(date.year, date.month, date.day, h, 0);
        if (candidate.isBefore(now)) continue;

        final recurringKey = '$normalizedDay|$time';
        if (blockedRecurring.contains(recurringKey)) {
          continue;
        }

        final oneTimeKey = '$dateIso|$normalizedDay|$time';
        if (blockedOneTime.contains(oneTimeKey)) {
          continue;
        }

        final occupiedByPending = activeRequests.any((req) {
          final status = (req['status'] ?? '').toString().toUpperCase();
          if (status != 'PENDING' && status != 'APPROVED') {
            return false;
          }
          return _isPendingOccupyingDateTime(req, candidate, dayName, time);
        });
        if (occupiedByPending) {
          continue;
        }

        available++;
      }
    }

    return available;
  }

  Future<List<Map<String, dynamic>>> _attachAvailableSlots(
    List<Map<String, dynamic>> trainers,
  ) async {
    final enriched = <Map<String, dynamic>>[];

    for (final trainer in trainers) {
      final trainerId = trainer['id'] is num
          ? (trainer['id'] as num).toInt()
          : int.tryParse((trainer['id'] ?? '').toString());

      if (trainerId == null) {
        enriched.add({...trainer, 'availableSlots': 0});
        continue;
      }

      try {
        final results = await Future.wait([
          AuthService.getTrainerSlots(trainerId),
          AuthService.getAllTrainerRequests(trainerId),
        ]);
        final blocked = results[0];
        final active = results[1]
            .where((req) {
              final status = (req['status'] ?? '').toString().toUpperCase();
              return status == 'PENDING' || status == 'APPROVED';
            })
            .toList();

        enriched.add({
          ...trainer,
          'availableSlots': _countTrainerAvailableSlots(blocked, active),
        });
      } catch (_) {
        enriched.add({...trainer, 'availableSlots': 0});
      }
    }

    return enriched;
  }

  Future<void> _loadFollowingStats(List<Map<String, dynamic>> connections) async {
    final ids = connections
        .map((conn) => conn['trainerId'])
        .where((id) => id != null)
        .map((id) => (id as num).toInt())
        .toSet()
        .toList();

    final avgMap = <int, double>{};
    final availableMap = <int, int>{};

    for (final trainerId in ids) {
      try {
        final results = await Future.wait([
          AuthService.getTrainerRatings(trainerId),
          AuthService.getTrainerSlots(trainerId),
          AuthService.getAllTrainerRequests(trainerId),
        ]);

        final ratings = results[0];
        final blocked = results[1];
        final active = results[2]
            .where((req) {
              final status = (req['status'] ?? '').toString().toUpperCase();
              return status == 'PENDING' || status == 'APPROVED';
            })
            .toList();

        if (ratings.isNotEmpty) {
          final sum = ratings.fold<int>(
            0,
            (acc, r) => acc + ((r['stars'] as num?)?.toInt() ?? 0),
          );
          avgMap[trainerId] = sum / ratings.length;
        } else {
          avgMap[trainerId] = 0;
        }

        availableMap[trainerId] = _countTrainerAvailableSlots(blocked, active);
      } catch (_) {
        avgMap[trainerId] = avgMap[trainerId] ?? 0;
        availableMap[trainerId] = availableMap[trainerId] ?? 0;
      }
    }

    if (!mounted) return;
    setState(() {
      _followingAvgRatings
        ..clear()
        ..addAll(avgMap);
      _followingAvailableSlots
        ..clear()
        ..addAll(availableMap);
    });
  }

  Future<void> _loadReceivedRatings() async {
    if (widget.studentId == null) return;
    setState(() => _loadingReceivedRatings = true);
    try {
      final ratings = await AuthService.getStudentRatings(widget.studentId!);
      if (!mounted) return;
      setState(() {
        _receivedRatings = ratings;
        _loadingReceivedRatings = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingReceivedRatings = false;
      });
    }
  }

  double get _avgReceivedRating {
    if (_receivedRatings.isEmpty) return 0;
    final sum = _receivedRatings.fold<int>(
      0,
      (acc, r) => acc + ((r['stars'] as num?)?.toInt() ?? 0),
    );
    return sum / _receivedRatings.length;
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pageScrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildProfileCard(
                      widget.studentId != null
                          ? AuthService.getUserPhotoUrl(widget.studentId!)
                          : null,
                    ),
                    const SizedBox(height: 20),
                    _buildTabs(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _tabMeuPersonal(),
                          _tabBuscar(),
                          _tabSeguindo(),
                          _tabSolicitacoes(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B4DBA), Color(0xFF1A6BE8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              const FitMatchLogo(height: 40, onDarkBackground: true),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Sair',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
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
    final sid = widget.studentId;
    if (sid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o controle de dieta.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DietControlView(
          userId: sid,
          userName: widget.userName,
          isTrainerSide: false,
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

  Widget _buildProfileCard(String? photoUrl) {
    final nivel = widget.nivel ?? '';
    final objetivos = widget.objetivos ?? '';
    final email = (widget.email ?? '').trim();
    final firstName = widget.userName.split(' ').first;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Banner
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0B4DBA),
                      Color(0xFF1565E8),
                      Color(0xFF2196F3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -10,
                      right: 80,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 18,
                      right: 22,
                      child: Opacity(
                        opacity: 0.75,
                        child: FitMatchLogo(
                          height: 28,
                          onDarkBackground: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Avatar
              Positioned(
                bottom: -46,
                left: 24,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE8F0FE), Color(0xFFD0E4FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B4DBA).withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            width: 92,
                            height: 92,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(
                                Icons.person_rounded,
                                size: 42,
                                color: Color(0xFF0B4DBA),
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 42,
                              color: Color(0xFF0B4DBA),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 56),
          // Dados
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Olá, $firstName!',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              email,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.black38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Divisor
                Container(height: 1, color: const Color(0xFFF0F4FB)),
                const SizedBox(height: 16),
                // Info chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const _Chip(
                      icon: Icons.school_outlined,
                      label: 'Aluno',
                      color: Color(0xFF0B4DBA),
                    ),
                    if (nivel.isNotEmpty)
                      _Chip(
                        icon: Icons.bar_chart_rounded,
                        label: nivel,
                        color: const Color(0xFF059669),
                      ),
                    if (objetivos.isNotEmpty)
                      _Chip(
                        icon: Icons.track_changes_rounded,
                        label: objetivos,
                        color: const Color(0xFFD97706),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: const Color(0xFFF0F4FB)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Avaliações dos Personais',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    if (_receivedRatings.isNotEmpty)
                      Text(
                        '${_avgReceivedRating.toStringAsFixed(1)} (${_receivedRatings.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loadingReceivedRatings)
                  const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0B4DBA),
                      ),
                    ),
                  )
                else if (_receivedRatings.isEmpty)
                  const Text(
                    'Você ainda não recebeu avaliações dos personais.',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  )
                else
                  Column(
                    children: _receivedRatings.take(3).map((r) {
                      final trainerName =
                          (r['trainerName'] ?? 'Personal').toString();
                      final stars = (r['stars'] as num?)?.toInt() ?? 0;
                      final comment = (r['comment'] ?? '').toString().trim();
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2EBFF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    trainerName,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(5, (i) {
                                    return Icon(
                                      i < stars
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      size: 13,
                                      color: const Color(0xFFF59E0B),
                                    );
                                  }),
                                ),
                              ],
                            ),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                comment,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B4DBA).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.black45,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Meu Personal'),
          Tab(text: 'Buscar'),
          Tab(text: 'Seguindo'),
          Tab(text: 'Solicitações'),
        ],
      ),
    );
  }

  // ─ Aba: Meu Personal ────────────────────────────────────────────────────────────────

  Widget _tabMeuPersonal() {
    final approvedRequests = _myRequests
        .where((r) => (r['status'] ?? '').toString() == 'APPROVED')
        .toList();
    final groupedApproved = <Map<String, dynamic>>[];
    final groupedIndex = <String, int>{};
    for (final req in approvedRequests) {
      final trainerKey = (req['trainerId'] ?? req['trainerName'] ?? '').toString();
      final existingIndex = groupedIndex[trainerKey];
      if (existingIndex == null) {
        groupedIndex[trainerKey] = groupedApproved.length;
        groupedApproved.add({
          'trainerId': req['trainerId'],
          'trainerName': req['trainerName'],
          'plans': [req],
        });
      } else {
        final plans = List<Map<String, dynamic>>.from(
          groupedApproved[existingIndex]['plans'] as List,
        )..add(req);
        groupedApproved[existingIndex] = {
          ...groupedApproved[existingIndex],
          'plans': plans,
        };
      }
    }

    Future<void> handleExpiredPlanAction(
      Map<String, dynamic> plan, {
      required bool changePlan,
    }) async {
      final requestId = int.tryParse((plan['id'] ?? '').toString());
      final trainerName = (plan['trainerName'] ?? 'Personal').toString();
      if (requestId == null) {
        return;
      }

      final title = changePlan
          ? 'Mudar plano vencido?'
          : 'Encerrar plano vencido?';
      final description = changePlan
          ? 'Seu plano com $trainerName venceu. Para mudar o plano, vamos encerrar o plano atual e você poderá enviar uma nova solicitação.'
          : 'Seu plano com $trainerName venceu. Deseja encerrar este plano agora?';

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white,
              ),
              child: Text(changePlan ? 'Mudar plano' : 'Encerrar plano'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      Future<void> openTrainerProfileForPlan(Map<String, dynamic> selectedPlan) async {
        final trainerId = int.tryParse((selectedPlan['trainerId'] ?? '').toString());
        if (trainerId == null || widget.studentId == null) {
          _tabController.animateTo(1);
          return;
        }

        final navigator = Navigator.of(context);
        Map<String, dynamic>? trainerData;
        try {
          trainerData = await AuthService.getUserById(trainerId);
        } catch (_) {
          trainerData = null;
        }

        if (!mounted) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => TrainerProfileView(
              trainerId: trainerId,
              studentId: widget.studentId,
              studentName: widget.userName,
              trainerName: (trainerData?['name'] ?? selectedPlan['trainerName'] ?? 'Personal').toString(),
              specialties: (trainerData?['especialidade'] ?? '').toString(),
              city: trainerData?['cidade']?.toString(),
              cref: trainerData?['cref']?.toString(),
              price: trainerData?['valorHora']?.toString(),
              bio: trainerData?['bio']?.toString(),
              horasPorSessao: trainerData?['horasPorSessao']?.toString(),
            ),
          ),
        );

        if (!mounted) return;
        await _loadMyRequests();
        await _loadConnections();
      }

      try {
        await AuthService.cancelStudentRequest(
          requestId,
          reason: changePlan ? 'CHANGE_PLAN' : null,
        );
        await _loadMyRequests();
        await _loadConnections();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changePlan
                  ? 'Plano encerrado. Você será direcionado ao perfil do personal para escolher o novo plano.'
                  : 'Plano encerrado com sucesso.',
            ),
          ),
        );

        if (changePlan) {
          await openTrainerProfileForPlan(plan);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
      }
    }

    DateTime _nextOccurrenceForRenewal(String dayName, String time) {
      String normalized = dayName
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

      int weekday;
      switch (normalized) {
        case 'segunda':
          weekday = DateTime.monday;
          break;
        case 'terca':
          weekday = DateTime.tuesday;
          break;
        case 'quarta':
          weekday = DateTime.wednesday;
          break;
        case 'quinta':
          weekday = DateTime.thursday;
          break;
        case 'sexta':
          weekday = DateTime.friday;
          break;
        case 'sabado':
          weekday = DateTime.saturday;
          break;
        case 'domingo':
          weekday = DateTime.sunday;
          break;
        default:
          weekday = DateTime.monday;
      }

      final parts = time.split(':');
      final hour = parts.isNotEmpty ? int.tryParse(parts[0].trim()) ?? 0 : 0;
      final minute = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;

      final now = DateTime.now();
      final sameDayAtTime = DateTime(now.year, now.month, now.day, hour, minute);
      var deltaDays = weekday - now.weekday;
      if (deltaDays < 0) deltaDays += 7;
      var candidate = sameDayAtTime.add(Duration(days: deltaDays));
      if (!candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      return candidate;
    }

    String _toDateIso(DateTime value) {
      final yyyy = value.year.toString().padLeft(4, '0');
      final mm = value.month.toString().padLeft(2, '0');
      final dd = value.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    }

    String _toDateLabel(DateTime value) {
      final dd = value.day.toString().padLeft(2, '0');
      final mm = value.month.toString().padLeft(2, '0');
      return '$dd/$mm';
    }

    Future<void> handleRenewSamePlan(Map<String, dynamic> plan) async {
      final requestId = int.tryParse((plan['id'] ?? '').toString());
      final trainerId = int.tryParse((plan['trainerId'] ?? '').toString());
      final trainerName = (plan['trainerName'] ?? 'Personal').toString();
      final planType = (plan['planType'] ?? 'DIARIO').toString();

      if (widget.studentId == null || requestId == null || trainerId == null) {
        return;
      }

      final rawSlots = _RequestItem._parseDays(plan['daysJson']?.toString());
      final slots = rawSlots.isNotEmpty
          ? rawSlots
          : [
              {
                'dayName': (plan['dayName'] ?? '').toString(),
                'time': (plan['time'] ?? '').toString(),
              },
            ];

      final validSlots = slots
          .map((slot) => {
                'dayName': (slot['dayName'] ?? '').toString().trim(),
                'time': (slot['time'] ?? '').toString().trim(),
              })
          .where((slot) => slot['dayName']!.isNotEmpty && slot['time']!.isNotEmpty)
          .toList();
      if (validSlots.isEmpty) {
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Manter o mesmo plano?'),
          content: Text(
            'Vamos encerrar o ciclo atual e enviar automaticamente uma nova solicitação com os mesmos horários para $trainerName. O personal precisará aprovar novamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
              ),
              child: const Text('Manter plano'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      try {
        await AuthService.cancelStudentRequest(
          requestId,
          reason: 'KEEP_PLAN',
        );

        final renewalSlots = validSlots
            .map((slot) {
              final next = _nextOccurrenceForRenewal(
                slot['dayName']!,
                slot['time']!,
              );
              return {
                'dayName': slot['dayName']!,
                'time': slot['time']!,
                'dateIso': _toDateIso(next),
                'dateLabel': _toDateLabel(next),
              };
            })
            .toList();

        final first = renewalSlots.first;
        await AuthService.sendRequest(
          trainerId: trainerId,
          studentId: widget.studentId!,
          studentName: widget.userName,
          trainerName: trainerName,
          dayName: first['dayName']!,
          time: first['time']!,
          planType: planType,
          daysJson: jsonEncode(renewalSlots),
        );

        await _loadMyRequests();
        await _loadConnections();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nova solicitação enviada com os mesmos horários.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
      }
    }

    return SingleChildScrollView(
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meu Personal',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Personais com solicitação aprovada',
                      style: TextStyle(fontSize: 11.5, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  _loadMyRequests();
                  _loadConnections();
                },
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: Color(0xFF059669),
                ),
                tooltip: 'Atualizar',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingMyRequests)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  color: Color(0xFF059669),
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (groupedApproved.isEmpty)
            _EmptyState(
              icon: Icons.fitness_center_rounded,
              title: 'Nenhum personal conectado',
              subtitle:
                  'Seu personal só aparece aqui após aprovar sua solicitação.',
              actionLabel: 'Buscar Personal',
              onAction: () => _tabController.animateTo(1),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: groupedApproved.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ApprovedTrainerItem(
                trainerData: groupedApproved[i],
                studentId: widget.studentId,
                onExpiredPlanAction: handleExpiredPlanAction,
                onRenewSamePlan: handleRenewSamePlan,
                onCancelPlan: (plan) async {
                  final requestId = int.tryParse((plan['id'] ?? '').toString());
                  final trainerId = int.tryParse((plan['trainerId'] ?? '').toString());
                  final trainerName = (plan['trainerName'] ?? 'Personal').toString();
                  if (widget.studentId == null || requestId == null || trainerId == null) {
                    return;
                  }

                  final planType = (plan['planType'] ?? 'DIARIO').toString();
                  final slots = _RequestItem._parseDays(plan['daysJson']?.toString());
                  final fallbackSlot = '${(plan['dayName'] ?? '').toString()} às ${(plan['time'] ?? '').toString()}';
                  final slotsText = slots.isNotEmpty
                      ? slots
                          .map((slot) => '${(slot['dayName'] ?? '').toString()} às ${(slot['time'] ?? '').toString()}')
                          .join(', ')
                      : fallbackSlot;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Cancelar plano?'),
                      content: Text(
                        'Se confirmar, seu $planType com $trainerName será cancelado e esses horários voltarão a ficar disponíveis.\n\n$slotsText',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Voltar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB91C1C),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Cancelar plano'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;

                  try {
                    await AuthService.cancelStudentRequest(requestId);
                    _loadMyRequests();
                    _loadConnections();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Plano cancelado e horários liberados'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString().replaceFirst('Exception: ', ''),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    ),
    );
  }

  // ─ Aba: Buscar ───────────────────────────────────────────────────────────────────

  Widget _tabBuscar() {
    return SingleChildScrollView(
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header da seção
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_search_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personal Trainers',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Trainers aprovados disponíveis',
                      style: TextStyle(fontSize: 11.5, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              if (_loadingTrainers)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF0B4DBA),
                  ),
                )
              else if (_trainersFetched)
                GestureDetector(
                  onTap: () {
                    setState(() => _trainersFetched = false);
                    _loadTrainers();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF4FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Color(0xFF0B4DBA),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Campo de busca
          TextField(
            controller: _searchCtrl,
            onChanged: (v) {
              if (v.trim().isEmpty) {
                setState(() {
                  _searchHasRun = false;
                  _filteredTrainers = [];
                });
                return;
              }
              if (!_trainersFetched && !_loadingTrainers) {
                _loadTrainers();
              } else {
                _runSearch();
              }
            },
            onSubmitted: (_) {
              if (!_trainersFetched && !_loadingTrainers) {
                _loadTrainers();
              } else {
                _runSearch();
              }
            },
            decoration: InputDecoration(
              hintText: _filterMode == 'Cidade'
                  ? 'Buscar por cidade...'
                  : _filterMode == 'Especialidade'
                  ? 'Buscar por especialidade...'
                  : _filterMode == 'Nome'
                  ? 'Buscar por nome...'
                  : 'Buscar por nome, especialidade ou cidade...',
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF0B4DBA),
                size: 20,
              ),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.black38,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchHasRun = false;
                          _filteredTrainers = [];
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF5F8FF),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFFDDE5F3),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFF0B4DBA),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filtros
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChipBtn(
                  label: 'Todos',
                  selected: _filterMode == 'Todos',
                  onTap: () => setState(() {
                    _filterMode = 'Todos';
                    _runSearch();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChipBtn(
                  label: 'Nome',
                  selected: _filterMode == 'Nome',
                  onTap: () => setState(() {
                    _filterMode = 'Nome';
                    _runSearch();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChipBtn(
                  label: 'Cidade',
                  selected: _filterMode == 'Cidade',
                  onTap: () => setState(() {
                    _filterMode = 'Cidade';
                    _runSearch();
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChipBtn(
                  label: 'Especialidade',
                  selected: _filterMode == 'Especialidade',
                  onTap: () => setState(() {
                    _filterMode = 'Especialidade';
                    _runSearch();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Contagem de resultados
          if (_searchHasRun &&
              _trainersFetched &&
              !_loadingTrainers &&
              _trainersError == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _filteredTrainers.isEmpty
                    ? 'Nenhum trainer encontrado'
                    : '${_filteredTrainers.length} trainer${_filteredTrainers.length != 1 ? 's' : ''} encontrado${_filteredTrainers.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          // Estados
          if (_loadingTrainers)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF0B4DBA),
                      strokeWidth: 2.5,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Carregando trainers...',
                      style: TextStyle(color: Colors.black38, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_trainersError != null)
            _ErrorState(message: _trainersError!, onRetry: _loadTrainers)
          else if (!_searchHasRun)
            const _EmptyState(
              icon: Icons.person_search_rounded,
              title: 'Pesquise um personal',
              subtitle:
                  'Digite o nome, cidade ou especialidade para encontrar trainers disponíveis.',
            )
          else if (_filteredTrainers.isEmpty)
            const _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nenhum resultado',
              subtitle: 'Tente ajustar o filtro ou busque com outros termos.',
            )
          else
            Column(
              children: _filteredTrainers
                  .map(
                    (t) => _TrainerCard(
                      data: t,
                      onTap: () =>
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TrainerProfileView(
                                trainerId: t['id'] != null
                                    ? (t['id'] as num).toInt()
                                    : null,
                                studentId: widget.studentId,
                                studentName: widget.userName,
                                trainerName: (t['name'] ?? '').toString(),
                                specialties: (t['especialidade'] ?? '')
                                    .toString(),
                                city: (t['cidade'] ?? '').toString(),
                                cref: (t['cref'] ?? '').toString(),
                                price: (t['valorHora'] ?? '').toString(),
                                bio: (t['bio'] ?? '').toString(),
                                horasPorSessao: t['horasPorSessao']?.toString(),
                              ),
                            ),
                          ).then((_) {
                            _loadConnections();
                            _loadMyRequests();
                          }),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    ),
    );
  }

  // ─ Aba: Seguindo ────────────────────────────────────────────────────────────

  Widget _tabSeguindo() {
    return SingleChildScrollView(
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF9F67FA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.people_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seguindo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Personais que você acompanha',
                      style: TextStyle(fontSize: 11.5, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              if (_loadingConnections)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7C3AED),
                  ),
                )
              else
                IconButton(
                  onPressed: _loadConnections,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Color(0xFF7C3AED),
                  ),
                  tooltip: 'Atualizar',
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingConnections)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  color: Color(0xFF7C3AED),
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (_myConnections.isEmpty)
            _EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'Você não segue nenhum personal',
              subtitle:
                  'Busque um personal e toque em "Seguir Personal" no perfil dele.',
              actionLabel: 'Buscar Personal',
              onAction: () => _tabController.animateTo(1),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _myConnections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final conn = _myConnections[i];
                final trainerId = conn['trainerId'];
                final trainerName = (conn['trainerName'] ?? 'Personal')
                    .toString();
                final trainerIdInt = trainerId != null
                  ? (trainerId as num).toInt()
                  : null;
                final avgRating = trainerIdInt != null
                  ? (_followingAvgRatings[trainerIdInt] ?? 0)
                  : 0;
                final availableSlots = trainerIdInt != null
                  ? (_followingAvailableSlots[trainerIdInt] ?? 0)
                  : 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF7FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4D9FF)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFF9F67FA)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: trainerIdInt != null
                              ? Image.network(
                                  AuthService.getUserPhotoUrl(trainerIdInt),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trainerName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const Text(
                              'Personal Trainer',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                avgRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: Color(0xFF22C55E),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$availableSlots disp. mês',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton(
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              Map<String, dynamic>? trainerData;
                              if (trainerIdInt != null) {
                                try {
                                  trainerData = await AuthService.getUserById(
                                    trainerIdInt,
                                  );
                                } catch (_) {
                                  trainerData = null;
                                }
                              }

                              if (!mounted) return;
                              navigator
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => TrainerProfileView(
                                        trainerId: trainerIdInt,
                                        studentId: widget.studentId,
                                        studentName: widget.userName,
                                        trainerName:
                                            (trainerData?['name'] ?? trainerName)
                                                .toString(),
                                        specialties:
                                            (trainerData?['especialidade'] ?? '')
                                                .toString(),
                                        city: trainerData?['cidade']?.toString(),
                                        cref: trainerData?['cref']?.toString(),
                                        price: trainerData?['valorHora']
                                            ?.toString(),
                                        bio: trainerData?['bio']?.toString(),
                                        horasPorSessao:
                                            trainerData?['horasPorSessao']
                                                ?.toString(),
                                      ),
                                    ),
                                  )
                                  .then((_) {
                                    if (mounted) {
                                      _loadConnections();
                                    }
                                  });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF7C3AED),
                              side: const BorderSide(color: Color(0xFF7C3AED)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Ver Perfil'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      ),
    );
  }

  // ─ Aba: Solicitações ────────────────────────────────────────────────────────

  Widget _tabSolicitacoes() {
    if (widget.studentId == null) {
      return const _SectionCard(
        child: _EmptyState(
          icon: Icons.access_time_rounded,
          title: 'Nenhuma solicitação',
          subtitle: 'Suas solicitações de horário aparecerão aqui.',
        ),
      );
    }

    return SingleChildScrollView(
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Minhas Solicitações',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadMyRequests,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: Color(0xFF0B4DBA),
                ),
                tooltip: 'Atualizar',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingMyRequests)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  color: Color(0xFF0B4DBA),
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (_myRequestsError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _myRequestsError!,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loadMyRequests,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          else if (_myRequests.isEmpty)
            const _EmptyState(
              icon: Icons.access_time_rounded,
              title: 'Nenhuma solicitação',
              subtitle: 'Suas solicitações de horário aparecerão aqui.',
            )
          else
            Builder(
              builder: (_) {
                final nonApproved = _myRequests
                    .where((r) => r['status'] != 'APPROVED')
                    .toList();
                if (nonApproved.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.access_time_rounded,
                    title: 'Nenhuma solicitação',
                    subtitle: 'Suas solicitações de horário aparecerão aqui.',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: nonApproved.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RequestItem(
                    data: nonApproved[i],
                    onDelete: () async {
                      final req = nonApproved[i];
                      final id = nonApproved[i]['id'];
                      if (id == null) return;
                      try {
                        final status = (req['status'] ?? '').toString();
                        final trainerId = int.tryParse(
                          (req['trainerId'] ?? '').toString(),
                        );
                        if (status == 'PENDING' &&
                            widget.studentId != null &&
                            trainerId != null) {
                          // Mensagem automática de cancelamento é gerada no backend
                          // no endpoint cancel-by-student para manter consistência.
                        }

                        if (status == 'PENDING') {
                          await AuthService.cancelStudentRequest(
                            int.parse(id.toString()),
                          );
                        } else {
                          await AuthService.hideRequestForStudent(
                            int.parse(id.toString()),
                          );
                        }
                        if (!mounted) return;
                        setState(() {
                          _locallyHiddenRequestIds.add(id.toString());
                          _myRequests.removeWhere(
                            (r) => r['id'].toString() == id.toString(),
                          );
                        });
                        await _persistHiddenRequestIds();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Solicitação removida das suas solicitações'),
                          ),
                        );
                      } catch (e) {
                        final errorText =
                            e.toString().replaceFirst('Exception: ', '');
                        final isNotFound = errorText.toLowerCase().contains(
                          'not found',
                        );
                        if (isNotFound) {
                          if (!mounted) return;
                          setState(() {
                            _locallyHiddenRequestIds.add(id.toString());
                            _myRequests.removeWhere(
                              (r) => r['id'].toString() == id.toString(),
                            );
                          });
                          await _persistHiddenRequestIds();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Solicitação removida das suas solicitações',
                              ),
                            ),
                          );
                          return;
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              errorText,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Request Item ───────────────────────────────────────────────────────────────

class _RequestItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onDelete;
  const _RequestItem({required this.data, this.onDelete});

  // Retorna cor e label do plano
  static (Color fg, Color bg, String label, IconData icon) _planStyle(
    String? planType,
  ) {
    switch (planType) {
      case 'SEMANAL':
        return (
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF),
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
          const Color(0xFF0B4DBA),
          const Color(0xFFEEF4FF),
          'Plano Diário',
          Icons.today_rounded,
        );
    }
  }

  // Parseia o daysJson para lista de slots
  static List<Map<String, dynamic>> _parseDays(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayName = (data['dayName'] ?? '').toString();
    final time = (data['time'] ?? '').toString();
    final status = (data['status'] ?? 'PENDING').toString();
    final trainerName = (data['trainerName'] ?? 'Personal').toString();
    final planType = data['planType']?.toString();
    final days = _parseDays(data['daysJson']?.toString());

    Color statusColor;
    Color statusBg;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'APPROVED':
        statusColor = const Color(0xFF059669);
        statusBg = const Color(0xFFECFDF3);
        statusLabel = 'Aprovado';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'REJECTED':
        statusColor = const Color(0xFFEF4444);
        statusBg = const Color(0xFFFEF2F2);
        statusLabel = 'Recusado';
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusBg = const Color(0xFFFFFBEB);
        statusLabel = 'Pendente';
        statusIcon = Icons.hourglass_top_rounded;
    }

    final canChat = status == 'PENDING' || status == 'APPROVED' || status == 'REJECTED';
    final (planFg, planBg, planLabel, planIcon) = _planStyle(planType);
    final isMultiDay = days.length > 1;

    void confirmDelete() {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar solicitação?'),
          content: Text(
            'Tem certeza que deseja excluir esta solicitação?\n\nSe confirmar, sua solicitação com $trainerName será cancelada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onDelete?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: const Text('Excluir solicitação'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2EBFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: planBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(planIcon, color: planFg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trainerName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B4DBA),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Badge do plano
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: planBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        planLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: planFg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete == null
                    ? null
                    : () {
                        if (status == 'REJECTED') {
                          onDelete?.call();
                        } else {
                          confirmDelete();
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Horários selecionados
          if (isMultiDay)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: days
                  .map(
                    (d) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: planBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: planFg.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '${d['dayName']} · ${d['time']}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: planFg,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            Text(
              '$dayName · $time',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          if (canChat) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrainerChatView(
                      requestId: data['id'] != null
                          ? int.tryParse(data['id'].toString())
                          : null,
                      trainerName: trainerName,
                      dayName: dayName,
                      time: time,
                      isTrainerSide: false,
                      senderId: data['studentId'] != null
                          ? int.tryParse(data['studentId'].toString())
                          : null,
                      receiverId: data['trainerId'] != null
                          ? int.tryParse(data['trainerId'].toString())
                          : null,
                      planType: data['planType']?.toString(),
                      daysJson: data['daysJson']?.toString(),
                      readOnly: status == 'REJECTED',
                      readOnlyMessage: status == 'REJECTED'
                          ? 'Este chat está disponível apenas para leitura porque sua solicitação foi encerrada. Para voltar a mandar mensagem, envie uma nova solicitação para este personal.'
                          : null,
                      readOnlyStartAtIso:
                          data['chatStartAtIso']?.toString() ?? data['createdAt']?.toString(),
                      readOnlyLockAtIso:
                          data['chatLockAtIso']?.toString(),
                      requestUpdatedAtIso: data['updatedAt']?.toString(),
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                label: const Text('Abrir Chat com Personal'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B4DBA),
                  side: const BorderSide(color: Color(0xFF0B4DBA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Approved Trainer Item (Meu Personal) ─────────────────────────────────────

class _ApprovedTrainerItem extends StatelessWidget {
  final Map<String, dynamic> trainerData;
  final int? studentId;
  final Future<void> Function(
    Map<String, dynamic> plan, {
    required bool changePlan,
  }) onExpiredPlanAction;
  final Future<void> Function(Map<String, dynamic> plan) onRenewSamePlan;
  final void Function(Map<String, dynamic> plan) onCancelPlan;

  const _ApprovedTrainerItem({
    required this.trainerData,
    this.studentId,
    required this.onExpiredPlanAction,
    required this.onRenewSamePlan,
    required this.onCancelPlan,
  });

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
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  DateTime _nextOccurrence(
    DateTime base,
    int weekday,
    int hour,
    int minute,
  ) {
    final sameDayAtTime = DateTime(
      base.year,
      base.month,
      base.day,
      hour,
      minute,
    );
    var deltaDays = weekday - base.weekday;
    if (deltaDays < 0) {
      deltaDays += 7;
    }
    var candidate = sameDayAtTime.add(Duration(days: deltaDays));
    if (candidate.isBefore(base)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  DateTime? _parseDateLabel(
    String dateLabel,
    int hour,
    int minute, {
    DateTime? base,
  }) {
    final text = dateLabel.trim();
    if (text.isEmpty) return null;

    final full = RegExp(r'^(\d{2})\/(\d{2})\/(\d{4})$').firstMatch(text);
    if (full != null) {
      final day = int.tryParse(full.group(1)!);
      final month = int.tryParse(full.group(2)!);
      final year = int.tryParse(full.group(3)!);
      if (day == null || month == null || year == null) return null;
      return DateTime(year, month, day, hour, minute);
    }

    final short = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(text);
    if (short != null) {
      final day = int.tryParse(short.group(1)!);
      final month = int.tryParse(short.group(2)!);
      final anchor = base ?? DateTime.now();
      if (day == null || month == null) return null;
      return DateTime(anchor.year, month, day, hour, minute);
    }

    return null;
  }

  DateTime? _parseIsoDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  List<Map<String, String>> _planSlots(Map<String, dynamic> plan) {
    final days = _RequestItem._parseDays(plan['daysJson']?.toString());
    if (days.isNotEmpty) {
      return days
          .map((slot) => {
                'dayName': (slot['dayName'] ?? '').toString(),
                'time': (slot['time'] ?? '').toString(),
                'dateLabel': (slot['dateLabel'] ?? '').toString(),
                'dateIso': (slot['dateIso'] ?? '').toString(),
              })
          .where(
            (slot) =>
                slot['dayName']!.trim().isNotEmpty &&
                slot['time']!.trim().isNotEmpty,
          )
          .toList();
    }

    final dayName = (plan['dayName'] ?? '').toString().trim();
    final time = (plan['time'] ?? '').toString().trim();
    if (dayName.isEmpty || time.isEmpty) {
      return const [];
    }
    return [
      {
        'dayName': dayName,
        'time': time,
        'dateLabel': '',
        'dateIso': '',
      }
    ];
  }

  DateTime? _resolveDailyLastSessionEndAt(Map<String, dynamic> plan) {
    final anchor =
        _parseIsoDate(plan['approvedAt']) ?? _parseIsoDate(plan['createdAt']) ?? DateTime.now();
    final slots = _planSlots(plan);
    if (slots.isEmpty) return null;

    DateTime? lastStart;
    for (final slot in slots) {
      final weekday = _weekdayFromPt(slot['dayName'] ?? '');
      final hm = _parseHourMinute(slot['time'] ?? '');
      if (weekday == null || hm == null) continue;

      DateTime? candidate;
      final rawIso = (slot['dateIso'] ?? '').trim();
      if (rawIso.isNotEmpty) {
        final parsedIso = DateTime.tryParse(rawIso);
        if (parsedIso != null) {
          candidate = DateTime(
            parsedIso.year,
            parsedIso.month,
            parsedIso.day,
            hm.$1,
            hm.$2,
          );
        }
      }

      candidate ??= _parseDateLabel(
        (slot['dateLabel'] ?? '').trim(),
        hm.$1,
        hm.$2,
        base: anchor,
      );

      candidate ??= _nextOccurrence(anchor, weekday, hm.$1, hm.$2);

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

      if (lastStart == null || candidate.isAfter(lastStart)) {
        lastStart = candidate;
      }
    }

    if (lastStart == null) return null;
    return lastStart.add(const Duration(hours: 1));
  }

  DateTime? _resolvePlanStartAt(Map<String, dynamic> plan) {
    final approvedAt =
        _parseIsoDate(plan['approvedAt']) ?? _parseIsoDate(plan['createdAt']);
    if (approvedAt == null) return null;

    final slots = _planSlots(plan);
    if (slots.isEmpty) {
      return approvedAt;
    }

    DateTime? firstSession;
    final planType = (plan['planType'] ?? 'DIARIO').toString().toUpperCase();
    for (final slot in slots) {
      final weekday = _weekdayFromPt(slot['dayName'] ?? '');
      final hm = _parseHourMinute(slot['time'] ?? '');
      if (weekday == null || hm == null) continue;
      var candidate = _nextOccurrence(
        approvedAt,
        weekday,
        hm.$1,
        hm.$2,
      );

      // Plano diário: se a aprovação aconteceu no mesmo dia da semana,
      // mas após o horário da sessão, consideramos a sessão daquele dia
      // (já encerrada), não a próxima semana.
      if (planType == 'DIARIO' && weekday == approvedAt.weekday) {
        final sameDayScheduled = DateTime(
          approvedAt.year,
          approvedAt.month,
          approvedAt.day,
          hm.$1,
          hm.$2,
        );
        if (sameDayScheduled.isBefore(approvedAt)) {
          candidate = sameDayScheduled;
        }
      }

      if (firstSession == null || candidate.isBefore(firstSession)) {
        firstSession = candidate;
      }
    }

    return firstSession ?? approvedAt;
  }

  DateTime? _resolvePlanExpiresAt(Map<String, dynamic> plan) {
    final startAt = _resolvePlanStartAt(plan);
    if (startAt == null) return null;

    final planType = (plan['planType'] ?? 'DIARIO').toString().toUpperCase();
    switch (planType) {
      case 'DIARIO':
        return _resolveDailyLastSessionEndAt(plan) ??
            startAt.add(const Duration(hours: 1));
      case 'SEMANAL':
        return startAt.add(const Duration(days: 7));
      case 'MENSAL':
        return startAt.add(const Duration(days: 30));
      default:
        return startAt.add(const Duration(days: 1));
    }
  }

  String _weekdayNamePt(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'segunda-feira';
      case DateTime.tuesday:
        return 'terça-feira';
      case DateTime.wednesday:
        return 'quarta-feira';
      case DateTime.thursday:
        return 'quinta-feira';
      case DateTime.friday:
        return 'sexta-feira';
      case DateTime.saturday:
        return 'sábado';
      case DateTime.sunday:
        return 'domingo';
      default:
        return '';
    }
  }

  String _calendarLabelForSlot(
    String dayName,
    String time, {
    DateTime? base,
    String? dateLabel,
  }) {
    final weekday = _weekdayFromPt(dayName);
    final hm = _parseHourMinute(time);
    final now = base ?? DateTime.now();
    if (weekday == null || hm == null) {
      final fallbackDay = dayName.trim();
      final fallbackTime = time.trim();
      if (fallbackDay.isNotEmpty && fallbackTime.isNotEmpty) {
        return '$fallbackDay horário $fallbackTime';
      }
      return '$fallbackDay $fallbackTime'.trim();
    }

    final parsedFromLabel = _parseDateLabel(
      (dateLabel ?? '').toString(),
      hm.$1,
      hm.$2,
      base: now,
    );
    final date = parsedFromLabel ?? _nextOccurrence(now, weekday, hm.$1, hm.$2);
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    final hh = hm.$1.toString().padLeft(2, '0');
    final min = hm.$2.toString().padLeft(2, '0');
    final weekdayName = _weekdayNamePt(date.weekday);
    return '$dd/$mm/$yyyy $weekdayName horário $hh:$min';
  }

  String _formatDateTime(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final weekdayName = _weekdayNamePt(value.weekday);
    return '$dd/$mm/$yyyy $weekdayName horário $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    final trainerName = (trainerData['trainerName'] ?? 'Personal').toString();
    final trainerId = trainerData['trainerId'] != null
        ? int.tryParse(trainerData['trainerId'].toString())
        : null;
    final plans = List<Map<String, dynamic>>.from(
      trainerData['plans'] as List? ?? const [],
    );
    final firstPlan = plans.isNotEmpty ? plans.first : <String, dynamic>{};

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: ClipOval(
                    child: trainerId != null
                        ? Image.network(
                            AuthService.getUserPhotoUrl(trainerId),
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
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        trainerName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Color(0xFF059669),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${plans.length} plano${plans.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Color(0xFF059669),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Column(
            children: plans.map((plan) {
              final planType = (plan['planType'] ?? 'DIARIO').toString();
              final dayName = (plan['dayName'] ?? '').toString();
              final time = (plan['time'] ?? '').toString();
              final planTrainerId = int.tryParse(
                (plan['trainerId'] ?? trainerData['trainerId'] ?? '').toString(),
              );
              final days = _RequestItem._parseDays(plan['daysJson']?.toString());
              final (planFg, planBg, planLabel, planIcon) =
                  _RequestItem._planStyle(planType);
              final expiresAt = _resolvePlanExpiresAt(plan);
              final isExpired =
                  expiresAt != null && DateTime.now().isAfter(expiresAt);
                final planBase =
                  _resolvePlanStartAt(plan) ??
                  _parseIsoDate(plan['approvedAt']) ??
                  _parseIsoDate(plan['createdAt']) ??
                  DateTime.now();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDEFE3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: planBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(planIcon, size: 12, color: planFg),
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
                        const Spacer(),
                        TextButton.icon(
                          onPressed: (studentId != null && planTrainerId != null)
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StudentWorkoutView(
                                        studentId: studentId!,
                                        trainerId: planTrainerId,
                                        trainerName: trainerName,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(
                            Icons.menu_book_rounded,
                            size: 15,
                          ),
                          label: const Text('Visualizar treino'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF0B4DBA),
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => onCancelPlan(plan),
                          icon: const Icon(
                            Icons.cancel_outlined,
                            size: 15,
                          ),
                          label: const Text('Cancelar plano'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFB91C1C),
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (days.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: days.map((slot) {
                          final slotDay = (slot['dayName'] ?? '').toString();
                          final slotTime = (slot['time'] ?? '').toString();
                          final slotDateLabel =
                              (slot['dateLabel'] ?? '').toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: planBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _calendarLabelForSlot(
                                slotDay,
                                slotTime,
                                base: planBase,
                                dateLabel: slotDateLabel,
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: planFg,
                              ),
                            ),
                          );
                        }).toList(),
                      )
                    else
                      Text(
                        _calendarLabelForSlot(
                          dayName,
                          time,
                          base: planBase,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    if (isExpired) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plano vencido em ${_formatDateTime(expiresAt)}.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Deseja encerrar o plano atual ou mudar o plano?',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => onExpiredPlanAction(
                                      plan,
                                      changePlan: false,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFB45309),
                                      side: const BorderSide(
                                        color: Color(0xFFF59E0B),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 9,
                                      ),
                                    ),
                                    child: const Text(
                                      'Encerrar plano',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => onRenewSamePlan(plan),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0B4DBA),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 9,
                                      ),
                                    ),
                                    child: const Text(
                                      'Manter plano',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => onExpiredPlanAction(
                                      plan,
                                      changePlan: true,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 9,
                                      ),
                                    ),
                                    child: const Text(
                                      'Mudar plano',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TrainerChatView(
                    trainerName: trainerName,
                    dayName: (firstPlan['dayName'] ?? '').toString(),
                    time: (firstPlan['time'] ?? '').toString(),
                    isTrainerSide: false,
                    senderId: studentId,
                    receiverId: trainerId,
                    planType: firstPlan['planType']?.toString(),
                    daysJson: firstPlan['daysJson']?.toString(),
                  ),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
              label: const Text('Chat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF059669),
                side: const BorderSide(color: Color(0xFF059669)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ─── Section Card ───────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: child,
    );
  }
}

// ─── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF4FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF0B4DBA), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black45, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.search, size: 16),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B4DBA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Error State ────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF4444),
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Falha ao carregar trainers',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(color: Colors.black45, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Chip Button ──────────────────────────────────────────────────────

class _FilterChipBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChipBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0B4DBA) : const Color(0xFFF0F4FB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF0B4DBA) : const Color(0xFFDDE5F3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trainer Star Rating ────────────────────────────────────────────────────────

class _TrainerStarRating extends StatelessWidget {
  final double? media;
  final int total;
  const _TrainerStarRating({this.media, required this.total});

  @override
  Widget build(BuildContext context) {
    if (media == null || total == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.star_outline_rounded, size: 13, color: Colors.black26),
          SizedBox(width: 3),
          Text(
            'Sem avaliações',
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ],
      );
    }
    final filled = media!.floor();
    final hasHalf = (media! - filled) >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            i <= filled
                ? Icons.star_rounded
                : (i == filled + 1 && hasHalf)
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            size: 14,
            color: const Color(0xFFF59E0B),
          ),
        const SizedBox(width: 4),
        Text(
          '${media!.toStringAsFixed(1)} ($total)',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Trainer Card ───────────────────────────────────────────────────────────────

class _TrainerCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _TrainerCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final trainerId = data['id'] is num ? (data['id'] as num).toInt() : null;
    final city = (data['cidade'] ?? '').toString();
    final spec = (data['especialidade'] ?? '').toString();
    final price = (data['valorHora'] ?? '').toString();
    final cref = (data['cref'] ?? '').toString();
    final availableSlots = (data['availableSlots'] as num?)?.toInt() ?? 0;
    final specList = spec.isNotEmpty
        ? spec.split(RegExp(r'[,;/]'))
        : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEBF0FA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar com borda gradiente
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEEF4FF),
                      ),
                      child: ClipOval(
                        child: trainerId != null
                            ? Image.network(
                                AuthService.getUserPhotoUrl(trainerId),
                                fit: BoxFit.cover,
                                width: 57,
                                height: 57,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  color: Color(0xFF0B4DBA),
                                  size: 24,
                                ),
                              )
                            : const Icon(
                                Icons.person_rounded,
                                color: Color(0xFF0B4DBA),
                                size: 24,
                              ),
                        ),
                      ),
                    ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nome + verificado
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: Color(0xFF0B4DBA),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Estrelas de avaliação
                      _TrainerStarRating(
                        media: data['mediaAvaliacao'] != null
                            ? (data['mediaAvaliacao'] as num).toDouble()
                            : null,
                        total: data['totalAvaliacoes'] != null
                            ? (data['totalAvaliacoes'] as num).toInt()
                            : 0,
                      ),
                      const SizedBox(height: 4),
                      // Cidade + CREF
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          if (city.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  size: 12,
                                  color: Colors.black38,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  city,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          if (cref.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.badge_outlined,
                                  size: 12,
                                  color: Colors.black38,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'CREF $cref',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (price.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'R\$ $price/h',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (specList.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: specList.take(3).map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF4FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFBFD7FF),
                                ),
                              ),
                              child: Text(
                                s.trim(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF1D4ED8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: Color(0xFF059669),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$availableSlots disp. mês',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF059669),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0B4DBA).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Ver',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
