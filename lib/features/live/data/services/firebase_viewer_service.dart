import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for tracking viewer presence in live sessions.
class FirebaseViewerService {
  final SupabaseClient _supabase;

  FirebaseViewerService(this._supabase);

  /// Join a live session as a viewer.
  Future<void> joinLive({
    required String liveSessionId,
    String? userId,
    String? deviceId,
  }) async {
    await _supabase.from('live_viewers').upsert({
      'session_id': liveSessionId,
      'user_id': userId,
      'device_id': deviceId ?? 'device_${DateTime.now().millisecondsSinceEpoch}',
      'joined_at': DateTime.now().toIso8601String(),
    });
  }

  /// Leave a live session.
  Future<void> leaveLive() async {
    // Implementation depends on how viewer sessions are tracked.
    // For now, this is a placeholder.
  }

  /// Stream the current viewer count.
  Stream<int> watchViewerCount(String sessionId) {
    return _supabase
        .from('live_viewers')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .map((list) => list.length);
  }
}
