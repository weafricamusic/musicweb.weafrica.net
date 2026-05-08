import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class LiveSessionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> heartbeat({required String channelId}) async {
    try {
      debugPrint('Heartbeat called for channel: $channelId');

      // Update last_heartbeat_at in live_sessions
      await _supabase
          .from('live_sessions')
          .update({
            'last_heartbeat_at': DateTime.now().toIso8601String(),
          })
          .eq('channel_id', channelId);

      debugPrint('Heartbeat successful for channel: $channelId');
    } catch (e, st) {
      debugPrint('Heartbeat failed for live_sessions: $e\n$st');
    }

    // Optional: Try to record heartbeat in live_watch_heartbeats table
    // This might fail due to RLS, but we don't want it to break the main heartbeat
    try {
      await _supabase
          .from('live_watch_heartbeats')
          .insert({
            'channel_id': channelId,
            'bucket': DateTime.now().toIso8601String(),
            'meta': {'type': 'host_heartbeat'}
          });
    } catch (e) {
      debugPrint('Heartbeat for live_watch_heartbeats failed (RLS expected): $e');
    }
  }
}