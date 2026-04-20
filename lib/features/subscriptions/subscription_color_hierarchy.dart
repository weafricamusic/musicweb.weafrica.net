import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme/weafrica_colors.dart';
import 'models/subscription_me.dart';
import 'models/subscription_plan.dart';

enum SubscriptionTier { free, premium, platinum, other }

SubscriptionTier subscriptionTierForPlanId(String planId) {
  final id = canonicalPlanId(planId);
  if (isFreeLikePlanId(id)) {
    return SubscriptionTier.free;
  }

  // Listener tiers.
  if (id == 'platinum') return SubscriptionTier.platinum;
  if (id == 'premium') return SubscriptionTier.premium;

  // Creator tiers (contract-aligned names).
  if (id == 'artist_premium' || id == 'dj_premium') {
    return SubscriptionTier.platinum;
  }
  if (id == 'artist_pro' || id == 'dj_pro') {
    return SubscriptionTier.premium;
  }

  return SubscriptionTier.other;
}

Color subscriptionTierAccent(SubscriptionTier tier, ColorScheme scheme) {
  switch (tier) {
    case SubscriptionTier.free:
      return scheme.outline;
    case SubscriptionTier.premium:
      return AppColors.stagePurple;
    case SubscriptionTier.platinum:
      return WeAfricaColors.gold;
    case SubscriptionTier.other:
      return scheme.primary;
  }
}

Color subscriptionBlockedAccent(ColorScheme scheme) => scheme.outline;

/// Yellow: "almost there" / nearing a limit.
Color subscriptionNearLimitAccent(ColorScheme scheme) => WeAfricaColors.goldLight;

/// Purple: premium/upgrade moments.
Color subscriptionUpgradeAccent(ColorScheme scheme) => AppColors.stagePurple;

/// Gold: exclusive/platinum moments.
Color subscriptionExclusiveAccent(ColorScheme scheme) => WeAfricaColors.gold;

Color subscriptionTierAccentForPlanId(String planId, ColorScheme scheme) {
  return subscriptionTierAccent(subscriptionTierForPlanId(planId), scheme);
}

/// How many whole days remain until the end of the current period.
///
/// Returns null if we don't have an end date.
int? subscriptionDaysLeftInPeriod(SubscriptionMe me, {DateTime? now}) {
  final end = me.currentPeriodEnd;
  if (end == null) return null;

  final current = now ?? DateTime.now();
  final diff = end.difference(current);

  // We want user-friendly messaging (“ends in 1 day”) so we ceil partial days.
  // Example: 0.2 days remaining → 1 day.
  final days = (diff.inHours / 24).ceil();
  return days;
}

Color subscriptionTrialAccent({required int daysLeft, required ColorScheme scheme}) {
  // Purple for “premium preview”, orange for warnings, red only for critical.
  if (daysLeft <= 1) return WeAfricaColors.error;
  if (daysLeft <= 3) return WeAfricaColors.warning;
  return AppColors.stagePurple;
}

String subscriptionTrialMessage(int daysLeft) {
  if (daysLeft <= 0) return 'Your trial ends today.';
  if (daysLeft == 1) return 'Your trial ends in 1 day.';
  return 'Your trial ends in $daysLeft days.';
}

Color subscriptionStatusAccent({
  required SubscriptionMe? me,
  required bool signedIn,
  required ColorScheme scheme,
  DateTime? now,
}) {
  if (!signedIn) return scheme.outline;
  if (me == null) return scheme.outline;

  final status = me.status.trim().toLowerCase();
  if (status == 'trialing') {
    final daysLeft = subscriptionDaysLeftInPeriod(me, now: now);
    if (daysLeft != null) {
      return subscriptionTrialAccent(daysLeft: daysLeft, scheme: scheme);
    }
    return AppColors.stagePurple;
  }

  if (me.isActive && !isFreeLikePlanId(me.planId)) {
    return WeAfricaColors.success;
  }

  // Gray for blocked/unavailable by default.
  return scheme.outline;
}
