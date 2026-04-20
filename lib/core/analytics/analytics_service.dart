import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService();

  void logEvent({required String name, Map<String, Object?>? parameters}) {
    // Best-effort: analytics must never crash the app.
    if (!kDebugMode) return;

    final p = parameters == null || parameters.isEmpty ? '' : ' $parameters';
    debugPrint('[Analytics] $name$p');
  }
}
