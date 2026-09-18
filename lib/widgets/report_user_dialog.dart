import 'package:flutter/material.dart';

import '../services/admin_service.dart';

/// Exibe o diálogo de denúncia de usuário com os motivos possíveis e a opção
/// "Outro" (que abre um campo de texto livre). Ao confirmar, envia a denúncia
/// para o administrador via [AdminService.reportUser].
Future<void> showReportUserDialog(
  BuildContext context, {
  required int reporterId,
  required int reportedUserId,
}) async {
  const reasons = [
    'Conteúdo ofensivo ou assédio',
    'Perfil falso ou enganoso',
    'Tentativa de golpe',
    'Comportamento inadequado',
    'Outro',
  ];

  String? selectedReason;
  String explanation = '';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Denunciar usuário'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Denunciar este usuário ao administrador?\nEscolha um motivo:',
              ),
              const SizedBox(height: 12),
              for (final reason in reasons)
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason),
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                ),
              if (selectedReason != null)
                TextField(
                  autofocus: true,
                  maxLines: 3,
                  onChanged: (v) => setDialogState(() => explanation = v),
                  decoration: InputDecoration(
                    hintText: selectedReason == 'Outro'
                        ? 'Descreva o motivo'
                        : 'Explique melhor o que aconteceu',
                    border: const OutlineInputBorder(),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
              foregroundColor: Colors.white,
            ),
            onPressed: (selectedReason == null ||
                    (selectedReason == 'Outro' && explanation.trim().isEmpty))
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Denunciar'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return;

  final isOther = selectedReason == 'Outro';
  final reason = isOther
      ? explanation.trim()
      : (selectedReason ?? '');
  final details = isOther
      ? null
      : (explanation.trim().isEmpty ? null : explanation.trim());

  try {
    await AdminService.reportUser(
      reporterId: reporterId,
      reportedUserId: reportedUserId,
      reason: reason,
      details: details,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Denúncia enviada ao administrador.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
