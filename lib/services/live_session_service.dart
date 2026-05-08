import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/live_session_model.dart';

class LiveSessionService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<LiveSessionModel> createLiveSession({
    required String channelId,
    required String hostId,
    String? hostName,
    String? hostAvatarUrl,
    String? title,
  }) async {
    final response = await _client.from('live_sessions').insert({
      'channel_id': channelId,
      'host_id': hostId,
      'host_name': hostName,
      'host_avatar_url': hostAvatarUrl,
      'title': title,
      'status': 'live',
      'is_live': true,
      'started_at': DateTime.now().toIso8601String(),
    }).select().single();

    return LiveSessionModel.fromJson(response);
  }

  Future<List<LiveSessionModel>> getActiveLiveSessions() async {
    final response = await _client
        .from('live_sessions')
        .select()
        .eq('is_live', true)
        .order('viewer_count', ascending: false);

    return (response as List).map((json) => LiveSessionModel.fromJson(json)).toList();
  }

  Future<LiveSessionModel?> getLiveSession(String sessionId) async {
    final response = await _client
        .from('live_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();

    if (response == null) return null;
    return LiveSessionModel.fromJson(response);
  }

  Future<void> endLiveSession(String sessionId) async {
    await _client.from('live_sessions').update({
      'is_live': false,
      'status': 'ended',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  Future<void> updateHeartbeat(String sessionId) async {
    await _client.from('live_sessions').update({
      'last_heartbeat': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  Future<void> incrementViewerCount(String sessionId) async {
    await _client.rpc('increment_live_viewer_count', params: {'session_id': sessionId});
  }

  Future<void> decrementViewerCount(String sessionId) async {
    await _client.rpc('decrement_live_viewer_count', params: {'session_id': sessionId});
  }

  Stream<List<Map<String, dynamic>>> subscribeToLiveSessions() {
    return _client
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .eq('is_live', true)
        .order('viewer_count', ascending: false);
  }

  Stream<List<Map<String, dynamic>>> subscribeToSession(String sessionId) {
    return _client
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId);
  }

  // --- Methods from the other version of the service ---

  Future<void> startSession() async {}
  Future<void> endSession() async {}

  Future<Map<String, dynamic>> joinSession({
    required String channelId,
    String? token,
    String? uid,
  }) async {
    // Placeholder
    return <String, dynamic>{};
  }

  Future<void> heartbeat({required String channelId}) async {}

  Future<void> endLiveAndEnsureCleared({
    required String channelId,
    String? liveSessionId,
  }) async {}
}
