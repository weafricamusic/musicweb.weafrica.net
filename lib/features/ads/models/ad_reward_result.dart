/// Result of watching a rewarded ad
class AdRewardResult {
  const AdRewardResult({
    required this.success,
    required this.coinsEarned,
    this.errorMessage,
    this.adId,
  });

  final bool success;
  final int coinsEarned;
  final String? errorMessage;
  final String? adId;

  factory AdRewardResult.success({
    required int coinsEarned,
    String? adId,
  }) {
    return AdRewardResult(
      success: true,
      coinsEarned: coinsEarned,
      adId: adId,
    );
  }

  factory AdRewardResult.failure(String errorMessage) {
    return AdRewardResult(
      success: false,
      coinsEarned: 0,
      errorMessage: errorMessage,
    );
  }
}