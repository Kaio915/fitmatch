import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

class StudentWorkoutView extends StatefulWidget {
  final int studentId;
  final int trainerId;
  final String trainerName;

  const StudentWorkoutView({
    super.key,
    required this.studentId,
    required this.trainerId,
    required this.trainerName,
  });

  @override
  State<StudentWorkoutView> createState() => _StudentWorkoutViewState();
}

class _StudentWorkoutViewState extends State<StudentWorkoutView> {
  static const List<String> _pdfLogoAssetPaths = [
    'assets/images/fitmatch_logo.png',
    'assets/images/fitmatch_logo_original.png',
  ];
  bool _loading = true;
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _approvedRequestPlans = [];
  final Set<String> _hiddenPlanIds = <String>{};
  final Set<String> _expandedPlanPanels = {};
  final Set<String> _exportingPlanKeys = {};
  final Set<String> _expandedDays = {};
  final Set<String> _expandedTimes = {};
  pw.MemoryImage? _pdfLogoImage;
  bool _pdfLogoLoadAttempted = false;

  static const Map<String, int> _dayOrder = {
    'Segunda': 1,
    'Terça': 2,
    'Quarta': 3,
    'Quinta': 4,
    'Sexta': 5,
    'Sábado': 6,
    'Domingo': 7,
  };

  @override
  void initState() {
    super.initState();
    _loadHiddenPlanIds().then((_) => _loadPlans());
  }

  String get _hiddenPlansStorageKey =>
      'student_hidden_workout_plans_${widget.studentId}_${widget.trainerId}';

  Future<void> _loadHiddenPlanIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_hiddenPlansStorageKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _hiddenPlanIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _persistHiddenPlanIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenPlansStorageKey, _hiddenPlanIds.toList());
  }

  String? _normalizePlanId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.toString();
    if (value is num) return value.toInt().toString();

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final direct = int.tryParse(raw);
    if (direct != null) return direct.toString();

    final numeric = num.tryParse(raw.replaceAll(',', '.'));
    if (numeric == null) return null;
    return numeric.toInt().toString();
  }

  Future<void> _loadPlans() async {
    setState(() => _loading = true);
    try {
      final responses = await Future.wait([
        AuthService.getStudentWorkoutPlansByTrainer(
          studentId: widget.studentId,
          trainerId: widget.trainerId,
        ),
        AuthService.getStudentRequests(widget.studentId),
      ]);
      final plans = List<Map<String, dynamic>>.from(
        responses[0],
      );
      final visiblePlans = plans.where((plan) {
        final id = _normalizePlanId(plan['id']);
        if (id == null) return true;
        return !_hiddenPlanIds.contains(id);
      }).toList();

      final existingIds = plans
          .map((plan) => _normalizePlanId(plan['id']))
          .whereType<String>()
          .toSet();
      final staleHiddenIds =
          _hiddenPlanIds.where((id) => !existingIds.contains(id)).toList();
      if (staleHiddenIds.isNotEmpty) {
        for (final id in staleHiddenIds) {
          _hiddenPlanIds.remove(id);
        }
        unawaited(_persistHiddenPlanIds());
      }

      final requests = List<Map<String, dynamic>>.from(
        responses[1],
      );
      if (!mounted) return;
      setState(() {
        _plans = visiblePlans;
        _approvedRequestPlans = _selectApprovedPlans(requests);
        _initializeExpandedSections();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  List<Map<String, String>> _extractExercises(dynamic raw) {
    final list = <Map<String, String>>[];
    if (raw is! List) return list;

    for (final item in raw) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString().trim();
      final category = (item['category'] ?? 'Outros').toString().trim();
      if (name.isEmpty) continue;
      list.add({
        'name': name,
        'category': category.isEmpty ? 'Outros' : category,
      });
    }

    return list;
  }

  String _normalizeDayName(String raw) {
    final source = raw
        .trim()
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
        .replaceAll('ç', 'c');

    if (source.startsWith('seg')) return 'segunda';
    if (source.startsWith('ter')) return 'terca';
    if (source.startsWith('qua')) return 'quarta';
    if (source.startsWith('qui')) return 'quinta';
    if (source.startsWith('sex')) return 'sexta';
    if (source.startsWith('sab')) return 'sabado';
    if (source.startsWith('dom')) return 'domingo';
    return source;
  }

  String _normalizeTime(String raw) {
    final text = raw.trim();
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

  String _slotKey(String dayName, String time) {
    return '${_normalizeDayName(dayName)}|${_normalizeTime(time)}';
  }

  int? _weekdayFromPt(String dayName) {
    switch (_normalizeDayName(dayName)) {
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

  String _weekdayLongPt(int weekday) {
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

  DateTime _requestReferenceDate(Map<String, dynamic> req) {
    return DateTime.tryParse((req['approvedAt'] ?? '').toString()) ??
        DateTime.tryParse((req['createdAt'] ?? '').toString()) ??
        DateTime.now();
  }

  List<Map<String, String>> _requestSlotsFromRequest(Map<String, dynamic> req) {
    final raw = req['daysJson']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final parsed = decoded
            .whereType<Map>()
            .map((slot) => {
                  'dayName': (slot['dayName'] ?? '').toString().trim(),
                  'time': (slot['time'] ?? '').toString().trim(),
                  'dateLabel': (slot['dateLabel'] ?? '').toString().trim(),
                  'dateIso': (slot['dateIso'] ?? '').toString().trim(),
                })
            .where((slot) =>
                slot['dayName']!.isNotEmpty && slot['time']!.isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {}
    }

    final dayName = (req['dayName'] ?? '').toString().trim();
    final time = (req['time'] ?? '').toString().trim();
    if (dayName.isEmpty || time.isEmpty) return const [];
    return [
      {'dayName': dayName, 'time': time, 'dateLabel': '', 'dateIso': ''}
    ];
  }

  DateTime? _parseSlotDate(
    Map<String, String> slot, {
    required DateTime anchor,
  }) {
    final time = (slot['time'] ?? '').trim();
    final hm = _parseHourMinute(time);
    if (hm == null) return null;

    final dateIso = (slot['dateIso'] ?? '').trim();
    if (dateIso.isNotEmpty) {
      final parsed = DateTime.tryParse(dateIso);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day, hm.$1, hm.$2);
      }
    }

    final dateLabel = (slot['dateLabel'] ?? '').trim();
    final full = RegExp(r'^(\d{2})\/(\d{2})\/(\d{4})$').firstMatch(dateLabel);
    if (full != null) {
      final day = int.tryParse(full.group(1)!);
      final month = int.tryParse(full.group(2)!);
      final year = int.tryParse(full.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, hm.$1, hm.$2);
      }
    }

    final short = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(dateLabel);
    if (short != null) {
      final day = int.tryParse(short.group(1)!);
      final month = int.tryParse(short.group(2)!);
      if (day != null && month != null) {
        return DateTime(anchor.year, month, day, hm.$1, hm.$2);
      }
    }

    final weekday = _weekdayFromPt((slot['dayName'] ?? '').trim());
    if (weekday == null) return null;
    return _nextOccurrence(anchor, weekday, hm.$1, hm.$2);
  }

  String _formatPlanChipLabel({
    required String dayName,
    required String time,
    DateTime? date,
  }) {
    final normalizedTime = time.trim();
    if (date == null) {
      return '$dayName horário $normalizedTime';
    }
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final weekday = _weekdayLongPt(date.weekday);
    return '$dd/$mm/$yyyy $weekday horário $hh:$min';
  }

  List<Map<String, dynamic>> _selectApprovedPlans(
    List<Map<String, dynamic>> requests,
  ) {
    final approved = requests.where((req) {
      final trainerId = (req['trainerId'] ?? '').toString();
      final status = (req['status'] ?? '').toString().toUpperCase();
      return trainerId == widget.trainerId.toString() && status == 'APPROVED';
    }).map((req) => Map<String, dynamic>.from(req)).toList();

    if (approved.isEmpty) return const [];
    approved.sort(
      (a, b) => _requestReferenceDate(b).compareTo(_requestReferenceDate(a)),
    );
    return approved;
  }

  String _requestPlanKey(Map<String, dynamic>? req) {
    if (req == null) return 'legacy';
    final id = (req['id'] ?? '').toString();
    if (id.isNotEmpty) return 'request-$id';
    final planType = (req['planType'] ?? '').toString().toUpperCase();
    final created = (req['createdAt'] ?? '').toString();
    return 'request-$planType-$created';
  }

  String _planTitleFromType(String? planType) {
    switch ((planType ?? '').toUpperCase()) {
      case 'SEMANAL':
        return 'Plano Semanal';
      case 'MENSAL':
        return 'Plano Mensal';
      case 'DIARIO':
        return 'Plano Diário';
      default:
        return 'Plano de Treino';
    }
  }

  DateTime? _requestCycleEnd(Map<String, dynamic> req) {
    final slots = _requestSlotsFromRequest(req);
    if (slots.isEmpty) return null;

    final anchor = _requestReferenceDate(req);
    DateTime? firstSlot;
    for (final slot in slots) {
      final slotDate = _parseSlotDate(slot, anchor: anchor);
      if (slotDate == null) continue;
      if (firstSlot == null || slotDate.isBefore(firstSlot)) {
        firstSlot = slotDate;
      }
    }
    if (firstSlot == null) return null;

    final planType = (req['planType'] ?? '').toString().toUpperCase();
    switch (planType) {
      case 'DIARIO':
        return firstSlot;
      case 'SEMANAL':
        return firstSlot.add(const Duration(days: 7));
      case 'MENSAL':
        return _addOneMonthKeepingDay(firstSlot);
      default:
        return null;
    }
  }

  bool _isPanelOld(Map<String, dynamic>? req, List<Map<String, dynamic>> plans) {
    if (req == null) {
      return plans.isNotEmpty;
    }
    final cycleEnd = _requestCycleEnd(req);
    if (cycleEnd == null) return false;
    return DateTime.now().isAfter(cycleEnd);
  }

  List<({String label, bool highlight})> _buildFallbackPlanChips(
    List<Map<String, dynamic>> plans,
  ) {
    final grouped = _groupPlansByDayAndTimeFor(plans);
    final chips = <({String label, bool highlight})>[];
    grouped.forEach((day, perTime) {
      for (final time in perTime.keys) {
        chips.add((
          label: time.isEmpty ? day : '$day horário $time',
          highlight: false,
        ));
      }
    });
    return chips;
  }

  List<({String label, bool highlight})> _buildPlanSummaryChips(
    Map<String, dynamic>? req,
    List<Map<String, dynamic>> plans,
  ) {
    if (req == null) {
      return _buildFallbackPlanChips(plans);
    }

    final slots = _requestSlotsFromRequest(req);
    if (slots.isEmpty) {
      return _buildFallbackPlanChips(plans);
    }

    final anchor = _requestReferenceDate(req);
    final chips = <({String label, bool highlight})>[];
    final patternByKey = <String, Map<String, dynamic>>{};
    DateTime? firstDate;

    for (final slot in slots) {
      final dayName = (slot['dayName'] ?? '').trim();
      final time = (slot['time'] ?? '').trim();
      if (dayName.isEmpty || time.isEmpty) continue;

      final date = _parseSlotDate(slot, anchor: anchor);
      if (date != null && (firstDate == null || date.isBefore(firstDate))) {
        firstDate = date;
      }

      chips.add((
        label: _formatPlanChipLabel(dayName: dayName, time: time, date: date),
        highlight: false,
      ));

      final weekday = _weekdayFromPt(dayName);
      final hm = _parseHourMinute(time);
      if (weekday != null && hm != null) {
        patternByKey['$weekday|${hm.$1}:${hm.$2}'] = {
          'weekday': weekday,
          'hour': hm.$1,
          'minute': hm.$2,
          'time': time,
        };
      }
    }

    final planType = (req['planType'] ?? '').toString().toUpperCase();
    if (planType == 'MENSAL' && firstDate != null && patternByKey.isNotEmpty) {
      final windowEnd = _addOneMonthKeepingDay(firstDate);
      DateTime? lastDate;
      String lastTime = '';

      for (final pattern in patternByKey.values) {
        var candidate = _nextOccurrence(
          firstDate,
          pattern['weekday'] as int,
          pattern['hour'] as int,
          pattern['minute'] as int,
        );
        if (candidate.isAfter(windowEnd)) continue;

        while (true) {
          final next = candidate.add(const Duration(days: 7));
          if (next.isAfter(windowEnd)) break;
          candidate = next;
        }

        if (lastDate == null || candidate.isAfter(lastDate)) {
          lastDate = candidate;
          lastTime = (pattern['time'] ?? '').toString();
        }
      }

      if (lastDate != null && lastTime.isNotEmpty) {
        final label = _formatPlanChipLabel(
          dayName: _weekdayLongPt(lastDate.weekday),
          time: lastTime,
          date: lastDate,
        );

        final existingIndex = chips.indexWhere((chip) => chip.label == label);
        if (existingIndex >= 0) {
          chips[existingIndex] = (label: label, highlight: true);
        } else {
          chips.add((label: label, highlight: true));
        }
      }
    }

    return chips;
  }

  String _formatDateTimePt(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  Future<pw.MemoryImage?> _loadPdfLogo() async {
    if (_pdfLogoLoadAttempted) return _pdfLogoImage;
    _pdfLogoLoadAttempted = true;
    for (final assetPath in _pdfLogoAssetPaths) {
      try {
        final data = await rootBundle.load(assetPath);
        _pdfLogoImage = pw.MemoryImage(data.buffer.asUint8List());
        break;
      } catch (_) {
        _pdfLogoImage = null;
      }
    }
    return _pdfLogoImage;
  }

  pw.Widget _pdfHeaderCard({
    required pw.MemoryImage? logo,
    required String title,
    required String subtitle,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#EAF1FF'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(
          color: PdfColor.fromHex('#C7DBFF'),
          width: 1,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 128,
            height: 44,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColor.fromHex('#BFDBFE'), width: 1),
            ),
            child: pw.Center(
              child: logo != null
                  ? pw.Image(
                      logo,
                      width: 108,
                      height: 26,
                      fit: pw.BoxFit.contain,
                    )
                  : pw.Text(
                      'FitMatch',
                      style: pw.TextStyle(
                        color: PdfColor.fromHex('#0B4DBA'),
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0B4DBA'),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitle,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    color: PdfColor.fromHex('#475569'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfInfoItem({required String label, required String value}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9.5,
              color: PdfColor.fromHex('#64748B'),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#0F172A'),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#0B4DBA'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  pw.Widget _pdfExerciseTile({
    required int index,
    required String name,
    required String category,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 18,
            height: 18,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#DBEAFE'),
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                '$index',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1D4ED8'),
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  name,
                  style: pw.TextStyle(
                    fontSize: 11.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  category,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#64748B'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _groupPlansByDayAndTimeFor(
    List<Map<String, dynamic>> sourcePlans,
  ) {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final plan in sourcePlans) {
      final day = (plan['dayName'] ?? 'Dia').toString().trim();
      final time = (plan['time'] ?? '').toString().trim();
      if (day.isEmpty) continue;
      grouped.putIfAbsent(day, () => <String, List<Map<String, dynamic>>>{});
      grouped[day]!.putIfAbsent(time, () => <Map<String, dynamic>>[]);
      grouped[day]![time]!.add(plan);
    }

    final sortedDays = grouped.keys.toList()
      ..sort((a, b) => (_dayOrder[a] ?? 99).compareTo(_dayOrder[b] ?? 99));

    final sortedGrouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final day in sortedDays) {
      final times = grouped[day]!.keys.toList()
        ..sort((a, b) {
          if (a.isEmpty && b.isEmpty) return 0;
          if (a.isEmpty) return 1;
          if (b.isEmpty) return -1;
          return a.compareTo(b);
        });
      final perTime = <String, List<Map<String, dynamic>>>{};
      for (final time in times) {
        perTime[time] = grouped[day]![time]!;
      }
      sortedGrouped[day] = perTime;
    }

    return sortedGrouped;
  }

  void _initializeExpandedSections() {
    _expandedDays.clear();
    _expandedTimes.clear();
    _expandedPlanPanels.clear();
  }

  Future<Uint8List> _buildPlanPdf(Map<String, dynamic> plan) async {
    final pdf = pw.Document();
    final logo = await _loadPdfLogo();
    final dayName = (plan['dayName'] ?? 'Dia').toString();
    final time = (plan['time'] ?? '').toString().trim();
    final exercises = _extractExercises(plan['exercises']);
    final generatedAt = _formatDateTimePt(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 26),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gerado em $generatedAt - Pagina ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromHex('#94A3B8'),
            ),
          ),
        ),
        build: (context) => [
          _pdfHeaderCard(
            logo: logo,
            title: 'FitMatch - Treino do Dia',
            subtitle: 'Treino personalizado para acompanhamento do aluno',
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfInfoItem(label: 'Personal', value: widget.trainerName),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfInfoItem(label: 'Dia', value: dayName),
              ),
              if (time.isNotEmpty) ...[
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _pdfInfoItem(label: 'Horario', value: time),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 12),
          _pdfSectionTitle('Exercicios'),
          pw.SizedBox(height: 8),
          if (exercises.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
              ),
              child: pw.Text(
                'Nenhum exercicio cadastrado para este treino.',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColor.fromHex('#64748B'),
                ),
              ),
            )
          else
            ...exercises.asMap().entries.map(
                  (entry) => _pdfExerciseTile(
                    index: entry.key + 1,
                    name: entry.value['name'] ?? '',
                    category: entry.value['category'] ?? 'Outros',
                  ),
                ),
        ],
      ),
    );

    return pdf.save();
  }

  String _planExportKey(Map<String, dynamic> plan) {
    final id = (plan['id'] ?? '').toString();
    final day = (plan['dayName'] ?? '').toString().trim().toLowerCase();
    final time = (plan['time'] ?? '').toString().trim().toLowerCase();
    return '$id|$day|$time';
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> _printPlan(Map<String, dynamic> plan) async {
    final key = _planExportKey(plan);
    if (_exportingPlanKeys.contains(key)) return;

    setState(() => _exportingPlanKeys.add(key));
    try {
      final bytes = await _buildPlanPdf(plan);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      _showErrorSnack('Não foi possível abrir a impressão deste treino.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(key));
      }
    }
  }

  Future<void> _downloadPlan(Map<String, dynamic> plan) async {
    final key = _planExportKey(plan);
    if (_exportingPlanKeys.contains(key)) return;

    setState(() => _exportingPlanKeys.add(key));
    try {
      final bytes = await _buildPlanPdf(plan);
      final dayName = (plan['dayName'] ?? 'dia').toString().toLowerCase();
        final time = (plan['time'] ?? '').toString().trim().toLowerCase();
      final safeDay = dayName
          .replaceAll(' ', '_')
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
          .replaceAll('ç', 'c');
      final safeTime = time
          .replaceAll(':', '_')
          .replaceAll(' ', '_');

      await Printing.sharePdf(
        bytes: bytes,
        filename: safeTime.isEmpty
            ? 'treino_$safeDay.pdf'
            : 'treino_${safeDay}_$safeTime.pdf',
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      _showErrorSnack('A exportação demorou demais. Tente novamente.');
    } catch (_) {
      _showErrorSnack('Não foi possível baixar este treino agora.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(key));
      }
    }
  }

  Future<Uint8List> _buildPlansPdfFor(
    List<Map<String, dynamic>> plans, {
    required String title,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadPdfLogo();
    final grouped = _groupPlansByDayAndTimeFor(plans);
    final generatedAt = _formatDateTimePt(DateTime.now());

    final blocks = <pw.Widget>[];
    grouped.forEach((dayName, perTime) {
      blocks.add(
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 10, bottom: 8),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#DBEAFE'),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColor.fromHex('#BFDBFE'), width: 1),
          ),
          child: pw.Text(
            dayName,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1D4ED8'),
            ),
          ),
        ),
      );

      perTime.forEach((time, plansAtTime) {
        final exercises = <Map<String, String>>[];
        for (final plan in plansAtTime) {
          exercises.addAll(_extractExercises(plan['exercises']));
        }

        blocks.add(
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#ECFDF3'),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor.fromHex('#BBF7D0'), width: 1),
            ),
            child: pw.Text(
              time.isEmpty ? 'Sem horario definido' : 'Horario: $time',
              style: pw.TextStyle(
                fontSize: 11.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#166534'),
              ),
            ),
          ),
        );

        if (exercises.isEmpty) {
          blocks.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
              ),
              child: pw.Text(
                'Nenhum exercicio cadastrado neste horario.',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  color: PdfColor.fromHex('#64748B'),
                ),
              ),
            ),
          );
        } else {
          for (int i = 0; i < exercises.length; i++) {
            final ex = exercises[i];
            blocks.add(
              _pdfExerciseTile(
                index: i + 1,
                name: ex['name'] ?? '',
                category: ex['category'] ?? 'Outros',
              ),
            );
          }
        }
      });
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 26),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gerado em $generatedAt - Pagina ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromHex('#94A3B8'),
            ),
          ),
        ),
        build: (context) => [
          _pdfHeaderCard(
            logo: logo,
            title: 'FitMatch - ${title.replaceAll(':', '')}',
            subtitle: 'Treinos deste plano organizados por dia e horario',
          ),
          pw.SizedBox(height: 12),
          _pdfInfoItem(label: 'Personal', value: widget.trainerName),
          pw.SizedBox(height: 12),
          _pdfSectionTitle('Agenda de exercicios'),
          pw.SizedBox(height: 8),
          ...blocks,
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> _printPlansByPanel(
    String panelKey,
    String panelTitle,
    List<Map<String, dynamic>> plans,
  ) async {
    final opKey = 'print|$panelKey';
    if (plans.isEmpty || _exportingPlanKeys.contains(opKey)) return;
    setState(() => _exportingPlanKeys.add(opKey));
    try {
      final bytes = await _buildPlansPdfFor(plans, title: panelTitle);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      _showErrorSnack('Não foi possível imprimir este plano agora.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(opKey));
      }
    }
  }

  Future<void> _deletePlansByPanel(
    String panelKey,
    String panelTitle,
    List<Map<String, dynamic>> plans,
  ) async {
    final opKey = 'delete|$panelKey';
    if (plans.isEmpty || _exportingPlanKeys.contains(opKey)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover do seu painel?'),
        content: Text(
          'Esta ação removerá ${plans.length} treino(s) de $panelTitle apenas da sua tela.',
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
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _exportingPlanKeys.add(opKey));
    try {
      final seen = <int>{};
      var changed = false;
      for (final plan in plans) {
        final normalizedId = _normalizePlanId(plan['id']);
        final planId = normalizedId == null ? null : int.tryParse(normalizedId);
        if (planId == null || seen.contains(planId)) continue;
        seen.add(planId);
        changed = _hiddenPlanIds.add(planId.toString()) || changed;
      }
      if (changed) {
        await _persistHiddenPlanIds();
      }
      await _loadPlans();
    } catch (_) {
      _showErrorSnack('Não foi possível remover este plano agora.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(opKey));
      }
    }
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unassignedPlans = List<Map<String, dynamic>>.from(_plans);
    final panelModels = <Map<String, dynamic>>[];

    for (final req in _approvedRequestPlans) {
      final requestSlots = _requestSlotsFromRequest(req);
      final slotKeys = requestSlots
          .map((slot) => _slotKey(
                (slot['dayName'] ?? '').toString(),
                (slot['time'] ?? '').toString(),
              ))
          .toSet();

      final plansForPanel = <Map<String, dynamic>>[];
      unassignedPlans.removeWhere((plan) {
        final matches = slotKeys.contains(
          _slotKey(
            (plan['dayName'] ?? '').toString(),
            (plan['time'] ?? '').toString(),
          ),
        );
        if (matches) plansForPanel.add(plan);
        return matches;
      });

      if (plansForPanel.isEmpty) {
        continue;
      }

      final planType = (req['planType'] ?? '').toString().toUpperCase();
      String panelTitle;
      if (planType == 'DIARIO' && requestSlots.isNotEmpty) {
        final slot = requestSlots.first;
        final dayName = (slot['dayName'] ?? '').toString().trim();
        final rawTime = (slot['time'] ?? '').toString().trim();
        final timeLabel = rawTime.endsWith(':00')
            ? '${rawTime.split(':').first}h'
            : rawTime;
        panelTitle = 'Plano diário: $dayName as $timeLabel';
      } else {
        panelTitle = '${_planTitleFromType(req['planType']?.toString())}:';
      }

      panelModels.add({
        'key': _requestPlanKey(req),
        'request': req,
        'title': panelTitle,
        'plans': plansForPanel,
        'chips': _buildPlanSummaryChips(req, plansForPanel),
      });
    }

    if (unassignedPlans.isNotEmpty) {
      panelModels.add({
        'key': 'legacy',
        'request': null,
        'title': 'Plano diário:',
        'plans': unassignedPlans,
        'chips': _buildPlanSummaryChips(null, unassignedPlans),
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Voltar',
        ),
        title: Text('Treinos • ${widget.trainerName}'),
        backgroundColor: const Color(0xFF0B4DBA),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B4DBA)),
            )
          : RefreshIndicator(
              onRefresh: _loadPlans,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (panelModels.isEmpty)
                    _sectionCard(
                      child: const Text(
                        'Seu personal ainda não organizou treinos para você.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    )
                  else
                    ...panelModels.map((panel) {
                      final panelKey = (panel['key'] ?? '').toString();
                      final panelTitle = (panel['title'] ?? '').toString();
                      final panelRequestRaw = panel['request'];
                      final panelRequest = panelRequestRaw is Map
                          ? Map<String, dynamic>.from(panelRequestRaw)
                          : null;
                      final panelPlans = List<Map<String, dynamic>>.from(
                        panel['plans'] as List? ?? const [],
                      );
                      final panelIsOld = _isPanelOld(panelRequest, panelPlans);
                      final panelChips = List<({String label, bool highlight})>.from(
                        panel['chips'] as List? ?? const <({String label, bool highlight})>[],
                      );
                      final panelExpanded = _expandedPlanPanels.contains(panelKey);
                      final groupedPanel = _groupPlansByDayAndTimeFor(panelPlans);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      panelTitle,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  if (panelIsOld)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1F2),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: const Color(0xFFFECACA)),
                                      ),
                                      child: const Text(
                                        'Plano antigo',
                                        style: TextStyle(
                                          color: Color(0xFFB91C1C),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    onPressed: panelPlans.isEmpty ||
                                            _exportingPlanKeys.contains('print|$panelKey')
                                        ? null
                                        : () => _printPlansByPanel(
                                              panelKey,
                                              panelTitle,
                                              panelPlans,
                                            ),
                                    tooltip: 'Imprimir',
                                    iconSize: 20,
                                    visualDensity: VisualDensity.compact,
                                    splashRadius: 18,
                                    icon: _exportingPlanKeys.contains('print|$panelKey')
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.print_rounded,
                                            color: Color(0xFF475569),
                                          ),
                                  ),
                                  IconButton(
                                    onPressed: panelPlans.isEmpty ||
                                            _exportingPlanKeys.contains('delete|$panelKey')
                                        ? null
                                        : () => _deletePlansByPanel(
                                              panelKey,
                                              panelTitle,
                                              panelPlans,
                                            ),
                                    tooltip: 'Deletar',
                                    iconSize: 20,
                                    visualDensity: VisualDensity.compact,
                                    splashRadius: 18,
                                    icon: _exportingPlanKeys.contains('delete|$panelKey')
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFF475569),
                                          ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        if (panelExpanded) {
                                          _expandedPlanPanels.remove(panelKey);
                                          _expandedDays.removeWhere(
                                            (key) => key.startsWith('$panelKey|'),
                                          );
                                          _expandedTimes.removeWhere(
                                            (key) => key.startsWith('$panelKey|'),
                                          );
                                        } else {
                                          _expandedPlanPanels.add(panelKey);
                                        }
                                      });
                                    },
                                    icon: Icon(
                                      panelExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: const Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                              if (panelChips.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: panelChips.map((chip) {
                                    final highlight = chip.highlight;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: highlight
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: highlight
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (highlight) ...[
                                            const Icon(
                                              Icons.star_rounded,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            chip.label,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: highlight
                                                  ? Colors.white
                                                  : const Color(0xFF475569),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                              if (panelExpanded) ...[
                                const SizedBox(height: 14),
                                ...groupedPanel.entries.map((dayEntry) {
                      final dayName = dayEntry.key;
                      final plansPerTime = dayEntry.value;
                      final dayExpanded = _expandedDays.contains('$panelKey|$dayName');

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (dayExpanded) {
                                      _expandedDays.remove('$panelKey|$dayName');
                                      _expandedTimes.removeWhere(
                                        (key) => key.startsWith('$panelKey|$dayName|'),
                                      );
                                    } else {
                                      _expandedDays.add('$panelKey|$dayName');
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDBEAFE),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          dayName,
                                          style: const TextStyle(
                                            color: Color(0xFF1D4ED8),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${plansPerTime.length} horário(s)',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        dayExpanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (dayExpanded) ...[
                                const SizedBox(height: 8),
                                ...plansPerTime.entries.map((timeEntry) {
                                  final time = timeEntry.key;
                                  final plansAtTime = timeEntry.value;
                                  final timeKey = '$panelKey|$dayName|$time';
                                  final timeExpanded = _expandedTimes.contains(timeKey);
                                  final primaryPlan = plansAtTime.first;
                                  final exercises = <Map<String, String>>[];
                                  for (final plan in plansAtTime) {
                                    exercises.addAll(_extractExercises(plan['exercises']));
                                  }

                                  final exportKey = _planExportKey(primaryPlan);
                                  final exporting = _exportingPlanKeys.contains(exportKey);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (timeExpanded) {
                                                _expandedTimes.remove(timeKey);
                                              } else {
                                                _expandedTimes.add(timeKey);
                                              }
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              children: [
                                                Text(
                                                  time.isEmpty ? 'Sem horário' : time,
                                                  style: const TextStyle(
                                                    color: Color(0xFF2563EB),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 26,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Icon(
                                                  timeExpanded
                                                      ? Icons.keyboard_arrow_up_rounded
                                                      : Icons.keyboard_arrow_down_rounded,
                                                  color: const Color(0xFF64748B),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (timeExpanded) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: exporting
                                                    ? null
                                                    : () => _printPlan(primaryPlan),
                                                icon: exporting
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(Icons.print_rounded, size: 16),
                                                label: const Text('Imprimir'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(0xFF475569),
                                                  side: const BorderSide(
                                                    color: Color(0xFFCBD5E1),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                onPressed: exporting
                                                    ? null
                                                    : () => _downloadPlan(primaryPlan),
                                                icon: exporting
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : const Icon(Icons.download_rounded, size: 16),
                                                label: const Text('Baixar'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF0B4DBA),
                                                  foregroundColor: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          if (exercises.isEmpty)
                                            const Text(
                                              'Nenhum exercício cadastrado para este horário.',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.black54,
                                              ),
                                            )
                                          else
                                            ...exercises.map(
                                              (ex) => Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(0xFFE2E8F0),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.fitness_center_rounded,
                                                      size: 14,
                                                      color: Color(0xFF1D4ED8),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        ex['name'] ?? '',
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          color: Colors.black87,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      ex['category'] ?? 'Outros',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(0xFF2563EB),
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
