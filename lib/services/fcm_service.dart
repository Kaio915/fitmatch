import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/chat_badge_notifier.dart';
import 'auth_service.dart';

/// Configura o Firebase Cloud Messaging (FCM) e as notificações locais.
///
/// Responsabilidades:
///  1. Inicializar o Firebase.
///  2. Solicitar permissão de notificação.
///  3. Obter o token FCM do dispositivo e enviá-lo à API.
///  4. Escutar mensagens em foreground / background / app fechado.
class FcmService {
  FcmService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Deve ser chamado uma única vez no main() (antes do runApp).
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Sem configuração do Firebase (ex.: web sem opções) o app continua funcionando.
      debugPrint('FCM: Firebase não configurado, notificações desabilitadas. $e');
      return;
    }

    await _initLocalNotifications();
    await requestPermission();
    await _registerToken();

    // Token renovado pelo Firebase (raro, mas pode acontecer).
    _messaging.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });

    // Foreground: app aberto e em uso.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background: usuário toca na notificação com o app em segundo plano.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    // App iniciado a partir de uma notificação (app estava totalmente fechado).
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _handleOpenedMessage(initial);
    }
  }

  /// Solicita permissão de notificação (Android 13+ pede no primeiro uso).
  static Future<void> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM: authorizationStatus=${settings.authorizationStatus}');
  }

  /// Obtém o token FCM do dispositivo.
  static Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM: falha ao obter token: $e');
      return null;
    }
  }

  static Future<void> _registerToken() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      await _sendTokenToBackend(token);
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      await AuthService.saveFcmToken(token);
      debugPrint('FCM: token enviado para a API.');
    } catch (e) {
      // Se ainda não estiver logado, o token é reenviado no próximo login.
      debugPrint('FCM: não foi possível enviar o token agora: $e');
    }
  }

  /// App aberto (foreground): incrementa o badge e exibe notificação local
  /// com o conteúdo do data payload (nome do remetente + trecho da mensagem).
  static void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] != 'chat_message') return;

    ChatBadgeNotifier.instance.incrementFromPush();
    _showLocalNotification(data);
  }

  /// App abriu a partir de uma notificação: busca o total autoritativo no servidor.
  static void _handleOpenedMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] != 'chat_message') return;
    ChatBadgeNotifier.instance.refreshFromServer();
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) {
        // Toque na notificação local (opcional: navegar para o chat).
      },
    );
  }

  static Future<void> _showLocalNotification(Map<String, dynamic> data) async {
    final senderName = (data['senderName'] ?? '').toString();
    final preview = (data['messagePreview'] ?? '').toString();

    const androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Mensagens do Chat',
      channelDescription: 'Notificações de novas mensagens de chat',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      senderName.isEmpty ? 'Nova mensagem' : senderName,
      preview.isEmpty ? 'Você recebeu uma nova mensagem' : preview,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
