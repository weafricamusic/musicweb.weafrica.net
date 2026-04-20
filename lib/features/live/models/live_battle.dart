import 'package:flutter/foundation.dart';

@immutable
class LiveBattle {
  const LiveBattle({
    required this.battleId,
    required this.channelId,
    this.hostAId,
    this.hostBId,
  });

  final String battleId;
  final String channelId;
  final String? hostAId;
  final String? hostBId;

  factory LiveBattle.fromMap(Map<String, dynamic> row) {
    String s(Object? v) => (v ?? '').toString().trim();

    final battleId = s(row['battle_id']).isNotEmpty ? s(row['battle_id']) : s(row['battleId']);
    final channelId = s(row['channel_id']).isNotEmpty ? s(row['channel_id']) : s(row['channelId']);

    return LiveBattle(
      battleId: battleId.isNotEmpty ? battleId : (channelId.isNotEmpty ? channelId : 'battle'),
      channelId: channelId.isNotEmpty ? channelId : (battleId.isNotEmpty ? 'live_$battleId' : ''),
      hostAId: s(row['host_a_id']).isNotEmpty ? s(row['host_a_id']) : (s(row['hostAId']).isNotEmpty ? s(row['hostAId']) : null),
      hostBId: s(row['host_b_id']).isNotEmpty ? s(row['host_b_id']) : (s(row['hostBId']).isNotEmpty ? s(row['hostBId']) : null),
    );
  }
}
