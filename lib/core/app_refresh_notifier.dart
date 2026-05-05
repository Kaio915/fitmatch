import 'package:flutter/foundation.dart';

class AppRefreshNotifier {
  AppRefreshNotifier._();

  static final ValueNotifier<int> signal = ValueNotifier<int>(0);

  static void trigger() {
    signal.value = signal.value + 1;
  }
}
