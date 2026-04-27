import 'package:flutter/foundation.dart';

class AppRefreshNotifier {
  AppRefreshNotifier._();

  static final ValueNotifier<int> signal = ValueNotifier<int>(0);
  static final ValueNotifier<bool> floatingVisible = ValueNotifier<bool>(true);

  static void trigger() {
    signal.value = signal.value + 1;
  }

  static void setFloatingVisible(bool value) {
    if (floatingVisible.value == value) return;
    floatingVisible.value = value;
  }

  static void hideFloating() => setFloatingVisible(false);

  static void showFloating() => setFloatingVisible(true);
}
