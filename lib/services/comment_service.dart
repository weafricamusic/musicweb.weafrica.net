import '../data/models/live_comment_model.dart';
import 'supabase_service.dart';

/// Service for managing live comments
class CommentService {
  final _client = SupabaseService.client;

  /// Send a comment to a live session
  Future<void> sendComment({
    required String sessionId,
    required String message,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _client.from('live_comments').insert({
      'live_session_id': sessionId,
      'user_id': user.id,
      'username': user.userMetadata?['username'] ?? user.email ?? 'User',
      'avatar_url': user.userMetadata?['avatar_url'],
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get recent comments for a session
  Future<List<LiveCommentModel>> getComments(String sessionId, {int limit = 50}) async {
    final response = await _client
        .from('live_comments')
        .select()
        .eq('live_session_id', sessionId)
        .order('created_at', ascending: true)
        .limit(limit);

    return (response as List)
        .map((json) => LiveCommentModel.fromJson(json))
        .toList();
  }

  /// Subscribe to new comments
  Stream<List<Map<String, dynamic>>> subscribeToComments(String sessionId) {
    return _client
        .from('live_comments')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .order('created_at', ascending: true);
  }
}