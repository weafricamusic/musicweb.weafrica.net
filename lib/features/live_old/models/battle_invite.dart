// Minimal stub for BattleInvite used by legacy screens.
class BattleInvite {
  final String id;
  final String? fromUserId;
  final String? toUserId;

  BattleInvite({required this.id, this.fromUserId, this.toUserId});

  factory BattleInvite.fromJson(Map<String, dynamic> json) {
    return BattleInvite(
      id: json['id']?.toString() ?? '',
      fromUserId: json['from_user_id'] as String?,
      toUserId: json['to_user_id'] as String?,
    );
  }
}
