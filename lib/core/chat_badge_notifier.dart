import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

/// Mantém o contador global de mensagens não lidas (badge do chat).
///
/// É um singleton (ChangeNotifier) consumido pelo widget [ChatBadge] e
/// atualizado por:
///  - push FCM (incremento otimista em foreground);
///  - refresh do servidor (valor autoritativo);
///  - abertura do chat (zera o contador).
class ChatBadgeNotifier extends ChangeNotifier {
  ChatBadgeNotifier._();

  static final ChatBadgeNotifier instance = ChatBadgeNotifier._();

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  /// Busca o total de mensagens não lidas no backend (valor autoritativo).
  Future<void> refreshFromServer() async {
    try {
      final count = await AuthService.getUnreadCount();
      _unreadCount = count;
      notifyListeners();
    } catch (_) {
      // Offline ou não logado: mantém o valor atual.
    }
  }

  /// Incrementa quando chega uma nova mensagem enquanto o app está aberto.
  void incrementFromPush() {
    _unreadCount++;
    notifyListeners();
  }

  /// Zera o contador (chamado ao abrir o chat).
  void clear() {
    if (_unreadCount == 0) return;
    _unreadCount = 0;
    notifyListeners();
  }
}
