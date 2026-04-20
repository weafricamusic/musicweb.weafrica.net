import 'package:flutter/material.dart';

import '../../auth/user_role.dart';
import '../models/gifting_tier.dart';
import '../models/subscription_capabilities.dart';
import '../models/subscription_plan.dart';
import '../subscription_color_hierarchy.dart';

enum UpgradeRequiredTier { premium, platinum }

String _tierLabel(UpgradeRequiredTier tier) {
  switch (tier) {
    case UpgradeRequiredTier.premium:
      return 'Premium';
    case UpgradeRequiredTier.platinum:
      return 'Platinum';
  }
}

String _planIdForTier({required UpgradeRequiredTier tier, required UserRole role}) {
  // Listener plans.
  if (role == UserRole.consumer) {
    return tier == UpgradeRequiredTier.platinum ? 'platinum' : 'premium';
  }

  // Creator plans (contract-aligned IDs).
  if (role == UserRole.artist) {
    return tier == UpgradeRequiredTier.platinum ? 'artist_premium' : 'artist_pro';
  }
  if (role == UserRole.dj) {
    return tier == UpgradeRequiredTier.platinum ? 'dj_premium' : 'dj_pro';
  }

  // Fallback.
  return tier == UpgradeRequiredTier.platinum ? 'platinum' : 'premium';
}

SubscriptionTier _subscriptionTierForRequiredTier(UpgradeRequiredTier tier) {
  return tier == UpgradeRequiredTier.platinum
      ? SubscriptionTier.platinum
      : SubscriptionTier.premium;
}

class UpgradePrompt {
  const UpgradePrompt({
    required this.role,
    required this.requiredTier,
    required this.title,
    required this.message,
    required this.ctaLabel,
    required this.icon,
    required this.benefit,
    this.nearLimitLabel,
  });

  final UserRole role;
  final UpgradeRequiredTier requiredTier;
  final String title;
  final String message;
  final String ctaLabel;
  final IconData icon;
  final List<String> benefit;

  /// Optional: used to render a yellow “almost there” hint.
  ///
  /// Examples: “2 uploads left this month”.
  final String? nearLimitLabel;

  String get requiredTierLabel => _tierLabel(requiredTier);

  SubscriptionTier get subscriptionTier =>
      _subscriptionTierForRequiredTier(requiredTier);

  String recommendedPlanId() =>
      canonicalPlanId(_planIdForTier(tier: requiredTier, role: role));

  String recommendedPlanDisplayName() => displayNameForPlanId(recommendedPlanId());
}

class UpgradePromptFactory {
  /// Locked mapping table (Ticket 2.21 requirement).
  ///
  /// Consumer
  /// - Downloads: Premium
  /// - Skips per hour: Premium
  /// - Full catalog access: Premium
  /// - Exclusive content: Platinum
  /// - Priority live access: Platinum
  /// - Standard gifts: Premium
  /// - VIP gifts: Platinum
  /// - Song requests: Platinum
  /// - Highlighted comments: Platinum
  static UpgradePrompt forConsumerCapability(
    ConsumerCapability capability, {
    String? nearLimitLabel,
  }) {
    UpgradePrompt withNearLimit(UpgradePrompt base) {
      final label = nearLimitLabel;
      if (label == null || label.trim().isEmpty) return base;
      return UpgradePrompt(
        role: base.role,
        requiredTier: base.requiredTier,
        title: base.title,
        message: base.message,
        ctaLabel: base.ctaLabel,
        icon: base.icon,
        benefit: base.benefit,
        nearLimitLabel: label,
      );
    }

    switch (capability) {
      case ConsumerCapability.downloads:
        return withNearLimit(
          const UpgradePrompt(
          role: UserRole.consumer,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock downloads',
          message: 'Upgrade to Premium to save tracks for offline listening.',
          ctaLabel: 'Start downloading',
          icon: Icons.download_for_offline,
          benefit: [
            'Save music for offline listening',
            'Enjoy uninterrupted playback',
            'Upgrade anytime — cancel anytime',
          ],
          ),
        );
      case ConsumerCapability.skips:
        return withNearLimit(
          const UpgradePrompt(
            role: UserRole.consumer,
            requiredTier: UpgradeRequiredTier.premium,
            title: 'Unlock unlimited skips',
            message: 'Upgrade to Premium for unlimited skips and uninterrupted listening.',
            ctaLabel: 'Get unlimited skips',
            icon: Icons.skip_next,
            benefit: [
              'Unlimited skips',
              'Less friction while discovering music',
              'Upgrade anytime — cancel anytime',
            ],
          ),
        );
      case ConsumerCapability.contentAccess:
        return withNearLimit(
          const UpgradePrompt(
            role: UserRole.consumer,
            requiredTier: UpgradeRequiredTier.premium,
            title: 'Unlock the full catalog',
            message: 'Upgrade to Premium to access the full music and video catalog.',
            ctaLabel: 'Unlock full access',
            icon: Icons.library_music,
            benefit: [
              'Access more tracks and videos',
              'Discover music without catalog limit',
              'Upgrade anytime — cancel anytime',
            ],
          ),
        );
      case ConsumerCapability.exclusiveContent:
        return withNearLimit(
          const UpgradePrompt(
            role: UserRole.consumer,
            requiredTier: UpgradeRequiredTier.platinum,
            title: 'Unlock exclusive content',
            message: 'Exclusive drops are reserved for Platinum fans.',
            ctaLabel: 'Unlock exclusives',
            icon: Icons.lock_open,
            benefit: [
              'Unlock exclusive tracks and videos',
              'Get more premium fan perks',
              'Stand out in live moments',
            ],
          ),
        );
      case ConsumerCapability.priorityLiveAccess:
        return withNearLimit(
          const UpgradePrompt(
            role: UserRole.consumer,
            requiredTier: UpgradeRequiredTier.platinum,
            title: 'Unlock priority live access',
            message: 'Priority access to live events is reserved for Platinum fans.',
            ctaLabel: 'Unlock priority access',
            icon: Icons.live_tv,
            benefit: [
              'Get priority access to live moments',
              'More premium fan features in live',
              'VIP recognition and perks',
            ],
          ),
        );
      case ConsumerCapability.standardGifts:
        return withNearLimit(
          const UpgradePrompt(
          role: UserRole.consumer,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock Premium gifts',
          message: 'Premium unlocks the standard gift catalog for stronger fan support.',
          ctaLabel: 'Unlock standard gifts',
          icon: Icons.card_giftcard,
          benefit: [
            'Unlock the standard gift catalog',
            'Support creators with more impact',
            'Stand out in live moments',
          ],
          ),
        );
      case ConsumerCapability.vipGifts:
        return withNearLimit(
          const UpgradePrompt(
          role: UserRole.consumer,
          requiredTier: UpgradeRequiredTier.platinum,
          title: 'Unlock VIP gifts',
          message: 'VIP gifts are reserved for Platinum fans.',
          ctaLabel: 'Unlock VIP gifts',
          icon: Icons.workspace_premium,
          benefit: [
            'Unlock VIP gifts',
            'Highest-impact fan support',
            'VIP recognition in live events',
          ],
          ),
        );
      case ConsumerCapability.songRequests:
        return withNearLimit(
          const UpgradePrompt(
          role: UserRole.consumer,
          requiredTier: UpgradeRequiredTier.platinum,
          title: 'Unlock song requests',
          message: 'Song requests are part of the Platinum fan experience.',
          ctaLabel: 'Start requesting songs',
          icon: Icons.queue_music,
          benefit: [
            'Request songs in live sessions',
            'Move from watching live to influencing it',
            'Get priority fan perks',
          ],
          ),
        );
      case ConsumerCapability.highlightedComments:
        return withNearLimit(
          const UpgradePrompt(
          role: UserRole.consumer,
          requiredTier: UpgradeRequiredTier.platinum,
          title: 'Unlock highlighted comments',
          message: 'Highlighted live comments are reserved for Platinum fans.',
          ctaLabel: 'Highlight my comments',
          icon: Icons.highlight,
          benefit: [
            'Get your comments highlighted',
            'Stand out in live chat',
            'VIP fan status perks',
          ],
          ),
        );
    }
  }

  static UpgradePrompt forGiftTier(GiftAccessTier requiredTier) {
    switch (requiredTier) {
      case GiftAccessTier.limited:
        // Should not be gated.
        return const UpgradePrompt(
          role: UserRole.consumer,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock gifts',
          message: 'Upgrade to unlock the full gift experience.',
          ctaLabel: 'Unlock gifts',
          icon: Icons.card_giftcard,
          benefit: ['Unlock more gifts'],
        );
      case GiftAccessTier.standard:
        return forConsumerCapability(ConsumerCapability.standardGifts);
      case GiftAccessTier.vip:
        return forConsumerCapability(ConsumerCapability.vipGifts);
    }
  }

  /// Locked mapping table (Ticket 2.21 requirement).
  ///
  /// Creators (Artist/DJ)
  /// - Uploads: Free limited; upgrades expand capacity
  /// - Go live: Premium
  /// - Battles: Premium (priority hosting can be positioned as Platinum later)
  /// - Earnings/Monetization: Premium
  /// - Withdraw: Premium
  static UpgradePrompt forCreatorCapability({
    required UserRole role,
    required CreatorCapability capability,
    String? nearLimitLabel,
  }) {
    final isArtist = role == UserRole.artist;
    final roleLabel = isArtist ? 'Artist' : 'DJ';

    switch (capability) {
      case CreatorCapability.uploadTrack:
        return UpgradePrompt(
          role: role,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock more uploads',
          message: '$roleLabel Free has limited uploads. Upgrade to publish more and grow faster.',
          ctaLabel: 'Unlock more uploads',
          icon: Icons.cloud_upload,
          benefit: const [
            'Publish more releases each month',
            'Unlock creator growth tools',
            'Start earning sooner',
          ],
          nearLimitLabel: nearLimitLabel,
        );
      case CreatorCapability.uploadVideo:
        return UpgradePrompt(
          role: role,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock video publishing',
          message: 'Upgrade to publish more videos and reach more fans.',
          ctaLabel: 'Unlock video uploads',
          icon: Icons.video_call,
          benefit: const [
            'Publish videos to expand your reach',
            'Unlock more creator tools',
            'Build a stronger fan base',
          ],
          nearLimitLabel: nearLimitLabel,
        );
      case CreatorCapability.goLive:
        return UpgradePrompt(
          role: role,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock live streaming',
          message: 'Upgrade to go live and connect with fans in real time.',
          ctaLabel: 'Start going live',
          icon: Icons.wifi_tethering,
          benefit: const [
            'Host live sessions',
            'Engage fans in real time',
            'Unlock creator earnings',
          ],
        );
      case CreatorCapability.battle:
        return UpgradePrompt(
          role: role,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock battles',
          message: 'Upgrade to join battles and grow your visibility.',
          ctaLabel: 'Unlock battles',
          icon: Icons.sports_mma,
          benefit: const [
            'Join standard battles',
            'Boost your reach and discovery',
            'Unlock monetization paths',
          ],
        );
      case CreatorCapability.monetization:
        return UpgradePrompt(
          role: role,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock earnings',
          message: 'Upgrade to unlock monetization and revenue insights.',
          ctaLabel: 'Start earning',
          icon: Icons.monetization_on,
          benefit: const [
            'Unlock monetization',
            'Access revenue insights',
            'Earn from streams and live moments',
          ],
        );
      case CreatorCapability.withdraw:
        return UpgradePrompt(
          role: role,
          requiredTier: UpgradeRequiredTier.premium,
          title: 'Unlock withdrawals',
          message: 'Upgrade to access withdrawals and start cashing out your earnings.',
          ctaLabel: 'Unlock withdrawals',
          icon: Icons.account_balance_wallet,
          benefit: const [
            'Withdraw your earnings',
            'Grow your creator business',
            'Unlock higher earning power',
          ],
        );
    }
  }
}
