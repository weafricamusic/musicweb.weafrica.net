import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class BattleTopGifter {
  const BattleTopGifter({
    required this.userId,
    required this.senderName,
    required this.coins,
  });

  final String userId;
  final String senderName;
  final int coins;

  factory BattleTopGifter.fromMap(Map<String, dynamic> row) {
    String s(Object? v) => (v ?? '').toString().trim();
    int i(Object? v) => (v is num) ? v.toInt() : int.tryParse(s(v)) ?? 0;

    final userId = s(row['user_id']).isNotEmpty ? s(row['user_id']) : s(row['userId']);
    final senderName = s(row['sender_name']).isNotEmpty ? s(row['sender_name']) : s(row['senderName']);
    return BattleTopGifter(
      userId: userId,
      senderName: senderName.isNotEmpty ? senderName : 'User',
      coins: i(row['coins']),
    );
  }
}

@immutable
class BattleStatus {
  const BattleStatus({
    required this.battleId,
    required this.channelId,
    required this.status,

    this.title,
    this.category,
    this.durationSeconds,
    this.battleType,
    this.beatName,
    required this.crowdBoostEnabled,
    this.coinGoal,
    this.country,
    required this.hostAId,
    required this.hostBId,
    required this.hostAScore,
    required this.hostBScore,

    this.totalSpentCoins,
    this.startedAt,
    this.endsAt,
    this.endedAt,
    this.winnerUid,

    this.timelineAnchorAt,
    required this.timelineAnchorElapsedSeconds,
    this.timelinePausedAt,
    required this.timelinePerfASeconds,
    required this.timelinePerfBSeconds,
    required this.timelineJudgingSeconds,
    required this.isDraw,

    this.topGifters = const <BattleTopGifter>[],
  });

  final String battleId;
  final String channelId;
  final String status;

  final String? title;
  final String? category;
  final int? durationSeconds;
  final String? battleType;
  final String? beatName;
  final bool crowdBoostEnabled;
  final int? coinGoal;
  final String? country;

  final String hostAId;
  final String hostBId;

  final int hostAScore;
  final int hostBScore;

  final int? totalSpentCoins;

  final DateTime? startedAt;
  final DateTime? endsAt;
  final DateTime? endedAt;

  /// Timeline state (turn-based mic control).
  ///
  /// Timeline elapsed is computed as:
  /// - effectiveNow = timelinePausedAt ?? DateTime.now().toUtc()
  /// - anchorAt = timelineAnchorAt ?? startedAt
  /// - elapsed = timelineAnchorElapsedSeconds + (effectiveNow - anchorAt)
  final DateTime? timelineAnchorAt;
  final int timelineAnchorElapsedSeconds;
  final DateTime? timelinePausedAt;
  final int timelinePerfASeconds;
  final int timelinePerfBSeconds;
  final int timelineJudgingSeconds;

  final String? winnerUid;
  final bool isDraw;

  final List<BattleTopGifter> topGifters;

  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';

  factory BattleStatus.fromMap(Map<String, dynamic> row) {
    String s(Object? v) => (v ?? '').toString().trim();
    int i(Object? v) => (v is num) ? v.toInt() : int.tryParse(s(v)) ?? 0;
    int? inull(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      final raw = s(v);
      if (raw.isEmpty) return null;
      return int.tryParse(raw);
    }
    DateTime? dt(Object? v) {
      final raw = s(v);
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    }

    List<BattleTopGifter> parseTopGifters(Object? v) {
      try {
        Object? normalized = v;
        if (normalized is String) {
          final trimmed = normalized.trim();
          if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
            normalized = jsonDecode(trimmed);
          }
        }
        if (normalized is! List) return const <BattleTopGifter>[];
        return normalized
            .whereType<Object?>()
            .map((e) {
              if (e is Map) {
                final m = e.map((k, v) => MapEntry(k.toString(), v));
                return BattleTopGifter.fromMap(Map<String, dynamic>.from(m));
              }
              return null;
            })
            .whereType<BattleTopGifter>()
            .toList(growable: false);
      } catch (_) {
        return const <BattleTopGifter>[];
      }
    }

    final battleId = s(row['battle_id']).isNotEmpty ? s(row['battle_id']) : s(row['battleId']);
    final channelId = s(row['channel_id']).isNotEmpty ? s(row['channel_id']) : s(row['channelId']);

    final status = s(row['status']).isNotEmpty ? s(row['status']) : 'waiting';

    final titleRaw = s(row['title']);
    final categoryRaw = s(row['category']);
    final battleTypeRaw = s(row['battle_type']).isNotEmpty ? s(row['battle_type']) : s(row['battleType']);
    final beatNameRaw = s(row['beat_name']).isNotEmpty ? s(row['beat_name']) : s(row['beatName']);
    final crowdBoostRaw = row['crowd_boost_enabled'] ?? row['crowdBoostEnabled'];
    final countryRaw = s(row['country']);

    final durationSeconds = inull(row['duration_seconds'] ?? row['durationSeconds']);
    final coinGoal = inull(row['coin_goal'] ?? row['coinGoal']);
    final totalSpentCoins = inull(row['total_spent_coins'] ?? row['totalSpentCoins']);
    final hostAId = s(row['host_a_id']).isNotEmpty ? s(row['host_a_id']) : s(row['hostAId']);
    final hostBId = s(row['host_b_id']).isNotEmpty ? s(row['host_b_id']) : s(row['hostBId']);

    final winnerUidRaw = s(row['winner_uid']).isNotEmpty ? s(row['winner_uid']) : s(row['winnerUid']);

    final isDrawRaw = row['is_draw'];
    final isDraw = isDrawRaw == true || s(isDrawRaw).toLowerCase() == 'true';

    final timelineAnchorAt = dt(row['timeline_anchor_at'] ?? row['timelineAnchorAt']);
    final timelinePausedAt = dt(row['timeline_paused_at'] ?? row['timelinePausedAt']);

    final timelineAnchorElapsedSeconds = inull(row['timeline_anchor_elapsed_seconds'] ?? row['timelineAnchorElapsedSeconds']) ?? 0;
    final timelinePerfASeconds = inull(row['timeline_perf_a_seconds'] ?? row['timelinePerfASeconds']) ?? 480;
    final timelinePerfBSeconds = inull(row['timeline_perf_b_seconds'] ?? row['timelinePerfBSeconds']) ?? 480;
    final timelineJudgingSeconds = inull(row['timeline_judging_seconds'] ?? row['timelineJudgingSeconds']) ?? 240;

    final topGifters = parseTopGifters(row['top_gifters'] ?? row['topGifters']);

    return BattleStatus(
      battleId: battleId,
      channelId: channelId,
      status: status,

      title: titleRaw.isNotEmpty ? titleRaw : null,
      category: categoryRaw.isNotEmpty ? categoryRaw : null,
      durationSeconds: durationSeconds,
      battleType: battleTypeRaw.isNotEmpty ? battleTypeRaw : null,
      beatName: beatNameRaw.isNotEmpty ? beatNameRaw : null,
      crowdBoostEnabled: crowdBoostRaw == true || s(crowdBoostRaw).toLowerCase() == 'true',
      coinGoal: coinGoal,
      country: countryRaw.isNotEmpty ? countryRaw : null,
      hostAId: hostAId,
      hostBId: hostBId,
      hostAScore: i(row['host_a_score']),
      hostBScore: i(row['host_b_score']),

      totalSpentCoins: totalSpentCoins,
      startedAt: dt(row['started_at']),
      endsAt: dt(row['ends_at']),
      endedAt: dt(row['ended_at']),

      timelineAnchorAt: timelineAnchorAt,
      timelineAnchorElapsedSeconds: timelineAnchorElapsedSeconds,
      timelinePausedAt: timelinePausedAt,
      timelinePerfASeconds: timelinePerfASeconds,
      timelinePerfBSeconds: timelinePerfBSeconds,
      timelineJudgingSeconds: timelineJudgingSeconds,

      winnerUid: winnerUidRaw.isNotEmpty ? winnerUidRaw : null,
      isDraw: isDraw,

      topGifters: topGifters,
    );
  }
}
