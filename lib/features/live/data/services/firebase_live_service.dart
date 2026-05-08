import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/live_session_model.dart';

/// Service for managing live session documents in Supabase.
class FirebaseLiveService {
  final SupabaseClient _supabase;

  FirebaseLiveService(this._supabase);

  /// Create a new live session.
  Future<LiveSessionModel> createSession({
    required String hostId,
    required String hostName,
    required String title,
    required String channelId,
    String? category,
  }) async {
    final response = await _supabase
        .from('live_sessions')
        .insert({
          'host_id': hostId,
          'host_name': hostName.trim().isEmpty ? 'Live Host' : hostName.trim(),
          'channel_id': channelId,
          'title': title,
          'category': category ?? 'music',
          'status': 'live',
          'is_live': true,
          'viewer_count': 0,
        })
        .select()
        .single();

    return LiveSessionModel.fromJson(response);
  }

  /// End an active live session.
  Future<void> endSession(String sessionId) async {
    await _supabase
        .from('live_sessions')
        .update({'status': 'ended', 'is_live': false})
        .eq('id', sessionId);
  }

  /// Update viewer count.
  Future<void> updateViewerCount(String sessionId, int count) async {
    await _supabase
        .from('live_sessions')
        .update({'viewer_count': count})
        .eq('id', sessionId);
  }

  /// Send heartbeat (keeps session alive).
  Future<void> heartbeat(String channelId) async {
    await _supabase
        .from('live_sessions')
        .update({
          'last_heartbeat_at': DateTime.now().toIso8601String(),
        })
        .eq('channel_id', channelId);
  }

  /// Fetch active live sessions.
  Future<List<LiveSessionModel>> getActiveSessions({int limit = 10}) async {
    final response = await _supabase
        .from('live_sessions')
        .select()
        .eq('is_live', true)
        .order('created_at', ascending: false)
        .limit(limit);

    return (response as List).map((e) => LiveSessionModel.fromJson(e)).toList();
  }
}