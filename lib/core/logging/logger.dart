import 'package:flutter/foundation.dart';

class AppLogger {
  const AppLogger._();

  static void i(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('INFO', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void w(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('WARN', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void _log(
    String level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final prefix = tag == null || tag.trim().isEmpty ? '' : '[${tag.trim()}] ';
    final base = '[$level] $prefix$message';

    if (error != null) {
      debugPrint('$base\nError: $error');
    } else {
      debugPrint(base);
    }

    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
