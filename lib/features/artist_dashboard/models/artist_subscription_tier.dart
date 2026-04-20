import 'package:flutter/foundation.dart';

import '../../subscriptions/models/subscription_plan.dart';

/// WeAfrica Artist subscription tiers.
///
/// Note: This is creator-facing (artist dashboard) tiering, not listener tiers.
/// Internal enum names stay stable, but the creator catalog maps them to
/// Artist Free / Artist Pro / Artist Premium for UI copy.
enum ArtistSubscriptionTier {
  free,
  premium,
  platinum,
}

ArtistSubscriptionTier artistTierForPlanId(String planId) {
  final id = canonicalPlanId(planId);
  if (id.isEmpty || isFreeLikePlanId(id)) return ArtistSubscriptionTier.free;

  if (id == 'artist_premium' || id.contains('platinum')) {
    return ArtistSubscriptionTier.platinum;
  }

  if (id == 'artist_pro' || id.contains('premium') || id.contains('pro')) {
    return ArtistSubscriptionTier.premium;
  }

  // Unknown paid creator plan: default to Premium so feature access stays
  // conservative unless the plan is explicitly platinum.
  return ArtistSubscriptionTier.premium;
}

@immutable
class ArtistSubscriptionPlanSpec {
  const ArtistSubscriptionPlanSpec({
    required this.tier,
    required this.monthlyPriceMwk,
    required this.songUploadsPerMonth,
    required this.videoUploadsPerMonth,
    required this.analyticsLabel,
    required this.monetizationLabel,
    required this.earningsSplitPercent,
    required this.battleLabel,
    required this.ticketLabel,
    required this.withdrawalLabel,
    required this.withdrawalFrequencyLabel,
    required this.supporterPerksLabel,
    required this.monthlyBonusCoins,
    required this.bulkUploadEnabled,
    required this.vipBadgeEnabled,
  });

  final ArtistSubscriptionTier tier;

  final int monthlyPriceMwk;

  /// `null` == unlimited.
  final int? songUploadsPerMonth;

  /// `null` == unlimited.
  final int? videoUploadsPerMonth;

  /// Basic / Standard / Advanced.
  final String analyticsLabel;

  /// High-level monetization summary used in dashboard copy.
  final String monetizationLabel;

  /// Creator earnings split percentage shown in plan copy.
  /// Note: this is display-only unless the backend enforces it.
  final int earningsSplitPercent;

  /// No battles / Standard battles / Priority battles.
  final String battleLabel;

  /// Ticket-selling capability summary.
  final String ticketLabel;

  /// None / Limited / Unlimited.
  final String withdrawalLabel;

  /// Weekly / Daily (or None).
  final String withdrawalFrequencyLabel;

  /// Summary for supporter/fan support tools.
  final String supporterPerksLabel;

  final int monthlyBonusCoins;

  final bool bulkUploadEnabled;

  final bool vipBadgeEnabled;

  String get tierLabel => switch (tier) {
      ArtistSubscriptionTier.free => 'FREE',
      ArtistSubscriptionTier.premium => 'PRO',
      ArtistSubscriptionTier.platinum => 'PREMIUM',
      };

  String get tierDisplayName => switch (tier) {
      ArtistSubscriptionTier.free => 'Artist Free',
      ArtistSubscriptionTier.premium => 'Artist Pro',
      ArtistSubscriptionTier.platinum => 'Artist Premium',
      };

  bool get isPaid => tier != ArtistSubscriptionTier.free;

  bool get canUseFanClub => tier == ArtistSubscriptionTier.platinum;

  bool get canJoinBattles => tier != ArtistSubscriptionTier.free;

  bool get canCreateBattles => tier != ArtistSubscriptionTier.free;

  bool get hasVipBadge => vipBadgeEnabled;
}

class ArtistSubscriptionCatalog {
  static const free = ArtistSubscriptionPlanSpec(
    tier: ArtistSubscriptionTier.free,
    monthlyPriceMwk: 0,
    songUploadsPerMonth: 5,
    videoUploadsPerMonth: 5,
    analyticsLabel: 'Basic',
    monetizationLabel: 'No creator earnings',
    earningsSplitPercent: 0,
    battleLabel: 'Watch only',
    ticketLabel: 'No ticket selling',
    withdrawalLabel: 'None',
    withdrawalFrequencyLabel: 'None',
    supporterPerksLabel: 'Supporter tiers unlock on Artist Premium.',
    monthlyBonusCoins: 0,
    bulkUploadEnabled: false,
    vipBadgeEnabled: false,
  );

  static const premium = ArtistSubscriptionPlanSpec(
    tier: ArtistSubscriptionTier.premium,
    monthlyPriceMwk: 6000,
    songUploadsPerMonth: null,
    videoUploadsPerMonth: 30,
    analyticsLabel: 'Standard',
    monetizationLabel: 'Gifts, coins, and live earnings',
    earningsSplitPercent: 70,
    battleLabel: 'Standard battles',
    ticketLabel: 'Standard and VIP tickets',
    withdrawalLabel: 'Limited',
    withdrawalFrequencyLabel: 'Weekly',
    supporterPerksLabel: 'Supporter tiers stay locked until Artist Premium.',
    monthlyBonusCoins: 0,
    bulkUploadEnabled: false,
    vipBadgeEnabled: false,
  );

  static const platinum = ArtistSubscriptionPlanSpec(
    tier: ArtistSubscriptionTier.platinum,
    monthlyPriceMwk: 12500,
    songUploadsPerMonth: null,
    videoUploadsPerMonth: null,
    analyticsLabel: 'Advanced',
    monetizationLabel: 'Full creator earnings and fan support',
    earningsSplitPercent: 85,
    battleLabel: 'Priority battles',
    ticketLabel: 'Standard, VIP, and priority tickets',
    withdrawalLabel: 'Unlimited',
    withdrawalFrequencyLabel: 'Daily',
    supporterPerksLabel: 'Fan support and supporter perks are unlocked.',
    monthlyBonusCoins: 200,
    bulkUploadEnabled: true,
    vipBadgeEnabled: true,
  );

  static const List<ArtistSubscriptionPlanSpec> all = <ArtistSubscriptionPlanSpec>[free, premium, platinum];

  static ArtistSubscriptionPlanSpec specForTier(ArtistSubscriptionTier tier) {
    return switch (tier) {
      ArtistSubscriptionTier.free => free,
      ArtistSubscriptionTier.premium => premium,
      ArtistSubscriptionTier.platinum => platinum,
    };
  }
}
