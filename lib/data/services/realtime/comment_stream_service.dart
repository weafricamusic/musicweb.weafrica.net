import 'package:supabase_flutter/supabase_flutter.dart';

class CommentStreamService {
  final SupabaseClient _supabase;

  CommentStreamService(this._supabase);

  Stream<List<Map<String, dynamic>>> subscribeToComments(String liveSessionId) {
    return _supabase
        .from('live_comments')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', liveSessionId)
        .order('created_at')
        .map((rows) => List<Map<String, dynamic>>.from(rows));
  }

  Future<void> sendComment({
    required String liveSessionId,
    required String userId,
    required String username,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    await _supabase.from('live_comments').insert({
      'live_session_id': liveSessionId,
      'user_id': userId,
      'username': username,
      'text': text.trim(),
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _supabase.from('live_comments').delete().eq('id', commentId);
  }

  Future<List<Map<String, dynamic>>> fetchRecentComments(String liveSessionId, {int limit = 50}) async {
    final resp = await _supabase
        .from('live_comments')
        .select()
        .eq('live_session_id', liveSessionId)
        .order('created_at', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from((resp as List?) ?? []);
  }
}
