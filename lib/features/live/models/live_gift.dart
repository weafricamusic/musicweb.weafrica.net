import 'package:flutter/foundation.dart';

import '../../subscriptions/models/gifting_tier.dart';

@immutable
class LiveGift {
  const LiveGift({
    required this.id,
    required this.name,
    required this.coinValue,
    this.accessTier = GiftAccessTier.limited,
  });

  final String id;
  final String name;
  final int coinValue;
  final GiftAccessTier accessTier;
}
