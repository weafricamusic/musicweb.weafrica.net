import '../models/live_session_model.dart';
import 'package:weafrica_music/services/live_session_service.dart';

/// Repository for live session operations
class LiveSessionRepository {
  final LiveSessionService _service = LiveSessionService();

  Future<LiveSessionModel> createSession({
    required String channelId,
    required String hostId,
    String? hostName,
    String? hostAvatarUrl,
    String? title,
  }) async {
    return await _service.createLiveSession(
      channelId: channelId,
      hostId: hostId,
      hostName: hostName,
      hostAvatarUrl: hostAvatarUrl,
      title: title,
    );
  }

  Future<List<LiveSessionModel>> getActiveSessions() async {
    return await _service.getActiveLiveSessions();
  }

  Future<LiveSessionModel?> getSession(String sessionId) async {
    return await _service.getLiveSession(sessionId);
  }

  Future<void> endSession(String sessionId) async {
    await _service.endLiveSession(sessionId);
  }

  Future<void> updateHeartbeat(String sessionId) async {
    await _service.updateHeartbeat(sessionId);
  }

  Future<void> incrementViewers(String sessionId) async {
    await _service.incrementViewerCount(sessionId);
  }

  Future<void> decrementViewers(String sessionId) async {
    await _service.decrementViewerCount(sessionId);
  }

  Stream<List<Map<String, dynamic>>> subscribeToSessions() {
    return _service.subscribeToLiveSessions();
  }

  Stream<List<Map<String, dynamic>>> subscribeToSession(String sessionId) {
    return _service.subscribeToSession(sessionId);
  }
}