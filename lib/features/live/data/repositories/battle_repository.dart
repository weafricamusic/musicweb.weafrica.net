import '../services/battle_request_service.dart';
import '../../core/models/battle_request_model.dart';

/// Repository for battle request operations.
class BattleRepository {
  final BattleRequestService _battleService;

  BattleRepository(this._battleService);

  Future<void> sendRequest({
    required String sessionId,
    required String fromUserId,
    required String fromUserName,
    String? fromAvatarUrl,
    required String toUserId,
  }) {
    return _battleService.sendRequest(
      sessionId: sessionId,
      fromUserId: fromUserId,
      fromUserName: fromUserName,
      fromAvatarUrl: fromAvatarUrl,
      toUserId: toUserId,
    );
  }

  Future<void> acceptRequest(String sessionId, String fromUserId) {
    return _battleService.acceptRequest(sessionId, fromUserId);
  }

  Future<void> declineRequest(String sessionId, String fromUserId) {
    return _battleService.declineRequest(sessionId, fromUserId);
  }

  Stream<List<BattleRequestModel>> streamRequests(String userId) {
    return _battleService.streamRequests(userId);
  }
}
