import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/admin_service.dart';

class AdminTicketView extends StatefulWidget {
  final Map<String, dynamic> user;

  const AdminTicketView({super.key, required this.user});

  @override
  State<AdminTicketView> createState() => _AdminTicketViewState();
}

class _AdminTicketViewState extends State<AdminTicketView> {
  final TextEditingController _msgController = TextEditingController();

  final List<_TicketMessage> _messages = [];

  String? _selectedAnalysisTemplate;

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  List<String> get _analysisTemplates {
    final type = (widget.user['type'] ?? '').toString().toLowerCase();

    final base = <String>[
      'Olá! Identificamos alguns pontos no seu cadastro. Por favor, revise e atualize os dados para prosseguirmos.',
      'Poderia confirmar se o e-mail informado está correto e ativo? Precisamos dele para validações.',
      'Seu nome precisa estar completo (nome e sobrenome) e sem abreviações. Ajuste e envie novamente.',
      'Detectamos inconsistência na cidade/UF. Ajuste o campo "Cidade" para o formato correto.',
    ];

    if (type == 'personal') {
      base.addAll([
        'Seu CREF parece inconsistente. Verifique o número/UF e atualize o cadastro.',
        'A especialidade está muito genérica. Informe algo mais específico (ex: Musculação, Funcional, Corrida...).',
        'A biografia precisa de mais detalhes (experiência, anos de atuação, foco de atendimento).',
      ]);
    } else {
      base.addAll([
        'Descreva melhor seus objetivos (ex: perder gordura, ganhar massa, melhorar condicionamento).',
        'Confirme seu nível de condicionamento. Isso ajuda a sugerir treinos adequados.',
      ]);
    }

    return base;
  }

  List<String> get _rejectTemplates {
    final type = (widget.user['type'] ?? '').toString().toLowerCase();

    final base = <String>[
      'Dados obrigatórios ausentes ou inválidos.',
      'Não foi possível validar as informações fornecidas.',
      'Não houve retorno dentro do prazo para correção das informações.',
    ];

    if (type == 'personal') {
      base.addAll([
        'CREF inválido ou não confirmável.',
        'Informações profissionais insuficientes para validação.',
      ]);
    } else {
      base.addAll([
        'Informações inconsistentes no cadastro.',
      ]);
    }

    return base;
  }

  void _applyTemplate(String text) {
    setState(() {
      _msgController.text = text;
      _msgController.selection = TextSelection.fromPosition(
        TextPosition(offset: _msgController.text.length),
      );
    });
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_TicketMessage(text: text, fromAdmin: true));
      _msgController.clear();
    });
  }

  Future<void> _approve() async {
    await AdminService.approveUser(widget.user['id']);
    if (!mounted) return;
    Navigator.pop(context, true);
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
                BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 18),
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
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                            const SnackBar(content: Text('Selecione um motivo de rejeição')),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: Text(
          'Análise - ${type == 'personal' ? 'Personal' : 'Aluno'}',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _headerCard(name: name, email: email),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhuma mensagem ainda.\nUse os modelos abaixo ou escreva uma mensagem.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
                    ),
            ),
            _templateBar(),
            _composer(),
            _actionsBar(),
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

    Widget avatar;

    if (base64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(base64);
        avatar = CircleAvatar(
          radius: 32,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        avatar = const CircleAvatar(
          radius: 32,
          child: Icon(Icons.person),
        );
      }
    } else {
      avatar = const CircleAvatar(
        radius: 32,
        child: Icon(Icons.person),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF8)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  'CPF: $cpf',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Conta: $typeLabel',
                    style: const TextStyle(
                      color: Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF1D4ED8), size: 18),
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
                .map((t) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _compactTemplate(t),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
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
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedAnalysisTemplate = v);
              _applyTemplate(v);
            },
            decoration: InputDecoration(
              hintText: 'Selecione uma mensagem pronta',
              filled: true,
              fillColor: const Color(0xFFF8FBFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Escreva uma mensagem para o usuário...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send),
              label: const Text('Enviar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _actionsBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _approve,
              icon: const Icon(Icons.check),
              label: const Text('Aprovar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showRejectReasonSheet,
              icon: const Icon(Icons.close),
              label: const Text('Rejeitar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_TicketMessage m) {
    final align = m.fromAdmin ? Alignment.centerRight : Alignment.centerLeft;
    final bg = m.fromAdmin ? const Color(0xFF0B4DBA) : Colors.white;
    final fg = m.fromAdmin ? Colors.white : Colors.black;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 6)],
        ),
        child: Text(m.text, style: TextStyle(color: fg)),
      ),
    );
  }
}

class _TicketMessage {
  final String text;
  final bool fromAdmin;
  _TicketMessage({required this.text, required this.fromAdmin});
}