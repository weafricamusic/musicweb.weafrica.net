/// Represents a live battle session.
class LiveBattle {
  final String battleId;
  final String channelId;
  final String? hostAId;
  final String? hostBId;
  final String? title;
  final DateTime? createdAt;

  LiveBattle({
    required this.battleId,
    required this.channelId,
    this.hostAId,
    this.hostBId,
    this.title,
    this.createdAt,
  });

  factory LiveBattle.fromMap(Map<String, dynamic> map) {
    return LiveBattle(
      battleId: (map['battle_id'] ?? '').toString(),
      channelId: (map['channel_id'] ?? map['channelId'] ?? '').toString(),
      hostAId: map['host_a_id']?.toString(),
      hostBId: map['host_b_id']?.toString(),
      title: map['title']?.toString(),
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'].toString()) 
          : null,
    );
  }
}

/// Represents a battle invitation.
class BattleInvite {
  final String id;
  final String fromUid;
  final String toUid;
  final String fromUserName;
  final String battleId;
  final DateTime expiresAt;
  final String status;

  BattleInvite({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.fromUserName,
    required this.battleId,
    required this.expiresAt,
    this.status = 'pending',
  });

  factory BattleInvite.fromMap(Map<String, dynamic> map) {
    return BattleInvite(
      id: (map['id'] ?? '').toString(),
      fromUid: (map['from_uid'] ?? '').toString(),
      toUid: (map['to_uid'] ?? '').toString(),
      fromUserName: (map['from_user_name'] ?? '').toString(),
      battleId: (map['battle_id'] ?? '').toString(),
      expiresAt: map['expires_at'] != null 
          ? DateTime.parse(map['expires_at'].toString()) 
          : DateTime.now(),
      status: (map['status'] ?? 'pending').toString(),
    );
  }
}