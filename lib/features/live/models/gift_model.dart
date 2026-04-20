import 'package:flutter/material.dart';

import '../../subscriptions/models/gifting_tier.dart';

enum GiftType {
  fire,
  love,
  mic,
  diamond,
  crown,
  rocket,
  rose,
  gift,
  balloon,
  star,
  fireworks,
  rainbow,
}

class GiftModel {
  const GiftModel({
    required this.id,
    required this.type,
    required this.senderName,
    required this.receiverId,
    required this.coinValue,
    required this.scoreValue,
    this.accessTier = GiftAccessTier.limited,
  });

  final String id;
  final GiftType type;
  final String senderName;
  final String receiverId;
  final int coinValue;
  final int scoreValue;
  final GiftAccessTier accessTier;

  String get displayName {
    switch (type) {
      case GiftType.fire:
        return 'Fire';
      case GiftType.love:
        return 'Heart';
      case GiftType.mic:
        return 'Mic';
      case GiftType.diamond:
        return 'Diamond';
      case GiftType.crown:
        return 'Crown';
      case GiftType.rocket:
        return 'Rocket';
      case GiftType.rose:
        return 'Rose';
      case GiftType.gift:
        return 'Gift';
      case GiftType.balloon:
        return 'Balloon';
      case GiftType.star:
        return 'Star';
      case GiftType.fireworks:
        return 'Fireworks';
      case GiftType.rainbow:
        return 'Rainbow';
    }
  }

  IconData get icon {
    switch (type) {
      case GiftType.fire:
        return Icons.whatshot;
      case GiftType.love:
        return Icons.favorite;
      case GiftType.mic:
        return Icons.mic;
      case GiftType.diamond:
        return Icons.diamond_outlined;
      case GiftType.crown:
        return Icons.emoji_events;
      case GiftType.rocket:
        return Icons.rocket_launch;
      case GiftType.rose:
        return Icons.local_florist;
      case GiftType.gift:
        return Icons.card_giftcard;
      case GiftType.balloon:
        return Icons.celebration_outlined;
      case GiftType.star:
        return Icons.star;
      case GiftType.fireworks:
        return Icons.celebration;
      case GiftType.rainbow:
        return Icons.auto_awesome;
    }
  }

  Color get color {
    switch (type) {
      case GiftType.fire:
        return Colors.orange;
      case GiftType.love:
        return Colors.pink;
      case GiftType.mic:
        return Colors.purple;
      case GiftType.diamond:
        return Colors.cyan;
      case GiftType.crown:
        return const Color(0xFFD4AF37);
      case GiftType.rocket:
        return Colors.red;
      case GiftType.rose:
        return const Color(0xFFE84A5F);
      case GiftType.gift:
        return const Color(0xFF2ECC71);
      case GiftType.balloon:
        return const Color(0xFF4AA3FF);
      case GiftType.star:
        return const Color(0xFFFFD166);
      case GiftType.fireworks:
        return const Color(0xFFFF7B54);
      case GiftType.rainbow:
        return const Color(0xFF8E6CFF);
    }
  }
}
