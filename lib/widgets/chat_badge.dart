import 'package:flutter/material.dart';

import '../core/chat_badge_notifier.dart';

/// Envolve um botão de chat com o badge de mensagens não lidas.
///
/// Exemplo de uso:
/// ```dart
/// ChatBadge(
///   child: OutlinedButton.icon(
///     icon: const Icon(Icons.chat_bubble_outline_rounded),
///     label: const Text('Chat'),
///     onPressed: () { ... },
///   ),
/// )
/// ```
class ChatBadge extends StatelessWidget {
  final Widget child;

  const ChatBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChatBadgeNotifier.instance,
      builder: (context, _) {
        final count = ChatBadgeNotifier.instance.unreadCount;
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
