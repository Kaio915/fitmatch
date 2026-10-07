import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

/// Mantém a contagem de mensagens não lidas POR conversa (badge do chat).
///
/// É um singleton (ChangeNotifier) consumido pelo widget [ChatBadge] e
/// atualizado por:
///  - push FCM (incremento otimista em foreground);
///  - refresh do servidor (valor autoritativo);
///  - abertura do chat (zera o contador daquela conversa).
class ChatBadgeNotifier extends ChangeNotifier {
  ChatBadgeNotifier._();

  static final ChatBadgeNotifier instance = ChatBadgeNotifier._();

  final Map<String, int> _unreadCountsPerUser = {};

  /// Cópia imutável do mapa {senderId -> quantidade de não lidas}.
  Map<String, int> get unreadCountsPerUser => Map.unmodifiable(_unreadCountsPerUser);

  /// Total de mensagens não lidas (soma de todas as conversas).
  int get unreadCount =>
      _unreadCountsPerUser.values.fold(0, (sum, value) => sum + value);

  /// Quantidade de mensagens não lidas vindas de um usuário específico.
  int unreadCountFor(String targetUserId) =>
      _unreadCountsPerUser[targetUserId] ?? 0;

  /// Busca as contagens de mensagens não lidas no backend (valor autoritativo).
  Future<void> refreshFromServer() async {
    try {
      final counts = await AuthService.getUnreadCounts();
      _unreadCountsPerUser
        ..clear()
        ..addAll(counts);
      notifyListeners();
    } catch (_) {
      // Offline ou não logado: mantém o valor atual.
    }
  }

  /// Incrementa quando chega uma nova mensagem de [senderId] com o app aberto.
  void incrementFromPush(String senderId) {
    final key = senderId.trim();
    if (key.isEmpty) return;
    _unreadCountsPerUser[key] = (_unreadCountsPerUser[key] ?? 0) + 1;
    notifyListeners();
  }

  /// Zera o contador de uma conversa específica (chamado ao abrir o chat).
  void clearFor(String targetUserId) {
    if (_unreadCountsPerUser.remove(targetUserId) != null) {
      notifyListeners();
    }
  }

  /// Zera o contador de todas as conversas.
  void clear() {
    if (_unreadCountsPerUser.isEmpty) return;
    _unreadCountsPerUser.clear();
    notifyListeners();
  }
}
