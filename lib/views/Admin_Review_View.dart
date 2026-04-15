import 'package:flutter/material.dart';

class AdminReviewView extends StatefulWidget {
  final dynamic user;

  const AdminReviewView({super.key, required this.user});

  @override
  State<AdminReviewView> createState() => _AdminReviewViewState();
}

class _AdminReviewViewState extends State<AdminReviewView> {
  final List<Map<String, dynamic>> messages = [];

  String? selectedCorrectionTemplate;
  String? selectedRejectionTemplate;

  final List<String> correctionTemplates = [
    "O CREF informado está inválido. Por favor, verifique e atualize.",
    "O email informado parece incorreto. Revise o cadastro.",
    "O nome informado não corresponde aos dados oficiais.",
    "A especialidade precisa ser melhor detalhada.",
    "A biografia está incompleta. Por favor, adicione mais informações.",
    "Os dados de experiência precisam ser ajustados."
  ];

  final List<String> rejectionTemplates = [
    "Cadastro rejeitado por violação das diretrizes da plataforma.",
    "Cadastro rejeitado por inconsistência nas informações fornecidas.",
    "Cadastro rejeitado por ausência de documentação válida.",
    "Cadastro rejeitado por não atender aos requisitos mínimos.",
    "Prazo de 24h para correção expirado."
  ];

  void _sendMessage(String text) {
    if (text.isEmpty) return;

    setState(() {
      messages.add({
        "sender": "ADMIN",
        "text": text,
        "time": TimeOfDay.now().format(context),
      });
    });

    selectedCorrectionTemplate = null;
  }

  void _rejectUser() {
    if (selectedRejectionTemplate == null) return;

    setState(() {
      messages.add({
        "sender": "ADMIN",
        "text": selectedRejectionTemplate,
        "time": TimeOfDay.now().format(context),
      });
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Análise de Cadastro",
            style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: _userInfoCard(u),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: _ticketArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userInfoCard(dynamic u) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u['name'],
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(u['email']),
          const Divider(height: 32),
          _info("Tipo", u['type']),
          _info("Cidade", u['cidade']),
          _info("CREF", u['cref']),
          _info("Especialidade", u['especialidade']),
          _info("Experiência", u['experiencia']),
        ],
      ),
    );
  }

  Widget _ticketArea() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Histórico da Análise",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),

          /// Histórico
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      "Nenhuma mensagem enviada ainda.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Administrador",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(msg['text']),
                            const SizedBox(height: 6),
                            Text(
                              msg['time'],
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            )
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const Divider(height: 32),

          /// Templates de correção
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: "Mensagem de correção",
              border: OutlineInputBorder(),
            ),
            initialValue: selectedCorrectionTemplate,
            items: correctionTemplates
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {
              setState(() => selectedCorrectionTemplate = value);
            },
          ),

          const SizedBox(height: 12),

          /// Botão enviar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: selectedCorrectionTemplate == null
                  ? null
                  : () => _sendMessage(selectedCorrectionTemplate!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
              child: const Text("Enviar Mensagem"),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Aprovar"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _showRejectionDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Rejeitar"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _showRejectionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Motivo da Rejeição"),
        content: DropdownButtonFormField<String>(
          initialValue: selectedRejectionTemplate,
          items: rejectionTemplates
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (value) {
            setState(() => selectedRejectionTemplate = value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: _rejectUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Confirmar Rejeição"),
          )
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8)
      ],
    );
  }

  Widget _info(String label, dynamic value) {
    if (value == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text("$label: $value"),
    );
  }
}