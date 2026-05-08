import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Tracks viewer join/leave sessions and provides simple helpers.
class ViewerTrackingService {
  final SupabaseClient _supabase;
  final _uuid = const Uuid();
  String? _currentSessionId;
  String? _viewerSessionId;

  ViewerTrackingService(this._supabase);

  Future<String> joinLive({
    required String liveSessionId,
    required String? userId,
    String? deviceId,
    String? country,
  }) async {
    _currentSessionId = liveSessionId;
    _viewerSessionId = _uuid.v4();

    await _supabase.from('viewer_sessions').insert({
      'id': _viewerSessionId,
      'live_session_id': liveSessionId,
      'user_id': userId,
      'device_id': deviceId,
      'country': country ?? 'MW',
      'joined_at': DateTime.now().toIso8601String(),
    });

    return _viewerSessionId!;
  }

  Future<void> leaveLive() async {
    final vid = _viewerSessionId;
    if (vid == null) return;

    await _supabase.from('viewer_sessions').update({
      'left_at': DateTime.now().toIso8601String(),
    }).eq('id', vid);

    _viewerSessionId = null;
    _currentSessionId = null;
  }

  Future<int> getCurrentViewerCount(String liveSessionId) async {
    final resp = await _supabase
      .from('viewer_sessions')
      .select('id')
      .eq('live_session_id', liveSessionId)
      .filter('left_at', 'is', null);

    final list = resp as List?;
    return list?.length ?? 0;
  }

  Stream<int> watchViewerCount(String liveSessionId) {
    return _supabase
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', liveSessionId)
        .map((rows) => rows.isNotEmpty ? (rows.first['viewers'] as int? ?? 0) : 0);
  }

  Future<void> heartbeat() async {
    final vid = _viewerSessionId;
    if (vid == null) return;
    await _supabase.from('viewer_sessions').update({
      'joined_at': DateTime.now().toIso8601String(),
    }).eq('id', vid);
  }
}
