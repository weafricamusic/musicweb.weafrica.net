import 'package:flutter/foundation.dart';

@immutable
class FanClubTier {
  const FanClubTier({
    required this.id,
    required this.tierKey,
    required this.title,
    required this.priceMwk,
    required this.description,
    required this.perks,
    required this.badgeLabel,
    required this.accentColor,
    required this.isActive,
    required this.memberCount,
  });

  final String id;
  final String tierKey;
  final String title;
  final int priceMwk;
  final String description;
  final List<String> perks;
  final String badgeLabel;
  final String accentColor;
  final bool isActive;
  final int memberCount;

  factory FanClubTier.fromRow(Map<String, dynamic> row) {
    final rawPerks = row['perks'];
    final perks = <String>[];
    if (rawPerks is List) {
      for (final item in rawPerks) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) perks.add(text);
      }
    }

    return FanClubTier(
      id: (row['id'] ?? '').toString(),
      tierKey: (row['tier_key'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      priceMwk: _readInt(row['price_mwk']),
      description: (row['description'] ?? '').toString(),
      perks: perks,
      badgeLabel: (row['badge_label'] ?? '').toString(),
      accentColor: (row['accent_color'] ?? '').toString(),
      isActive: row['is_active'] == true,
      memberCount: _readInt(row['member_count_cache']),
    );
  }

  Map<String, dynamic> toUpsertRow({required String artistUid}) {
    return {
      'artist_uid': artistUid,
      'tier_key': tierKey,
      'title': title,
      'price_mwk': priceMwk,
      'description': description,
      'perks': perks,
      'badge_label': badgeLabel,
      'accent_color': accentColor,
      'is_active': isActive,
    };
  }

  FanClubTier copyWith({
    String? title,
    int? priceMwk,
    String? description,
    List<String>? perks,
    String? badgeLabel,
    String? accentColor,
    bool? isActive,
    int? memberCount,
  }) {
    return FanClubTier(
      id: id,
      tierKey: tierKey,
      title: title ?? this.title,
      priceMwk: priceMwk ?? this.priceMwk,
      description: description ?? this.description,
      perks: perks ?? this.perks,
      badgeLabel: badgeLabel ?? this.badgeLabel,
      accentColor: accentColor ?? this.accentColor,
      isActive: isActive ?? this.isActive,
      memberCount: memberCount ?? this.memberCount,
    );
  }
}

@immutable
class FanClubFan {
  const FanClubFan({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.tierKey,
    required this.joinedAt,
    required this.totalSpentMwk,
    required this.giftsSent,
    required this.comments,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String tierKey;
  final DateTime? joinedAt;
  final double totalSpentMwk;
  final int giftsSent;
  final int comments;

  String get tierLabel => switch (tierKey) {
        'vip' => 'VIP Member',
        'premium' => 'Premium Member',
        _ => 'Free Member',
      };

  FanClubFan copyWith({
    String? tierKey,
    DateTime? joinedAt,
    double? totalSpentMwk,
    int? giftsSent,
    int? comments,
  }) {
    return FanClubFan(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      tierKey: tierKey ?? this.tierKey,
      joinedAt: joinedAt ?? this.joinedAt,
      totalSpentMwk: totalSpentMwk ?? this.totalSpentMwk,
      giftsSent: giftsSent ?? this.giftsSent,
      comments: comments ?? this.comments,
    );
  }
}

@immutable
class FanClubContentItem {
  const FanClubContentItem({
    required this.id,
    required this.title,
    required this.description,
    required this.contentType,
    required this.accessTier,
    required this.mediaUrl,
    required this.playsCount,
    required this.commentsCount,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String description;
  final String contentType;
  final String accessTier;
  final String? mediaUrl;
  final int playsCount;
  final int commentsCount;
  final DateTime? publishedAt;

  factory FanClubContentItem.fromRow(Map<String, dynamic> row) {
    return FanClubContentItem(
      id: (row['id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      contentType: (row['content_type'] ?? 'message').toString(),
      accessTier: (row['access_tier'] ?? 'premium').toString(),
      mediaUrl: (row['media_url'] ?? '').toString().trim().isEmpty ? null : (row['media_url'] ?? '').toString(),
      playsCount: _readInt(row['plays_count']),
      commentsCount: _readInt(row['comments_count']),
      publishedAt: DateTime.tryParse((row['published_at'] ?? '').toString()),
    );
  }
}

@immutable
class FanClubAnnouncementItem {
  const FanClubAnnouncementItem({
    required this.id,
    required this.audience,
    required this.message,
    required this.linkUrl,
    required this.imageUrl,
    required this.status,
    required this.sentAt,
  });

  final String id;
  final String audience;
  final String message;
  final String? linkUrl;
  final String? imageUrl;
  final String status;
  final DateTime? sentAt;

  factory FanClubAnnouncementItem.fromRow(Map<String, dynamic> row) {
    return FanClubAnnouncementItem(
      id: (row['id'] ?? '').toString(),
      audience: (row['audience'] ?? '').toString(),
      message: (row['message'] ?? '').toString(),
      linkUrl: (row['link_url'] ?? '').toString().trim().isEmpty ? null : (row['link_url'] ?? '').toString(),
      imageUrl: (row['image_url'] ?? '').toString().trim().isEmpty ? null : (row['image_url'] ?? '').toString(),
      status: (row['status'] ?? 'sent').toString(),
      sentAt: DateTime.tryParse((row['sent_at'] ?? '').toString()),
    );
  }
}

@immutable
class FanClubRewardItem {
  const FanClubRewardItem({
    required this.id,
    required this.rewardType,
    required this.audience,
    required this.note,
    required this.recipientsCount,
    required this.createdAt,
  });

  final String id;
  final String rewardType;
  final String audience;
  final String note;
  final int recipientsCount;
  final DateTime? createdAt;

  factory FanClubRewardItem.fromRow(Map<String, dynamic> row) {
    return FanClubRewardItem(
      id: (row['id'] ?? '').toString(),
      rewardType: (row['reward_type'] ?? '').toString(),
      audience: (row['audience'] ?? '').toString(),
      note: (row['note'] ?? '').toString(),
      recipientsCount: _readInt(row['recipients_count']),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
    );
  }
}

@immutable
class FanClubAnalytics {
  const FanClubAnalytics({
    required this.growthDelta,
    required this.topGifters,
    required this.topSpenders,
    required this.commentsCount,
    required this.likesCount,
    required this.sharesCount,
  });

  final int growthDelta;
  final List<FanClubFan> topGifters;
  final List<FanClubFan> topSpenders;
  final int commentsCount;
  final int likesCount;
  final int sharesCount;
}

@immutable
class FanClubHubData {
  const FanClubHubData({
    required this.artistGenre,
    required this.artistCountry,
    required this.fansCount,
    required this.followersCount,
    required this.clubEarningsMwk,
    required this.vipMembersCount,
    required this.membersGrowthThisMonth,
    required this.followersGrowthThisMonth,
    required this.vipGrowthThisMonth,
    required this.averageRating,
    required this.tiers,
    required this.fans,
    required this.contentItems,
    required this.announcements,
    required this.rewards,
    required this.analytics,
  });

  final String artistGenre;
  final String artistCountry;
  final int fansCount;
  final int followersCount;
  final double clubEarningsMwk;
  final int vipMembersCount;
  final int membersGrowthThisMonth;
  final int followersGrowthThisMonth;
  final int vipGrowthThisMonth;
  final double averageRating;
  final List<FanClubTier> tiers;
  final List<FanClubFan> fans;
  final List<FanClubContentItem> contentItems;
  final List<FanClubAnnouncementItem> announcements;
  final List<FanClubRewardItem> rewards;
  final FanClubAnalytics analytics;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}