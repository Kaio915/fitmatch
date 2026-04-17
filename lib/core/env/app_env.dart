class AppEnv {
  const AppEnv._();

  // Lido em build-time via --dart-define=API_BASE_URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}
