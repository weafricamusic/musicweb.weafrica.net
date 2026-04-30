/// WeAfrica Music Coin Transaction Model
/// 
/// Tracks all coin movements in the system
enum TransactionType {
  earn,      // From ads, promotions
  purchase,  // Buying with real money
  giftSent,  // Sending to artist
  giftReceived, // Artist receiving
  battleEntry, // Joining battle
  battleWinnings, // Winning battle
  withdrawal, // Artist withdrawing
  refund,    // Refunds
}

enum TransactionStatus {
  pending,
  completed,
  failed,
  cancelled,
}

class CoinTransaction {
  const CoinTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.balanceAfter,
    this.description,
    this.relatedUserId, // For gifts
    this.relatedEntityId, // Battle ID, etc
    this.metadata,
    this.status = TransactionStatus.completed,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final TransactionType type;
  final int amount; // Positive = credit, Negative = debit
  final int? balanceAfter;
  final String? description;
  final String? relatedUserId;
  final String? relatedEntityId;
  final Map<String, dynamic>? metadata;
  final TransactionStatus status;
  final DateTime createdAt;

  bool get isCredit => amount > 0;
  bool get isDebit => amount < 0;

  factory CoinTransaction.fromJson(Map<String, dynamic> json) {
    return CoinTransaction(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.earn,
      ),
      amount: json['amount'] ?? 0,
      balanceAfter: json['balance_after'],
      description: json['description']?.toString(),
      relatedUserId: json['related_user_id']?.toString(),
      relatedEntityId: json['related_entity_id']?.toString(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TransactionStatus.completed,
      ),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.name,
      'amount': amount,
      'balance_after': balanceAfter,
      'description': description,
      'related_user_id': relatedUserId,
      'related_entity_id': relatedEntityId,
      'metadata': metadata,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}