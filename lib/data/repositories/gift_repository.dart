import '../../services/gift_service.dart';

/// Repository for gift operations
class GiftRepository {
  final GiftService _service = GiftService();

  Future<void> sendGift({
    required String sessionId,
    required String hostId,
    required String giftType,
    required double amount,
  }) async {
    await _service.sendGift(
      sessionId: sessionId,
      hostId: hostId,
      giftType: giftType,
      amount: amount,
    );
  }

  Future<double> getTotalGifts(String sessionId) async {
    return await _service.getTotalGifts(sessionId);
  }

  Future<List<Map<String, dynamic>>> getGiftLeaderboard(String sessionId) async {
    return await _service.getGiftLeaderboard(sessionId);
  }
}