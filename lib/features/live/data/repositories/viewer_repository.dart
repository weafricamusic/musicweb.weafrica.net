import '../services/firebase_viewer_service.dart';

/// Repository for viewer tracking.
class ViewerRepository {
  final FirebaseViewerService _viewerService;

  ViewerRepository(this._viewerService);

  Future<void> joinLive({
    required String liveSessionId,
    String? userId,
    String? deviceId,
  }) {
    return _viewerService.joinLive(
      liveSessionId: liveSessionId,
      userId: userId,
      deviceId: deviceId,
    );
  }

  Future<void> leaveLive() {
    return _viewerService.leaveLive();
  }

  Stream<int> watchViewerCount(String sessionId) {
    return _viewerService.watchViewerCount(sessionId);
  }
}
