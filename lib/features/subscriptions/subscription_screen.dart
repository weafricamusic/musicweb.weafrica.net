import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../auth/user_role.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../app/config/api_env.dart';
import '../../app/config/app_env.dart';
import '../../app/config/debug_flags.dart';
import 'checkout_webview_screen.dart';
import 'models/subscription_me.dart';
import 'models/subscription_plan.dart';
import 'services/subscriptions_api.dart';
import 'services/upgrade_flow_manager.dart';
import 'subscription_color_hierarchy.dart';
import 'subscriptions_controller.dart';

enum SubscriptionCatalog { listener, creator }

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.initialCatalog = SubscriptionCatalog.listener,
    this.showCatalogToggle = true,
    this.showComparisonTable = true,
    this.showAppBar = true,
    this.title = 'Upgrade',
    this.userRole,
    this.signedInOverride,
  });

  final UserRole? userRole;

  final SubscriptionCatalog initialCatalog;

  /// Whether to show the Listener/Creator catalog toggle.
  ///
  /// For role-specific entry points (e.g. Artist dashboard), this can be hidden
  /// to avoid presenting irrelevant catalogs.
  final bool showCatalogToggle;

  /// Whether to show the creator plan comparison table.
  ///
  /// Dashboard-managed upgrade flows can disable this to keep the screen more
  /// compact while leaving the broader subscription experience unchanged.
  final bool showComparisonTable;

  /// Whether to show the top AppBar.
  ///
  /// When embedding this screen inside a shell that already provides an AppBar
  /// (e.g. mobile dashboard), set this to false to avoid double AppBars.
  final bool showAppBar;

  /// Title for the AppBar (when [showAppBar] is true).
  final String title;

  /// Test hook: forces the signed-in state without requiring Firebase.
  ///
  /// When null (default), signed-in state is derived from FirebaseAuth.
  final bool? signedInOverride;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _controller = SubscriptionsController.instance;

  late SubscriptionCatalog _catalog;

  bool _loadingCreatorPlans = false;
  String? _creatorPlansError;
  List<SubscriptionPlan> _creatorPlans = const <SubscriptionPlan>[];

  @override
  void initState() {
    super.initState();

    _catalog = _enforcedCatalogForRole(
      widget.initialCatalog,
      userRole: widget.userRole,
    );

    // Safe to call multiple times.
    _controller.initialize();
    _controller.loadPlans();

    final firebaseReady = _firebaseReady;
    final signedIn = widget.signedInOverride ??
        (firebaseReady && FirebaseAuth.instance.currentUser != null);
    if (signedIn) {
      _controller.refreshMe();
    }

    if (_catalog == SubscriptionCatalog.creator) {
      _loadCreatorPlans();
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the caller changes role or initial catalog, keep the UI consistent.
    final enforced = _enforcedCatalogForRole(
      widget.initialCatalog,
      userRole: widget.userRole,
    );
    if (enforced != _catalog) {
      _catalog = enforced;
      if (_catalog == SubscriptionCatalog.creator) {
        unawaited(_loadCreatorPlans());
      }
    }
  }

  SubscriptionCatalog _enforcedCatalogForRole(
    SubscriptionCatalog requested, {
    required UserRole? userRole,
  }) {
    if (userRole == null) return requested;
    if (userRole == UserRole.consumer) return SubscriptionCatalog.listener;
    if (userRole == UserRole.artist || userRole == UserRole.dj) {
      return SubscriptionCatalog.creator;
    }
    return requested;
  }

  bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadCreatorPlans({bool force = false}) async {
    if (_loadingCreatorPlans) return;
    if (!force && _creatorPlans.isNotEmpty) return;

    setState(() {
      _loadingCreatorPlans = true;
      _creatorPlansError = null;
    });

    try {
      final audience = switch (widget.userRole) {
        UserRole.artist => 'artist',
        UserRole.dj => 'dj',
        _ => 'creator',
      };
      final plans = await SubscriptionsApi.fetchPlans(audience: audience);
      if (!mounted) return;
      setState(() {
        _creatorPlans = plans;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('loadCreatorPlans failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _creatorPlansError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCreatorPlans = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Safety: even if this screen is reached with an unexpected initial
        // catalog, always respect the role.
        final enforcedCatalog = _enforcedCatalogForRole(
          _catalog,
          userRole: widget.userRole,
        );

        if (enforcedCatalog != _catalog) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _catalog = enforcedCatalog;
            });
          });
        }

        final me = _controller.me;
        final signedIn = widget.signedInOverride ??
            (_firebaseReady && FirebaseAuth.instance.currentUser != null);

        final activePlans = enforcedCatalog == SubscriptionCatalog.listener
          ? _controller.plans
          : _creatorPlans;
        final loadingPlans = enforcedCatalog == SubscriptionCatalog.listener
            ? _controller.loadingPlans
            : _loadingCreatorPlans;
        final plansError = enforcedCatalog == SubscriptionCatalog.listener
            ? _controller.lastError
            : _creatorPlansError;

        final roleFilteredPlans = enforcedCatalog == SubscriptionCatalog.creator
          ? _filterCreatorPlansForRole(activePlans, userRole: widget.userRole)
            .toList(growable: false)
          : activePlans;

        final visiblePlans =
          _visiblePlans(roleFilteredPlans).toList(growable: false);
        final currentPlanName = _planNameForPlanId(
          planId: me?.planId ?? '',
          plans: <SubscriptionPlan>[..._controller.plans, ..._creatorPlans],
        );

        // Hide catalog toggle for consumers, artists, and DJs
        final hideCatalogToggle =
            (widget.userRole == UserRole.consumer ||
            widget.userRole == UserRole.artist ||
            widget.userRole == UserRole.dj);

        return Scaffold(
          appBar: widget.showAppBar
              ? AppBar(
                  title: Text(widget.title),
                  actions: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () {
                        _controller.loadPlans();
                        if (signedIn) _controller.refreshMe();
                        if (_catalog == SubscriptionCatalog.creator) {
                          _loadCreatorPlans(force: true);
                        }
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              _hero(
                context,
                me: me,
                signedIn: signedIn,
                catalog: enforcedCatalog,
                currentPlanName: currentPlanName,
                userRole: widget.userRole,
              ),
              const SizedBox(height: 14),
              if (widget.showCatalogToggle && !hideCatalogToggle) ...[
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Listeners'),
                      selected: enforcedCatalog == SubscriptionCatalog.listener,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() {
                          _catalog = SubscriptionCatalog.listener;
                        });
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('Creators'),
                      selected: enforcedCatalog == SubscriptionCatalog.creator,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() {
                          _catalog = SubscriptionCatalog.creator;
                        });
                        _loadCreatorPlans();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Text(
                _catalog == SubscriptionCatalog.creator
                    ? switch (widget.userRole) {
                        UserRole.artist => 'Choose your artist plan',
                        UserRole.dj => 'Choose your DJ plan',
                        _ => 'Choose your creator plan',
                      }
                    : 'Choose your listening plan',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (loadingPlans)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visiblePlans.isEmpty &&
                  (plansError?.isNotEmpty ?? false))
                _plansErrorCard(
                  context,
                  onRetry: () {
                    if (_catalog == SubscriptionCatalog.creator) {
                      _loadCreatorPlans(force: true);
                    } else {
                      _controller.loadPlans();
                    }
                  },
                )
              else if (visiblePlans.isEmpty)
                _emptyPlansCard(context)
              else ...[
                ...visiblePlans.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlanCard(
                      plan: p,
                      currentPlanId: _controller.currentPlanId,
                      signedIn: signedIn,
                      onUpgrade: () => p.isFree
                          ? _continueWithFreePlan(context)
                          : _startPayment(context, p),
                    ),
                  ),
                ),
                if (_catalog == SubscriptionCatalog.creator &&
                    widget.showComparisonTable)
                  _comparisonTable(context, userRole: widget.userRole),
              ],
            ],
          ),
        );
      },
    );
  }

  void _continueWithFreePlan(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You can stay on Free. Upgrade when you need live tools, monetization, or more reach.',
        ),
      ),
    );
  }

  Future<void> _startPayment(
    BuildContext context,
    SubscriptionPlan plan,
  ) async {
    try {
      final session = await SubscriptionsApi.startPayChanguPaymentSession(
        plan: plan,
      );
      final checkoutUrl = session.checkoutUrl;
      final txRef = session.txRef;

      if (!context.mounted) return;

      if (kIsWeb) {
        // webview_flutter has no web implementation — open checkout in the browser.
        final launched = await launchUrl(
          checkoutUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw Exception('Could not open checkout URL: $checkoutUrl');
        }
      } else {
        // Keep the user inside the app during checkout.
        final outcome = await Navigator.of(context).push<CheckoutOutcome>(
          MaterialPageRoute<CheckoutOutcome>(
            builder: (_) => CheckoutWebviewScreen(
              initialUrl: checkoutUrl,
              expectedPlanId: plan.planId,
            ),
          ),
        );

        if (outcome == CheckoutOutcome.canceled) {
          if (!context.mounted) return;
          await _controller.refreshMe();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Upgrade not completed.')));
          return;
        }
      }

      if (txRef.trim().isNotEmpty) {
        for (var i = 0; i < 4; i++) {
          try {
            final ok = await SubscriptionsApi.verifyPayChanguSubscription(
              txRef: txRef,
              expectedPlanId: plan.planId,
            );
            if (ok) break;
          } catch (_) {
            // Ignore and retry briefly; webhook/manual verify races are expected.
          }
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }

      // When the user returns from checkout, refresh access.
      if (!context.mounted) return;
      await _controller.refreshMe();

      // Webhook reconciliation can take a few seconds; poll briefly so users
      // don’t get stuck thinking “it didn’t work”.
      final me = _controller.me;
      final alreadyActiveForPlan =
          me != null && me.isActive && planIdMatches(me.planId, plan.planId);

      if (!alreadyActiveForPlan) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processing payment… This may take a moment.'),
          ),
        );

        try {
          await SubscriptionsApi.pollMeUntilActive(
            timeout: const Duration(minutes: 2),
            expectedPlanId: plan.planId,
          );
        } catch (_) {
          // Ignore: user may have cancelled checkout or webhook may be delayed.
        }

        if (!context.mounted) return;
        await _controller.refreshMe();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout closed. Subscription refreshed.'),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Payment error: $e');
      }
      if (!context.mounted) return;

      final showDiagnostics = DebugFlags.showDeveloperUi;
      final message = _paymentFriendlyMessage(e);
      final diagnostics = showDiagnostics ? _paymentDiagnostics(e) : '';

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment unavailable'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  if (showDiagnostics && diagnostics.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Details',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      diagnostics,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (showDiagnostics)
              TextButton(
                onPressed: () {
                  final text = diagnostics.isEmpty
                      ? message
                      : '$message\n\n$diagnostics';
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied payment details.')),
                  );
                },
                child: const Text('Copy'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

Iterable<SubscriptionPlan> _filterCreatorPlansForRole(
  Iterable<SubscriptionPlan> plans, {
  required UserRole? userRole,
}) {
  final prefix = switch (userRole) {
    UserRole.artist => 'artist_',
    UserRole.dj => 'dj_',
    _ => null,
  };
  if (prefix == null) return plans;

  return plans.where((p) {
    final id = canonicalPlanId(p.planId).toLowerCase();
    return id.startsWith(prefix);
  });
}

String _paymentFriendlyMessage(Object error) {
  final d = error.toString().toLowerCase();

  if (d.contains('not logged in')) {
    return 'Please sign in to start payment.';
  }

  if (d.contains('timed out') || d.contains('timeout')) {
    return 'Payment timed out. Please try again.';
  }

  if (d.contains('socketexception') ||
      d.contains('failed host lookup') ||
      (d.contains('connection') && d.contains('refused')) ||
      d.contains('network is unreachable')) {
    return 'Network error. Check your connection and try again.';
  }

  if (d.contains('unknown/inactive plan_id') ||
      d.contains('subscription_plans')) {
    return 'This plan is currently unavailable. Please choose another plan.';
  }

  // Configuration / deployment mismatches should not be shown to end users.
  if (d.contains('missing weafrica_paychangu_start_path') ||
      d.contains('missing paychangu_secret_key') ||
      (d.contains('vercel') &&
          (d.contains('authentication required') ||
              d.contains('protection'))) ||
      d.contains('does not implement post') ||
      d.contains('http 404') ||
      d.contains('http 405')) {
    return 'Payments are temporarily unavailable. Please try again later.';
  }

  return 'Payment is unavailable right now. Please try again later.';
}

String _paymentDiagnostics(Object error) {
  final buf = StringBuffer();
  buf.writeln('API base: ${ApiEnv.baseUrl}');
  buf.writeln(
    'Start path: ${AppEnv.payChanguStartPath.isEmpty ? '(missing)' : AppEnv.payChanguStartPath}',
  );

  buf.writeln('Error: $error');

  return buf.toString().trim();
}

String _planNameForPlanId({
  required String planId,
  required List<SubscriptionPlan> plans,
}) {
  final needle = planId.trim();
  if (needle.isEmpty) return '';

  for (final p in plans) {
    if (planIdMatches(p.planId, needle)) {
      final name = p.name.trim();
      return name.isEmpty ? p.planId.trim() : name;
    }
  }

  return displayNameForPlanId(needle);
}

String _currentAccessLabel({
  required SubscriptionMe? me,
  required bool signedIn,
  required String currentPlanName,
}) {
  if (!signedIn) return 'Sign in to view your access.';
  if (me == null) return 'Checking your access…';

  if (isFreeLikePlanId(me.planId)) {
    final name = currentPlanName.trim();
    if (name.isNotEmpty) return 'You are on $name.';
    return 'You are on Free.';
  }

  if (!me.isActive) return 'Your subscription is inactive.';

  final name = currentPlanName.trim();
  if (name.isNotEmpty) return 'You are on $name.';
  return 'Subscription active.';
}

bool _isPaymentIssueStatus(String status) {
  final s = status.trim().toLowerCase();
  return s == 'past_due' ||
      s == 'unpaid' ||
      s == 'incomplete' ||
      s == 'incomplete_expired' ||
      s == 'payment_failed' ||
      s == 'failed';
}

String? _paymentIssueMessage(SubscriptionMe me, {DateTime? now}) {
  if (isFreeLikePlanId(me.planId)) return null;
  if (me.isActive) return null;

  final isPaymentIssue = _isPaymentIssueStatus(me.status);
  if (!isPaymentIssue) return null;

  final current = now ?? DateTime.now();
  final end = me.gracePeriodEnd ?? me.currentPeriodEnd;
  if (end == null) {
    return 'We couldn\'t process your last payment. Retry now to keep your access.';
  }

  final daysLeft = (end.difference(current).inHours / 24).ceil();
  if (daysLeft <= 0) {
    return 'Payment failed and your access has ended. Retry now to restore access.';
  }
  if (daysLeft == 1) {
    return 'Payment failed. Your grace period ends in 1 day.';
  }
  return 'Payment failed. Your grace period ends in $daysLeft days.';
}

Iterable<SubscriptionPlan> _visiblePlans(List<SubscriptionPlan> plans) {
  return plans.where((p) {
    if (isLegacyCompatibilityPlanId(p.planId)) return false;
    final interval = p.billingInterval.trim().toLowerCase();
    if (interval == 'week' || interval == 'weekly') return false;
    return true;
  });
}

String _formatPrice(SubscriptionPlan plan) {
  final interval = plan.billingInterval.trim().toLowerCase();
  final intervalLabel = switch (interval) {
    'week' || 'weekly' => ' / week',
    'month' || 'monthly' => ' / month',
    '' => '',
    _ => ' / $interval',
  };
  final formatted = NumberFormat.decimalPattern().format(plan.priceMwk);

  final currencyLabel = plan.currency.isEmpty ? 'MWK' : plan.currency;
  if (currencyLabel.toUpperCase() == 'MWK') {
    return 'MK $formatted$intervalLabel';
  }
  return '$currencyLabel $formatted$intervalLabel';
}

Widget _hero(
  BuildContext context, {
  required SubscriptionMe? me,
  required bool signedIn,
  required SubscriptionCatalog catalog,
  required String currentPlanName,
  required UserRole? userRole,
}) {
  final scheme = Theme.of(context).colorScheme;
  final now = DateTime.now();
  final paymentIssueMessage =
      (signedIn && me != null) ? _paymentIssueMessage(me, now: now) : null;
  final statusAccent = subscriptionStatusAccent(
    me: me,
    signedIn: signedIn,
    scheme: scheme,
    now: now,
  );
  final isTrialing =
      signedIn && me != null && me.status.trim().toLowerCase() == 'trialing';
  final trialDaysLeft =
      isTrialing ? subscriptionDaysLeftInPeriod(me, now: now) : null;
    final trialMe = me;
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [scheme.primaryContainer, scheme.surface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: scheme.outlineVariant.withAlpha(153)),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          catalog == SubscriptionCatalog.creator
              ? switch (userRole) {
                  UserRole.artist =>
                    'Free gets you in. Platinum makes you visible.',
                  UserRole.dj =>
                    'Start free. Upgrade when you want battles and earnings.',
                  _ =>
                    'Free tests the platform. Platinum holds the real power.',
                }
              : 'Free keeps discovery open. Premium brings freedom. Platinum adds VIP status and control.',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          catalog == SubscriptionCatalog.creator
              ? switch (userRole) {
                  UserRole.artist =>
                    'Keep Free for testing, use Premium for growth, and reserve Platinum for fame, monetization, and live power.',
                  UserRole.dj =>
                    'Keep Free as the trial tier, move to Premium for live sets, and use Platinum for battles, rewards, and top placement.',
                  _ =>
                    'Build the ladder clearly: Free for trial, Premium for progress, Platinum for full power.',
                }
              : 'Use Free for discovery, Premium for freedom (no ads, downloads, background play), and Platinum for VIP status, song requests, priority live access, and bonus coins.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.verified_user, color: statusAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentAccessLabel(
                  me: me,
                  signedIn: signedIn,
                  currentPlanName: currentPlanName,
                ),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (isTrialing && trialDaysLeft != null && trialMe != null) ...[
          const SizedBox(height: 10),
          _trialBanner(
            context,
            accent: subscriptionTrialAccent(daysLeft: trialDaysLeft, scheme: scheme),
            message: subscriptionTrialMessage(trialDaysLeft),
            ctaLabel: signedIn ? 'Upgrade now' : 'Sign in to upgrade',
            onCtaPressed: () async {
              if (!signedIn) {
                await UpgradeFlowManager.instance
                    .ensureSignedInOrNavigateToLogin(context);
                return;
              }

              final subs = SubscriptionsController.instance;
              final plan = subs.planForId(trialMe.planId) ?? subs.currentCatalogPlan;
              if (plan == null) return;
              await UpgradeFlowManager.instance.upgradePlan(
                context: context,
                plan: plan,
                source: 'trial_banner',
              );
            },
          ),
        ],
        if (paymentIssueMessage != null && me != null) ...[
          const SizedBox(height: 10),
          _paymentIssueBanner(
            context,
            message: paymentIssueMessage,
            onRetryPayment: () async {
              final role = switch ((me.audience ?? '').trim().toLowerCase()) {
                'artist' => UserRole.artist,
                'dj' => UserRole.dj,
                _ => UserRole.consumer,
              };

              final plan = await UpgradeFlowManager.instance
                  .resolvePlan(planId: me.planId, role: role);
              if (!context.mounted) return;
              await UpgradeFlowManager.instance.upgradePlan(
                context: context,
                plan: plan,
                source: 'payment_issue_banner',
              );
            },
          ),
        ],
        if (!signedIn) ...[
          const SizedBox(height: 10),
          Text(
            'Sign in to upgrade and sync your access.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    ),
  );
}

Widget _paymentIssueBanner(
  BuildContext context, {
  required String message,
  required Future<void> Function() onRetryPayment,
}) {
  final scheme = Theme.of(context).colorScheme;
  final accent = scheme.error;

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: accent.withAlpha(26),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withAlpha(128)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: () => onRetryPayment(),
          child: const Text('Retry payment'),
        ),
      ],
    ),
  );
}

Widget _trialBanner(
  BuildContext context, {
  required Color accent,
  required String message,
  required String ctaLabel,
  required Future<void> Function() onCtaPressed,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: accent.withAlpha(26),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withAlpha(128)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.hourglass_top, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: () => onCtaPressed(),
          child: Text(ctaLabel),
        ),
      ],
    ),
  );
}

Widget _emptyPlansCard(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: scheme.outlineVariant.withAlpha(153)),
    ),
    child: Text(
      'Plans will appear here when ready.',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

Widget _plansErrorCard(BuildContext context, {required VoidCallback onRetry}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: scheme.outlineVariant.withAlpha(153)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unable to load plans',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Check your internet connection and try again.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.currentPlanId,
    required this.signedIn,
    required this.onUpgrade,
  });

  final SubscriptionPlan plan;
  final String currentPlanId;
  final bool signedIn;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tier = subscriptionTierForPlanId(plan.planId);
    final isCurrent = planIdMatches(plan.planId, currentPlanId);

    final accent = subscriptionTierAccent(tier, scheme);

    final gradientLead = switch (tier) {
      SubscriptionTier.premium => accent.withAlpha(38),
      SubscriptionTier.platinum => accent.withAlpha(38),
      SubscriptionTier.free => scheme.surface,
      SubscriptionTier.other => scheme.primaryContainer,
    };
    final bg = LinearGradient(
      colors: [gradientLead, scheme.surface],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final planDisplayName = displayNameForPlanId(plan.planId);
    final titleText = planDisplayName.isNotEmpty
        ? planDisplayName
        : (plan.name.isEmpty ? plan.planId : plan.name);

    final bullets = _marketingBulletsFor(plan);

    return Container(
      decoration: BoxDecoration(
        gradient: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withAlpha(153)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _pill(
                          context,
                          _pillLabelForTier(tier),
                          accent: accent,
                        ),
                      ],
                    ),
                    if ((plan.marketingTagline ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        plan.marketingTagline!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatPrice(plan),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (plan.billingInterval.trim().isEmpty)
                    Text(
                      'per month',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bullets
              .take(8)
              .map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle, size: 18, color: accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(b)),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [_SmallChip(label: 'Cancel anytime')],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (isCurrent)
                const _SmallChip(label: 'Current plan')
              else
                Expanded(
                  child: FilledButton(
                    style: (tier == SubscriptionTier.premium ||
                            tier == SubscriptionTier.platinum)
                        ? FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: ThemeData
                                        .estimateBrightnessForColor(accent) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black,
                          )
                        : null,
                    onPressed: signedIn ? onUpgrade : null,
                    child: Text(
                      _ctaLabelForPlan(plan: plan, signedIn: signedIn),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _pill(BuildContext context, String text, {required Color accent}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(140)),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(230),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withAlpha(153)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _pillLabelForTier(SubscriptionTier tier) {
  switch (tier) {
    case SubscriptionTier.free:
      return 'ENTRY';
    case SubscriptionTier.premium:
      return 'UPGRADE';
    case SubscriptionTier.platinum:
      return 'POWER TIER';
    case SubscriptionTier.other:
      return 'PLAN';
  }
}

String _ctaLabelForPlan({
  required SubscriptionPlan plan,
  required bool signedIn,
}) {
  if (!signedIn) {
    return plan.isFree ? 'Sign in to continue' : 'Sign in to upgrade';
  }

  final planDisplayName = displayNameForPlanId(plan.planId);
  final labelName = planDisplayName.isNotEmpty
      ? planDisplayName
      : (plan.name.isEmpty ? plan.planId : plan.name);

  switch (subscriptionTierForPlanId(plan.planId)) {
    case SubscriptionTier.free:
      return 'Continue Free';
    case SubscriptionTier.premium:
      return 'Upgrade to $labelName';
    case SubscriptionTier.platinum:
      return 'Go $labelName';
    case SubscriptionTier.other:
      return 'Choose $labelName';
  }
}

List<String> _marketingBulletsFor(SubscriptionPlan plan) {
  if (plan.marketingBullets.isNotEmpty) return plan.marketingBullets;

  switch (canonicalPlanId(plan.planId)) {
    case 'artist_starter':
      return const [
        'Upload up to 5 songs per month',
        'Basic creator analytics while you build traction',
        'Watch battles now and upgrade later for monetization',
      ];
    case 'artist_pro':
      return const [
        'Upload up to 20 songs and 5 videos each month',
        'Go live, join standard battles, and monetize releases',
        'Sell standard tickets with limited withdrawals',
      ];
    case 'artist_premium':
      return const [
        'Unlimited uploads with bulk publishing and priority battles',
        'Advanced analytics, fan support, and unlimited withdrawals',
        'Sell VIP and priority tickets plus 200 monthly bonus coins',
      ];
    case 'dj_starter':
      return const [
        'Upload up to 5 mixes while you build your crowd',
        'Basic DJ analytics with no live hosting yet',
        'Upgrade when you are ready for monetization and battles',
      ];
    case 'dj_pro':
      return const [
        'Unlimited mix uploads plus live DJ sets and standard battles',
        'Monetize through streams, live gifts, and standard tickets',
        'Medium analytics with limited withdrawals',
      ];
    case 'dj_premium':
      return const [
        'Unlimited bulk uploads with priority battles and crowd controls',
        'Advanced analytics, full monetization, and unlimited withdrawals',
        'Sell VIP and priority tickets plus 200 monthly bonus coins',
      ];
  }

  // Fallback copy (only if backend does not provide marketing bullets yet).
  // Prefer returning this from the admin-controlled plans API.
  switch (subscriptionTierForPlanId(plan.planId)) {
    case SubscriptionTier.free:
      return const [
        'Start free with ads and limited control',
        'Built for discovery and casual listening',
        'Upgrade when you want ad-free freedom',
      ];
    case SubscriptionTier.platinum:
      return const [
        'Status tier with VIP badge and highlighted comments',
        'Priority live access, VIP gifts, and song requests',
        'Exclusive drops plus monthly bonus coins',
      ];
    case SubscriptionTier.premium:
      return const [
        'Freedom tier: no ads, downloads, and background play',
        'Standard gifts with full live interaction',
        'Limited early-access drops before full release',
      ];
    case SubscriptionTier.other:
      return const ['Uninterrupted listening', 'Offline downloads'];
  }
}

class _ComparisonRow {
  const _ComparisonRow({
    required this.label,
    required this.free,
    required this.premium,
    required this.platinum,
  });

  final String label;
  final String free;
  final String premium;
  final String platinum;
}

Widget _comparisonTable(BuildContext context, {required UserRole? userRole}) {
  final scheme = Theme.of(context).colorScheme;
  final rows = _comparisonRowsFor(userRole);
  final strategyNote = userRole == UserRole.consumer || userRole == null
      ? 'Free drives discovery, Premium sells freedom, and Platinum sells status plus control.'
      : 'Keep Free as the test tier, make Premium the improvement tier, and reserve Platinum for the real power.';

  Widget buildCell(String text, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: header
            ? Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)
            : Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  return Container(
    margin: const EdgeInsets.only(top: 8),
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: scheme.outlineVariant.withAlpha(153)),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plan comparison',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          strategyNote,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.6),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
          },
          border: TableBorder(
            horizontalInside: BorderSide(
              color: scheme.outlineVariant.withAlpha(102),
            ),
          ),
          children: [
            TableRow(
              children: [
                buildCell('Feature', header: true),
                buildCell('Free', header: true),
                buildCell('Premium', header: true),
                buildCell('Platinum', header: true),
              ],
            ),
            ...rows.map(
              (row) => TableRow(
                children: [
                  buildCell(row.label, header: true),
                  buildCell(row.free),
                  buildCell(row.premium),
                  buildCell(row.platinum),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

List<_ComparisonRow> _comparisonRowsFor(UserRole? userRole) {
  switch (userRole) {
    case UserRole.artist:
      return const [
        _ComparisonRow(
          label: 'Upload limit',
          free: '5 songs / month',
          premium: '20 songs / month',
          platinum: 'Unlimited + bulk',
        ),
        _ComparisonRow(
          label: 'Video upload',
          free: '5 videos / month',
          premium: '5 videos / month',
          platinum: 'Unlimited',
        ),
        _ComparisonRow(
          label: 'Live streaming',
          free: 'No',
          premium: 'Host live',
          platinum: 'Live + multi-guest',
        ),
        _ComparisonRow(
          label: 'Battles',
          free: '1 battle / week (10 min max)',
          premium: 'Standard access',
          platinum: 'Priority access',
        ),
        _ComparisonRow(
          label: 'Monetization',
          free: 'None',
          premium: 'Streams + coins',
          platinum: 'Full + fan support',
        ),
        _ComparisonRow(
          label: 'Ticket selling',
          free: 'No',
          premium: 'Standard tickets',
          platinum: 'VIP + priority',
        ),
        _ComparisonRow(
          label: 'Withdrawals',
          free: 'No',
          premium: 'Limited',
          platinum: 'Unlimited',
        ),
        _ComparisonRow(
          label: 'Analytics',
          free: 'Basic',
          premium: 'Medium',
          platinum: 'Advanced',
        ),
        _ComparisonRow(
          label: 'Monthly bonus coins',
          free: '0',
          premium: '0',
          platinum: '200',
        ),
        _ComparisonRow(
          label: 'VIP badge',
          free: 'No',
          premium: 'No',
          platinum: 'Yes',
        ),
      ];
    case UserRole.dj:
      return const [
        _ComparisonRow(
          label: 'Mix uploads',
          free: '5 mixes / month',
          premium: 'Unlimited',
          platinum: 'Unlimited + bulk',
        ),
        _ComparisonRow(
          label: 'Live DJ sets',
          free: 'No',
          premium: 'Yes',
          platinum: 'Yes + crowd tools',
        ),
        _ComparisonRow(
          label: 'DJ battles',
          free: '1 battle / week (10 min max)',
          premium: 'Standard access',
          platinum: 'Priority access',
        ),
        _ComparisonRow(
          label: 'Monetization',
          free: 'None',
          premium: 'Streams + live gifts',
          platinum: 'Full + fan support',
        ),
        _ComparisonRow(
          label: 'Ticket hosting',
          free: 'No',
          premium: 'Standard tickets',
          platinum: 'VIP + priority',
        ),
        _ComparisonRow(
          label: 'Withdrawals',
          free: 'No',
          premium: 'Limited',
          platinum: 'Unlimited',
        ),
        _ComparisonRow(
          label: 'Analytics',
          free: 'Basic',
          premium: 'Medium',
          platinum: 'Advanced',
        ),
        _ComparisonRow(
          label: 'Monthly bonus coins',
          free: '0',
          premium: '0',
          platinum: '200',
        ),
        _ComparisonRow(
          label: 'VIP badge',
          free: 'No',
          premium: 'No',
          platinum: 'Yes',
        ),
      ];
    case UserRole.consumer:
    case null:
      return const [
        _ComparisonRow(
          label: 'Ads',
          free: 'Yes',
          premium: 'No',
          platinum: 'No',
        ),
        _ComparisonRow(
          label: 'Audio quality',
          free: 'Standard',
          premium: 'High / 320 kbps',
          platinum: 'Studio / ultra',
        ),
        _ComparisonRow(
          label: 'Skips',
          free: 'Limited',
          premium: 'Unlimited',
          platinum: 'Unlimited',
        ),
        _ComparisonRow(
          label: 'Background play',
          free: 'No',
          premium: 'Yes',
          platinum: 'Yes',
        ),
        _ComparisonRow(
          label: 'Audio downloads',
          free: 'No',
          premium: 'Yes',
          platinum: 'Yes',
        ),
        _ComparisonRow(
          label: 'Video downloads',
          free: 'No',
          premium: 'No',
          platinum: 'Yes',
        ),
        _ComparisonRow(
          label: 'Gifts',
          free: 'Light gifts only',
          premium: 'Standard gifts',
          platinum: 'VIP gifts',
        ),
        _ComparisonRow(
          label: 'Live perks',
          free: 'Watch only',
          premium: 'Watch + interact',
          platinum: 'Priority + requests',
        ),
        _ComparisonRow(
          label: 'Fan status',
          free: 'Standard',
          premium: 'Premium listener',
          platinum: 'VIP badge + highlight',
        ),
        _ComparisonRow(
          label: 'Exclusive + early content',
          free: 'No',
          premium: 'Limited early access',
          platinum: 'Exclusive + early',
        ),
        _ComparisonRow(
          label: 'Bonus coins',
          free: '0 (top-up anytime)',
          premium: '0 (top-up anytime)',
          platinum: '200 / month + top-up',
        ),
      ];
  }
}
