class AiPricingItem {
  final String action;
  final int coinCost;
  final int dailyFreeLimit;
  final bool enabled;

  const AiPricingItem({
    required this.action,
    required this.coinCost,
    required this.dailyFreeLimit,
    required this.enabled,
  });

  factory AiPricingItem.fromJson(Map<String, dynamic> json) {
    return AiPricingItem(
      action: (json['action'] ?? '').toString(),
      coinCost: (json['coin_cost'] ?? 0) as int,
      dailyFreeLimit: (json['daily_free_limit'] ?? 0) as int,
      enabled: (json['enabled'] ?? true) as bool,
    );
  }
}

class AiBalanceBeatGeneration {
  final String day;
  final int freeRemaining;
  final int coinCost;

  const AiBalanceBeatGeneration({
    required this.day,
    required this.freeRemaining,
    required this.coinCost,
  });

  factory AiBalanceBeatGeneration.fromJson(Map<String, dynamic> json) {
    return AiBalanceBeatGeneration(
      day: (json['day'] ?? '').toString(),
      freeRemaining: (json['free_remaining'] ?? 0) as int,
      coinCost: (json['coin_cost'] ?? 0) as int,
    );
  }
}

class AiBalanceResponse {
  final String uid;
  final String planId;
  final bool isPremiumActive;
  final int coinBalance;
  final int aiCreditBalance;
  final AiBalanceBeatGeneration beatGeneration;

  const AiBalanceResponse({
    required this.uid,
    required this.planId,
    required this.isPremiumActive,
    required this.coinBalance,
    required this.aiCreditBalance,
    required this.beatGeneration,
  });

  factory AiBalanceResponse.fromJson(Map<String, dynamic> json) {
    return AiBalanceResponse(
      uid: (json['uid'] ?? '').toString(),
      planId: (json['plan_id'] ?? 'free').toString(),
      isPremiumActive: (json['is_premium_active'] ?? false) as bool,
      coinBalance: (json['coin_balance'] ?? 0) as int,
      aiCreditBalance: (json['ai_credit_balance'] ?? 0) as int,
      beatGeneration: AiBalanceBeatGeneration.fromJson(
        Map<String, dynamic>.from((json['beat_generation'] ?? {}) as Map),
      ),
    );
  }
}
