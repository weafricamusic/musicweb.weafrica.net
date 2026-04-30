/// Coin Balance Model
/// 
/// User's coin balance information
class CoinBalance {
  const CoinBalance({
    required this.userId,
    required this.balance,
    required this.lifetimeEarned,
    required this.lifetimeSpent,
    this.lastUpdated,
  });

  final String userId;
  final int balance;
  final int lifetimeEarned;
  final int lifetimeSpent;
  final DateTime? lastUpdated;

  factory CoinBalance.fromJson(Map<String, dynamic> json) {
    return CoinBalance(
      userId: json['user_id']?.toString() ?? '',
      balance: json['balance'] ?? 0,
      lifetimeEarned: json['lifetime_earned'] ?? 0,
      lifetimeSpent: json['lifetime_spent'] ?? 0,
      lastUpdated: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'balance': balance,
      'lifetime_earned': lifetimeEarned,
      'lifetime_spent': lifetimeSpent,
      'updated_at': lastUpdated?.toIso8601String(),
    };
  }
}