import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/live_session_model.dart';
import 'supabase_service.dart';

/// Service for managing live sessions
class LiveSessionService {
  final _client = SupabaseService.client;

  /// Create a new live session
  Future<LiveSessionModel> createLiveSession({
    required String channelId,
    required String hostId,
    String? hostName,
    String? hostAvatarUrl,
    String? title,
  }) async {
    // Check if user already has an active live session
    final existing = await _client
        .from('live_sessions')
        .select()
        .eq('host_id', hostId)
        .eq('is_live', true)
        .maybeSingle();

    if (existing != null) {
      throw Exception('You already have an active live session');
    }

    // Create new session
    final response = await _client
        .from('live_sessions')
        .insert({
          'channel_id': channelId,
          'host_id': hostId,
          'host_name': hostName,
          'host_avatar_url': hostAvatarUrl,
          'title': title,
          'status': 'live',
          'is_live': true,
          'live_type': 'solo',
          'viewer_count': 0,
          'gift_count': 0,
          'last_heartbeat': DateTime.now().toIso8601String(),
          'started_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return LiveSessionModel.fromJson(response);
  }

  /// Get all active live sessions
  Future<List<LiveSessionModel>> getActiveLiveSessions() async {
    final response = await _client
        .from('live_sessions')
        .select()
        .eq('is_live', true)
        .eq('live_type', 'solo')
        .order('viewer_count', ascending: false)
        .limit(50);

    return (response as List)
        .map((json) => LiveSessionModel.fromJson(json))
        .toList();
  }

  /// Get a single live session by ID
  Future<LiveSessionModel?> getLiveSession(String sessionId) async {
    final response = await _client
        .from('live_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();

    if (response == null) return null;
    return LiveSessionModel.fromJson(response);
  }

  /// End a live session
  Future<void> endLiveSession(String sessionId) async {
    await _client
        .from('live_sessions')
        .update({
          'is_live': false,
          'status': 'ended',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  /// Update heartbeat to keep session alive
  Future<void> updateHeartbeat(String sessionId) async {
    await _client
        .from('live_sessions')
        .update({
          'last_heartbeat': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  /// Increment viewer count
  Future<void> incrementViewerCount(String sessionId) async {
    try {
      await _client.rpc(
        'increment_viewer_count',
        params: {'session_id': sessionId},
      );
    } catch (e) {
      // Fallback if RPC doesn't exist
      final session = await getLiveSession(sessionId);
      if (session != null) {
        await _client
            .from('live_sessions')
            .update({'viewer_count': session.viewerCount + 1})
            .eq('id', sessionId);
      }
    }
  }

  /// Decrement viewer count
  Future<void> decrementViewerCount(String sessionId) async {
    try {
      await _client.rpc(
        'decrement_viewer_count',
        params: {'session_id': sessionId},
      );
    } catch (e) {
      // Fallback if RPC doesn't exist
      final session = await getLiveSession(sessionId);
      if (session != null) {
        final newCount = session.viewerCount > 0 ? session.viewerCount - 1 : 0;
        await _client
            .from('live_sessions')
            .update({'viewer_count': newCount})
            .eq('id', sessionId);
      }
    }
  }

  /// Subscribe to live session changes (realtime)
  Stream<List<Map<String, dynamic>>> subscribeToLiveSessions() {
    return _client
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .map((data) => data.where((row) => 
          row['is_live'] == true && row['live_type'] == 'solo'
        ).toList());
  }

  /// Subscribe to a specific session
  Stream<List<Map<String, dynamic>>> subscribeToSession(String sessionId) {
    return _client
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .map((data) => data.where((row) => 
          row['id'].toString() == sessionId
        ).toList());
  }
}