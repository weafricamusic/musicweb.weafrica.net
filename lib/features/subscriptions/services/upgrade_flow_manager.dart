import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/weafrica_colors.dart';
import '../../auth/user_role.dart';
import '../../auth/login_screen.dart';
import '../checkout_webview_screen.dart';
import '../models/subscription_me.dart';
import '../models/subscription_plan.dart';
import '../subscriptions_controller.dart';
import 'paychangu_checkout_loader.dart';
import 'subscriptions_api.dart';

enum UpgradeFlowOutcome { success, canceled, failed }

class UpgradeFlowResult {
  const UpgradeFlowResult({
    required this.outcome,
    this.me,
    this.error,
  });

  final UpgradeFlowOutcome outcome;
  final SubscriptionMe? me;
  final Object? error;

  bool get isSuccess => outcome == UpgradeFlowOutcome.success;
}

class UpgradeFlowManager {
  UpgradeFlowManager({
    SubscriptionsController? subscriptions,
    PayChanguCheckoutLoader? checkoutLoader,
  })  : _subscriptions = subscriptions ?? SubscriptionsController.instance,
        _checkoutLoader = checkoutLoader ?? PayChanguCheckoutLoader.instance;

  static final UpgradeFlowManager instance = UpgradeFlowManager();

  final SubscriptionsController _subscriptions;
  final PayChanguCheckoutLoader _checkoutLoader;

  static const _prefsKeyPrefix = 'weafrica.upgrade.last_plan.';

  void track(String event, {Map<String, String>? props}) {
    // Lightweight analytics hook (no external dependency).
    // Wire this to a real analytics provider later.
    if (kDebugMode) {
      debugPrint('📈 upgrade:$event ${props ?? const <String, String>{}}');
    }
  }

  Future<void> rememberLastPlanId(UserRole role, String planId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsKeyPrefix${role.id}', planId.trim());
  }

  Future<String?> lastPlanId(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('$_prefsKeyPrefix${role.id}')?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<bool> ensureSignedInOrNavigateToLogin(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return true;
    if (!context.mounted) return false;

    track('sign_in_required');

    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );

    return FirebaseAuth.instance.currentUser != null;
  }

  Future<SubscriptionPlan> resolvePlan({
    required String planId,
    required UserRole role,
  }) async {
    await _subscriptions.initialize();
    final canonical = canonicalPlanId(planId);

    // Fast path: consumer plans usually already in controller.
    if (role == UserRole.consumer) {
      final local = _subscriptions.planForId(canonical);
      if (local != null) return local;

      final fetched = await SubscriptionsApi.fetchPlans(audience: 'consumer');
      for (final p in fetched) {
        if (planIdMatches(p.planId, canonical)) return p;
      }
      throw StateError('Plan not found in consumer catalog: $canonical');
    }

    final audience = role == UserRole.artist
        ? 'artist'
        : role == UserRole.dj
            ? 'dj'
            : 'creator';

    final fetched = await SubscriptionsApi.fetchPlans(audience: audience);
    for (final p in fetched) {
      if (planIdMatches(p.planId, canonical)) return p;
    }

    throw StateError('Plan not found for audience=$audience: $canonical');
  }

  Future<UpgradeFlowResult> upgradePlan({
    required BuildContext context,
    required SubscriptionPlan plan,
    Uri? preloadedCheckoutUrl,
    String? preloadedTxRef,
    String source = 'unknown',
  }) async {
    try {
      track('upgrade_clicked', props: {
        'source': source,
        'plan_id': plan.planId,
      });

      final signedIn = await ensureSignedInOrNavigateToLogin(context);
      if (!signedIn) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }
      if (!context.mounted) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      await rememberLastPlanId(_roleForPlan(plan), plan.planId);
      if (!context.mounted) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      Uri checkoutUrl;
      String txRef = preloadedTxRef?.trim() ?? '';
      if (preloadedCheckoutUrl != null) {
        checkoutUrl = preloadedCheckoutUrl;
      } else {
        _showSnack(context, 'Preparing secure checkout…');
        final session = await _checkoutLoader.getOrCreateSession(plan: plan);
        checkoutUrl = session.checkoutUrl;
        txRef = session.txRef;
      }

      if (!context.mounted) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      track('checkout_started', props: {
        'source': source,
        'plan_id': plan.planId,
      });

      CheckoutOutcome? checkoutOutcome;
      if (kIsWeb) {
        final launched = await launchUrl(
          checkoutUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw Exception('Could not open checkout URL: $checkoutUrl');
        }

        if (!context.mounted) {
          return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
        }

        // Best-effort: poll while user completes payment in the browser.
        _showSnack(context, 'Processing your payment… This may take a few seconds.');
      } else {
        checkoutOutcome = await Navigator.of(context).push<CheckoutOutcome>(
          MaterialPageRoute(
            builder: (_) => CheckoutWebviewScreen(
              initialUrl: checkoutUrl,
              expectedPlanId: plan.planId,
            ),
            fullscreenDialog: true,
          ),
        );
      }

      if (!context.mounted) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      // If user explicitly closed the checkout, don’t pretend it succeeded.
      if (checkoutOutcome == CheckoutOutcome.canceled) {
        track('checkout_canceled', props: {
          'source': source,
          'plan_id': plan.planId,
        });

        await _subscriptions.refreshMe();
        if (!context.mounted) {
          return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
        }
        _showSnack(context, 'Upgrade not completed.');
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      if (txRef.trim().isNotEmpty) {
        _showSnack(context, 'Finalizing your payment…');
        await _verifySubscriptionWithRetry(
          txRef: txRef,
          expectedPlanId: plan.planId,
        );
      }

      // When returning from checkout, refresh access.
      await _subscriptions.refreshMe();
      if (!context.mounted) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      final me = _subscriptions.me;
      final alreadyActiveForPlan =
          me != null && me.isActive && planIdMatches(me.planId, plan.planId);

      if (!alreadyActiveForPlan) {
        _showSnack(context, 'Processing your payment… This may take a few seconds.');

        try {
          await SubscriptionsApi.pollMeUntilActive(
            timeout: const Duration(minutes: 2),
            interval: const Duration(seconds: 3),
            expectedPlanId: plan.planId,
          );
        } catch (_) {
          // Ignore: user may have cancelled or webhook may be delayed.
        }

        if (!context.mounted) {
          return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
        }

        await _subscriptions.refreshMe();
        if (!context.mounted) {
          return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
        }
      }

      if (!context.mounted) {
        return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
      }

      final me2 = _subscriptions.me;
      final activeNow =
          me2 != null && me2.isActive && planIdMatches(me2.planId, plan.planId);

      if (activeNow) {
        track('checkout_completed', props: {
          'source': source,
          'plan_id': plan.planId,
        });

        _checkoutLoader.invalidateAll();
        _showSuccess(context, 'Upgrade successful. Access unlocked.');
        return UpgradeFlowResult(outcome: UpgradeFlowOutcome.success, me: me2);
      }

      track('checkout_failed', props: {
        'source': source,
        'plan_id': plan.planId,
      });

      _showSnack(context, 'Upgrade not completed.');
      return const UpgradeFlowResult(outcome: UpgradeFlowOutcome.canceled);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('UpgradeFlowManager.upgradePlan error: $e');
      }
      if (context.mounted) {
        _showSnack(context, 'Payments are temporarily unavailable. Please try again.');
      }
      return UpgradeFlowResult(outcome: UpgradeFlowOutcome.failed, error: e);
    }
  }

  Future<bool> upgradeAndResume({
    required BuildContext context,
    required String planId,
    required UserRole role,
    required Future<void> Function() onSuccessAction,
    String source = 'unknown',
    Uri? preloadedCheckoutUrl,
    String? preloadedTxRef,
  }) async {
    final plan = await resolvePlan(planId: planId, role: role);
    if (!context.mounted) return false;

    final result = await upgradePlan(
      context: context,
      plan: plan,
      preloadedCheckoutUrl: preloadedCheckoutUrl,
      preloadedTxRef: preloadedTxRef,
      source: source,
    );

    if (!context.mounted) return false;
    if (!result.isSuccess) return false;

    try {
      await onSuccessAction();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('upgradeAndResume onSuccessAction failed: $e');
      }
    }

    return true;
  }

  UserRole _roleForPlan(SubscriptionPlan plan) {
    final audience = (plan.audience ?? '').trim().toLowerCase();
    return switch (audience) {
      'artist' => UserRole.artist,
      'dj' => UserRole.dj,
      _ => UserRole.consumer,
    };
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _verifySubscriptionWithRetry({
    required String txRef,
    required String expectedPlanId,
  }) async {
    final ref = txRef.trim();
    if (ref.isEmpty) return false;

    for (var i = 0; i < 4; i++) {
      try {
        final ok = await SubscriptionsApi.verifyPayChanguSubscription(
          txRef: ref,
          expectedPlanId: expectedPlanId,
        );
        if (ok) return true;
      } catch (_) {
        // Ignore and retry briefly; webhook/manual verify races are expected.
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    return false;
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: WeAfricaColors.success,
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
  }
}
