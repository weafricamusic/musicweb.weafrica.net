import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/gifting_tier.dart';
export '../models/subscription_capabilities.dart' show ConsumerCapability;
import '../models/subscription_capabilities.dart';
import '../subscriptions_controller.dart';
import '../widgets/contextual_upgrade_modal.dart';
import '../widgets/upgrade_prompt_factory.dart';

class ConsumerGateDecision {
  const ConsumerGateDecision({
    required this.allowed,
    required this.title,
    required this.message,
    this.offerUpgrade = true,
  });

  final bool allowed;
  final String title;
  final String message;
  final bool offerUpgrade;

  const ConsumerGateDecision.allowed()
    : allowed = true,
      title = '',
      message = '',
      offerUpgrade = false;
}

class ConsumerEntitlementGate {
  ConsumerEntitlementGate({SubscriptionsController? subscriptions})
    : _subscriptions = subscriptions ?? SubscriptionsController.instance;

  static final ConsumerEntitlementGate instance = ConsumerEntitlementGate();

  final SubscriptionsController _subscriptions;

  Future<void> _ensureSubscriptionState() async {
    await _subscriptions.initialize();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null &&
        _subscriptions.me == null &&
        !_subscriptions.loadingMe) {
      await _subscriptions.refreshMe();
    }
  }

  Future<bool> ensureAllowed(
    BuildContext context, {
    required ConsumerCapability capability,
  }) async {
    await _ensureSubscriptionState();
    final decision = check(capability: capability);
    if (decision.allowed) return true;
    if (!context.mounted) return false;

    final prompt = UpgradePromptFactory.forConsumerCapability(capability);
    final upgraded = await showContextualUpgradeModal(
      context,
      prompt: prompt,
      source: 'consumer_gate:${capability.name}',
    );

    if (!upgraded) return false;
    await _subscriptions.refreshMe();
    return check(capability: capability).allowed;
  }

  Future<bool> ensureGiftTier(
    BuildContext context, {
    required GiftAccessTier requiredTier,
  }) async {
    await _ensureSubscriptionState();
    final decision = checkGiftTier(requiredTier: requiredTier);
    if (decision.allowed) return true;
    if (!context.mounted) return false;

    final prompt = UpgradePromptFactory.forGiftTier(requiredTier);
    final upgraded = await showContextualUpgradeModal(
      context,
      prompt: prompt,
      source: 'consumer_gate:gift_${requiredTier.name}',
    );

    if (!upgraded) return false;
    await _subscriptions.refreshMe();
    return checkGiftTier(requiredTier: requiredTier).allowed;
  }

  ConsumerGateDecision check({required ConsumerCapability capability}) {
    switch (capability) {
      case ConsumerCapability.downloads:
        return _subscriptions.canDownloadOffline
            ? const ConsumerGateDecision.allowed()
            : const ConsumerGateDecision(
                allowed: false,
                title: 'Downloads require Premium',
                message:
                    'Offline downloads start on Premium. Upgrade to save tracks and videos for offline listening.',
              );
      case ConsumerCapability.skips:
        // Skip soft limit are handled by `PlaybackSkipsGate` (non-blocking
        // warnings + enforcement in the audio handler).
        return const ConsumerGateDecision.allowed();
      case ConsumerCapability.contentAccess:
        return _subscriptions.entitlements.effectiveContentAccess.trim().toLowerCase() != 'limited'
            ? const ConsumerGateDecision.allowed()
            : const ConsumerGateDecision(
                allowed: false,
                title: 'Full catalog requires Premium',
                message:
                    'This plan includes limited catalog access. Upgrade to Premium to unlock the full music and video catalog.',
              );
      case ConsumerCapability.exclusiveContent:
        return _subscriptions.hasExclusiveContent
            ? const ConsumerGateDecision.allowed()
            : const ConsumerGateDecision(
                allowed: false,
                title: 'Exclusive content requires Platinum',
                message:
                    'Exclusive drops are reserved for Platinum fans. Upgrade to unlock exclusive tracks and videos.',
              );
      case ConsumerCapability.priorityLiveAccess:
        return _subscriptions.hasPriorityLiveAccess
            ? const ConsumerGateDecision.allowed()
            : const ConsumerGateDecision(
                allowed: false,
                title: 'Priority live access requires Platinum',
                message:
                    'Priority access to live events is reserved for Platinum fans. Upgrade to unlock priority live access.',
              );
      case ConsumerCapability.standardGifts:
        return checkGiftTier(requiredTier: GiftAccessTier.standard);
      case ConsumerCapability.vipGifts:
        return checkGiftTier(requiredTier: GiftAccessTier.vip);
      case ConsumerCapability.songRequests:
        return _subscriptions.canRequestSongInLive
            ? const ConsumerGateDecision.allowed()
            : const ConsumerGateDecision(
                allowed: false,
                title: 'Song requests require Platinum',
                message:
                    'Song requests are part of the Platinum fan experience. Upgrade to move from watching live to influencing it.',
              );
      case ConsumerCapability.highlightedComments:
        return _subscriptions.hasHighlightedComments
            ? const ConsumerGateDecision.allowed()
            : const ConsumerGateDecision(
                allowed: false,
                title: 'Highlighted comments require Platinum',
                message:
                    'Highlighted live comments are reserved for Platinum fans.',
              );
    }
  }

  ConsumerGateDecision checkGiftTier({required GiftAccessTier requiredTier}) {
    if (requiredTier == GiftAccessTier.limited) {
      return const ConsumerGateDecision.allowed();
    }

    if (_subscriptions.entitlements.canSendGiftTier(requiredTier)) {
      return const ConsumerGateDecision.allowed();
    }

    switch (requiredTier) {
      case GiftAccessTier.limited:
        return const ConsumerGateDecision.allowed();
      case GiftAccessTier.standard:
        return const ConsumerGateDecision(
          allowed: false,
          title: 'Premium gifts are locked',
          message:
              'Free listeners can send the light gifts. Upgrade to Premium to unlock the standard gift catalog and stronger fan support.',
        );
      case GiftAccessTier.vip:
        return const ConsumerGateDecision(
          allowed: false,
          title: 'VIP gifts require Platinum',
          message:
              'VIP gifts are reserved for Platinum fans. Upgrade to unlock the highest-impact fan gifts.',
        );
    }
  }

  // Ticket 2.21/2.22: upgrade prompting is handled by the contextual modal.
}
