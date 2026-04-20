import 'dart:convert';
import 'dart:developer' as developer;

import '../app/config/api_env.dart';
import '../app/network/firebase_authed_http.dart';

class JourneyService {
  JourneyService._();
  static final JourneyService instance = JourneyService._();

  Future<void> logEvent({
    required String eventType,
    String? eventKey,
    Map<String, Object?>? metadata,
    DateTime? occurredAtUtc,
  }) async {
    final type = eventType.trim();
    if (type.isEmpty) return;

    try {
      final base = ApiEnv.baseUrl.endsWith('/')
          ? ApiEnv.baseUrl.substring(0, ApiEnv.baseUrl.length - 1)
          : ApiEnv.baseUrl;
      final uri = Uri.parse('$base/api/journey/event');

      final body = <String, Object?>{
        'event_type': type,
        if (eventKey != null && eventKey.trim().isNotEmpty) 'event_key': eventKey.trim(),
        if (occurredAtUtc != null) 'occurred_at': occurredAtUtc.toUtc().toIso8601String(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      };

      await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
        timeout: const Duration(seconds: 8),
        includeAuthIfAvailable: true,
        requireAuth: true,
      );
    } catch (e) {
      developer.log('Journey event failed (best-effort): $e', name: 'WEAFRICA.Journey');
    }
  }
}
