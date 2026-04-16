import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../services/auth_service.dart';
import '../widgets/fitmatch_logo.dart';
import 'trainer_chat_view.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

enum SlotState { available, requested, unavailable }

class _Slot {
  final String time;
  SlotState state;
  _Slot(this.time) : state = SlotState.available;
}

// ─── Main View ───────────────────────────────────────────────────────────────

class TrainerProfileView extends StatefulWidget {
  final String trainerName;
  final String specialties;
  final String? email;
  final String? cref;
  final String? city;
  final String? price;
  final String? bio;
  final int? trainerId;
  final int? studentId;
  final String? studentName;
  final String? horasPorSessao;

  const TrainerProfileView({
    super.key,
    this.trainerName = '',
    this.specialties = '',
    this.email,
    this.cref,
    this.city,
    this.price,
    this.bio,
    this.trainerId,
    this.studentId,
    this.studentName,
    this.horasPorSessao,
  });

  @override
  State<TrainerProfileView> createState() => _TrainerProfileViewState();
}

class _TrainerProfileViewState extends State<TrainerProfileView> {
  int _selectedDay = 0;
  int _scheduleWeekOffset = 0;
  bool _isFavorite = false;
  bool _sendingRequest = false;
  bool _loadingSlots = true;
  bool _applyingBlockRange = false;
  bool _initialSchedulePositioned = false;
  String _inlinePlanType = 'DIARIO';
  List<Map<String, String>> _inlineSelectedSlots = [];

  // Conexão (seguir/amigo)
  bool _connected = false;
  bool _sendingConnection = false;
  int? _connectionId;

  // Avaliações
  List<Map<String, dynamic>> _ratings = [];
  bool _loadingRatings = true;
  double _avgRating = 0;

  // Pendências do aluno e de outros alunos (para overlay por data real)
  List<Map<String, dynamic>> _studentPendingRequests = [];
  List<Map<String, dynamic>> _otherPendingRequests = [];
  List<Map<String, dynamic>> _approvedRequests = [];
  List<Map<String, String>> _oneTimeManualBlocks = [];
  List<Map<String, String>> _oneTimeManualUnblocks = [];

  // Timer para atualizar slots pendentes periodicamente
  Timer? _slotsRefreshTimer;

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

  static const List<Map<String, String>> _planOptions = [
    {'type': 'DIARIO', 'label': 'Diário', 'sub': 'Mesmo dia'},
    {'type': 'SEMANAL', 'label': 'Semanal', 'sub': 'Recorrente'},
    {'type': 'MENSAL', 'label': 'Mensal', 'sub': 'Por 1 mês'},
  ];

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

    if (source.startsWith('seg')) return 'Segunda';
    if (source.startsWith('ter')) return 'Terça';
    if (source.startsWith('qua')) return 'Quarta';
    if (source.startsWith('qui')) return 'Quinta';
    if (source.startsWith('sex')) return 'Sexta';
    if (source.startsWith('sab')) return 'Sábado';
    if (source.startsWith('dom')) return 'Domingo';

    return raw.trim();
  }

  String _normalizeTime(String raw) {
    final text = raw.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return text;
    final hh = (int.tryParse(match.group(1) ?? '') ?? 0).toString().padLeft(2, '0');
    final mm = (int.tryParse(match.group(2) ?? '') ?? 0).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  late final Map<String, List<_Slot>> _schedule;

  List<Map<String, String>> _requestSlotsFromData(Map<String, dynamic> req) {
    final raw = req['daysJson']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        return decoded
            .whereType<Map>()
            .map((slot) => {
              'dayName': _normalizeDayName((slot['dayName'] ?? '').toString()),
              'time': _normalizeTime((slot['time'] ?? '').toString()),
              'dateLabel': (slot['dateLabel'] ?? '').toString().trim(),
              'dateIso': (slot['dateIso'] ?? '').toString().trim(),
                })
            .where((slot) =>
                slot['dayName']!.isNotEmpty && slot['time']!.isNotEmpty)
            .toList();
      } catch (_) {
        // usa os campos principais como fallback
      }
    }

    final dayName = _normalizeDayName((req['dayName'] ?? '').toString());
    final time = _normalizeTime((req['time'] ?? '').toString());
    if (dayName.isEmpty || time.isEmpty) return [];
    return [
      {'dayName': dayName, 'time': time, 'dateLabel': '', 'dateIso': ''}
    ];
  }

  DateTime _requestAnchorFromReq(Map<String, dynamic> req) {
    return DateTime.tryParse((req['createdAt'] ?? '').toString()) ?? DateTime.now();
  }

  DateTime? _requestSlotStartDateTime(
    Map<String, String> slot,
    DateTime anchor,
  ) {
    final dayName = (slot['dayName'] ?? '').trim();
    final time = (slot['time'] ?? '').trim();
    final weekday = _weekdayFromDayName(dayName);
    final hm = _parseHourMinute(time);
    if (weekday == null || hm == null) return null;

    final iso = (slot['dateIso'] ?? '').trim();
    if (iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
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
    return candidate;
  }

  bool _isDailyPendingMatch(
    List<Map<String, dynamic>> requests,
    String dayName,
    String time,
  ) {
    final dayIndex = _days.indexOf(dayName);
    if (dayIndex < 0) return false;

    final candidate = _slotDateTimeFor(dayIndex, time);
    if (candidate == null) return false;

    final normalizedDay = _normalizeDayName(dayName);
    final normalizedTime = _normalizeTime(time);

    for (final req in requests) {
      if ((req['status'] ?? '').toString() != 'PENDING') continue;
      if ((req['planType'] ?? 'DIARIO').toString().toUpperCase() != 'DIARIO') {
        continue;
      }

      final anchor = _requestAnchorFromReq(req);
      for (final selected in _requestSlotsFromData(req)) {
        final reqDay = _normalizeDayName((selected['dayName'] ?? '').toString());
        final reqTime = _normalizeTime((selected['time'] ?? '').toString());
        if (reqDay != normalizedDay || reqTime != normalizedTime) continue;

        final startAt = _requestSlotStartDateTime(selected, anchor);
        if (startAt == null) continue;

        final sameMoment =
            candidate.year == startAt.year &&
            candidate.month == startAt.month &&
            candidate.day == startAt.day &&
            candidate.hour == startAt.hour &&
            candidate.minute == startAt.minute;
        if (sameMoment) {
          return true;
        }
      }
    }

    return false;
  }

  SlotState _effectiveStudentSlotState(String dayName, String time, SlotState baseState) {
    if (widget.studentId == null) return baseState;

    if (_isApprovedSlotMatch(dayName, time)) {
      return SlotState.unavailable;
    }

    if (_isDailyPendingMatch(_studentPendingRequests, dayName, time)) {
      return SlotState.requested;
    }

    if (_isWeeklyOrMonthlyPendingMatch(_studentPendingRequests, dayName, time)) {
      return SlotState.requested;
    }

    if (baseState == SlotState.available &&
        _isDailyPendingMatch(_otherPendingRequests, dayName, time)) {
      return SlotState.unavailable;
    }

    if (baseState == SlotState.available &&
        _isWeeklyOrMonthlyPendingMatch(_otherPendingRequests, dayName, time)) {
      return SlotState.unavailable;
    }

    if (_hasOneTimeManualUnblock(dayName, time)) {
      return SlotState.available;
    }

    if (_hasOneTimeManualBlock(dayName, time)) {
      return SlotState.unavailable;
    }

    return baseState;
  }

  String _toDateIso(DateTime value) {
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  bool _hasOneTimeManualBlock(String dayName, String time) {
    final dayIndex = _days.indexOf(_normalizeDayName(dayName));
    if (dayIndex < 0) return false;

    final slotDate = _slotDateTimeFor(dayIndex, time, weekOffset: _scheduleWeekOffset);
    if (slotDate == null) return false;

    final dateIso = _toDateIso(slotDate);
    final normalizedTime = _normalizeTime(time);
    final normalizedDay = _normalizeDayName(dayName);

    for (final blocked in _oneTimeManualBlocks) {
      final blockedDay = _normalizeDayName((blocked['dayName'] ?? '').toString());
      final blockedTime = _normalizeTime((blocked['time'] ?? '').toString());
      final blockedDate = (blocked['dateIso'] ?? '').toString().trim();
      final dayMatches = blockedDay.isEmpty || blockedDay == normalizedDay;
      if (dayMatches && blockedTime == normalizedTime && blockedDate == dateIso) {
        return true;
      }
    }
    return false;
  }

  bool _hasOneTimeManualUnblock(String dayName, String time) {
    final dayIndex = _days.indexOf(_normalizeDayName(dayName));
    if (dayIndex < 0) return false;

    final slotDate =
        _slotDateTimeFor(dayIndex, time, weekOffset: _scheduleWeekOffset);
    if (slotDate == null) return false;

    final dateIso = _toDateIso(slotDate);
    final normalizedTime = _normalizeTime(time);
    final normalizedDay = _normalizeDayName(dayName);

    for (final unblocked in _oneTimeManualUnblocks) {
      final unblockedDay =
          _normalizeDayName((unblocked['dayName'] ?? '').toString());
      final unblockedTime =
          _normalizeTime((unblocked['time'] ?? '').toString());
      final unblockedDate = (unblocked['dateIso'] ?? '').toString().trim();
      final dayMatches = unblockedDay.isEmpty || unblockedDay == normalizedDay;
      if (dayMatches &&
          unblockedTime == normalizedTime &&
          unblockedDate == dateIso) {
        return true;
      }
    }
    return false;
  }

  bool _isWeeklyOrMonthlyPendingMatch(
    List<Map<String, dynamic>> requests,
    String dayName,
    String time,
  ) {
    final dayIndex = _days.indexOf(_normalizeDayName(dayName));
    if (dayIndex < 0) return false;

    final candidate = _slotDateTimeFor(
      dayIndex,
      time,
      weekOffset: _scheduleWeekOffset,
    );
    if (candidate == null) return false;

    final normalizedDay = _normalizeDayName(dayName);
    final normalizedTime = _normalizeTime(time);

    for (final req in requests) {
      if ((req['status'] ?? '').toString().toUpperCase() != 'PENDING') {
        continue;
      }

      final planType = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      if (planType != 'SEMANAL' && planType != 'MENSAL') {
        continue;
      }

      final anchor =
          DateTime.tryParse((req['createdAt'] ?? '').toString()) ?? DateTime.now();
        final windowEnd = planType == 'MENSAL'
          ? _addOneMonthKeepingDay(anchor)
          : null;

      for (final selected in _requestSlotsFromData(req)) {
        final reqDay = _normalizeDayName((selected['dayName'] ?? '').toString());
        final reqTime = _normalizeTime((selected['time'] ?? '').toString());
        if (reqDay != normalizedDay || reqTime != normalizedTime) continue;

        final slotStart = _requestSlotStartDateTime(selected, anchor);
        if (slotStart == null) continue;

        final sameMoment =
            candidate.year == slotStart.year &&
            candidate.month == slotStart.month &&
            candidate.day == slotStart.day &&
            candidate.hour == slotStart.hour &&
            candidate.minute == slotStart.minute;

        if (planType == 'SEMANAL') {
          if (sameMoment) return true;
          continue;
        }

        if (candidate.isBefore(slotStart) || candidate.isAfter(windowEnd!)) {
          continue;
        }

        final diffDays = candidate.difference(slotStart).inDays;
        if (diffDays % 7 == 0) {
          return true;
        }
      }
    }

    return false;
  }

  DateTime _requestAnchorForAvailability(Map<String, dynamic> req) {
    return DateTime.tryParse((req['approvedAt'] ?? '').toString()) ??
        DateTime.tryParse((req['createdAt'] ?? '').toString()) ??
        DateTime.now();
  }

  bool _isApprovedSlotMatch(String dayName, String time) {
    final dayIndex = _days.indexOf(_normalizeDayName(dayName));
    if (dayIndex < 0) return false;

    final candidate = _slotDateTimeFor(
      dayIndex,
      time,
      weekOffset: _scheduleWeekOffset,
    );
    if (candidate == null) return false;

    final normalizedDay = _normalizeDayName(dayName);
    final normalizedTime = _normalizeTime(time);

    for (final req in _approvedRequests) {
      if ((req['status'] ?? '').toString().toUpperCase() != 'APPROVED') {
        continue;
      }

      final planType = (req['planType'] ?? 'DIARIO').toString().toUpperCase();
      final slots = _requestSlotsFromData(req);
      if (slots.isEmpty) continue;

      if (planType == 'SEMANAL') {
        final anchor = DateTime.tryParse((req['createdAt'] ?? '').toString()) ??
            _requestAnchorForAvailability(req);

        for (final slot in slots) {
          final reqDay = _normalizeDayName((slot['dayName'] ?? '').toString());
          final reqTime = _normalizeTime((slot['time'] ?? '').toString());
          if (reqDay != normalizedDay || reqTime != normalizedTime) continue;

          final slotStart = _requestSlotStartDateTime(slot, anchor);
          if (slotStart == null) continue;

          final sameMoment =
              candidate.year == slotStart.year &&
              candidate.month == slotStart.month &&
              candidate.day == slotStart.day &&
              candidate.hour == slotStart.hour &&
              candidate.minute == slotStart.minute;
          if (sameMoment) {
            return true;
          }
        }
        continue;
      }

      if (planType == 'DIARIO') {
        final anchor = _requestAnchorForAvailability(req);
        for (final slot in slots) {
          final reqDay = _normalizeDayName((slot['dayName'] ?? '').toString());
          final reqTime = _normalizeTime((slot['time'] ?? '').toString());
          if (reqDay != normalizedDay || reqTime != normalizedTime) continue;

          final startAt = _requestSlotStartDateTime(slot, anchor);
          if (startAt == null) continue;

          final sameMoment =
              candidate.year == startAt.year &&
              candidate.month == startAt.month &&
              candidate.day == startAt.day &&
              candidate.hour == startAt.hour &&
              candidate.minute == startAt.minute;
          if (sameMoment) {
            return true;
          }
        }
        continue;
      }

      if (planType == 'MENSAL') {
        final anchor = DateTime.tryParse((req['createdAt'] ?? '').toString()) ??
            _requestAnchorForAvailability(req);
        final windowEnd = _addOneMonthKeepingDay(anchor);

        for (final slot in slots) {
          final reqDay = _normalizeDayName((slot['dayName'] ?? '').toString());
          final reqTime = _normalizeTime((slot['time'] ?? '').toString());
          if (reqDay != normalizedDay || reqTime != normalizedTime) continue;

          final slotStart = _requestSlotStartDateTime(slot, anchor);
          if (slotStart == null || candidate.isBefore(slotStart)) continue;
          if (candidate.isAfter(windowEnd)) continue;

          final diffDays = candidate.difference(slotStart).inDays;
          if (diffDays % 7 == 0) {
            return true;
          }
        }
      }
    }

    return false;
  }

  String _buildRequestAutoMessage({
    required String planType,
    required List<Map<String, String>> selectedSlots,
  }) {
    final planLabel = planType == 'SEMANAL'
        ? 'Plano Semanal'
        : planType == 'MENSAL'
            ? 'Plano Mensal'
            : 'Plano Diário';

    final slotsText = planType.toUpperCase() == 'MENSAL'
        ? _monthlySelectionSummaryLabels(selectedSlots, forChat: true).join('\n')
        : selectedSlots
            .map((s) {
              final dayName = (s['dayName'] ?? '').trim();
              final time = (s['time'] ?? '').trim();
              final dateLabel = (s['dateLabel'] ?? '').trim();
              if (dateLabel.isNotEmpty) {
                return '$dayName $dateLabel às $time';
              }
              return '$dayName às $time';
            })
            .join('\n');

    return 'Gostaria de solicitar um $planLabel com os seguintes horários:\n$slotsText';
  }

  DateTime _startOfWeek(DateTime baseDate) {
    final normalized = DateTime(baseDate.year, baseDate.month, baseDate.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  DateTime _dateForDayIndex(int dayIndex, {int? weekOffset}) {
    final offset = weekOffset ?? _scheduleWeekOffset;
    final weekStart = _startOfWeek(DateTime.now()).add(Duration(days: offset * 7));
    return weekStart.add(Duration(days: dayIndex));
  }

  String _formatDateLabel(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }

  String _dayChipDateLabel(int dayIndex) {
    return _formatDateLabel(_dateForDayIndex(dayIndex));
  }

  String _weekRangeLabel() {
    final start = _dateForDayIndex(0);
    final end = _dateForDayIndex(6);
    final startLabel = _formatDateLabel(start);
    final endLabel = _formatDateLabel(end);
    return '$startLabel-$endLabel';
  }

  DateTime? _slotDateTimeFor(
    int dayIndex,
    String time, {
    int? weekOffset,
  }) {
    final parts = time.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;

    final dayDate = _dateForDayIndex(dayIndex, weekOffset: weekOffset);
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      hour,
      minute,
    );
  }

  bool _isPastSlotFor(int dayIndex, String time, {int? weekOffset}) {
    final slotDateTime = _slotDateTimeFor(dayIndex, time, weekOffset: weekOffset);
    if (slotDateTime == null) return false;
    return slotDateTime.isBefore(DateTime.now());
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _selectionWindowEnd(String planType, {DateTime? anchor}) {
    final normalizedPlan = planType.toUpperCase();
    final base = _dateOnly(anchor ?? DateTime.now());

    if (normalizedPlan == 'MENSAL') {
      final endDate = _addOneMonthKeepingDay(base);
      return DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    }

    return DateTime(9999, 12, 31);
  }

  DateTime _selectionAnchorForPlan(
    String planType, {
    DateTime? fallback,
    List<Map<String, String>>? selections,
  }) {
    final normalizedPlan = planType.toUpperCase();
    final effectiveSelections = selections ?? _inlineSelectedSlots;
    if (normalizedPlan != 'SEMANAL' && normalizedPlan != 'MENSAL') {
      return _dateOnly(fallback ?? DateTime.now());
    }

    for (final selection in effectiveSelections) {
      final dt = _selectionDateTime(selection);
      if (dt == null) continue;
      return _dateOnly(dt);
    }

    return _dateOnly(fallback ?? DateTime.now());
  }

  bool _isWithinSelectionWindow(
    DateTime slotDateTime,
    String planType, {
    DateTime? anchor,
  }) {
    final normalizedPlan = planType.toUpperCase();
    if (normalizedPlan != 'MENSAL') {
      return true;
    }
    final start = _dateOnly(anchor ?? DateTime.now());
    final end = _selectionWindowEnd(normalizedPlan, anchor: start);
    return !slotDateTime.isBefore(start) && !slotDateTime.isAfter(end);
  }

  int _countDistinctSelectedDates(
    List<Map<String, String>> selections, {
    DateTime? extraDate,
  }) {
    final dateKeys = <String>{};
    for (final s in selections) {
      final dt = _selectionDateTime(s);
      if (dt == null) continue;
      dateKeys.add(_toDateIso(dt));
    }
    if (extraDate != null) {
      dateKeys.add(_toDateIso(extraDate));
    }
    return dateKeys.length;
  }

  DateTime _weeklyEarliestStartDate() {
    final now = DateTime.now();
    final today = _dateOnly(now);

    if (now.weekday == DateTime.monday || now.weekday == DateTime.tuesday) {
      return today.add(const Duration(days: 1));
    }

    return _startOfWeek(today).add(const Duration(days: 7));
  }

  bool _isBlockedByWeeklyStartRule(int dayIndex, {int? weekOffset}) {
    return false;
  }

  String _inlineSelectionLabel(Map<String, String> selection) {
    final dayName = selection['dayName'] ?? '';
    final time = selection['time'] ?? '';
    final dateLabel = selection['dateLabel'];

    if (dateLabel != null && dateLabel.isNotEmpty) {
      return '$dayName $dateLabel · $time';
    }

    final dayIndex = _days.indexOf(dayName);
    if (dayIndex >= 0) {
      return '$dayName ${_dayChipDateLabel(dayIndex)} · $time';
    }
    return '$dayName · $time';
  }

  int? _weekdayFromDayName(String dayName) {
    final normalized = _normalizeDayName(dayName);
    final idx = _days.indexOf(normalized);
    if (idx < 0) return null;
    return idx + 1; // DateTime: monday=1 ... sunday=7
  }

  String _dayNameFromWeekday(int weekday) {
    final idx = weekday - 1;
    if (idx < 0 || idx >= _days.length) return '';
    return _days[idx];
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

  DateTime? _selectionDateTime(Map<String, String> selection) {
    final iso = (selection['dateIso'] ?? '').trim();
    if (iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) return parsed;
    }

    final dayName = (selection['dayName'] ?? '').trim();
    final time = (selection['time'] ?? '').trim();
    final hm = _parseHourMinute(time);
    final weekday = _weekdayFromDayName(dayName);
    if (hm == null || weekday == null) return null;

    final dateLabel = (selection['dateLabel'] ?? '').trim();
    final dateMatch = RegExp(r'^(\d{2})\/(\d{2})$').firstMatch(dateLabel);
    if (dateMatch != null) {
      final day = int.tryParse(dateMatch.group(1)!);
      final month = int.tryParse(dateMatch.group(2)!);
      if (day != null && month != null) {
        final now = DateTime.now();
        return DateTime(now.year, month, day, hm.$1, hm.$2);
      }
    }

    final fallback = _nextOccurrence(DateTime.now(), weekday, hm.$1, hm.$2);
    return fallback;
  }

  String _formatMonthlyLabel({
    required String dayName,
    required String time,
    DateTime? date,
    required bool forChat,
  }) {
    final dateLabel = date != null ? _formatDateLabel(date) : '';
    if (dateLabel.isNotEmpty) {
      return forChat
          ? '$dayName $dateLabel às $time'
          : '$dayName $dateLabel · $time';
    }
    return forChat ? '$dayName às $time' : '$dayName · $time';
  }

  List<String> _monthlySelectionSummaryLabels(
    List<Map<String, String>> selections, {
    bool forChat = false,
  }) {
    if (selections.isEmpty) return const [];

    final parsed = <Map<String, dynamic>>[];
    for (final s in selections) {
      final dayName = (s['dayName'] ?? '').trim();
      final time = (s['time'] ?? '').trim();
      final date = _selectionDateTime(s);
      final hm = _parseHourMinute(time);
      final weekday = _weekdayFromDayName(dayName);
      if (dayName.isEmpty || time.isEmpty || date == null || hm == null || weekday == null) {
        continue;
      }
      parsed.add({
        'dayName': dayName,
        'time': time,
        'date': date,
        'weekday': weekday,
        'hour': hm.$1,
        'minute': hm.$2,
      });
    }

    if (parsed.isEmpty) {
      return selections.map(_inlineSelectionLabel).toList();
    }

    parsed.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    final first = parsed.first;
    final firstDate = first['date'] as DateTime;
    final windowEnd = _addOneMonthKeepingDay(firstDate);

    final patterns = <String, Map<String, dynamic>>{};
    for (final item in parsed) {
      final key = '${item['weekday']}|${item['time']}';
      patterns.putIfAbsent(key, () => item);
    }

    final firstKey = '${first['weekday']}|${first['time']}';
    final middlePatterns = patterns.entries
        .where((e) => e.key != firstKey)
        .map((e) => e.value)
        .toList();

    middlePatterns.sort((a, b) {
      final nextA = _nextOccurrence(
        firstDate,
        a['weekday'] as int,
        a['hour'] as int,
        a['minute'] as int,
      );
      final nextB = _nextOccurrence(
        firstDate,
        b['weekday'] as int,
        b['hour'] as int,
        b['minute'] as int,
      );
      return nextA.compareTo(nextB);
    });

    DateTime? lastDate;
    Map<String, dynamic>? lastPattern;
    for (final pattern in patterns.values) {
      var candidate = _nextOccurrence(
        firstDate,
        pattern['weekday'] as int,
        pattern['hour'] as int,
        pattern['minute'] as int,
      );
      if (candidate.isAfter(windowEnd)) continue;

      while (candidate.add(const Duration(days: 7)).isBefore(windowEnd) ||
          candidate.add(const Duration(days: 7)).isAtSameMomentAs(windowEnd)) {
        candidate = candidate.add(const Duration(days: 7));
      }

      if (lastDate == null || candidate.isAfter(lastDate)) {
        lastDate = candidate;
        lastPattern = pattern;
      }
    }

    final labels = <String>[
      _formatMonthlyLabel(
        dayName: first['dayName'] as String,
        time: first['time'] as String,
        date: firstDate,
        forChat: forChat,
      ),
    ];

    for (final pattern in middlePatterns) {
      labels.add(
        _formatMonthlyLabel(
          dayName: pattern['dayName'] as String,
          time: pattern['time'] as String,
          forChat: forChat,
        ),
      );
    }

    if (lastDate != null && lastPattern != null && lastDate.isAfter(firstDate)) {
      final lastDayName = _dayNameFromWeekday(lastDate.weekday);
      labels.add(
        _formatMonthlyLabel(
          dayName: lastDayName.isNotEmpty
              ? lastDayName
              : (lastPattern['dayName'] as String),
          time: lastPattern['time'] as String,
          date: lastDate,
          forChat: forChat,
        ),
      );
    }

    return labels;
  }

  int _minimumWeekOffsetForPlanType(String planType) {
    return 0;
  }

  bool _hasRequestableSlot(int dayIndex, int weekOffset) {
    final dayName = _days[dayIndex];
    final daySlots = _schedule[dayName] ?? const <_Slot>[];
    return daySlots.any(
      (slot) =>
          slot.state == SlotState.available &&
          !_isPastSlotFor(dayIndex, slot.time, weekOffset: weekOffset),
    );
  }

  void _positionScheduleForStudent() {
    if (_initialSchedulePositioned || widget.studentId == null) return;

    final now = DateTime.now();
    final todayIndex = now.weekday - 1; // monday=1 -> index 0
    const maxFutureWeeks = 8;

    // Prioriza o dia atual. Se não houver horários válidos, avança para o próximo dia/semana.
    for (int week = 0; week <= maxFutureWeeks; week++) {
      final startDay = week == 0 ? todayIndex : 0;
      for (int day = startDay; day < _days.length; day++) {
        if (_hasRequestableSlot(day, week)) {
          setState(() {
            _scheduleWeekOffset = week;
            _selectedDay = day;
            _initialSchedulePositioned = true;
          });
          return;
        }
      }
    }

    // Fallback: mantém a semana atual e abre no dia de hoje.
    setState(() {
      _scheduleWeekOffset = 0;
      _selectedDay = todayIndex;
      _initialSchedulePositioned = true;
    });
  }

  @override
  void initState() {
    super.initState();
    final allSlots = [
      for (int h = 0; h < 24; h++) '${h.toString().padLeft(2, '0')}:00'
    ];
    _schedule = {
      for (final d in _days) d: allSlots.map((t) => _Slot(t)).toList(),
    };
    _loadSlotStates();
    // Atualiza slots pendentes a cada 5 segundos para refletir solicitações recebidas em tempo real
    _slotsRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadSlotStates(),
    );
  }

  Future<void> _loadSlotStates() async {
    if (widget.trainerId == null) {
      if (mounted) setState(() => _loadingSlots = false);
      return;
    }
    try {
      // Carrega slots, solicitações, conexões, avaliações e solicitações pendentes em paralelo
      final futures = await Future.wait([
        AuthService.getTrainerSlots(widget.trainerId!),
        widget.studentId != null
            ? AuthService.getStudentRequests(widget.studentId!)
            : Future.value(<Map<String, dynamic>>[]),
        widget.studentId != null
            ? AuthService.getTrainerConnections(widget.trainerId!)
            : Future.value(<Map<String, dynamic>>[]),
        AuthService.getTrainerRatings(widget.trainerId!),
        AuthService.getAllTrainerRequests(widget.trainerId!),
      ]);
      if (!mounted) return;
      final blockedSlots = futures[0];
      final studentReqs = futures[1];
      final connections = futures[2];
      final ratings = futures[3];
      final allTrainerReqs = futures[4];

        final studentPendingForTrainer = studentReqs
          .where((req) =>
            req['trainerId'].toString() == widget.trainerId.toString() &&
            (req['status'] ?? '').toString() == 'PENDING')
          .map((req) => Map<String, dynamic>.from(req))
          .toList();

        final otherPendingForTrainer = allTrainerReqs
          .where((req) =>
            widget.studentId == null ||
            req['studentId'].toString() != widget.studentId.toString())
          .where((req) => (req['status'] ?? '').toString() == 'PENDING')
          .map((req) => Map<String, dynamic>.from(req))
          .toList();

        final approvedForTrainer = allTrainerReqs
          .where((req) => (req['status'] ?? '').toString() == 'APPROVED')
          .map((req) => Map<String, dynamic>.from(req))
          .toList();

      // Processa avaliações
      double avg = 0;
      if (ratings.isNotEmpty) {
        final total =
            ratings.fold<int>(0, (s, r) => s + ((r['stars'] ?? 0) as int));
        avg = total / ratings.length;
      }

      // Verifica se o aluno já está conectado ao personal
      int? connId;
      bool isConn = false;
      if (widget.studentId != null) {
        for (final c in connections) {
          if (c['studentId'].toString() ==
              widget.studentId.toString()) {
            isConn = true;
            connId = c['id'] is int
                ? c['id'] as int
                : int.tryParse(c['id'].toString());
            break;
          }
        }
      }

      setState(() {
        _oneTimeManualBlocks = [];
        _oneTimeManualUnblocks = [];
        // Reseta para disponível antes de aplicar o estado atual vindo da API.
        for (final daySlots in _schedule.values) {
          for (final slot in daySlots) {
            slot.state = SlotState.available;
          }
        }

        // Marca bloqueados
        for (final s in blockedSlots) {
          final day = _normalizeDayName(s['dayName']?.toString() ?? '');
          final time = _normalizeTime(s['time']?.toString() ?? '');
          final dateIso = (s['dateIso'] ?? '').toString().trim();
          final state = (s['state'] ?? '').toString().toUpperCase();

          // No perfil visto pelo aluno, slots de estado REQUEST devem ser
          // calculados pelos requests ativos (PENDING/APPROVED) para respeitar
          // regra de data real e evitar recorrência indevida em aula avulsa.
          if (widget.studentId != null && state == 'REQUEST') {
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
          final daySlots = _schedule[day];
          if (daySlots != null) {
            for (final slot in daySlots) {
              if (slot.time == time) slot.state = SlotState.unavailable;
            }
          }
        }
        // Marca slots que o próprio aluno já solicitou (pendentes) → exibe como "solicitado"
        for (final req in studentReqs) {
          if (req['trainerId'].toString() !=
              widget.trainerId.toString()) {
            continue;
          }
          if ((req['status'] ?? '') != 'PENDING') {
            continue;
          }
          if (widget.studentId != null) {
            continue;
          }
          final planType =
              (req['planType'] ?? 'DIARIO').toString().toUpperCase();
          if (planType == 'DIARIO') {
            continue;
          }
          for (final selected in _requestSlotsFromData(req)) {
            final day = selected['dayName'] ?? '';
            final time = selected['time'] ?? '';
            final daySlots = _schedule[day];
            if (daySlots != null) {
              for (final slot in daySlots) {
                if (slot.time == time &&
                    slot.state != SlotState.unavailable) {
                  slot.state = SlotState.requested;
                }
              }
            }
          }
        }
        // Marca slots pendentes de solicitações
        // - Se for o perfil do personal (studentId == null): marca como "solicitado" (amarelo)
        // - Se for um aluno vendo o perfil: marca apenas outros alunos como indisponível (cinza)
        for (final req in allTrainerReqs) {
          if ((req['status'] ?? '').toString() != 'PENDING') {
            continue;
          }
          if (widget.studentId != null) {
            continue;
          }
          // Se é aluno vendo o perfil, pula solicitações do próprio aluno
          if (widget.studentId != null &&
              req['studentId'].toString() == widget.studentId.toString()) {
            continue;
          }
          final planType =
              (req['planType'] ?? 'DIARIO').toString().toUpperCase();
          if (widget.studentId != null && planType == 'DIARIO') {
            continue;
          }
          for (final selected in _requestSlotsFromData(req)) {
            final day = selected['dayName'] ?? '';
            final time = selected['time'] ?? '';
            final daySlots = _schedule[day];
            if (daySlots != null) {
              for (final slot in daySlots) {
                if (slot.time == time && slot.state == SlotState.available) {
                  // Se é o perfil do personal (studentId == null), marca como solicitado (amarelo)
                  // Se é aluno vendo, marca como indisponível (cinza)
                  final newState = widget.studentId == null
                      ? SlotState.requested  // Personal vendo seu próprio perfil
                      : SlotState.unavailable; // Aluno vendo perfil de outro personal
                  slot.state = newState;
                }
              }
            }
          }
        }
        _loadingSlots = false;
        _ratings = List<Map<String, dynamic>>.from(ratings);
        _avgRating = avg;
        _loadingRatings = false;
        _connected = isConn;
        _connectionId = connId;
        _studentPendingRequests = studentPendingForTrainer;
        _otherPendingRequests = otherPendingForTrainer;
        _approvedRequests = approvedForTrainer;
      });

      _positionScheduleForStudent();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingSlots = false;
          _loadingRatings = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _slotsRefreshTimer?.cancel();
    super.dispose();
  }

  // ── Conexão (seguir personal) ─────────────────────────────────────────────

  Future<void> _connect() async {
    if (widget.studentId == null) return;
    setState(() => _sendingConnection = true);
    try {
      // Se studentName não foi passado, busca do backend
      String resolvedStudentName = widget.studentName ?? '';
      if (resolvedStudentName.isEmpty) {
        try {
          final userData = await AuthService.getUserById(widget.studentId!);
          resolvedStudentName = (userData['name'] ?? 'Aluno').toString();
        } catch (_) {
          resolvedStudentName = 'Aluno';
        }
      }
      final result = await AuthService.createConnection(
        studentId: widget.studentId!,
        trainerId: widget.trainerId!,
        studentName: resolvedStudentName,
        trainerName: widget.trainerName,
      );
      setState(() {
        _connected = true;
        _connectionId = result['id'] is int
            ? result['id'] as int
            : int.tryParse(result['id'].toString());
      });
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('Failed to fetch')
            ? 'Sem conexão com o servidor'
            : e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');
        _showSnack(
          msg,
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFEF4444),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingConnection = false);
    }
  }

  Future<void> _disconnect() async {
    if (_connectionId == null) return;
    setState(() => _sendingConnection = true);
    try {
      await AuthService.deleteConnection(_connectionId!);
      setState(() {
        _connected = false;
        _connectionId = null;
      });
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('Failed to fetch')
            ? 'Sem conexão com o servidor'
            : e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');
        _showSnack(
          msg,
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFEF4444),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingConnection = false);
    }
  }

  Widget _buildConnectionButton() {
    if (_sendingConnection) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: Color(0xFF0B4DBA), strokeWidth: 2),
          ),
        ),
      );
    }
    if (_connected) {
      return OutlinedButton.icon(
        onPressed: _disconnect,
        icon: const Icon(Icons.person_remove_rounded, size: 16),
        label: const Text('Deixar de Seguir'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFEF4444),
          side: const BorderSide(color: Color(0xFFEF4444)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          minimumSize: const Size(double.infinity, 0),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: _connect,
      icon: const Icon(Icons.person_add_rounded, size: 16),
      label: const Text('Seguir Personal'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0B4DBA),
        foregroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: const Size(double.infinity, 0),
        elevation: 0,
      ),
    );
  }

  // ── Diálogo de avaliação ──────────────────────────────────────────────────

  void _showRatingDialog() {
    if (widget.studentId == null || widget.studentName == null) return;
    showDialog(
      context: context,
      builder: (ctx) => _RatingDialog(
        trainerName: widget.trainerName,
        trainerId: widget.trainerId!,
        studentId: widget.studentId!,
        studentName: widget.studentName!,
        onSubmitted: (stars, comment) async {
          await AuthService.rateTrainer(
            trainerId: widget.trainerId!,
            studentId: widget.studentId!,
            studentName: widget.studentName!,
            stars: stars,
            comment: comment,
          );
          // Recarrega avaliações
          final updated =
              await AuthService.getTrainerRatings(widget.trainerId!);
          if (!mounted) return;
          double avg = 0;
          if (updated.isNotEmpty) {
            final total = updated.fold<int>(
                0, (s, r) => s + ((r['stars'] ?? 0) as int));
            avg = total / updated.length;
          }
          setState(() {
            _ratings = List<Map<String, dynamic>>.from(updated);
            _avgRating = avg;
          });
          if (!mounted) return;
          _showSnack('Avaliação enviada!',
              icon: Icons.star_rounded,
              color: const Color(0xFFF59E0B));
        },
      ),
    );
  }

  // ── Lógica de toque num horário ──────────────────────────────────────────

  void _onSlotTap(_Slot slot, String dayName) {
    if (widget.studentId == null) {
      if (slot.state == SlotState.requested) {
        _showSnack(
          '$dayName às ${slot.time} possui solicitação pendente.',
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFFF59E0B),
        );
        return;
      }
      _toggleTrainerSlotState(dayName, slot.time, slot.state == SlotState.available);
      return;
    }

    final dayIndex = _days.indexOf(dayName);
    if (dayIndex >= 0 && _isBlockedByWeeklyStartRule(dayIndex)) {
      final startDate = _weeklyEarliestStartDate();
      final startDayName = _dayNameFromWeekday(startDate.weekday);
      _showSnack(
        'No plano semanal, você pode iniciar a partir de $startDayName ${_formatDateLabel(startDate)}.',
        icon: Icons.event_repeat_rounded,
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    if (dayIndex >= 0 && _isPastSlotFor(dayIndex, slot.time)) {
      _showSnack(
        '$dayName às ${slot.time} está indisponível (horário passado).',
        icon: Icons.block_rounded,
        color: const Color(0xFFEF4444),
      );
      return;
    }

    switch (slot.state) {
      case SlotState.unavailable:
        _showSnack(
          '$dayName às ${slot.time} está indisponível',
          icon: Icons.block_rounded,
          color: const Color(0xFFEF4444),
        );
        return;
      case SlotState.requested:
        _showSnack(
          '$dayName às ${slot.time} – solicitação enviada, aguardando confirmação',
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFFF59E0B),
        );
        return;
      case SlotState.available:
        final selectedDayIndex = _days.indexOf(dayName);
        _toggleInlineSlot(
          dayName,
          slot.time,
          slotDate: selectedDayIndex >= 0
              ? _dateForDayIndex(selectedDayIndex, weekOffset: _scheduleWeekOffset)
              : DateTime.now(),
        );
        return;
    }
  }

  Future<void> _toggleTrainerSlotState(
    String dayName,
    String time,
    bool block,
  ) async {
    if (widget.trainerId == null) return;

    try {
      if (block) {
        await AuthService.blockSlot(widget.trainerId!, dayName, time);
      } else {
        await AuthService.unblockSlot(widget.trainerId!, dayName, time);
      }

      if (!mounted) return;
      setState(() {
        final daySlots = _schedule[dayName];
        if (daySlots == null) return;
        final idx = daySlots.indexWhere((s) => s.time == time);
        if (idx >= 0) {
          daySlots[idx].state = block ? SlotState.unavailable : SlotState.available;
        }
      });

      _showSnack(
        block
            ? '$dayName às $time bloqueado com sucesso.'
            : '$dayName às $time desbloqueado com sucesso.',
        icon: block ? Icons.lock_rounded : Icons.lock_open_rounded,
        color: block ? const Color(0xFF334155) : const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), ''),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
    }
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
    bool repeatAllDays = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Repetir horários bloqueados'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dia base: $dayName',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black54),
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
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: repeatAllDays,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aplicar em todos os dias da semana'),
                    onChanged: (v) {
                      setDialogState(() => repeatAllDays = v ?? false);
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
                    'repeatAllDays': repeatAllDays,
                  }),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    await _applyBlockRange(
      dayName: dayName,
      startTime: result['startTime'] as String,
      endTime: result['endTime'] as String,
      repeatAllDays: result['repeatAllDays'] as bool,
    );
  }

  Future<void> _applyBlockRange({
    required String dayName,
    required String startTime,
    required String endTime,
    required bool repeatAllDays,
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

    final targetDays = repeatAllDays ? List<String>.from(_days) : [dayName];
    var changedCount = 0;

    setState(() => _applyingBlockRange = true);
    try {
      for (final targetDay in targetDays) {
        final targetSlots = _schedule[targetDay] ?? [];
        for (int i = startIdx; i <= endIdx && i < targetSlots.length; i++) {
          final slot = targetSlots[i];
          if (slot.state == SlotState.unavailable || slot.state == SlotState.requested) {
            continue;
          }

          await AuthService.blockSlot(widget.trainerId!, targetDay, slot.time);
          slot.state = SlotState.unavailable;
          changedCount++;
        }
      }

      if (!mounted) return;
      setState(() {});
      _showSnack(
        changedCount > 0
            ? 'Bloqueio aplicado em $changedCount horário${changedCount > 1 ? 's' : ''}.'
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

  bool _isInlineSelected(String dayName, String time, {int? dayIndex}) {
    final normalizedDay = _normalizeDayName(dayName);
    final normalizedTime = _normalizeTime(time);
    final idx = dayIndex ?? _days.indexOf(normalizedDay);
    String currentDateIso = '';
    if (idx >= 0) {
      final currentDate = _dateForDayIndex(idx, weekOffset: _scheduleWeekOffset);
      currentDateIso = _toDateIso(currentDate);
    }

    return _inlineSelectedSlots.any((s) {
      final selDay = _normalizeDayName((s['dayName'] ?? '').toString());
      final selTime = _normalizeTime((s['time'] ?? '').toString());
      if (selDay != normalizedDay || selTime != normalizedTime) {
        return false;
      }

      final rawIso = (s['dateIso'] ?? '').toString().trim();
      final selDateIso = rawIso.length >= 10 ? rawIso.substring(0, 10) : rawIso;
      if (selDateIso.isNotEmpty && currentDateIso.isNotEmpty) {
        return selDateIso == currentDateIso;
      }

      final selOffset = int.tryParse((s['weekOffset'] ?? '').toString().trim());
      return selOffset == null || selOffset == _scheduleWeekOffset;
    });
  }

  void _changeInlinePlanType(String nextType) {
    final minOffset = _minimumWeekOffsetForPlanType(nextType);

    setState(() {
      _inlinePlanType = nextType;
      if (_scheduleWeekOffset < minOffset) {
        _scheduleWeekOffset = minOffset;
      }

      if (_inlinePlanType == 'SEMANAL') {
        _inlineSelectedSlots = [];
      }

      if (_inlinePlanType == 'DIARIO' && _inlineSelectedSlots.length > 1) {
        final firstDay = _inlineSelectedSlots.first['dayName'];
        _inlineSelectedSlots = _inlineSelectedSlots
            .where((s) => s['dayName'] == firstDay)
            .toList();
      }
    });

    if (nextType.toUpperCase() == 'SEMANAL') {
      _showSnack(
        'Plano semanal permite selecionar horários em até 7 dias a partir do primeiro horário escolhido.',
        icon: Icons.event_repeat_rounded,
        color: const Color(0xFF0B4DBA),
      );
    }
  }

  void _toggleInlineSlot(String dayName, String time, {DateTime? slotDate}) {
    final dayIndex = _days.indexOf(dayName);
    final resolvedDate = slotDate ??
        (dayIndex >= 0 ? _dateForDayIndex(dayIndex) : DateTime.now());
    final resolvedDateIso = _toDateIso(resolvedDate);

    final idx = _inlineSelectedSlots.indexWhere((s) {
      final selDay = _normalizeDayName((s['dayName'] ?? '').toString());
      final selTime = _normalizeTime((s['time'] ?? '').toString());
      if (selDay != _normalizeDayName(dayName) || selTime != _normalizeTime(time)) {
        return false;
      }
      final rawIso = (s['dateIso'] ?? '').toString().trim();
      final selDateIso = rawIso.length >= 10 ? rawIso.substring(0, 10) : rawIso;
      if (selDateIso.isNotEmpty) {
        return selDateIso == resolvedDateIso;
      }
      final selOffset = int.tryParse((s['weekOffset'] ?? '').trim());
      return selOffset == _scheduleWeekOffset;
    });

    if (idx >= 0) {
      setState(() {
        _inlineSelectedSlots = List.from(_inlineSelectedSlots)..removeAt(idx);
      });
      return;
    }

    if (_inlinePlanType == 'DIARIO' && _inlineSelectedSlots.isNotEmpty) {
      final selectedDay = _inlineSelectedSlots.first['dayName'];
      if (selectedDay != dayName) {
        _showSnack(
          'No Plano Diário, selecione horários apenas no mesmo dia.',
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF0B4DBA),
        );
        return;
      }
    }

    if (dayIndex >= 0 && _isBlockedByWeeklyStartRule(dayIndex)) {
      final startDate = _weeklyEarliestStartDate();
      final startDayName = _dayNameFromWeekday(startDate.weekday);
      _showSnack(
        'No plano semanal, selecione horários a partir de $startDayName ${_formatDateLabel(startDate)}.',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    final anchor = _selectionAnchorForPlan(
      _inlinePlanType,
      fallback: resolvedDate,
    );

    if (_inlinePlanType.toUpperCase() == 'SEMANAL') {
      final selectedDays = _countDistinctSelectedDates(
        _inlineSelectedSlots,
        extraDate: resolvedDate,
      );
      if (selectedDays > 7) {
        _showSnack(
          'Plano semanal permite no máximo 7 dias selecionados.',
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF0B4DBA),
        );
        return;
      }
    }

    if (!_isWithinSelectionWindow(resolvedDate, _inlinePlanType, anchor: anchor)) {
      final end = _selectionWindowEnd(_inlinePlanType, anchor: anchor);
      final limitLabel = _formatDateLabel(end);
      final msg = _inlinePlanType.toUpperCase() == 'SEMANAL'
          ? 'Plano semanal permite selecionar horários somente até $limitLabel.'
          : 'Plano mensal permite selecionar horários somente até $limitLabel.';
      _showSnack(
        msg,
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    setState(() {
      _inlineSelectedSlots = List.from(_inlineSelectedSlots)
        ..add({
          'dayName': dayName,
          'time': time,
          'dateLabel': _formatDateLabel(resolvedDate),
          'dateIso': resolvedDate.toIso8601String(),
          'weekOffset': _scheduleWeekOffset.toString(),
        });
    });
  }

  Future<void> _submitInlineRequest() async {
    if (_inlineSelectedSlots.isEmpty) {
      _showSnack(
        'Selecione pelo menos um horário para enviar.',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    final sent = await _sendRequest(
      planType: _inlinePlanType,
      selectedSlots: _inlineSelectedSlots,
    );
    if (!mounted) return;

    if (sent) {
      setState(() {
        _inlineSelectedSlots = [];
      });
    }
  }

  Future<bool> _sendRequest({
    required String planType,
    required List<Map<String, String>> selectedSlots,
  }) async {
    if (widget.trainerId == null ||
        widget.studentId == null ||
        widget.studentName == null) {
      _showSnack(
        'Não foi possível enviar a solicitação.',
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
      return false;
    }
    setState(() => _sendingRequest = true);
    try {
      final slotsWithDate = selectedSlots
          .map((s) => {
                'dayName': (s['dayName'] ?? '').trim(),
                'time': (s['time'] ?? '').trim(),
                'dateLabel': (s['dateLabel'] ?? '').trim(),
                'dateIso': (s['dateIso'] ?? '').trim(),
              })
          .where((s) => s['dayName']!.isNotEmpty && s['time']!.isNotEmpty)
          .toList();

      final normalizedSlots = selectedSlots
          .map((s) => {
                'dayName': s['dayName'] ?? '',
                'time': s['time'] ?? '',
              })
          .where((s) => s['dayName']!.isNotEmpty && s['time']!.isNotEmpty)
          .toList();

      if (normalizedSlots.isEmpty || slotsWithDate.isEmpty) {
        _showSnack(
          'Nenhum horário válido foi selecionado.',
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF0B4DBA),
        );
        return false;
      }

      final normalizedPlanType = planType.toUpperCase();
      if (normalizedPlanType == 'SEMANAL' || normalizedPlanType == 'MENSAL') {
        final mappedSelections = slotsWithDate
            .map((slot) => {
                  'dayName': (slot['dayName'] ?? '').toString(),
                  'time': (slot['time'] ?? '').toString(),
                  'dateLabel': (slot['dateLabel'] ?? '').toString(),
                  'dateIso': (slot['dateIso'] ?? '').toString(),
                })
            .toList();

        if (normalizedPlanType == 'SEMANAL') {
          final selectedDays = _countDistinctSelectedDates(mappedSelections);
          if (selectedDays > 7) {
            _showSnack(
              'Plano semanal permite no máximo 7 dias selecionados.',
              icon: Icons.info_outline_rounded,
              color: const Color(0xFF0B4DBA),
            );
            return false;
          }
        }

        final windowStart = _selectionAnchorForPlan(
          normalizedPlanType,
          selections: mappedSelections,
          fallback: DateTime.now(),
        );
        final windowEnd = normalizedPlanType == 'MENSAL'
            ? _selectionWindowEnd(
                normalizedPlanType,
                anchor: windowStart,
              )
            : null;

        for (final slot in slotsWithDate) {
          final candidate = _requestSlotStartDateTime(
            {
              'dayName': (slot['dayName'] ?? '').toString(),
              'time': (slot['time'] ?? '').toString(),
              'dateLabel': (slot['dateLabel'] ?? '').toString(),
              'dateIso': (slot['dateIso'] ?? '').toString(),
            },
            windowStart,
          );

          if (candidate == null) {
            _showSnack(
              'Horário selecionado inválido para envio.',
              icon: Icons.info_outline_rounded,
              color: const Color(0xFF0B4DBA),
            );
            return false;
          }

          if (normalizedPlanType == 'MENSAL' &&
              (candidate.isBefore(windowStart) || candidate.isAfter(windowEnd!))) {
            final limitLabel = _formatDateLabel(windowEnd!);
            final msg = 'Plano mensal permite solicitar horários somente até $limitLabel.';
            _showSnack(
              msg,
              icon: Icons.info_outline_rounded,
              color: const Color(0xFF0B4DBA),
            );
            return false;
          }
        }
      }

      final firstSlot = normalizedSlots.first;
      final dayName = firstSlot['dayName']!;
      final time = firstSlot['time']!;

      // Sempre envia daysJson com TODOS os slots selecionados
      final daysJson = jsonEncode(slotsWithDate);

      await AuthService.sendRequest(
        trainerId: widget.trainerId!,
        studentId: widget.studentId!,
        studentName: widget.studentName!,
        trainerName: widget.trainerName,
        dayName: dayName,
        time: time,
        planType: planType,
        daysJson: daysJson,
      );

      final requestMessage = _buildRequestAutoMessage(
        planType: planType,
        selectedSlots: slotsWithDate,
      );
      await AuthService.sendChatMessage(
        senderId: widget.studentId!,
        receiverId: widget.trainerId!,
        text: requestMessage,
      );

      // Marca todos os slots selecionados como solicitados em uma única chamada
      setState(() {
        for (final s in normalizedSlots) {
          final d = s['dayName']!;
          final t = s['time']!;
          final dayList = _schedule[d];
          if (dayList != null) {
            final idx = dayList.indexWhere((sl) => sl.time == t);
            if (idx >= 0) {
              dayList[idx].state = SlotState.requested;
            }
          }
        }
      });

      if (!mounted) return true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrainerChatView(
            trainerName: widget.trainerName,
            dayName: dayName,
            time: time,
            isTrainerSide: false,
            senderId: widget.studentId,
            receiverId: widget.trainerId,
            planType: planType,
            daysJson: daysJson,
            showProfileButton: false,
          ),
        ),
      );
      return true;
    } catch (e) {
      final msg = e.toString().contains('Failed to fetch')
          ? 'Sem conexão com o servidor'
          : e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');
      _showSnack(
        msg,
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _sendingRequest = false);
      }
    }
  }

  void _showSnack(String msg,
      {required IconData icon, required Color color}) {
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ── Build principal ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      bottomNavigationBar: null,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    _buildHeroCard(),
                    const SizedBox(height: 16),
                    _buildAboutCard(),
                    const SizedBox(height: 16),
                    _buildScheduleCard(),
                    const SizedBox(height: 16),
                    _buildReviewsCard(),
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
          colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: Colors.white),
              ),
              const FitMatchLogo(height: 34, onDarkBackground: true),
              const Spacer(),
              if (_sendingRequest)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  onPressed: () =>
                      setState(() => _isFavorite = !_isFavorite),
                  icon: Icon(
                    _isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 22,
                    color: _isFavorite
                        ? const Color(0xFFFFB3B3)
                        : Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero card ─────────────────────────────────────────────────────────────

  Widget _buildHeroCard() {
    final hasCref =
        widget.cref != null && widget.cref!.trim().isNotEmpty;
    final subtitle = hasCref
        ? 'Personal Trainer  •  CREF ${widget.cref!.trim()}'
        : 'Personal Trainer';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFE7EBF3)),
      ),
      child: Column(
        children: [
          // Banner
          Container(
            height: 140,
            decoration: const BoxDecoration(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(18)),
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0B4DBA),
                  Color(0xFF2563EB),
                  Color(0xFF60A5FA),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -24,
                  top: -24,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 50,
                  bottom: -40,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: -20,
                  bottom: -30,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                if (hasCref)
                  const Positioned(
                    top: 14,
                    right: 14,
                    child: _BadgeChip(
                      icon: Icons.verified_rounded,
                      label: 'CREF Verificado',
                      color: Color(0xFF22C55E),
                    ),
                  ),
                Positioned(
                  left: 20,
                  top: 14,
                  child: Icon(
                    Icons.fitness_center,
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
          // Conteúdo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar sobreposto
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.white, width: 4),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFD9E8FB),
                          Color(0xFFEEF4FC),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0B4DBA)
                              .withValues(alpha: 0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: ClipOval(
                        child: widget.trainerId != null
                            ? Image.network(
                                AuthService.getUserPhotoUrl(widget.trainerId!),
                                fit: BoxFit.cover,
                                width: 88,
                                height: 88,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  size: 38,
                                  color: Color(0xFF0B4DBA),
                                ),
                              )
                            : const Icon(
                                Icons.person_rounded,
                                size: 38,
                                color: Color(0xFF0B4DBA),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.trainerName.trim().isEmpty
                                    ? 'Personal Trainer'
                                    : widget.trainerName,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            if (hasCref) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded,
                                  color: Color(0xFF0B4DBA), size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              color: Colors.black45, fontSize: 12.5),
                        ),
                        const SizedBox(height: 12),
                        if (widget.specialties.trim().isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final s in widget.specialties
                                  .split(RegExp(r'[,;]'))
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty))
                                _SpecialtyChip(label: s),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.studentId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: _buildConnectionButton(),
            ),
        ],
      ),
    );
  }

  // ── Sobre ─────────────────────────────────────────────────────────────────

  Widget _buildAboutCard() {
    final hasBio =
        widget.bio != null && widget.bio!.trim().isNotEmpty;
    final hasCity =
        widget.city != null && widget.city!.trim().isNotEmpty;
    final hasPrice =
        widget.price != null && widget.price!.trim().isNotEmpty;

    return _SectionCard(
      title: 'Sobre o Personal',
      icon: Icons.person_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          hasBio
              ? Text(
                  widget.bio!,
                  style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 13.5,
                      height: 1.65),
                )
              : const Text(
                  'Este personal ainda não adicionou uma descrição.',
                  style: TextStyle(
                    color: Colors.black38,
                    fontSize: 13.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (hasCity)
                _InfoChip(
                    icon: Icons.location_on_rounded,
                    label: widget.city!),
              if (hasPrice)
                _InfoChip(
                    icon: Icons.attach_money_rounded,
                    label: 'R\$ ${widget.price!} / sessão'),
              _InfoChip(
                  icon: Icons.access_time_rounded,
                  label: widget.horasPorSessao != null && widget.horasPorSessao!.trim().isNotEmpty ? widget.horasPorSessao! : '1h por sessão'),
            ],
          ),
        ],
      ),
    );
  }

  // ── Agenda ────────────────────────────────────────────────────────────────

  Widget _buildScheduleCard() {
    final slots = _schedule[_days[_selectedDay]] ?? [];
    final canRequest = widget.studentId != null;
    final minWeekOffset = _minimumWeekOffsetForPlanType(_inlinePlanType);
    final summaryLabels = _inlinePlanType == 'MENSAL'
        ? _monthlySelectionSummaryLabels(_inlineSelectedSlots)
        : _inlineSelectedSlots.map(_inlineSelectionLabel).toList();
    final availableCount = slots.where((s) {
      final state = canRequest
          ? _effectiveStudentSlotState(_days[_selectedDay], s.time, s.state)
          : s.state;
      if (state != SlotState.available) return false;
      if (!canRequest) return true;
      if (_isBlockedByWeeklyStartRule(_selectedDay, weekOffset: _scheduleWeekOffset)) {
        return false;
      }
      return !_isPastSlotFor(_selectedDay, s.time);
    }).length;
    final total = slots.length;
    final canGoPrevWeek = _scheduleWeekOffset > minWeekOffset;

    String planLabel(String type) {
      switch (type) {
        case 'SEMANAL':
          return 'Plano Semanal';
        case 'MENSAL':
          return 'Plano Mensal';
        default:
          return 'Plano Diário';
      }
    }

    return _SectionCard(
      title: 'Agenda Semanal',
      icon: Icons.calendar_month_rounded,
      trailing: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: availableCount > 0
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          total == 0
              ? 'Sem horários'
              : '$availableCount/$total disponíveis',
          style: TextStyle(
            color: availableCount > 0
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingSlots)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(
                    color: Color(0xFF0B4DBA), strokeWidth: 2.5),
              ),
            )
          else ...[
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
                        ? () => setState(() => _scheduleWeekOffset -= 1)
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
                    onTap: () => setState(() => _scheduleWeekOffset += 1),
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
            SizedBox(
              height: 56,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 6.0;
                  final chipWidth =
                      (constraints.maxWidth - spacing * (_days.length - 1)) /
                          _days.length;

                  return Wrap(
                    spacing: spacing,
                    children: List.generate(_days.length, (i) {
                      final isSelected = _selectedDay == i;
                      final daySlots = _schedule[_days[i]] ?? [];
                      final hasAvail = daySlots.any(
                        (s) {
                          final state = canRequest
                              ? _effectiveStudentSlotState(_days[i], s.time, s.state)
                              : s.state;
                          return state == SlotState.available &&
                              (!canRequest ||
                                  !_isBlockedByWeeklyStartRule(i, weekOffset: _scheduleWeekOffset)) &&
                              (!canRequest || !_isPastSlotFor(i, s.time));
                        },
                      );
                      final hasRequested =
                          daySlots.any((s) {
                            final state = canRequest
                                ? _effectiveStudentSlotState(_days[i], s.time, s.state)
                                : s.state;
                            return state == SlotState.requested;
                          });

                      Color? dotColor;
                      if (!isSelected) {
                        if (hasAvail) {
                          dotColor = const Color(0xFF22C55E);
                        } else if (hasRequested) {
                          dotColor = const Color(0xFFF59E0B);
                        } else {
                          dotColor = const Color(0xFF9CA3AF);
                        }
                      }

                      return SizedBox(
                        width: chipWidth,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDay = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0B4DBA)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF0B4DBA)
                                    : const Color(0xFFE7EBF3),
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF0B4DBA)
                                            .withValues(alpha: 0.28),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _dayLabels[i],
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    if (dotColor != null) ...[
                                      const SizedBox(width: 3),
                                      Container(
                                        width: 5.5,
                                        height: 5.5,
                                        decoration: BoxDecoration(
                                          color: dotColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _dayChipDateLabel(i),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          // Legenda
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _LegendItem(
                color: Color(0xFF22C55E),
                label: canRequest
                    ? 'Disponível – toque para solicitar'
                    : 'Disponível – toque para bloquear',
              ),
              _LegendItem(
                color: Color(0xFFFDE68A),
                label: 'Aguardando confirmação',
              ),
              _LegendItem(
                color: Color(0xFFE5E7EB),
                label: 'Indisponível',
              ),
            ],
          ),
          if (!canRequest) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _applyingBlockRange ? null : _showRepeatBlockedDialog,
                icon: _applyingBlockRange
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Repetir horários bloqueados'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ],
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
                      border: Border.all(
                          color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Icon(Icons.event_busy_rounded,
                        color: Color(0xFF9CA3AF), size: 22),
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
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 2.5,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: slots.length,
              itemBuilder: (_, i) {
                final baseSlot = slots[i];
                final blockedByWeeklyRule =
                    canRequest && _isBlockedByWeeklyStartRule(_selectedDay, weekOffset: _scheduleWeekOffset);
                final isPastSlot = canRequest && _isPastSlotFor(_selectedDay, baseSlot.time);
                final effectiveState = canRequest
                    ? _effectiveStudentSlotState(_days[_selectedDay], baseSlot.time, baseSlot.state)
                    : baseSlot.state;
                final viewSlot = _Slot(baseSlot.time)..state = effectiveState;
                return _SlotTile(
                  slot: viewSlot,
                  forceUnavailable: isPastSlot || blockedByWeeklyRule,
                  isPicked: !isPastSlot &&
                      !blockedByWeeklyRule &&
                      _isInlineSelected(
                        _days[_selectedDay],
                        baseSlot.time,
                        dayIndex: _selectedDay,
                      ),
                  onTap: () => _onSlotTap(
                    canRequest ? viewSlot : baseSlot,
                    _days[_selectedDay],
                  ),
                );
              },
            ),

          if (canRequest) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 14),
            const Text(
              'Solicitação de atendimento',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(_planOptions.length, (i) {
                final option = _planOptions[i];
                final type = option['type']!;
                final isSelected = _inlinePlanType == type;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _changeInlinePlanType(type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: EdgeInsets.only(
                        right: i < _planOptions.length - 1 ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFDBEAFE)
                            : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFFE5E7EB),
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            option['label']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            option['sub']!,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(
              _inlineSelectedSlots.isEmpty
                  ? 'Toque nos horários para montar seu plano.'
                  : '${_inlineSelectedSlots.length} horário${_inlineSelectedSlots.length > 1 ? 's' : ''} selecionado${_inlineSelectedSlots.length > 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            if (_inlineSelectedSlots.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: summaryLabels
                      .map(
                        (label) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFBFDBFE),
                            ),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11.8,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _sendingRequest
                        ? null
                        : () {
                            setState(() {
                              _inlineSelectedSlots = [];
                            });
                          },
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Limpar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sendingRequest ? null : _submitInlineRequest,
                      icon: _sendingRequest
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text('Enviar · ${planLabel(_inlinePlanType)}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4DBA),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
          ], // fim do else (_loadingSlots)
        ],
      ),
    );
  }

  // ── Avaliações ────────────────────────────────────────────────────────────

  Widget _buildReviewsCard() {
    return _SectionCard(
      title: 'Avaliações',
      icon: Icons.star_outline_rounded,
      trailing: _ratings.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded,
                    size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 3),
                Text(
                  _avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                Text(
                  ' (${_ratings.length})',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingRatings)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                    color: Color(0xFF0B4DBA), strokeWidth: 2.5),
              ),
            )
          else if (_ratings.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9EE),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Icon(Icons.star_border_rounded,
                        color: Color(0xFFF59E0B), size: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nenhuma avaliação ainda',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'As avaliações dos alunos aparecerão aqui',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.black38),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ratings.length,
              separatorBuilder: (_, __) => const Divider(height: 20),
              itemBuilder: (_, i) => _RatingItem(data: _ratings[i]),
            ),
          if (widget.studentId != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showRatingDialog,
                icon: const Icon(Icons.star_rounded, size: 16),
                label: const Text('Avaliar Personal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFBEB),
                  foregroundColor: const Color(0xFFF59E0B),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
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

// ─── Diálogo de avaliação ─────────────────────────────────────────────────────

class _RatingDialog extends StatefulWidget {
  final String trainerName;
  final int trainerId;
  final int studentId;
  final String studentName;
  final Future<void> Function(int stars, String? comment) onSubmitted;

  const _RatingDialog({
    required this.trainerName,
    required this.trainerId,
    required this.studentId,
    required this.studentName,
    required this.onSubmitted,
  });

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Avaliar Personal',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              widget.trainerName,
              style: const TextStyle(
                  color: Colors.black45, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            // Estrelas
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _stars = star),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      _stars >= star
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: const Color(0xFFF59E0B),
                      size: 38,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Comentário (opcional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: Color(0xFFE7EBF3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Cancelar',
                        style: TextStyle(color: Colors.black54)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting || _stars == 0
                        ? null
                        : () async {
                            setState(() => _submitting = true);
                            try {
                              await widget.onSubmitted(
                                _stars,
                                _commentCtrl.text.trim().isEmpty
                                    ? null
                                    : _commentCtrl.text.trim(),
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                final msg = e.toString().contains('Failed to fetch')
                                    ? 'Sem conexão com o servidor'
                                    : e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _submitting = false);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4DBA),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Enviar'),
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

// ─── Item de avaliação ────────────────────────────────────────────────────────

class _RatingItem extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RatingItem({required this.data});

  @override
  Widget build(BuildContext context) {
    final studentName = (data['studentName'] ?? 'Aluno').toString();
    final studentId = data['studentId'] is num ? (data['studentId'] as num).toInt() : null;
    final stars = (data['stars'] ?? 0) as int;
    final comment = (data['comment'] ?? '').toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFEEF4FF),
          child: ClipOval(
            child: studentId != null
                ? Image.network(
                    AuthService.getUserPhotoUrl(studentId),
                    fit: BoxFit.cover,
                    width: 36,
                    height: 36,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF0B4DBA),
                      size: 18,
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF0B4DBA),
                    size: 18,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(studentName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 15,
                  );
                }),
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(comment,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Widgets reutilizáveis ────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BadgeChip(
      {required this.icon,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
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
                color: color),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Colors.black54)),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EBF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    size: 17,
                    color: const Color(0xFF0B4DBA)),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final _Slot slot;
  final VoidCallback onTap;
  final bool isPicked;
  final bool forceUnavailable;

  const _SlotTile({
    required this.slot,
    required this.onTap,
    this.isPicked = false,
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
      iconData = Icons.cancel_rounded;
    } else {
      switch (slot.state) {
      case SlotState.available:
        if (isPicked) {
          bgColor = const Color(0xFF1D4ED8);
          borderColor = const Color(0xFF1D4ED8);
          iconColor = Colors.white;
          textColor = Colors.white;
          iconData = Icons.check_circle_rounded;
        } else {
          bgColor = const Color(0xFFF0FDF4);
          borderColor = const Color(0xFFBBF7D0);
          iconColor = const Color(0xFF22C55E);
          textColor = const Color(0xFF15803D);
          iconData = Icons.check_circle_rounded;
        }
        break;
      case SlotState.requested:
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        iconColor = const Color(0xFFF59E0B);
        textColor = const Color(0xFFB45309);
        iconData = Icons.hourglass_top_rounded;
        break;
      case SlotState.unavailable:
        bgColor = const Color(0xFFF9FAFB);
        borderColor = const Color(0xFFE5E7EB);
        iconColor = const Color(0xFFD1D5DB);
        textColor = const Color(0xFF9CA3AF);
        iconData = Icons.cancel_rounded;
        break;
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 15, color: iconColor),
              const SizedBox(height: 3),
              Text(
                slot.time,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
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
        Text(label,
            style: const TextStyle(
                fontSize: 11.5, color: Colors.black45)),
      ],
    );
  }
}
