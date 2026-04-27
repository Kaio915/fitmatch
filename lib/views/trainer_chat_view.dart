import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../services/auth_service.dart';
import 'student_profile_view.dart';
import 'trainer_profile_view.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isMe;
  final DateTime time;

  const _ChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
  });
}

// ─── View ─────────────────────────────────────────────────────────────────────

class TrainerChatView extends StatefulWidget {
  final String trainerName;
  final String dayName;
  final String time;
  /// true = tela aberta pelo personal (ve mensagem do aluno como recebida)
  /// false = tela aberta pelo aluno (mensagem pré-preenchida enviada por ele)
  final bool isTrainerSide;
  /// ID do usuário que está vendo o chat (remetente atual)
  final int? senderId;
  /// ID do outro usuário na conversa
  final int? receiverId;
  /// Tipo do plano: DIARIO, SEMANAL ou MENSAL (opcional)
  final String? planType;
  /// JSON com os dias/horários do plano (opcional)
  final String? daysJson;
  /// Exibe botão para abrir perfil na barra superior
  final bool showProfileButton;
  /// Quando true, o usuário só pode ler a conversa
  final bool readOnly;
  final String? readOnlyMessage;
  final String? readOnlyStartAtIso;
  final String? readOnlyLockAtIso;
  final String? requestUpdatedAtIso;
  final int? requestId;

  const TrainerChatView({
    super.key,
    required this.trainerName,
    required this.dayName,
    required this.time,
    this.isTrainerSide = false,
    this.senderId,
    this.receiverId,
    this.planType,
    this.daysJson,
    this.showProfileButton = true,
    this.readOnly = false,
    this.readOnlyMessage,
    this.readOnlyStartAtIso,
    this.readOnlyLockAtIso,
    this.requestUpdatedAtIso,
    this.requestId,
  });

  @override
  State<TrainerChatView> createState() => _TrainerChatViewState();
}

class _TrainerChatViewState extends State<TrainerChatView> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _loadingMessages = true;
  bool _hideProfileButtonForBlockedStudent = false;
  Timer? _refreshTimer;
  bool _isSessionReadOnly = false;
  String? _sessionReadOnlyMessage;

  void _onGlobalRefresh() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _messageCtrl.clear();
    _loadBlockedStateForProfileButton();
    _loadMessages();
  }

  bool get _effectiveReadOnly => widget.readOnly || _isSessionReadOnly;

  String get _effectiveReadOnlyMessage =>
      _sessionReadOnlyMessage ??
      widget.readOnlyMessage ??
      'Este chat está disponível apenas para leitura.';

  void _activateReadOnlyMode([String? message]) {
    if (_effectiveReadOnly) return;
    _refreshTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isSessionReadOnly = true;
      _sessionReadOnlyMessage = message;
    });
  }

  int? _extractRequestIdMarker(String text) {
    final marker = RegExp(r'\[\[REQ:(\d+)\]\]').firstMatch(text);
    if (marker == null) return null;
    return int.tryParse(marker.group(1) ?? '');
  }

  String _stripRequestIdMarker(String text) {
    return text.replaceAll(RegExp(r'\s*\[\[REQ:\d+\]\]'), '').trim();
  }

  bool _messageMatchesCurrentRequestId(String text) {
    if (widget.requestId == null) return false;
    final markerId = _extractRequestIdMarker(text);
    if (markerId == null) return false;
    return markerId == widget.requestId;
  }

  bool _messageHasDifferentRequestId(String text) {
    if (widget.requestId == null) return false;
    final markerId = _extractRequestIdMarker(text);
    if (markerId == null) return false;
    return markerId != widget.requestId;
  }

  bool _isTerminationMessageText(String text) {
    final normalized = _stripRequestIdMarker(text).toLowerCase();
    return normalized.contains('somente para leitura') ||
        normalized.contains('disponível apenas para leitura') ||
        normalized.contains('solicitação foi recusada') ||
        normalized.contains('cancelou suas solicitações ativas') ||
        normalized.contains('não faz mais parte de meus alunos') ||
        normalized.contains('chat foi encerrado');
  }

  String _normalizeForMatch(String value) {
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
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int? _weekdayFromPt(String dayName) {
    switch (_normalizeForMatch(dayName)) {
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

  String _fallbackDateLabelForSlot(String dayName, String time) {
    final weekday = _weekdayFromPt(dayName);
    final hm = _parseHourMinute(time);
    if (weekday == null || hm == null) return '';

    final anchor = DateTime.tryParse((widget.requestUpdatedAtIso ?? '').toString()) ??
        DateTime.tryParse((widget.readOnlyStartAtIso ?? '').toString()) ??
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

  String _slotLabelForDisplay({
    required String dayName,
    required String time,
    String? dateLabel,
    bool forChat = true,
  }) {
    final safeDate = (dateLabel ?? '').trim();
    final safeTime = _normalizeTimeValue(time);
    if (safeDate.isNotEmpty) {
      return forChat
          ? '$dayName $safeDate às $safeTime'
          : '$dayName $safeDate  $safeTime';
    }
    return forChat ? '$dayName às $safeTime' : '$dayName  $safeTime';
  }

  List<String> _monthlySummaryLabels(
    List<Map<String, String>> slots, {
    bool forChat = true,
  }) {
    if (slots.isEmpty) return const [];

    final anchor = DateTime.tryParse((widget.readOnlyStartAtIso ?? '').toString()) ??
        DateTime.now();
    final parsed = <Map<String, dynamic>>[];
    for (final slot in slots) {
      final dayName = (slot['dayName'] ?? '').toString().trim();
      final time = (slot['time'] ?? '').toString().trim();
      final weekday = _weekdayFromPt(dayName);
      final hm = _parseHourMinute(time);
      if (dayName.isEmpty || time.isEmpty || weekday == null || hm == null) continue;

      final fromMeta = _parseSlotDateMeta(slot, hm.$1, hm.$2, anchor);
      final startAt = fromMeta ?? _nextOccurrence(anchor, weekday, hm.$1, hm.$2);
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
          .map((slot) => _slotLabelForDisplay(
                dayName: (slot['dayName'] ?? '').toString(),
                time: (slot['time'] ?? '').toString(),
                dateLabel: (slot['dateLabel'] ?? '').toString(),
                forChat: forChat,
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
      _slotLabelForDisplay(
        dayName: first['dayName'] as String,
        time: first['time'] as String,
        dateLabel:
            '${firstAt.day.toString().padLeft(2, '0')}/${firstAt.month.toString().padLeft(2, '0')}',
        forChat: forChat,
      ),
    ];

    for (final pattern in middle) {
      labels.add(
        _slotLabelForDisplay(
          dayName: pattern['dayName'] as String,
          time: pattern['time'] as String,
          forChat: forChat,
        ),
      );
    }

    if (lastAt != null && lastPattern != null && lastAt.isAfter(firstAt)) {
      labels.add(
        _slotLabelForDisplay(
          dayName: lastPattern['dayName'] as String,
          time: lastPattern['time'] as String,
          dateLabel:
              '${lastAt.day.toString().padLeft(2, '0')}/${lastAt.month.toString().padLeft(2, '0')}',
          forChat: forChat,
        ),
      );
    }

    return labels;
  }

  List<String> _currentRequestSlotTokens() {
    final tokens = <String>[];

    if ((widget.daysJson ?? '').trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(widget.daysJson!) as List<dynamic>;
        for (final slot in decoded.whereType<Map>()) {
          final dayName = (slot['dayName'] ?? '').toString().trim();
          final time = (slot['time'] ?? '').toString().trim();
          if (dayName.isEmpty || time.isEmpty) continue;
          tokens.add(_normalizeForMatch('$dayName às $time'));
          tokens.add(_normalizeForMatch('$dayName as $time'));
        }
      } catch (_) {}
    }

    if (tokens.isEmpty) {
      final dayName = widget.dayName.trim();
      final time = widget.time.trim();
      if (dayName.isNotEmpty && time.isNotEmpty) {
        tokens.add(_normalizeForMatch('$dayName às $time'));
        tokens.add(_normalizeForMatch('$dayName as $time'));
      }
    }

    return tokens;
  }

  Set<String> _currentRequestSlotSet() {
    final slots = <String>{};

    if ((widget.daysJson ?? '').trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(widget.daysJson!) as List<dynamic>;
        for (final slot in decoded.whereType<Map>()) {
          final dayName = _normalizeForMatch((slot['dayName'] ?? '').toString());
          final time = _normalizeForMatch((slot['time'] ?? '').toString());
          if (dayName.isEmpty || time.isEmpty) continue;
          slots.add('$dayName|$time');
        }
      } catch (_) {}
    }

    if (slots.isEmpty) {
      final dayName = _normalizeForMatch(widget.dayName);
      final time = _normalizeForMatch(widget.time);
      if (dayName.isNotEmpty && time.isNotEmpty) {
        slots.add('$dayName|$time');
      }
    }

    return slots;
  }

  Set<String> _extractSlotsFromMessage(String text) {
    final normalized = _normalizeForMatch(text);
    final regex = RegExp(
      r'(segunda|terca|terça|quarta|quinta|sexta|sabado|sábado|domingo)\s*(as|às)\s*(\d{1,2}:\d{2})',
      caseSensitive: false,
    );

    final slots = <String>{};
    for (final match in regex.allMatches(normalized)) {
      final day = _normalizeForMatch(match.group(1) ?? '');
      final time = _normalizeForMatch(match.group(3) ?? '');
      if (day.isEmpty || time.isEmpty) continue;
      slots.add('$day|$time');
    }
    return slots;
  }

  bool _sameSlotSet(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  bool _isRequestInitialMessageForCurrentChat(String text) {
    if (_messageHasDifferentRequestId(text)) return false;
    if (_messageMatchesCurrentRequestId(text)) return true;

    final normalized = _normalizeForMatch(text);
    final isInitialMessage = normalized.contains('gostaria de solicitar');
    if (!isInitialMessage) return false;

    final currentSlots = _currentRequestSlotSet();
    if (currentSlots.isNotEmpty) {
      final messageSlots = _extractSlotsFromMessage(text);
      if (messageSlots.isNotEmpty) {
        return _sameSlotSet(messageSlots, currentSlots);
      }
    }

    final tokens = _currentRequestSlotTokens();
    if (tokens.isEmpty) return false;
    return tokens.any(normalized.contains);
  }

  bool _hasSlotIntersection(Set<String> a, Set<String> b) {
    for (final value in a) {
      if (b.contains(value)) return true;
    }
    return false;
  }

  bool _isTerminationMessageForCurrentChat(
    String text, {
    bool allowGenericForApprovedContext = false,
  }) {
    if (!_isTerminationMessageText(text)) return false;

    if (_messageHasDifferentRequestId(text)) return false;
    if (_messageMatchesCurrentRequestId(text)) return true;

    final normalized = _normalizeForMatch(text);
    // Mensagem antiga/genérica não deve ser roteada para chats específicos.
    if (normalized.contains('cancelou suas solicitacoes ativas')) {
      if (widget.requestId != null) return false;
      return allowGenericForApprovedContext;
    }

    final currentSlots = _currentRequestSlotSet();
    final messageSlots = _extractSlotsFromMessage(text);

    if (currentSlots.isNotEmpty && messageSlots.isNotEmpty) {
      return _sameSlotSet(messageSlots, currentSlots) ||
          _hasSlotIntersection(messageSlots, currentSlots);
    }

    if (widget.requestId != null) {
      return false;
    }

    // Sem horário explícito só pode ser associada quando houver contexto claro
    // de aprovação deste chat (fallback para mensagens legadas).
    return allowGenericForApprovedContext;
  }

  bool _isApprovalMessageForCurrentChat(String text) {
    if (_messageHasDifferentRequestId(text)) return false;
    if (_messageMatchesCurrentRequestId(text)) return true;

    final normalized = _normalizeForMatch(text);
    final isApproval = normalized.contains('sua solicitacao foi confirmada') ||
        normalized.contains('solicitacao foi confirmada');
    if (!isApproval) return false;

    final currentSlots = _currentRequestSlotSet();
    final messageSlots = _extractSlotsFromMessage(text);

    if (currentSlots.isNotEmpty && messageSlots.isNotEmpty) {
      return _sameSlotSet(messageSlots, currentSlots) ||
          _hasSlotIntersection(messageSlots, currentSlots);
    }

    final tokens = _currentRequestSlotTokens();
    if (tokens.isEmpty) return false;
    return tokens.any(normalized.contains);
  }

  DateTime? _resolveReadOnlyLockAt(
    List<_ChatMessage> parsedMessages,
    DateTime? startAt,
    DateTime? lockAt,
  ) {
    DateTime? terminationAt;
    DateTime? markedTerminationAt;

    for (final message in parsedMessages) {
      if (_isTerminationMessageForCurrentChat(
            message.text,
            allowGenericForApprovedContext: true,
          ) &&
          (startAt == null || !message.time.isBefore(startAt))) {
        // Mantém a terminação mais recente do ciclo para não cortar
        // mensagens novas de bloqueio/encerramento do mesmo request.
        if (terminationAt == null || message.time.isAfter(terminationAt)) {
          terminationAt = message.time;
        }

        // Se houver marcador explícito do request atual, prioriza esse horário
        // mesmo quando houver lock temporal anterior.
        if (_messageMatchesCurrentRequestId(message.text)) {
          if (markedTerminationAt == null || message.time.isAfter(markedTerminationAt)) {
            markedTerminationAt = message.time;
          }
        }
      }
    }

    if (terminationAt == null) {
      return lockAt;
    }

    if (markedTerminationAt != null) {
      return markedTerminationAt;
    }

    if (lockAt == null) {
      return terminationAt;
    }

    return terminationAt.isBefore(lockAt) ? terminationAt : lockAt;
  }

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_onGlobalRefresh);
    _loadBlockedStateForProfileButton();
    _loadMessages();
    if (!_effectiveReadOnly) {
      // Polling a cada 4 segundos para mensagens em tempo real
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _loadMessages(scrollToBottom: false),
      );
    }
  }

  Future<void> _loadBlockedStateForProfileButton() async {
    if (widget.isTrainerSide) return;
    if (widget.senderId == null || widget.receiverId == null) return;

    try {
      final isBlocked = await AuthService.isStudentBlockedByTrainer(
        widget.receiverId!,
        widget.senderId!,
      );
      if (!mounted) return;
      setState(() {
        _hideProfileButtonForBlockedStudent = isBlocked;
      });
    } catch (_) {}
  }

  Future<void> _loadMessages({bool scrollToBottom = true}) async {
    // Chat bloqueado não carrega nenhuma mensagem adicional
    if (_effectiveReadOnly && !_loadingMessages) {
      return;
    }

    if (widget.senderId == null || widget.receiverId == null) {
      // Sem IDs: exibe mensagem local pré-preenchida
      if (_loadingMessages) {
        setState(() {
          _loadingMessages = false;
          _messages.add(_ChatMessage(
            text: _buildAutoMessage(),
            isMe: !widget.isTrainerSide,
            time: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
      return;
    }

    // Chat bloqueado: carrega mensagens apenas uma vez e nunca mais
    if (_effectiveReadOnly && _messages.isNotEmpty) {
      return;
    }
    try {
      final msgs = await AuthService.getChatMessages(
        userId1: widget.senderId!,
        userId2: widget.receiverId!,
        requestId: widget.requestId,
      );

      final parsedMessages = <_ChatMessage>[];
      for (final msg in msgs) {
        final sentAt = msg['sentAt'] != null
            ? DateTime.tryParse(msg['sentAt'].toString()) ?? DateTime.now()
            : DateTime.now();
        parsedMessages.add(_ChatMessage(
          text: (msg['text'] ?? '').toString(),
          isMe: msg['senderId'].toString() == widget.senderId.toString(),
          time: sentAt,
        ));
      }

        final startAt = widget.readOnlyStartAtIso != null
          ? DateTime.tryParse(widget.readOnlyStartAtIso!)
          : null;

        final lockAt = widget.readOnlyLockAtIso != null
          ? DateTime.tryParse(widget.readOnlyLockAtIso!)
          : null;

        final requestUpdatedAt = widget.requestUpdatedAtIso != null
          ? DateTime.tryParse(widget.requestUpdatedAtIso!)
          : null;

        final effectiveLockAt = _effectiveReadOnly
          ? _resolveReadOnlyLockAt(parsedMessages, startAt, lockAt)
          : lockAt;

        // Sempre aplica filtragem temporal quando houver janela da solicitação.
        // Isso isola cada ciclo do chat e evita mistura/duplicação de mensagens.
        final shouldApplyTemporalFiltering =
          startAt != null || effectiveLockAt != null;

      bool isWithinWindow(_ChatMessage message) {
        if (startAt != null && message.time.isBefore(startAt)) return false;
        if (effectiveLockAt != null && !message.time.isBefore(effectiveLockAt)) return false;
        return true;
      }

      bool isCancellationMessageText(String text) {
        if (_messageHasDifferentRequestId(text)) return false;
        final normalized = _normalizeForMatch(text);
        return normalized.contains('decidi cancelar minha solicitacao para');
      }

      bool isCancellationMessageForCurrentChat(String text) {
        if (_messageHasDifferentRequestId(text)) return false;
        if (_messageMatchesCurrentRequestId(text)) return true;
        if (!isCancellationMessageText(text)) return false;

        final currentSlots = _currentRequestSlotSet();
        final messageSlots = _extractSlotsFromMessage(text);

        if (currentSlots.isNotEmpty && messageSlots.isNotEmpty) {
          return _sameSlotSet(messageSlots, currentSlots);
        }

        final normalized = _normalizeForMatch(text);
        final tokens = _currentRequestSlotTokens();
        if (tokens.isEmpty) return false;
        return tokens.any(normalized.contains);
      }

      bool isCancellationMessageForAnotherChat(String text) {
        if (_messageHasDifferentRequestId(text)) return true;
        if (_messageMatchesCurrentRequestId(text)) return false;
        if (!isCancellationMessageText(text)) return false;
        if (isCancellationMessageForCurrentChat(text)) return false;

        // Só remove quando a mensagem claramente referencia outro slot.
        final messageSlots = _extractSlotsFromMessage(text);
        return messageSlots.isNotEmpty;
      }

      _ChatMessage? resolveForcedTerminationMessage() {
        if (!shouldApplyTemporalFiltering) return null;

        final hasAnyRequestMarker = parsedMessages.any(
          (message) => _extractRequestIdMarker(message.text) != null,
        );

        if (!_effectiveReadOnly) {
          final activeCandidates = parsedMessages
              .where((message) {
                if (!_isTerminationMessageText(message.text)) return false;
                if (!_messageMatchesCurrentRequestId(message.text)) return false;
                if (startAt != null && message.time.isBefore(startAt)) return false;
                return true;
              })
              .toList();

          if (activeCandidates.isEmpty) return null;
          activeCandidates.sort((a, b) => a.time.compareTo(b.time));
          return activeCandidates.last;
        }

        final hasApprovalForCurrentChat = parsedMessages.any((message) {
          if (startAt != null && message.time.isBefore(startAt)) return false;
          return _isApprovalMessageForCurrentChat(message.text);
        });

        final candidates = parsedMessages
            .where((message) {
              final isCurrentReqMarker =
                  _messageMatchesCurrentRequestId(message.text);
              if (!_isTerminationMessageForCurrentChat(
                message.text,
                allowGenericForApprovedContext: hasApprovalForCurrentChat,
              )) {
                return false;
              }
              if (startAt != null && message.time.isBefore(startAt)) return false;
              if (!isCurrentReqMarker &&
                  effectiveLockAt != null &&
                  !message.time.isBefore(effectiveLockAt)) {
                return false;
              }
              return true;
            })
            .toList();

        if (candidates.isEmpty && requestUpdatedAt != null) {
          final allowRelaxedFallback =
              widget.requestId == null || !hasAnyRequestMarker;
          if (!allowRelaxedFallback) {
            return null;
          }

          // Fallback defensivo para histórico legado/sem marcador:
          // usa mensagem de terminação mais próxima do updatedAt da solicitação.
          final relaxedCandidates = parsedMessages
              .where((message) {
                if (!_isTerminationMessageText(message.text)) return false;
                if (startAt != null && message.time.isBefore(startAt)) {
                  return false;
                }

                if (widget.requestId != null) {
                  final markerId = _extractRequestIdMarker(message.text);
                  // Em chat por request, fallback só considera mensagens sem marcador
                  // e compatíveis com o slot deste chat (legado).
                  if (markerId != null) return false;
                  if (!_isTerminationMessageForCurrentChat(message.text)) {
                    return false;
                  }
                }

                final diffMinutes = message.time
                    .difference(requestUpdatedAt)
                    .abs()
                    .inMinutes;
                return diffMinutes <= 180;
              })
              .toList();

          if (relaxedCandidates.isNotEmpty) {
            relaxedCandidates.sort((a, b) {
              final aDiff =
                  a.time.difference(requestUpdatedAt).abs().inMilliseconds;
              final bDiff =
                  b.time.difference(requestUpdatedAt).abs().inMilliseconds;
              if (aDiff != bDiff) return aDiff.compareTo(bDiff);
              return a.time.compareTo(b.time);
            });
            return relaxedCandidates.first;
          }
        }

        if (candidates.isEmpty) return null;

        if (requestUpdatedAt != null) {
          final nearest = List<_ChatMessage>.from(candidates)
            ..sort((a, b) {
              final aDiff = a.time.difference(requestUpdatedAt).abs().inMilliseconds;
              final bDiff = b.time.difference(requestUpdatedAt).abs().inMilliseconds;
              if (aDiff != bDiff) return aDiff.compareTo(bDiff);
              return a.time.compareTo(b.time);
            });

          final best = nearest.first;
          return best;
        }

        candidates.sort((a, b) => a.time.compareTo(b.time));
        return candidates.last;
      }

      final forcedTerminationMessage = resolveForcedTerminationMessage();

      bool isForcedTermination(_ChatMessage message) {
        if (forcedTerminationMessage == null) return false;
        return identical(message, forcedTerminationMessage);
      }

      bool isForcedInitialRequest(_ChatMessage message) {
        if (!shouldApplyTemporalFiltering) return false;
        if (!_isRequestInitialMessageForCurrentChat(message.text)) return false;
        if (effectiveLockAt != null && !message.time.isBefore(effectiveLockAt)) return false;
        return true;
      }

      _ChatMessage? resolveForcedCancellationMessage() {
        if (!shouldApplyTemporalFiltering) return null;

        final candidates = parsedMessages
            .where((message) {
              final isCurrentReqMarker =
                  _messageMatchesCurrentRequestId(message.text);
              if (!isCancellationMessageText(message.text)) {
                return false;
              }
              if (startAt != null && message.time.isBefore(startAt)) return false;
              if (!isCurrentReqMarker &&
                  effectiveLockAt != null &&
                  !message.time.isBefore(effectiveLockAt)) {
                return false;
              }
              if (isCurrentReqMarker) {
                return true;
              }
              return isCancellationMessageForCurrentChat(message.text);
            })
            .toList();

        if (candidates.isEmpty) return null;

        candidates.sort((a, b) {
          if (requestUpdatedAt != null) {
            final aDiff = a.time.difference(requestUpdatedAt).abs().inMilliseconds;
            final bDiff = b.time.difference(requestUpdatedAt).abs().inMilliseconds;
            if (aDiff != bDiff) return aDiff.compareTo(bDiff);
          }

          final aHasReq = _messageMatchesCurrentRequestId(a.text) ? 0 : 1;
          final bHasReq = _messageMatchesCurrentRequestId(b.text) ? 0 : 1;
          if (aHasReq != bHasReq) {
            return aHasReq.compareTo(bHasReq);
          }

          return a.time.compareTo(b.time);
        });

        if (requestUpdatedAt != null) {
          return candidates.first;
        }

        if (effectiveLockAt != null) {
          final insideLock = candidates.where((m) => m.time.isBefore(effectiveLockAt)).toList();
          if (insideLock.isNotEmpty) {
            insideLock.sort((a, b) => a.time.compareTo(b.time));
            return insideLock.last;
          }
          return null;
        }

        return candidates.last;
      }

      final forcedCancellationMessage = resolveForcedCancellationMessage();

      bool isForcedCancellation(_ChatMessage message) {
        if (forcedCancellationMessage == null) return false;
        return identical(message, forcedCancellationMessage);
      }

      _ChatMessage? resolveBestInitialRequestMessage() {
        if (!shouldApplyTemporalFiltering) return null;

        final candidates = parsedMessages
            .where((message) {
              if (!_isRequestInitialMessageForCurrentChat(message.text)) {
                return false;
              }
              if (effectiveLockAt != null && !message.time.isBefore(effectiveLockAt)) {
                return false;
              }
              return true;
            })
            .toList();

        if (candidates.isEmpty) return null;
        if (startAt == null) return candidates.last;

        candidates.sort((a, b) {
          final aDiff = a.time.difference(startAt).inMilliseconds.abs();
          final bDiff = b.time.difference(startAt).inMilliseconds.abs();
          if (aDiff != bDiff) return aDiff.compareTo(bDiff);

          final aAfter = !a.time.isBefore(startAt);
          final bAfter = !b.time.isBefore(startAt);
          if (aAfter != bAfter) return aAfter ? -1 : 1;

          return a.time.compareTo(b.time);
        });

        return candidates.first;
      }

      List<_ChatMessage> visibleMessages;
      if (shouldApplyTemporalFiltering) {
        // Chat com janela temporal definida (solicitação rejeitada com datas específicas)
        visibleMessages = parsedMessages
            .where((m) {
              if (isCancellationMessageForAnotherChat(m.text) && !isForcedCancellation(m)) {
                return false;
              }

              return isWithinWindow(m) ||
                  isForcedTermination(m) ||
                  isForcedInitialRequest(m) ||
                  isForcedCancellation(m);
            })
            .toList();

        final bestInitialMessage = resolveBestInitialRequestMessage();
        if (bestInitialMessage != null) {
          // Mantém apenas UMA mensagem inicial da solicitação atual no ciclo.
          visibleMessages = visibleMessages.where((m) {
            final isSameInitialType = _isRequestInitialMessageForCurrentChat(m.text);
            if (!isSameInitialType) return true;
            return identical(m, bestInitialMessage);
          }).toList();

          if (!visibleMessages.contains(bestInitialMessage)) {
            visibleMessages.add(bestInitialMessage);
          }

          visibleMessages.sort((a, b) => a.time.compareTo(b.time));
        }

        if (forcedCancellationMessage != null) {
          visibleMessages = visibleMessages.where((m) {
            if (!isCancellationMessageForCurrentChat(m.text)) return true;
            return identical(m, forcedCancellationMessage);
          }).toList();

          if (!visibleMessages.contains(forcedCancellationMessage)) {
            visibleMessages.add(forcedCancellationMessage);
          }

          visibleMessages.sort((a, b) => a.time.compareTo(b.time));
        }

        // Garantia final: toda mensagem de terminação marcada com o request atual
        // deve aparecer no chat deste request, mesmo em casos de lock temporal
        // legado/inconsistente entre ciclos.
        if (widget.requestId != null) {
          final requiredMarkedTerminations = parsedMessages
              .where((message) {
                if (!_isTerminationMessageText(message.text)) return false;
                if (!_messageMatchesCurrentRequestId(message.text)) return false;
                if (startAt != null && message.time.isBefore(startAt)) return false;
                return true;
              })
              .toList();

          for (final message in requiredMarkedTerminations) {
            if (!visibleMessages.contains(message)) {
              visibleMessages.add(message);
            }
          }

          visibleMessages.sort((a, b) => a.time.compareTo(b.time));
        }

        // Fallback: evita chat vazio quando a mensagem inicial não foi
        // persistida/retornada, mas a solicitação existe na tela.
        if (visibleMessages.isEmpty) {
          visibleMessages = [
            _ChatMessage(
              text: _buildAutoMessage(),
              isMe: !widget.isTrainerSide,
              time: startAt ?? DateTime.now(),
            ),
          ];
        }
      } else if (_effectiveReadOnly) {
        // Chat bloqueado sem janela temporal: mostra apenas até a primeira msg de terminação
        final cutoffIndex = parsedMessages.lastIndexWhere(
          (m) => _isTerminationMessageText(m.text),
        );
        // Se encontrou mensagem de terminação, mostra até ela; caso contrário, vazio
        visibleMessages = cutoffIndex >= 0
            ? parsedMessages.sublist(0, cutoffIndex + 1)
            : <_ChatMessage>[];
      } else {
        // Chat ativo: mostra todas as mensagens
        visibleMessages = parsedMessages;
      }

      bool isTerminationFromCurrentCycle(_ChatMessage message) {
        if (!_isTerminationMessageText(message.text)) return false;

        // Marcador explícito da solicitação atual: pode encerrar direto.
        if (_messageMatchesCurrentRequestId(message.text)) {
          return true;
        }

        // Sem marcador de request, só considera quando existe janela temporal
        // do ciclo atual para evitar fechar chats pendentes/aprovados por
        // mensagens antigas de outros ciclos no mesmo par aluno/personal.
        if (startAt == null) {
          return false;
        }
        if (message.time.isBefore(startAt)) {
          return false;
        }
        if (effectiveLockAt != null && !message.time.isBefore(effectiveLockAt)) {
          return false;
        }

        return _isTerminationMessageForCurrentChat(message.text);
      }

      final mustAutoCloseChat = !_effectiveReadOnly && widget.requestId != null &&
          parsedMessages.any(isTerminationFromCurrentCycle);

      if (mustAutoCloseChat) {
        _activateReadOnlyMode(
          'Este chat foi encerrado e está disponível apenas para leitura.',
        );
      }

      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _messages.clear();
        _messages.addAll(visibleMessages);
      });
      if (scrollToBottom) _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  /// Monta a mensagem automática inicial com informações do plano
  String _buildAutoMessage() {
    final plan = widget.planType ?? 'DIARIO';
    final planLabel = plan == 'SEMANAL'
        ? 'Plano Semanal'
        : plan == 'MENSAL'
            ? 'Plano Mensal'
            : 'Plano Diário';

    final raw = widget.daysJson;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final slots = decoded
            .whereType<Map>()
            .map((s) => {
                  'dayName': (s['dayName'] ?? '').toString().trim(),
                  'time': (s['time'] ?? '').toString().trim(),
                  'dateLabel': (s['dateLabel'] ?? '').toString().trim(),
                  'dateIso': (s['dateIso'] ?? '').toString().trim(),
                })
            .where((s) => s['dayName']!.isNotEmpty && s['time']!.isNotEmpty)
            .toList();

        final slotsText = plan == 'MENSAL'
            ? _monthlySummaryLabels(slots, forChat: true).join('\n')
            : slots
                .map((s) {
                  final dayName = (s['dayName'] ?? '').toString().trim();
                  final time = (s['time'] ?? '').toString().trim();
                  final dateLabel = (s['dateLabel'] ?? '').toString().trim().isNotEmpty
                      ? (s['dateLabel'] ?? '').toString().trim()
                      : _fallbackDateLabelForSlot(dayName, time);
                  if (dateLabel.isNotEmpty) {
                    return '$dayName $dateLabel às $time';
                  }
                  return '$dayName às $time';
                })
                .join('\n');
        return 'Gostaria de solicitar um $planLabel com os seguintes horários:\n$slotsText';
      } catch (_) {}
    }
    return 'Gostaria de solicitar um Plano Diário\n${widget.dayName} às ${widget.time}';
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_onGlobalRefresh);
    _refreshTimer?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_effectiveReadOnly) return;
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    if (widget.senderId == null || widget.receiverId == null) return;

    try {
      await AuthService.sendChatMessage(
        senderId: widget.senderId!,
        receiverId: widget.receiverId!,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: text, isMe: true, time: DateTime.now()));
        _messageCtrl.clear();
      });
      _scrollToBottom();
    } catch (e) {
      final errorText = e.toString().toLowerCase();
      if (errorText.contains('somente para leitura') ||
          errorText.contains('disponível apenas para leitura') ||
          errorText.contains('conversa bloqueada')) {
        _activateReadOnlyMode(
          'Este chat foi encerrado e está disponível apenas para leitura.',
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final peerPhotoUrl = widget.receiverId != null
        ? AuthService.getUserPhotoUrl(widget.receiverId!)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(peerPhotoUrl),
            _buildRequestBanner(),
            Expanded(child: _buildMessageList()),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar(String? peerPhotoUrl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 64, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE7EBF3)),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: Colors.black87,
          ),
          // Avatar do personal
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEEF4FD),
                child: ClipOval(
                  child: peerPhotoUrl != null
                      ? Image.network(
                          peerPhotoUrl,
                          fit: BoxFit.cover,
                          width: 44,
                          height: 44,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            size: 22,
                            color: Color(0xFF0B4DBA),
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 22,
                          color: Color(0xFF0B4DBA),
                        ),
                ),
              ),
              Positioned(
                bottom: 1,
                right: 1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.trainerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: Colors.black87,
                  ),
                ),
                const Text(
                  'Online agora',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF22C55E)),
                ),
              ],
            ),
          ),
          if (widget.showProfileButton && !_hideProfileButtonForBlockedStudent) ...[
            IconButton(
              onPressed: () async {
                if (widget.isTrainerSide) {
                  // Personal vendo perfil do aluno
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentProfileView(
                        studentId: widget.receiverId!,
                        studentName: widget.trainerName,
                        trainerId: widget.senderId,
                        trainerName: null,
                      ),
                    ),
                  );
                } else {
                  // Aluno vendo perfil do personal
                  Map<String, dynamic>? trainerData;
                  Map<String, dynamic>? studentData;
                  if (widget.receiverId != null) {
                    try {
                      trainerData = await AuthService.getUserById(widget.receiverId!);
                    } catch (_) {
                      trainerData = null;
                    }
                  }
                  if (widget.senderId != null) {
                    try {
                      studentData = await AuthService.getUserById(widget.senderId!);
                    } catch (_) {
                      studentData = null;
                    }
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrainerProfileView(
                        trainerName: (trainerData?['name'] ?? widget.trainerName).toString(),
                        specialties: (trainerData?['especialidade'] ?? '').toString(),
                        email: trainerData?['email']?.toString(),
                        cref: trainerData?['cref']?.toString(),
                        city: trainerData?['cidade']?.toString(),
                        price: trainerData?['valorHora']?.toString(),
                        bio: trainerData?['bio']?.toString(),
                        horasPorSessao: trainerData?['horasPorSessao']?.toString(),
                        trainerId: widget.receiverId,
                        studentId: widget.senderId,
                        studentName: studentData?['name']?.toString(),
                      ),
                    ),
                  );
                }
              },
              tooltip: 'Ver Perfil',
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFD3F5)),
                ),
                child: const Icon(
                  Icons.person_search_rounded,
                  size: 18,
                  color: Color(0xFF0B4DBA),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  // ── Banner da solicitação ─────────────────────────────────────────────────

  Widget _buildRequestBanner() {
    final plan = widget.planType ?? 'DIARIO';
    final planLabel = plan == 'SEMANAL'
        ? 'Semanal'
        : plan == 'MENSAL'
            ? 'Mensal'
            : 'Diário';
    final (planFg, planBg) = plan == 'SEMANAL'
        ? (const Color(0xFF0B4DBA), const Color(0xFFEEF4FD))
        : plan == 'MENSAL'
        ? (const Color(0xFF0B4DBA), const Color(0xFFEEF4FD))
        : (const Color(0xFFB45309), const Color(0xFFFFFBEB));

    // Tenta parsear daysJson para exibir os slots
    List<Map<String, String>> slots = [];
    final raw = widget.daysJson;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        slots = decoded
            .whereType<Map>()
            .map((s) => {
                  'dayName': (s['dayName'] ?? '').toString(),
                  'time': (s['time'] ?? '').toString(),
                  'dateLabel': (s['dateLabel'] ?? '').toString(),
                  'dateIso': (s['dateIso'] ?? '').toString(),
                })
            .toList();
      } catch (_) {}
    }
    if (slots.isEmpty && widget.dayName.isNotEmpty) {
      slots = [{'dayName': widget.dayName, 'time': widget.time}];
    }

    final slotLabels = plan == 'MENSAL'
        ? _monthlySummaryLabels(slots, forChat: false)
        : slots
            .map((s) {
              final dayName = (s['dayName'] ?? '').toString().trim();
              final time = (s['time'] ?? '').toString().trim();
              final rawDateLabel = (s['dateLabel'] ?? '').toString().trim();
              final dateLabel = rawDateLabel.isNotEmpty
                  ? rawDateLabel
                  : _fallbackDateLabelForSlot(dayName, time);
              if (dateLabel.isNotEmpty) {
                return '$dayName $dateLabel  $time';
              }
              return '$dayName  $time';
            })
            .toList();

    // Determina o texto baseado em quem está vendo
    final bannerText = widget.isTrainerSide
        ? 'Solicitação recebida de ${widget.trainerName}'
        : 'Solicitação enviada para ${widget.trainerName}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: planBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: planFg.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                bannerText,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: planFg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Plano $planLabel',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: slotLabels
                    .map((label) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: planFg.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: planFg.withOpacity(0.3)),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: planFg,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Lista de mensagens ────────────────────────────────────────────────────

  Widget _buildMessageList() {
    if (_loadingMessages) {
      return const Center(
        child: CircularProgressIndicator(
            color: Color(0xFF0B4DBA), strokeWidth: 2.5),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Nenhuma mensagem ainda.\nSeja o primeiro a dizer olá!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black38, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: _messages[i],
        myPhotoUrl: widget.senderId != null
            ? AuthService.getUserPhotoUrl(widget.senderId!)
            : null,
        peerPhotoUrl: widget.receiverId != null
            ? AuthService.getUserPhotoUrl(widget.receiverId!)
            : null,
      ),
    );
  }

  // ── Input ─────────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    if (_effectiveReadOnly) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE7EBF3))),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _effectiveReadOnlyMessage,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Color(0xFF7C2D12),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE7EBF3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageCtrl,
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Digite uma mensagem...',
                hintStyle:
                    const TextStyle(color: Colors.black38, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7F9FD),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: Color(0xFFE7EBF3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: Color(0xFFE7EBF3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                      color: Color(0xFF0B4DBA), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: const Color(0xFF0B4DBA),
            borderRadius: BorderRadius.circular(999),
            elevation: 2,
            shadowColor: const Color(0xFF0B4DBA),
            child: InkWell(
              onTap: _sendMessage,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bolha de mensagem ────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final String? myPhotoUrl;
  final String? peerPhotoUrl;

  const _MessageBubble({
    required this.message,
    this.myPhotoUrl,
    this.peerPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final displayText = message.text
      .replaceAll(RegExp(r'\s*\[\[REQ:\d+\]\]'), '')
      .trim();
    final timeStr =
        '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar do personal (esquerda)
          if (!isMe) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFEEF4FD),
              child: ClipOval(
                child: peerPhotoUrl != null
                    ? Image.network(
                        peerPhotoUrl!,
                        fit: BoxFit.cover,
                        width: 30,
                        height: 30,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_rounded,
                          size: 14,
                          color: Color(0xFF0B4DBA),
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: Color(0xFF0B4DBA),
                      ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Bolha
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [Color(0xFF0B4DBA), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMe
                        ? const Color(0xFF0B4DBA).withOpacity(0.18)
                        : Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: isMe
                    ? null
                    : Border.all(color: const Color(0xFFE7EBF3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayText,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14,
                      height: 1.48,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isMe
                              ? Colors.white.withOpacity(0.6)
                              : Colors.black38,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_all_rounded,
                          size: 14,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Avatar do aluno (direita)
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFEEF4FD),
              child: ClipOval(
                child: myPhotoUrl != null
                    ? Image.network(
                        myPhotoUrl!,
                        fit: BoxFit.cover,
                        width: 30,
                        height: 30,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_rounded,
                          size: 14,
                          color: Color(0xFF0B4DBA),
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: Color(0xFF0B4DBA),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
