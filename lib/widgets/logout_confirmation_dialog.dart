import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Exibe o diálogo de confirmação de saída e, quando confirmado, limpa a
/// sessão e redireciona o usuário para a tela inicial.
Future<void> showLogoutConfirmationDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sair da conta?'),
      content: const Text('Tem certeza que deseja sair do aplicativo?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Sair'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  await AuthService.clearSession();
  if (context.mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
}
