import 'package:flutter/material.dart';

import '../core/chat_badge_notifier.dart';

/// Envolve um botão de chat com o badge de mensagens não lidas.
///
/// Exemplo de uso:
/// ```dart
/// ChatBadge(
///   targetUserId: '123', // id do outro usuário da conversa
///   child: OutlinedButton.icon(
///     icon: const Icon(Icons.chat_bubble_outline_rounded),
///     label: const Text('Chat'),
///     onPressed: () { ... },
///   ),
/// )
/// ```
class ChatBadge extends StatelessWidget {
  /// ID do usuário cuja conversa será observada. O badge só aparece quando
  /// existem mensagens não lidas vindas DESTE usuário específico.
  final String targetUserId;

  final Widget child;

  const ChatBadge({
    super.key,
    required this.targetUserId,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChatBadgeNotifier.instance,
      builder: (context, _) {
        final count = ChatBadgeNotifier.instance.unreadCountFor(targetUserId);
        return Badge(
          isLabelVisible: count > 0,
          backgroundColor: Colors.red,
          label: Text(count > 99 ? '99+' : count.toString()),
          child: child,
        );
      },
    );
  }
}
