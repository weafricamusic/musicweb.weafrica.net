/// Simple logger for live streaming events.
class LiveLogger {
  static void log(String tag, String message) {
    debugPrint('[Live][$tag] $message');
  }
}
