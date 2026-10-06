import 'package:flutter/material.dart';
import 'app.dart';
import 'services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FcmService.initialize();
  runApp(const App());
}
