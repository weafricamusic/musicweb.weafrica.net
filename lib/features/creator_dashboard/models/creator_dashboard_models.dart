class DjDashboardSummary {
  final int events;
  final double avgLikesPerMin;
  final double avgCoinsPerMin;
  final double avgViewersChange;
  final double? winRate;
  final String? bestStyle;
  final String? topDecision;

  const DjDashboardSummary({
    required this.events,
    required this.avgLikesPerMin,
    required this.avgCoinsPerMin,
    required this.avgViewersChange,
    required this.winRate,
    required this.bestStyle,
    required this.topDecision,
  });

  factory DjDashboardSummary.fromJson(Map<String, dynamic> json) {
    return DjDashboardSummary(
      events: (json['events'] as num?)?.toInt() ?? 0,
      avgLikesPerMin: (json['avg_likes_per_min'] as num?)?.toDouble() ?? 0,
      avgCoinsPerMin: (json['avg_coins_per_min'] as num?)?.toDouble() ?? 0,
      avgViewersChange: (json['avg_viewers_change'] as num?)?.toDouble() ?? 0,
      winRate: (json['win_rate'] as num?)?.toDouble(),
      bestStyle: json['best_style']?.toString(),
      topDecision: json['top_decision']?.toString(),
    );
  }
}

class DjDashboardRecentItem {
  final DateTime createdAt;
  final String? decision;
  final String? style;
  final double likesPerMin;
  final double coinsPerMin;
  final double viewersChange;
  final String? outcome;

  const DjDashboardRecentItem({
    required this.createdAt,
    required this.decision,
    required this.style,
    required this.likesPerMin,
    required this.coinsPerMin,
    required this.viewersChange,
    required this.outcome,
  });

  factory DjDashboardRecentItem.fromJson(Map<String, dynamic> json) {
    return DjDashboardRecentItem(
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      decision: json['decision']?.toString(),
      style: json['style']?.toString(),
      likesPerMin: (json['likes_per_min'] as num?)?.toDouble() ?? 0,
      coinsPerMin: (json['coins_per_min'] as num?)?.toDouble() ?? 0,
      viewersChange: (json['viewers_change'] as num?)?.toDouble() ?? 0,
      outcome: json['outcome']?.toString(),
    );
  }
}

class DjDashboardResponse {
  final DjDashboardSummary? summary;
  final List<String> advice;
  final List<DjDashboardRecentItem> recent;
  final Map<String, dynamic> premium;

  const DjDashboardResponse({
    required this.summary,
    required this.advice,
    required this.recent,
    required this.premium,
  });

  factory DjDashboardResponse.empty() => const DjDashboardResponse(
        summary: null,
        advice: <String>[],
        recent: <DjDashboardRecentItem>[],
        premium: <String, dynamic>{},
      );

  factory DjDashboardResponse.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'];
    final adviceJson = json['advice'];
    final recentJson = json['recent'];
    final premiumJson = json['premium'];

    return DjDashboardResponse(
      summary: summaryJson is Map<String, dynamic>
          ? DjDashboardSummary.fromJson(summaryJson)
          : null,
      advice: adviceJson is List
          ? adviceJson.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      recent: recentJson is List
          ? recentJson
              .whereType<Map>()
              .map(
                (e) => DjDashboardRecentItem.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(growable: false)
          : const <DjDashboardRecentItem>[],
      premium: premiumJson is Map<String, dynamic>
          ? premiumJson
          : const <String, dynamic>{},
    );
  }
}

class ArtistDashboardSummary {
  final int earnedCoins;
  final int withdrawableCoins;
  final int giftsCount;
  final int giftsCoins;
  final String? topLiveId;
  final int? topLiveCoins;
  final String? topGiftId;
  final int? topGiftCount;

  const ArtistDashboardSummary({
    required this.earnedCoins,
    required this.withdrawableCoins,
    required this.giftsCount,
    required this.giftsCoins,
    required this.topLiveId,
    required this.topLiveCoins,
    required this.topGiftId,
    required this.topGiftCount,
  });

  factory ArtistDashboardSummary.fromJson(Map<String, dynamic> json) {
    return ArtistDashboardSummary(
      earnedCoins: (json['earned_coins'] as num?)?.toInt() ?? 0,
      withdrawableCoins: (json['withdrawable_coins'] as num?)?.toInt() ?? 0,
      giftsCount: (json['gifts_count'] as num?)?.toInt() ?? 0,
      giftsCoins: (json['gifts_coins'] as num?)?.toInt() ?? 0,
      topLiveId: json['top_live_id']?.toString(),
      topLiveCoins: (json['top_live_coins'] as num?)?.toInt(),
      topGiftId: json['top_gift_id']?.toString(),
      topGiftCount: (json['top_gift_count'] as num?)?.toInt(),
    );
  }
}

class ArtistDashboardGiftItem {
  final DateTime createdAt;
  final String? giftId;
  final String? liveId;
  final String? channelId;
  final int coinCost;

  const ArtistDashboardGiftItem({
    required this.createdAt,
    required this.giftId,
    required this.liveId,
    required this.channelId,
    required this.coinCost,
  });

  factory ArtistDashboardGiftItem.fromJson(Map<String, dynamic> json) {
    return ArtistDashboardGiftItem(
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      giftId: json['gift_id']?.toString(),
      liveId: json['live_id']?.toString(),
      channelId: json['channel_id']?.toString(),
      coinCost: (json['coin_cost'] as num?)?.toInt() ?? 0,
    );
  }
}

class ArtistDashboardResponse {
  final ArtistDashboardSummary? summary;
  final List<String> advice;
  final List<ArtistDashboardGiftItem> recentGifts;
  final Map<String, dynamic> premium;

  const ArtistDashboardResponse({
    required this.summary,
    required this.advice,
    required this.recentGifts,
    required this.premium,
  });

  factory ArtistDashboardResponse.empty() => const ArtistDashboardResponse(
        summary: null,
        advice: <String>[],
        recentGifts: <ArtistDashboardGiftItem>[],
        premium: <String, dynamic>{},
      );

  factory ArtistDashboardResponse.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'];
    final adviceJson = json['advice'];
    final recentJson = json['recent_gifts'] ?? json['recentGifts'];
    final premiumJson = json['premium'];

    return ArtistDashboardResponse(
      summary: summaryJson is Map<String, dynamic>
          ? ArtistDashboardSummary.fromJson(summaryJson)
          : null,
      advice: adviceJson is List
          ? adviceJson.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      recentGifts: recentJson is List
          ? recentJson
              .whereType<Map>()
              .map(
                (e) => ArtistDashboardGiftItem.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(growable: false)
          : const <ArtistDashboardGiftItem>[],
      premium: premiumJson is Map<String, dynamic>
          ? premiumJson
          : const <String, dynamic>{},
    );
  }
}
