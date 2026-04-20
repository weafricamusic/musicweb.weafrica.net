class BattleInvite {
  final String id;
  final String battleId;
  final String fromUid;
  final String toUid;
  final String fromUserName;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? battleTitle;

  BattleInvite({
    required this.id,
    required this.battleId,
    required this.fromUid,
    required this.toUid,
    required this.fromUserName,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.battleTitle,
  });

  factory BattleInvite.fromMap(Map<String, dynamic> map) {
    final fromProfileRaw = map['from_profile'];
    final fromProfile = fromProfileRaw is Map
        ? fromProfileRaw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final fromDisplayName = (fromProfile['display_name'] ?? '').toString().trim();
    final fromUsername = (fromProfile['username'] ?? '').toString().trim();
    final fallbackFrom = map['from_user_name']?.toString().trim() ?? '';
    final resolvedFromName = fromDisplayName.isNotEmpty
        ? fromDisplayName
        : (fromUsername.isNotEmpty ? '@$fromUsername' : fallbackFrom);

    return BattleInvite(
      id: map['id']?.toString() ?? '',
      battleId: map['battle_id']?.toString() ?? '',
      fromUid: map['from_uid']?.toString() ?? '',
      toUid: map['to_uid']?.toString() ?? '',
      fromUserName: resolvedFromName.isNotEmpty ? resolvedFromName : 'Someone',
      status: map['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      expiresAt: DateTime.tryParse(map['expires_at']?.toString() ?? '') ?? DateTime.now().add(const Duration(minutes: 5)),
      battleTitle: map['battle_title']?.toString() ?? map['title']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'battle_id': battleId,
      'from_uid': fromUid,
      'to_uid': toUid,
      'from_user_name': fromUserName,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'battle_title': battleTitle,
    };
  }
}
