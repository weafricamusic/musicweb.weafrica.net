import '../models/live_comment_model.dart';
import '../../services/comment_service.dart';

/// Repository for comment operations
class CommentRepository {
  final CommentService _service = CommentService();

  Future<void> sendComment({
    required String sessionId,
    required String message,
  }) async {
    await _service.sendComment(
      sessionId: sessionId,
      message: message,
    );
  }

  Future<List<LiveCommentModel>> getComments(String sessionId, {int limit = 50}) async {
    return await _service.getComments(sessionId, limit: limit);
  }

  Stream<List<Map<String, dynamic>>> subscribeToComments(String sessionId) {
    return _service.subscribeToComments(sessionId);
  }
}