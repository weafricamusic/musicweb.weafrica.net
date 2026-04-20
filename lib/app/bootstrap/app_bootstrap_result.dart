/// Result of the bootstrap process with detailed status.
class AppBootstrapResult {
  const AppBootstrapResult({
    required this.firebaseInitError,
    required this.supabaseInitError,
    required this.deviceReady,
    required this.initializationTimeMs,
    required this.offlineMode,
  });

  final Object? firebaseInitError;
  final Object? supabaseInitError;
  final bool deviceReady;
  final int initializationTimeMs;
  final bool offlineMode;

  /// Supabase is the critical path for the app.
  bool get success => supabaseInitError == null;

  /// Can the user enter the live/streaming experience?
  bool get canEnterStage => supabaseInitError == null && deviceReady;

  String get userFriendlyMessage {
    if (offlineMode) return 'You are offline. Some features may be limited.';
    if (supabaseInitError != null) {
      return 'Unable to connect. Please check your internet connection.';
    }
    if (!deviceReady) return 'Camera and microphone access needed to perform.';
    return 'Ready.';
  }
}
