/// Model for a battle invite request between two artists.
class BattleRequestModel {
  final String sessionId;
  final String fromUserId;
  final String fromUserName;
  final String? fromAvatarUrl;
  final String toUserId;
  final String status; // pending, accepted, declined, cancelled
  final DateTime createdAt;

  const BattleRequestModel({
    required this.sessionId,
    required this.fromUserId,
    required this.fromUserName,
    this.fromAvatarUrl,
    required this.toUserId,
    required this.status,
    required this.createdAt,
  });

  factory BattleRequestModel.fromJson(Map<String, dynamic> json) {
    return BattleRequestModel(
      sessionId: json['session_id']?.toString() ?? '',
      fromUserId: json['from_user_id']?.toString() ?? '',
      fromUserName: json['from_user_name']?.toString() ?? 'Unknown',
      fromAvatarUrl: json['from_avatar_url']?.toString(),
      toUserId: json['to_user_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}