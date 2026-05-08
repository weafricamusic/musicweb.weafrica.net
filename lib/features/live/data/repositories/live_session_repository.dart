import '../services/firebase_live_service.dart';
import '../../core/models/live_session_model.dart';
import '../../core/models/live_user_model.dart';

/// Repository that mediates between Cubits and the Firebase service.
class LiveSessionRepository {
  final FirebaseLiveService _liveService;

  LiveSessionRepository(this._liveService);

  Future<LiveSessionModel> startSession({
    required String hostId,
    required String hostName,
    required String title,
    required String channelId,
    String? category,
  }) {
    return _liveService.createSession(
      hostId: hostId,
      hostName: hostName,
      title: title,
      channelId: channelId,
      category: category,
    );
  }

  Future<void> endSession(String sessionId) {
    return _liveService.endSession(sessionId);
  }

  Future<void> heartbeat(String channelId) {
    return _liveService.heartbeat(channelId);
  }

  Future<List<LiveSessionModel>> getActiveSessions({int limit = 10}) {
    return _liveService.getActiveSessions(limit: limit);
  }

  Future<void> updateViewerCount(String sessionId, int count) {
    return _liveService.updateViewerCount(sessionId, count);
  }
}
