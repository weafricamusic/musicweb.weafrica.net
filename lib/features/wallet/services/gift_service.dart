import 'package:flutter/foundation.dart';

import 'coin_service.dart';

/// Gift item definition
class GiftItem {
  const GiftItem({
    required this.id,
    required this.name,
    required this.coinCost,
    required this.emoji,
    this.animationUrl,
    this.soundUrl,
  });

  final String id;
  final String name;
  final int coinCost;
  final String emoji;
  final String? animationUrl;
  final String? soundUrl;
}

/// WeAfrica Music Gift Service
/// 
/// Allows fans to send virtual gifts to artists during battles/live
class GiftService {
  GiftService._();
  static final GiftService instance = GiftService._();

  /// Available gifts catalog
  final List<GiftItem> _gifts = const [
    GiftItem(id: 'clap', name: 'Clap', coinCost: 10, emoji: '👏'),
    GiftItem(id: 'fire', name: 'Fire', coinCost: 25, emoji: '🔥'),
    GiftItem(id: 'heart', name: 'Love', coinCost: 50, emoji: '❤️'),
    GiftItem(id: 'mic', name: 'Mic Drop', coinCost: 100, emoji: '🎤'),
    GiftItem(id: 'crown', name: 'Crown', coinCost: 250, emoji: '👑'),
    GiftItem(id: 'trophy', name: 'Trophy', coinCost: 500, emoji: '🏆'),
    GiftItem(id: 'diamond', name: 'Diamond', coinCost: 1000, emoji: '💎'),
  ];

  /// Get all available gifts
  List<GiftItem> get availableGifts => List.unmodifiable(_gifts);

  /// Get gift by ID
  GiftItem? getGift(String id) {
    try {
      return _gifts.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Send gift to artist
  /// Returns true if successful
  Future<bool> sendGift({
    required String fromUserId,
    required String toArtistId,
    required String giftId,
    String? battleId,
    String? liveStreamId,
  }) async {
    final gift = getGift(giftId);
    if (gift == null) {
      debugPrint('⚠️ Gift not found: $giftId');
      return false;
    }

    final success = await CoinService.instance.transferCoins(
      fromUserId: fromUserId,
      toUserId: toArtistId,
      amount: gift.coinCost,
      description: 'Sent ${gift.name} ${gift.emoji}',
      relatedEntityId: battleId ?? liveStreamId,
    );

    if (success) {
      debugPrint('✅ Gift sent: ${gift.name} from $fromUserId to $toArtistId');
      
      // TODO: Trigger gift animation
      // TODO: Show gift in chat/overlay
      // TODO: Notify artist
    }

    return success;
  }

  /// Send quick gift (for one-tap gifting)
  Future<bool> sendQuickGift({
    required String fromUserId,
    required String toArtistId,
    required String giftId,
  }) async {
    return sendGift(
      fromUserId: fromUserId,
      toArtistId: toArtistId,
      giftId: giftId,
    );
  }

  /// Get total gifts sent in a battle
  Future<Map<String, int>> getBattleGifts(String battleId) async {
    // TODO: Query database for gift totals
    return {};
  }

  /// Get top gifters for an artist
  Future<List<Map<String, dynamic>>> getTopGifters(
    String artistId, {
    int limit = 10,
  }) async {
    // TODO: Query database for top supporters
    return [];
  }
}