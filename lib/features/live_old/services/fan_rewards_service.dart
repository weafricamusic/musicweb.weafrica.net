import 'package:supabase_flutter/supabase_flutter.dart';

class FanRewardsService {
  FanRewardsService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<FanRewardItem>> listAvailableRewards() async {
    final rows = await _supabase
        .from('fan_rewards')
        .select('id,name,description,trigger_type,trigger_threshold,reward_type,reward_value,enabled,updated_at')
        .eq('enabled', true)
        .order('trigger_threshold', ascending: true);

    return rows
        .whereType<Map>()
        .map((row) => FanRewardItem.fromMap(
              row.map((k, v) => MapEntry(k.toString(), v)),
            ))
        .toList(growable: false);
  }

  Future<List<FanRewardClaim>> listMyClaims() async {
    final uid = _supabase.auth.currentUser?.id.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Not signed in');
    }

    final rows = await _supabase
        .from('fan_reward_claims')
        .select('id,user_id,reward_id,claimed_at,metadata')
        .eq('user_id', uid)
        .order('claimed_at', ascending: false);

    return rows
        .whereType<Map>()
        .map((row) => FanRewardClaim.fromMap(
              row.map((k, v) => MapEntry(k.toString(), v)),
            ))
        .toList(growable: false);
  }

  Future<FanRewardClaimResult> claimReward({required String rewardId}) async {
    final uid = _supabase.auth.currentUser?.id.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('Not signed in');
    }

    final normalizedRewardId = rewardId.trim();
    if (normalizedRewardId.isEmpty) {
      throw ArgumentError('rewardId is required');
    }

    final rpcRes = await _supabase.rpc(
      'claim_fan_reward',
      params: <String, dynamic>{
        'p_user_id': uid,
        'p_reward_id': normalizedRewardId,
      },
    );

    if (rpcRes is List && rpcRes.isNotEmpty && rpcRes.first is Map) {
      final first = (rpcRes.first as Map).map((k, v) => MapEntry(k.toString(), v));
      return FanRewardClaimResult.fromMap(first);
    }

    if (rpcRes is Map) {
      return FanRewardClaimResult.fromMap(
        rpcRes.map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    throw StateError('Invalid reward claim response');
  }
}

class FanRewardItem {
  const FanRewardItem({
    required this.id,
    required this.name,
    required this.description,
    required this.triggerType,
    required this.triggerThreshold,
    required this.rewardType,
    required this.rewardValue,
  });

  final String id;
  final String name;
  final String description;
  final String triggerType;
  final int triggerThreshold;
  final String rewardType;
  final int rewardValue;

  factory FanRewardItem.fromMap(Map<String, dynamic> row) {
    int asInt(dynamic raw, [int fallback = 0]) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw') ?? fallback;
    }

    return FanRewardItem(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      triggerType: (row['trigger_type'] ?? '').toString(),
      triggerThreshold: asInt(row['trigger_threshold']),
      rewardType: (row['reward_type'] ?? '').toString(),
      rewardValue: asInt(row['reward_value']),
    );
  }
}

class FanRewardClaim {
  const FanRewardClaim({
    required this.id,
    required this.userId,
    required this.rewardId,
    required this.claimedAt,
  });

  final String id;
  final String userId;
  final String rewardId;
  final DateTime? claimedAt;

  factory FanRewardClaim.fromMap(Map<String, dynamic> row) {
    final claimedAtRaw = (row['claimed_at'] ?? '').toString().trim();
    return FanRewardClaim(
      id: (row['id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      rewardId: (row['reward_id'] ?? '').toString(),
      claimedAt: claimedAtRaw.isEmpty ? null : DateTime.tryParse(claimedAtRaw),
    );
  }
}

class FanRewardClaimResult {
  const FanRewardClaimResult({
    required this.ok,
    required this.creditedCoins,
    required this.newBalance,
  });

  final bool ok;
  final int creditedCoins;
  final int newBalance;

  factory FanRewardClaimResult.fromMap(Map<String, dynamic> row) {
    int asInt(dynamic raw, [int fallback = 0]) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw') ?? fallback;
    }

    return FanRewardClaimResult(
      ok: row['ok'] == true,
      creditedCoins: asInt(row['credited_coins']),
      newBalance: asInt(row['new_balance']),
    );
  }
}
