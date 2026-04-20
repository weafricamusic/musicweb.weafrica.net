import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'models/gifting_tier.dart';
import 'models/subscription_me.dart';
import 'models/subscription_plan.dart';
import 'services/subscriptions_api.dart';
import 'services/subscription_plans_cache.dart';

class SubscriptionsController extends ChangeNotifier {
  SubscriptionsController._();

  static final SubscriptionsController instance = SubscriptionsController._();

  StreamSubscription<User?>? _authSub;

  bool _initialized = false;

  bool _loadingPlans = false;
  bool _loadingMe = false;
  String? _lastError;

  final SubscriptionPlansCache _plansCache = SubscriptionPlansCache();

  List<SubscriptionPlan> _plans = const [];
  SubscriptionMe? _me;

  bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get loadingPlans => _loadingPlans;
  bool get loadingMe => _loadingMe;
  String? get lastError => _lastError;

  List<SubscriptionPlan> get plans => List.unmodifiable(_plans);
  SubscriptionMe? get me => _me;

  SubscriptionPlan? planForId(String planId) {
    for (final plan in _plans) {
      if (planIdMatches(plan.planId, planId)) return plan;
    }
    return null;
  }

  SubscriptionPlan? get currentCatalogPlan =>
      planForId(effectivePlanId) ?? planForId(currentPlanId);

  String? get currentPlanAudience =>
      _me?.audience ?? currentCatalogPlan?.audience;

  bool get currentPlanHasTrialOffer =>
      (_me?.hasTrialOffer ?? false) ||
      (currentCatalogPlan?.hasTrialOffer ?? false);

  int get currentPlanTrialDurationDays =>
      _me?.trialDurationDays ?? currentCatalogPlan?.trialDurationDays ?? 0;

  List<SubscriptionPlan> plansForAudience(String audience) {
    final normalized = audience.trim().toLowerCase();
    return _plans
        .where((plan) => (plan.audience ?? '').trim().toLowerCase() == normalized)
        .toList(growable: false);
  }

  String get currentPlanId => _me?.planId ?? 'free';
  bool get isPremiumActive =>
      _me != null && _me!.isActive && !isFreeLikePlanId(_me!.planId);

  bool _shouldPreserveInactivePlan(SubscriptionMe me) {
    if (isFreeLikePlanId(me.planId)) return true;
    return me.entitlements.raw.isNotEmpty && isCreatorPlanId(me.planId);
  }

  bool _shouldUseInactiveEntitlements(SubscriptionMe me) {
    if (me.entitlements.raw.isEmpty) return false;
    return isFreeLikePlanId(me.planId) || isCreatorPlanId(me.planId);
  }

  Entitlements _mergedEntitlementsFor(SubscriptionMe me) {
    final ent = me.entitlements;
    if (ent.raw.isEmpty) {
      return Entitlements.defaultsForPlanId(me.planId);
    }

    final base = Entitlements.defaultsForPlanId(me.planId);
    return Entitlements(
      raw: ent.raw,
      adsEnabled: ent.adsEnabled ?? base.adsEnabled,
      interstitialEverySongs:
          ent.interstitialEverySongs ?? base.interstitialEverySongs,
      backgroundPlayEnabled:
          ent.backgroundPlayEnabled ?? base.backgroundPlayEnabled,
      downloadsEnabled: ent.downloadsEnabled ?? base.downloadsEnabled,
      videoDownloadsEnabled:
          ent.videoDownloadsEnabled ?? base.videoDownloadsEnabled,
      playlistsCreateEnabled:
          ent.playlistsCreateEnabled ?? base.playlistsCreateEnabled,
      playlistsMixEnabled: ent.playlistsMixEnabled ?? base.playlistsMixEnabled,
      maxAudioKbps: ent.maxAudioKbps ?? base.maxAudioKbps,
      maxSkipsPerHour: ent.maxSkipsPerHour ?? base.maxSkipsPerHour,
      giftingTier: ent.giftingTier ?? base.giftingTier,
      vipBadgeEnabled: ent.vipBadgeEnabled ?? base.vipBadgeEnabled,
      highlightedCommentsEnabled:
          ent.highlightedCommentsEnabled ?? base.highlightedCommentsEnabled,
      exclusiveContentEnabled:
          ent.exclusiveContentEnabled ?? base.exclusiveContentEnabled,
      priorityLiveAccessEnabled:
          ent.priorityLiveAccessEnabled ?? base.priorityLiveAccessEnabled,
      songRequestsEnabled: ent.songRequestsEnabled ?? base.songRequestsEnabled,
      earlyAccessEnabled: ent.earlyAccessEnabled ?? base.earlyAccessEnabled,
      contentAccess: ent.contentAccess ?? base.contentAccess,
      contentLimitRatio: ent.contentLimitRatio ?? base.contentLimitRatio,
      battlePriority: ent.battlePriority ?? base.battlePriority,
      featured: ent.featured ?? base.featured,
      monthlyFreeCoins: ent.monthlyFreeCoins ?? base.monthlyFreeCoins,
      weeklyFreeCoins: ent.weeklyFreeCoins ?? base.weeklyFreeCoins,
      monthlyBonusCoins: ent.monthlyBonusCoins ?? base.monthlyBonusCoins,
    );
  }

  /// Effective plan id for feature gating.
  ///
  /// Preserve creator tiers when `/api/subscriptions/me` already includes
  /// concrete entitlements, even if `subscription.status` is missing or stale.
  String get effectivePlanId {
    if (_me == null) return 'free';
    if (_me!.isActive) return _me!.planId;
    if (_shouldPreserveInactivePlan(_me!)) return _me!.planId;
    return 'free';
  }

  /// Listener feature gating source of truth is `/api/subscriptions/me`
  /// entitlements. Firebase custom claims are only optional hints.
  bool get canCreatePlaylists => entitlements.effectivePlaylistsCreateEnabled;

  bool get canDownloadOffline => entitlements.effectiveDownloadsEnabled;

  bool get canDownloadVideos => entitlements.effectiveVideoDownloadsEnabled;

  bool get canUseHighQualityAudio =>
      entitlements.effectiveHighQualityAudioEnabled;

  GiftAccessTier get giftingTier => entitlements.effectiveGiftingTier;

  bool get canSendStandardGifts =>
      entitlements.canSendGiftTier(GiftAccessTier.standard);

  bool get canSendVipGifts => entitlements.canSendGiftTier(GiftAccessTier.vip);

  bool get canRequestSongInLive => entitlements.effectiveSongRequestsEnabled;

  bool get hasVipFanBadge => entitlements.effectiveVipBadgeEnabled;

  bool get hasHighlightedComments =>
      entitlements.effectiveHighlightedCommentsEnabled;

  bool get hasExclusiveContent => entitlements.effectiveExclusiveContentEnabled;

  bool get hasPriorityLiveAccess =>
      entitlements.effectivePriorityLiveAccessEnabled;

  bool get hasEarlyAccessDrops => entitlements.effectiveEarlyAccessEnabled;

  int get monthlyBonusCoins => entitlements.effectiveMonthlyBonusCoins;

  int get maxSkipsPerHour => entitlements.effectiveMaxSkipsPerHour;

  bool get hasUnlimitedSkips => entitlements.hasUnlimitedSkips;

  /// Effective entitlements for feature gating.
  ///
  /// If inactive/missing, use Free defaults. If active but the backend omitted
  /// some fields, fall back to sensible defaults for that plan id.
  Entitlements get entitlements {
    if (_me == null) {
      return Entitlements.defaultsForPlanId('free');
    }

    if (!_me!.isActive) {
      if (_shouldUseInactiveEntitlements(_me!)) {
        return _mergedEntitlementsFor(_me!);
      }
      return Entitlements.defaultsForPlanId('free');
    }

    return _mergedEntitlementsFor(_me!);
  }

  void _notifyListenersSafe() {
    if (!hasListeners) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Integration tests and some dev harnesses can run without Firebase
    // initialization. Avoid touching FirebaseAuth in that case.
    if (_firebaseReady) {
      _authSub = FirebaseAuth.instance.userChanges().listen((user) {
        if (user == null) {
          _me = null;
          _notifyListenersSafe();
          return;
        }

        unawaited(refreshMe());
      });
    }

    // Preload plans early (public endpoint).
    unawaited(loadPlans());

    // If already signed in, fetch me.
    if (_firebaseReady && FirebaseAuth.instance.currentUser != null) {
      unawaited(refreshMe());
    }
  }

  Future<void> loadPlans({String audience = 'consumer', bool forceRefresh = false}) async {
    if (_loadingPlans) return;
    _loadingPlans = true;
    _lastError = null;
    _notifyListenersSafe();

    try {
      final normalizedAudience = audience.trim().isEmpty ? 'consumer' : audience.trim().toLowerCase();

      // Ticket 2.15: read local cache first for a faster subscriptions UI.
      // If fresh, skip network entirely.
      final cachedFresh = forceRefresh
          ? null
          : await _plansCache.readFresh(audience: normalizedAudience);
      if (cachedFresh != null && cachedFresh.isNotEmpty) {
        final merged = <String, SubscriptionPlan>{
          for (final plan in _plans) plan.planId: plan,
          for (final plan in cachedFresh) plan.planId: plan,
        };
        _plans = merged.values.toList(growable: false);
        return;
      }

      // If cache is stale/missing, still try to show whatever we have before
      // hitting the network.
      final cachedAny = forceRefresh
          ? null
          : await _plansCache.readStaleOk(audience: normalizedAudience);
      if (cachedAny != null && cachedAny.isNotEmpty) {
        final merged = <String, SubscriptionPlan>{
          for (final plan in _plans) plan.planId: plan,
          for (final plan in cachedAny) plan.planId: plan,
        };
        _plans = merged.values.toList(growable: false);
        _notifyListenersSafe();
      }

      final fetchedPlans = await SubscriptionsApi.fetchPlans(audience: normalizedAudience);
      final mergedPlans = <String, SubscriptionPlan>{
        for (final plan in _plans) plan.planId: plan,
      };
      for (final plan in fetchedPlans) {
        mergedPlans[plan.planId] = plan;
      }
      _plans = mergedPlans.values.toList(growable: false);

      await _plansCache.write(audience: normalizedAudience, plans: fetchedPlans);
    } catch (e) {
      _lastError = e.toString();
      if (kDebugMode) debugPrint('loadPlans failed: $e');
    } finally {
      _loadingPlans = false;
      _notifyListenersSafe();
    }
  }

  Future<void> refreshMe() async {
    if (_loadingMe) return;
    _loadingMe = true;
    _lastError = null;
    _notifyListenersSafe();

    try {
      _me = await SubscriptionsApi.fetchMe();
      final meAudience = _me?.audience ?? defaultAudienceForPlanId(_me?.planId ?? '');
      if (meAudience != null && planForId(_me?.planId ?? '') == null) {
        unawaited(loadPlans(audience: meAudience));
      }
    } catch (e) {
      _lastError = e.toString();
      if (kDebugMode) debugPrint('refreshMe failed: $e');
    } finally {
      _loadingMe = false;
      _notifyListenersSafe();
    }
  }

  Future<void> refreshPlans({String audience = 'consumer'}) {
    return loadPlans(audience: audience, forceRefresh: true);
  }

  Future<void> disposeController() async {
    await _authSub?.cancel();
    _authSub = null;
  }
}
