import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../core/app_refresh_notifier.dart';
import '../core/date_utils.dart';

class AdminTicketView extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool readOnly;

  const AdminTicketView({super.key, required this.user, this.readOnly = false});

  @override
  State<AdminTicketView> createState() => _AdminTicketViewState();
}

class _AdminTicketViewState extends State<AdminTicketView> {
  final TextEditingController _msgController = TextEditingController();

  final List<_TicketMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  String? _selectedAnalysisTemplate;
  int? _adminId;
  bool _hasSentMessage = false;

  // Rejeição anterior do mesmo email (motivo + última mensagem do admin).
  Map<String, dynamic>? _previousRejection;

  // Conta excluída anteriormente do mesmo email (motivo da exclusão).
  Map<String, dynamic>? _previousExclusion;

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_handleRefresh);
    _msgController.addListener(_onTextChanged);
    _initChat();
  }

  Future<void> _initChat() async {
    final session = await AuthService.loadSession();
    final adminId = session?['id'] != null ? (session!['id'] as num).toInt() : null;
    final userId = widget.user['id'];

    if (adminId != null && userId != null) {
      try {
        final msgs = await AuthService.getChatMessages(
          userId1: adminId,
          userId2: (userId as num).toInt(),
          // Chat ativo: mostra apenas a tentativa atual (cada novo cadastro
          // redefine o createdAt). Histórico (somente leitura): mostra as
          // mensagens até o evento terminal daquela tentativa (recordedAt).
          since: widget.readOnly
              ? null
              : (widget.user['createdAt'] ?? '').toString(),
          until: widget.readOnly
              ? (widget.user['recordedAt'] ?? '').toString()
              : null,
          limit: widget.readOnly ? 2000 : null,
        );
        if (!mounted) return;

        final createdAt = (widget.user['createdAt'] ?? '').toString();
        final loaded = msgs.map((m) {
          final fromAdmin = (m['senderId'] is num) &&
              (m['senderId'] as num).toInt() == adminId;
          final sentAt = (m['sentAt'] ?? '').toString();
          // No histórico (somente leitura), mensagens anteriores ao createdAt
          // desta tentativa pertencem a tentativas de cadastro anteriores.
          final fromPreviousAttempt = widget.readOnly &&
              createdAt.isNotEmpty &&
              sentAt.isNotEmpty &&
              sentAt.compareTo(createdAt) < 0;
          return _TicketMessage(
            text: (m['text'] ?? '').toString(),
            fromAdmin: fromAdmin,
            fromPreviousAttempt: fromPreviousAttempt,
          );
        }).toList();

        setState(() {
          _messages
            ..clear()
            ..addAll(loaded);
          _hasSentMessage = loaded.any((m) => m.fromAdmin);
        });
        _scrollToBottom();
      } catch (_) {
        // Sem histórico ainda ou falha silenciosa ao carregar o chat.
      }
    }

    if (!mounted) return;
    setState(() => _adminId = adminId);

    _loadPreviousRejection();
    _loadPreviousExclusion();
  }

  Future<void> _loadPreviousRejection() async {
    // No histórico (somente leitura) a conversa completa já é exibida no chat,
    // então não é necessário mostrar o resumo da rejeição anterior.
    if (widget.readOnly) return;

    final email = (widget.user['email'] ?? '').toString().trim();
    if (email.isEmpty) return;

    try {
      final data = await AdminService.getPreviousRejection(email);
      if (!mounted) return;
      if (data['found'] == true) {
        setState(() => _previousRejection = data);
      }
    } catch (_) {
      // Falha silenciosa: apenas não exibe o histórico anterior.
    }
  }

  Future<void> _loadPreviousExclusion() async {
    // No histórico (somente leitura) a conversa completa já é exibida no chat.
    if (widget.readOnly) return;

    final email = (widget.user['email'] ?? '').toString().trim();
    if (email.isEmpty) return;

    try {
      final data = await AdminService.getPreviousExclusion(email);
      if (!mounted) return;
      if (data['found'] == true) {
        setState(() => _previousExclusion = data);
      }
    } catch (_) {
      // Falha silenciosa: apenas não exibe o aviso.
    }
  }

  List<Widget> _buildExclusionReasons() {
    final raw = _previousExclusion?['exclusions'];
    final exclusions = raw is List ? raw : const <dynamic>[];
    final items = <Map<String, String>>[];
    for (final e in exclusions) {
      if (e is Map) {
        final reason = (e['exclusionReason'] ?? '').toString().trim();
        if (reason.isNotEmpty) {
          items.add({
            'reason': reason,
            'date': ((e['excludedAt'] ?? e['recordedAt']) ?? '').toString(),
          });
        }
      }
    }
    if (items.isEmpty) return const [];

    if (items.length == 1) {
      return [
        const SizedBox(height: 8),
        Text(
          'Motivo da exclusão: ${items.first['reason']}',
          style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5),
        ),
        if ((items.first['date'] ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'Data: ${formatIsoDateToPtBr(items.first['date'])}',
            style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5),
          ),
        ],
      ];
    }

    return [
      const SizedBox(height: 8),
      const Text(
        'Motivos das exclusões:',
        style: TextStyle(
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
      const SizedBox(height: 4),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            _formatReasonWithDate(item['reason'] ?? '', item['date'] ?? ''),
            style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5),
          ),
        ),
    ];
  }

  List<Widget> _buildRejectionReasons() {
    final raw = _previousRejection?['rejections'];
    final rejections = raw is List ? raw : const <dynamic>[];
    final items = <Map<String, String>>[];
    for (final e in rejections) {
      if (e is Map) {
        final reason = (e['rejectionReason'] ?? '').toString().trim();
        if (reason.isNotEmpty) {
          items.add({
            'reason': reason,
            'date': (e['recordedAt'] ?? '').toString(),
          });
        }
      }
    }
    if (items.isEmpty) return const [];

    if (items.length == 1) {
      return [
        const SizedBox(height: 8),
        Text(
          'Motivo da rejeição: ${items.first['reason']}',
          style: const TextStyle(color: Color(0xFFB45309), fontSize: 12.5),
        ),
        if ((items.first['date'] ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'Data: ${formatIsoDateToPtBr(items.first['date'])}',
            style: const TextStyle(color: Color(0xFFB45309), fontSize: 12.5),
          ),
        ],
      ];
    }

    return [
      const SizedBox(height: 8),
      const Text(
        'Motivos das rejeições:',
        style: TextStyle(
          color: Color(0xFFB45309),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
      const SizedBox(height: 4),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            _formatReasonWithDate(item['reason'] ?? '', item['date'] ?? ''),
            style: const TextStyle(color: Color(0xFFB45309), fontSize: 12.5),
          ),
        ),
    ];
  }

  String _formatReasonWithDate(String reason, String date) {
    final formattedDate = date.trim().isEmpty ? null : formatIsoDateToPtBr(date);
    return formattedDate == null ? '• $reason' : '• $reason ($formattedDate)';
  }

  void _handleRefresh() {
    if (!mounted) return;
    setState(() {
      _selectedAnalysisTemplate = null;
      _msgController.clear();
    });
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_handleRefresh);
    _msgController.removeListener(_onTextChanged);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _analysisTemplates {
    final type = (widget.user['type'] ?? '').toString().toLowerCase();

    final base = <String>[
      'Olá! Identificamos alguns pontos no seu cadastro. Por favor, revise e atualize os dados para prosseguirmos.',
      'Sua foto de perfil não está adequada. Envie uma nova foto em um ambiente claro, com o rosto totalmente visível, sem boné, sem óculos escuros e sem outras pessoas na imagem.',
      'Seu nome precisa estar completo (nome e sobrenome) e sem abreviações. Ajuste e envie novamente.',
      'Revise o campo "Cidade" do seu cadastro e confirme se está realmente correto.',
    ];

    if (type == 'personal') {
      base.addAll([
        'Seu CREF parece inconsistente. Verifique o número/UF e atualize o cadastro.',
        'A biografia precisa de mais detalhes (experiência, anos de atuação, foco de atendimento).',
      ]);
    }

    return base;
  }

  List<String> get _rejectTemplates {
    return <String>[
      'Não foi possível validar as informações fornecidas (e-mail inválido).',
      'Não houve retorno dentro do prazo para correção das informações.',
      'Usuário com histórico de contas excluídas por desrespeitar as diretrizes, entre outros.',
    ];
  }

  void _applyTemplate(String text) {
    setState(() {
      _msgController.text = text;
      _msgController.selection = TextSelection.fromPosition(
        TextPosition(offset: _msgController.text.length),
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) {
      _showSnack('Escreva uma mensagem antes de enviar.');
      return;
    }

    final adminId = _adminId;
    final receiverId = widget.user['id'];
    if (adminId == null || receiverId == null) {
      _showSnack('Não foi possível identificar os participantes do chat.');
      return;
    }

    setState(() {
      _messages.add(_TicketMessage(text: text, fromAdmin: true));
      _msgController.clear();
    });
    _scrollToBottom();

    try {
      await AuthService.sendChatMessage(
        senderId: adminId,
        receiverId: (receiverId as num).toInt(),
        text: text,
      );
      if (mounted) {
        setState(() => _hasSentMessage = true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _temporarilyReject() async {
    final userId = widget.user['id'];
    if (userId == null) {
      _showSnack('Não foi possível identificar o usuário.');
      return;
    }

    final reason = _messages
        .reversed
        .firstWhere(
          (m) => m.fromAdmin,
          orElse: () => _TicketMessage(text: '', fromAdmin: true),
        )
        .text
        .trim();
    if (reason.isEmpty) {
      _showSnack('Envie uma mensagem antes de rejeitar temporariamente.');
      return;
    }

    try {
      await AdminService.temporarilyRejectUser(
        (userId as num).toInt(),
        reason: reason,
      );
      if (!mounted) return;
      widget.user['status'] = 'TEMPORARILY_REJECTED';
      setState(() {});
      _showSnack('Usuário rejeitado temporariamente e notificado por e-mail.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _approve() async {
    await AdminService.approveUser(widget.user['id']);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _ban() async {
    final userId = widget.user['id'];
    if (userId == null) {
      _showSnack('Não foi possível identificar o usuário.');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Banir usuário'),
            content: const Text(
              'O usuário será banido da plataforma e o cadastro será '
              'rejeitado automaticamente. Ele não poderá mais acessar ou '
              'criar uma nova conta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F1D1D),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Banir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await AdminService.banUser(
        (userId as num).toInt(),
        reason: AdminService.banReason,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _reject(String reason) async {
    await AdminService.rejectUser(widget.user['id'], reason: reason);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _showRejectReasonSheet() async {
    String? selectedReason;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) => Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE6F5)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 18),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.rule_rounded, color: Color(0xFFEF4444)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Selecione o motivo da rejeição',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        children: _rejectTemplates.map((reason) {
                          final checked = selectedReason == reason;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setModalState(() {
                              selectedReason = checked ? null : reason;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: checked,
                                    onChanged: (_) => setModalState(() {
                                      selectedReason = checked ? null : reason;
                                    }),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 11),
                                      child: Text(reason),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final reason = (selectedReason ?? '').trim();
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione um motivo de rejeição'),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(sheetCtx);
                        await _reject(reason);
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Enviar motivo da rejeição'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.user['name'] ?? '').toString();
    final email = (widget.user['email'] ?? '').toString();
    final type = (widget.user['type'] ?? '').toString().toLowerCase();
    final typeLabel = type == 'personal' ? 'Personal' : 'Aluno';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        actions: [
          IconButton(
            onPressed: _handleRefresh,
            tooltip: 'Atualizar',
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF0B4DBA),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        title: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Análise',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1.1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0B4DBA).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF0B4DBA).withValues(alpha: .22),
                ),
              ),
              child: Text(
                typeLabel,
                style: const TextStyle(
                  color: Color(0xFF0B4DBA),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.1,
                ),
              ),
            ),
            if (widget.readOnly)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: .3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: Color(0xFFB45309)),
                    SizedBox(width: 4),
                    Text(
                      'Somente leitura',
                      style: TextStyle(
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _headerCard(name: name, email: email),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        widget.readOnly
                            ? 'Nenhuma mensagem nesta conversa.'
                            : 'Nenhuma mensagem ainda.\nUse os modelos abaixo ou escreva uma mensagem.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
                    ),
            ),
            _templateBar(),
            _composer(),
            if (!widget.readOnly) _actionsBar(),
          ],
        ),
      ),
    );
  }

  String _compactTemplate(String text) {
    final cleaned = text.replaceAll('\n', ' ').trim();
    if (cleaned.length <= 70) return cleaned;
    return '${cleaned.substring(0, 67)}...';
  }

  Widget _headerCard({required String name, required String email}) {
    final cpf = (widget.user['cpf'] ?? '-').toString();
    final base64 = (widget.user['photoBase64'] ?? '').toString();
    final type = (widget.user['type'] ?? '').toString().toLowerCase();
    final typeLabel = type == 'personal' ? 'Personal' : 'Aluno';
    final status = (widget.user['status'] ?? '-').toString();
    final createdAt = (widget.user['createdAt'] ?? '').toString();
    final createdDate = createdAt.isEmpty
        ? ''
        : formatIsoDateToPtBr(createdAt);
    final cidade = (widget.user['cidade'] ?? '').toString();
    final cref = (widget.user['cref'] ?? '').toString();
    final especialidade = (widget.user['especialidade'] ?? '').toString();
    final experiencia = (widget.user['experiencia'] ?? '').toString();
    final valorHora = (widget.user['valorHora'] ?? '').toString();
    final objetivos = (widget.user['objetivos'] ?? '').toString();
    final nivel = (widget.user['nivel'] ?? '').toString();
    final bio = (widget.user['bio'] ?? '').toString();
    final normalizedStatus = status.trim().toUpperCase();
    final isApproved = normalizedStatus == 'APPROVED';
    final isRejected = normalizedStatus == 'REJECTED';
    final statusLabel = switch (normalizedStatus) {
      'PENDING' => 'Pendente',
      'TEMPORARILY_REJECTED' => 'Rejeitado temporariamente',
      'APPROVED' => 'Aprovado',
      'REJECTED' => 'Rejeitado',
      _ => normalizedStatus,
    };
    final statusBg = isApproved
        ? const Color(0xFFDCFCE7)
        : isRejected
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFFFEDD5);
    final statusFg = isApproved
        ? const Color(0xFF166534)
        : isRejected
        ? const Color(0xFFB91C1C)
        : const Color(0xFF9A3412);

    Widget avatar;

    if (base64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(base64);
        avatar = CircleAvatar(radius: 32, backgroundImage: MemoryImage(bytes));
      } catch (_) {
        avatar = const CircleAvatar(radius: 32, child: Icon(Icons.person));
      }
    } else {
      avatar = const CircleAvatar(radius: 32, child: Icon(Icons.person));
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: .08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.35,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Status: $statusLabel',
                        style: TextStyle(
                          color: statusFg,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _infoChip('CPF: $cpf', icon: Icons.badge_outlined),
                        _infoChip(
                          'Conta: $typeLabel',
                          icon: Icons.manage_accounts_outlined,
                        ),
                        if (createdDate.isNotEmpty)
                          _infoChip(
                            'Criado em: $createdDate',
                            icon: Icons.event_note_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dados complementares',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (cidade.isNotEmpty)
                      _infoChip(
                        'Cidade: $cidade',
                        icon: Icons.location_on_outlined,
                      ),
                    if (cref.isNotEmpty)
                      _infoChip(
                        'CREF: $cref',
                        icon: Icons.workspace_premium_outlined,
                      ),
                    if (especialidade.isNotEmpty)
                      _infoChip(
                        'Especialidade: $especialidade',
                        icon: Icons.fitness_center_outlined,
                      ),
                    if (experiencia.isNotEmpty)
                      _infoChip(
                        'Experiência: $experiencia',
                        icon: Icons.school_outlined,
                      ),
                    if (valorHora.isNotEmpty)
                      _infoChip(
                        'Valor/h: $valorHora',
                        icon: Icons.attach_money_outlined,
                      ),
                    if (objetivos.isNotEmpty)
                      _infoChip(
                        'Objetivo: $objetivos',
                        icon: Icons.flag_outlined,
                      ),
                    if (nivel.isNotEmpty)
                      _infoChip(
                        'Nível: $nivel',
                        icon: Icons.trending_up_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'Bio: $bio',
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
          if (_previousRejection != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history, size: 16, color: Color(0xFF92400E)),
                      SizedBox(width: 6),
                      Text(
                        'Cadastro anterior (mesmo email)',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  ..._buildRejectionReasons(),
                ],
              ),
            ),
          ],
          if (_previousExclusion != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_off_outlined,
                          size: 16, color: Color(0xFFB91C1C)),
                      SizedBox(width: 6),
                      Text(
                        'Conta excluída anteriormente',
                        style: TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  ..._buildExclusionReasons(),
                ],
              ),
            ),
          ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        border: Border.all(color: const Color(0xFFD6E4FF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xFF335AA3)),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF1D4ED8),
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'Mensagens prontas (análise)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedAnalysisTemplate,
            isExpanded: true,
            selectedItemBuilder: (context) => _analysisTemplates
                .map(
                  (t) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _compactTemplate(t),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            items: _analysisTemplates
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      _compactTemplate(t),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                )
                .toList(),
            onChanged: widget.readOnly
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _selectedAnalysisTemplate = v);
                    _applyTemplate(v);
                  },
            decoration: InputDecoration(
              hintText: 'Selecione uma mensagem pronta',
              filled: true,
              fillColor: const Color(0xFFF8FBFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ao selecionar, o texto é preenchido automaticamente no campo de mensagem.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: const Color(0xFFF4F6FA),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgController,
              enabled: !widget.readOnly,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: widget.readOnly
                    ? 'Somente leitura'
                    : 'Escreva uma mensagem para o usuário...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: widget.readOnly ? null : _sendMessage,
              icon: const Icon(Icons.send),
              label: const Text('Enviar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      color: Colors.white,
      child: Row(
        children: [
          _actionButton(
            label: 'Aprovar',
            icon: Icons.check,
            color: const Color(0xFF0B4DBA),
            onPressed: _approve,
          ),
          _actionButton(
            label: 'Rejeitar',
            icon: Icons.close,
            color: Colors.red,
            onPressed: _showRejectReasonSheet,
          ),
          _actionButton(
            label: 'Rejeitar temporariamente',
            icon: Icons.block,
            color: const Color(0xFFF59E0B),
            onPressed: _hasSentMessage ? _temporarilyReject : null,
            disabledColor: const Color(0xFFFDE7C8),
            disabledForegroundColor: const Color(0xFF9A6B2B),
          ),
          _actionButton(
            label: 'Banir usuário',
            icon: Icons.gavel,
            color: const Color(0xFF7F1D1D),
            onPressed: _ban,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    Color? disabledColor,
    Color? disabledForegroundColor,
  }) {
    final enabled = onPressed != null;
    final bg = enabled
        ? color
        : (disabledColor ?? color.withValues(alpha: .35));
    final fg = enabled
        ? Colors.white
        : (disabledForegroundColor ?? Colors.white);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 58,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 19, color: fg),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(_TicketMessage m) {
    final align = m.fromAdmin ? Alignment.centerRight : Alignment.centerLeft;

    final Color bg;
    final Color fg;
    if (m.fromPreviousAttempt) {
      bg = const Color(0xFFF3F4F6);
      fg = const Color(0xFF6B7280);
    } else if (m.fromAdmin) {
      bg = const Color(0xFF0B4DBA);
      fg = Colors.white;
    } else {
      bg = Colors.white;
      fg = Colors.black;
    }

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: m.fromPreviousAttempt
              ? Border.all(color: const Color(0xFFE5E7EB))
              : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 6),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.fromPreviousAttempt) ...[
              const Text(
                'Tentativa anterior',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(m.text, style: TextStyle(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _TicketMessage {
  final String text;
  final bool fromAdmin;
  final bool fromPreviousAttempt;
  _TicketMessage({
    required this.text,
    required this.fromAdmin,
    this.fromPreviousAttempt = false,
  });
}
