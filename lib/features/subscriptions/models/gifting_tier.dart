enum GiftAccessTier { limited, standard, vip }

GiftAccessTier? giftAccessTierFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'free':
    case 'limited':
    case 'basic':
      return GiftAccessTier.limited;
    case 'premium':
    case 'standard':
      return GiftAccessTier.standard;
    case 'vip':
    case 'platinum':
      return GiftAccessTier.vip;
    default:
      return null;
  }
}

GiftAccessTier inferGiftAccessTier({
  String? rawTier,
  String? giftId,
  int? coinCost,
}) {
  final explicit = giftAccessTierFromString(rawTier);
  if (explicit != null) return explicit;

  final normalizedGiftId = (giftId ?? '').trim().toLowerCase();
  final effectiveCoinCost = coinCost ?? 0;

  if (normalizedGiftId.contains('rocket') || effectiveCoinCost >= 250) {
    return GiftAccessTier.vip;
  }

  if (normalizedGiftId.contains('diamond') ||
      normalizedGiftId.contains('crown') ||
      normalizedGiftId.contains('mic') ||
      effectiveCoinCost >= 50) {
    return GiftAccessTier.standard;
  }

  return GiftAccessTier.limited;
}

bool giftAccessTierAllows(
  GiftAccessTier currentTier,
  GiftAccessTier requiredTier,
) {
  return _giftAccessTierRank(currentTier) >= _giftAccessTierRank(requiredTier);
}

String giftAccessTierLabel(GiftAccessTier tier) {
  switch (tier) {
    case GiftAccessTier.limited:
      return 'Free';
    case GiftAccessTier.standard:
      return 'Premium';
    case GiftAccessTier.vip:
      return 'Platinum';
  }
}

int _giftAccessTierRank(GiftAccessTier tier) {
  switch (tier) {
    case GiftAccessTier.limited:
      return 0;
    case GiftAccessTier.standard:
      return 1;
    case GiftAccessTier.vip:
      return 2;
  }
}
