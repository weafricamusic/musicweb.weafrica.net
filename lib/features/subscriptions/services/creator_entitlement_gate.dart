import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../artist_dashboard/services/artist_identity_service.dart';
import '../../auth/user_role.dart';
import '../models/subscription_me.dart';
import '../models/subscription_plan.dart';
export '../models/subscription_capabilities.dart' show CreatorCapability;
import '../models/subscription_capabilities.dart';
import '../subscriptions_controller.dart';
import '../widgets/contextual_upgrade_modal.dart';
import '../widgets/upgrade_prompt_factory.dart';

class CreatorGateDecision {
  const CreatorGateDecision({
    required this.allowed,
    required this.title,
    required this.message,
    this.offerUpgrade = true,
    this.nearLimitLabel,
    this.softWarning = false,
  });

  final bool allowed;
  final String title;
  final String message;
  final bool offerUpgrade;
  final String? nearLimitLabel;
  final bool softWarning;

  const CreatorGateDecision.allowed()
      : allowed = true,
        title = '',
        message = '',
    offerUpgrade = false,
    nearLimitLabel = null,
    softWarning = false;
}

class CreatorEntitlementGate {
  CreatorEntitlementGate({
    SupabaseClient? client,
    SubscriptionsController? subscriptions,
    ArtistIdentityService? artistIdentity,
  })  : _client = client ?? Supabase.instance.client,
        _subscriptions = subscriptions ?? SubscriptionsController.instance,
        _artistIdentity = artistIdentity ?? ArtistIdentityService();

  static final CreatorEntitlementGate instance = CreatorEntitlementGate();

  final SupabaseClient _client;
  final SubscriptionsController _subscriptions;
  final ArtistIdentityService _artistIdentity;

  static final Map<String, DateTime> _softWarningLastShownAt = <String, DateTime>{};
  static const Duration _softWarningCooldown = Duration(hours: 2);

  Future<void> _ensureSubscriptionState() async {
    await _subscriptions.initialize();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && _subscriptions.me == null && !_subscriptions.loadingMe) {
      await _subscriptions.refreshMe();
    }
  }

  Future<bool> ensureAllowed(
    BuildContext context, {
    required UserRole role,
    required CreatorCapability capability,
  }) async {
    final decision = await check(role: role, capability: capability);
    if (decision.allowed) {
      if (decision.softWarning && context.mounted) {
        final key = '${role.id}:${capability.name}';
        final now = DateTime.now();
        final last = _softWarningLastShownAt[key];
        final canShow = last == null || now.difference(last) >= _softWarningCooldown;
        if (canShow) {
          _softWarningLastShownAt[key] = now;

          final prompt = UpgradePromptFactory.forCreatorCapability(
            role: role,
            capability: capability,
            nearLimitLabel: decision.nearLimitLabel,
          );
          // Non-blocking warning: regardless of upgrade success, allow the action.
          await showContextualUpgradeModal(
            context,
            prompt: prompt,
            source: 'creator_soft_limit:${role.id}:${capability.name}',
          );
        }
      }
      return true;
    }
    if (!context.mounted) return false;

    if (!decision.offerUpgrade) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(decision.title),
            content: Text(decision.message),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return false;
    }

    final prompt = UpgradePromptFactory.forCreatorCapability(
      role: role,
      capability: capability,
      nearLimitLabel: decision.nearLimitLabel,
    );

    final upgraded = await showContextualUpgradeModal(
      context,
      prompt: prompt,
      source: 'creator_gate:${role.id}:${capability.name}',
    );

    if (!upgraded) return false;
    await _subscriptions.refreshMe();
    final decision2 = await check(role: role, capability: capability);
    return decision2.allowed;
  }

  Future<CreatorGateDecision> check({
    required UserRole role,
    required CreatorCapability capability,
  }) async {
    await _ensureSubscriptionState();

    final entitlements = _subscriptions.entitlements;
    final planId = _normalizedCreatorPlanId(role, _subscriptions.effectivePlanId);

    switch (capability) {
      case CreatorCapability.uploadTrack:
        return _checkTrackUpload(role: role, planId: planId, entitlements: entitlements);
      case CreatorCapability.uploadVideo:
        return _checkVideoUpload(role: role, planId: planId, entitlements: entitlements);
      case CreatorCapability.goLive:
        return _checkGoLive(role: role, planId: planId, entitlements: entitlements);
      case CreatorCapability.battle:
        return _checkBattle(role: role, planId: planId, entitlements: entitlements);
      case CreatorCapability.monetization:
        return _checkMonetization(role: role, planId: planId, entitlements: entitlements);
      case CreatorCapability.withdraw:
        return _checkWithdraw(role: role, planId: planId, entitlements: entitlements);
    }
  }

  Future<CreatorGateDecision> _checkTrackUpload({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) async {
    final limit = _trackUploadLimit(role: role, planId: planId, entitlements: entitlements);
    if (limit == null) {
      // Fail open when subscription state is temporarily unavailable.
      // Upload APIs still enforce creator/auth checks server-side.
      if (_subscriptions.me == null) {
        return const CreatorGateDecision.allowed();
      }
      return CreatorGateDecision(
        allowed: false,
        title: 'Uploads unavailable',
        message: 'This account does not have track uploads enabled.',
      );
    }

    if (limit < 0) return const CreatorGateDecision.allowed();

    final used = await _countTrackUploads(role: role, stopAt: limit + 1);
    if (used < limit) {
      final remaining = (limit - used).clamp(0, limit);
      final roleLabel = role == UserRole.artist ? 'Artist' : 'DJ';
      final unitLabel = role == UserRole.artist ? 'song uploads' : 'mix uploads';
      if (remaining <= 2) {
        return CreatorGateDecision(
          allowed: true,
          title: 'Almost at your upload limit',
          message: '$roleLabel Free has $remaining $unitLabel left this month. Upgrade to ${_premiumTierLabel(role)} to unlock more uploads.',
          offerUpgrade: true,
          nearLimitLabel: '$remaining $unitLabel left this month',
          softWarning: true,
        );
      }

      return const CreatorGateDecision.allowed();
    }

    final roleLabel = role == UserRole.artist ? 'Artist' : 'DJ';
    final unitLabel = role == UserRole.artist ? 'song uploads' : 'mix uploads';
    return CreatorGateDecision(
      allowed: false,
      title: 'Upload limit reached',
      message: '$roleLabel Free includes up to $limit $unitLabel. Upgrade to ${_premiumTierLabel(role)} to unlock more uploads.',
      nearLimitLabel: '0 $unitLabel left this month',
    );
  }

  Future<CreatorGateDecision> _checkVideoUpload({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) async {
    final limit = _videoUploadLimit(role: role, planId: planId, entitlements: entitlements);
    if (limit == null) {
      // Fail open when entitlement metadata is missing/unknown.
      // Upload APIs still enforce creator/auth checks server-side.
      return const CreatorGateDecision.allowed();
    }

    if (limit == 0) {
      final roleLabel = role == UserRole.artist ? 'Artist' : 'DJ';
      return CreatorGateDecision(
        allowed: false,
        title: 'Video uploads locked',
        message: '$roleLabel Free does not include video uploads. Upgrade to ${_premiumTierLabel(role)} to unlock video publishing.',
      );
    }

    if (limit < 0) return const CreatorGateDecision.allowed();

    final used = await _countVideoUploads(role: role, stopAt: limit + 1);
    if (used < limit) {
      final remaining = (limit - used).clamp(0, limit);
      final roleLabel = role == UserRole.artist ? 'Artist' : 'DJ';
      if (remaining <= 2) {
        return CreatorGateDecision(
          allowed: true,
          title: 'Almost at your video limit',
          message: '$roleLabel Free has $remaining video uploads left this month. Upgrade to ${_premiumTierLabel(role)} to unlock more video publishing.',
          offerUpgrade: true,
          nearLimitLabel: '$remaining video uploads left this month',
          softWarning: true,
        );
      }

      return const CreatorGateDecision.allowed();
    }

    return CreatorGateDecision(
      allowed: false,
      title: 'Video limit reached',
      message: '${role == UserRole.artist ? 'Artist' : 'DJ'} Free includes up to $limit video uploads. Upgrade to ${_premiumTierLabel(role)} for more video publishing capacity.',
      nearLimitLabel: '0 video uploads left this month',
    );
  }

  Future<CreatorGateDecision> _checkGoLive({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) async {
    if (_canGoLive(planId: planId, entitlements: entitlements)) {
      return const CreatorGateDecision.allowed();
    }

    final message = role == UserRole.artist
        ? 'Live streaming starts on Artist Pro. Upgrade to go live and unlock creator earnings.'
        : 'Live DJ sets start on DJ Pro. Upgrade to stream live and earn from your sets.';
    return CreatorGateDecision(
      allowed: false,
      title: 'Live requires an upgrade',
      message: message,
    );
  }

  Future<CreatorGateDecision> _checkBattle({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) async {
    if (_canBattle(planId: planId, entitlements: entitlements)) {
      return const CreatorGateDecision.allowed();
    }

    return CreatorGateDecision(
      allowed: false,
      title: 'Battles require an upgrade',
      message: role == UserRole.artist
          ? 'Battles start on ${_premiumTierLabel(role)} and move to priority access on ${_platinumTierLabel(role)}.'
          : 'DJ battles start on ${_premiumTierLabel(role)} and unlock priority hosting on ${_platinumTierLabel(role)}.',
    );
  }

  Future<CreatorGateDecision> _checkMonetization({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) async {
    if (_canMonetize(planId: planId, entitlements: entitlements)) {
      return const CreatorGateDecision.allowed();
    }

    final message = role == UserRole.artist
        ? 'Creator earnings start on Artist Pro. Upgrade to unlock monetization, revenue insights, and live earnings.'
        : 'Creator earnings start on DJ Pro. Upgrade to unlock live gifts, monetization, and payout-ready earnings.';
    return CreatorGateDecision(
      allowed: false,
      title: 'Earnings require an upgrade',
      message: message,
    );
  }

  Future<CreatorGateDecision> _checkWithdraw({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) async {
    if (_withdrawAccess(planId: planId, entitlements: entitlements) != 'none') {
      return const CreatorGateDecision.allowed();
    }

    return CreatorGateDecision(
      allowed: false,
      title: 'Withdrawals require an upgrade',
      message: 'Withdrawals start on ${_premiumTierLabel(role)} and expand further on ${_platinumTierLabel(role)}.',
    );
  }

  String _normalizedCreatorPlanId(UserRole role, String rawPlanId) {
    final planId = canonicalPlanId(rawPlanId);
    if (role == UserRole.artist) {
      switch (planId) {
        case '':
        case 'free':
        case 'starter':
        case 'artist_free':
          return 'artist_starter';
        case 'premium':
        case 'pro':
          return 'artist_pro';
        case 'platinum':
        case 'elite':
        case 'vip':
          return 'artist_premium';
        default:
          return planId.isEmpty ? 'artist_starter' : planId;
      }
    }

    if (role == UserRole.dj) {
      switch (planId) {
        case '':
        case 'free':
        case 'starter':
        case 'dj_free':
          return 'dj_starter';
        case 'premium':
        case 'pro':
          return 'dj_pro';
        case 'platinum':
        case 'elite':
        case 'vip':
          return 'dj_premium';
        default:
          return planId.isEmpty ? 'dj_starter' : planId;
      }
    }

    return planId.isEmpty ? 'free' : planId;
  }

  int? _trackUploadLimit({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) {
    final fromEntitlements = entitlements.creatorTrackUploadLimit(
      _creatorRoleId(role),
      fallbackPlanId: planId,
    );
    return fromEntitlements;
  }

  int? _videoUploadLimit({
    required UserRole role,
    required String planId,
    required Entitlements entitlements,
  }) {
    final fromEntitlements = entitlements.creatorVideoUploadLimit(
      _creatorRoleId(role),
      fallbackPlanId: planId,
    );
    return fromEntitlements;
  }

  bool _canGoLive({required String planId, required Entitlements entitlements}) {
    return entitlements.creatorCanGoLive();
  }

  bool _canBattle({required String planId, required Entitlements entitlements}) {
    return entitlements.creatorCanBattle();
  }

  bool _canMonetize({required String planId, required Entitlements entitlements}) {
    return entitlements.creatorCanMonetize();
  }

  String _withdrawAccess({required String planId, required Entitlements entitlements}) {
    return entitlements.creatorWithdrawalAccess();
  }

  Future<int> _countTrackUploads({
    required UserRole role,
    required int stopAt,
  }) async {
    if (role == UserRole.artist) {
      final artistId = await _artistIdentity.resolveArtistIdForCurrentUser();
      final id = (artistId ?? '').trim();
      if (id.isEmpty) return 0;
      return _countRows(
        table: 'songs',
        column: 'artist_id',
        value: id,
        stopAt: stopAt,
      );
    }

    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return 0;
    return _countRows(
      table: 'songs',
      column: 'uploader_id',
      value: uid,
      stopAt: stopAt,
    );
  }

  Future<int> _countVideoUploads({
    required UserRole role,
    required int stopAt,
  }) async {
    final uid = _artistIdentity.currentFirebaseUid();
    final id = (uid ?? '').trim();
    if (id.isEmpty) return 0;
    return _countRows(
      table: 'videos',
      column: 'uploader_id',
      value: id,
      stopAt: stopAt,
    );
  }

  Future<int> _countRows({
    required String table,
    required String column,
    required String value,
    required int stopAt,
  }) async {
    final rows = await _client
        .from(table)
        .select('id')
        .eq(column, value)
        .limit(stopAt);
    final count = rows.length;
    return count > stopAt ? stopAt : count;
  }

  String _creatorRoleId(UserRole role) {
    switch (role) {
      case UserRole.artist:
        return 'artist';
      case UserRole.dj:
        return 'dj';
      case UserRole.consumer:
        return 'consumer';
    }
  }

  String _premiumTierLabel(UserRole role) {
    switch (role) {
      case UserRole.artist:
        return 'Artist Pro';
      case UserRole.dj:
        return 'DJ Pro';
      case UserRole.consumer:
        return 'Premium';
    }
  }

  String _platinumTierLabel(UserRole role) {
    switch (role) {
      case UserRole.artist:
        return 'Artist Premium';
      case UserRole.dj:
        return 'DJ Premium';
      case UserRole.consumer:
        return 'Platinum';
    }
  }
}