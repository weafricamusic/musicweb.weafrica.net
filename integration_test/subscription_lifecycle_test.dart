import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:weafrica_music/app/app_root.dart';
import 'package:weafrica_music/features/subscriptions/models/subscription_me.dart';
import 'package:weafrica_music/features/subscriptions/models/subscription_plan.dart';
import 'package:weafrica_music/features/subscriptions/services/subscriptions_api.dart';
import 'package:weafrica_music/features/subscriptions/subscription_screen.dart';
import 'package:weafrica_music/features/subscriptions/subscriptions_controller.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

class _FakeSubscriptionsApiDelegate implements SubscriptionsApiDelegate {
  _FakeSubscriptionsApiDelegate({
    required this.plans,
    required SubscriptionMe initialMe,
  }) : _me = initialMe;

  final List<SubscriptionPlan> plans;

  SubscriptionMe _me;

  set me(SubscriptionMe value) {
    _me = value;
  }

  @override
  Future<List<SubscriptionPlan>> fetchPlans({required String audience}) async {
    return plans;
  }

  @override
  Future<SubscriptionMe> fetchMe({String? idToken}) async {
    return _me;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSubscriptionsApiDelegate delegate;

  setUp(() {
    final consumerPlans = <SubscriptionPlan>[
      const SubscriptionPlan(
        planId: 'free',
        name: 'Free',
        priceMwk: 0,
        billingInterval: 'month',
        audience: 'consumer',
      ),
      const SubscriptionPlan(
        planId: 'premium',
        name: 'Premium',
        priceMwk: 5000,
        billingInterval: 'month',
        audience: 'consumer',
      ),
      const SubscriptionPlan(
        planId: 'platinum',
        name: 'Platinum',
        priceMwk: 10000,
        billingInterval: 'month',
        audience: 'consumer',
      ),
    ];

    final trialMe = SubscriptionMe(
      planId: 'premium',
      status: 'trialing',
      entitlements: Entitlements.defaultsForPlanId('premium'),
      raw: const <String, dynamic>{},
      currentPeriodEnd: DateTime.now().add(const Duration(days: 5)),
    );

    delegate = _FakeSubscriptionsApiDelegate(plans: consumerPlans, initialMe: trialMe);
    SubscriptionsApi.delegate = delegate;
  });

  tearDown(() {
    SubscriptionsApi.delegate = null;
  });

  testWidgets('Subscription lifecycle: trial → active → inactive → grace', (tester) async {
    await tester.pumpWidget(
      const MyApp(
        homeOverride: SubscriptionScreen(
          showAppBar: false,
          signedInOverride: true,
        ),
      ),
    );

    // Initial load should show trial banner.
    await _pumpUntilFound(tester, find.textContaining('Your trial ends'));
    expect(find.textContaining('Your trial ends'), findsOneWidget);
    expect(find.text('Upgrade now'), findsOneWidget);
    expect(find.text('You are on Premium.'), findsOneWidget);

    // Upgrade: active should remove trial banner.
    delegate.me = SubscriptionMe(
      planId: 'premium',
      status: 'active',
      entitlements: Entitlements.defaultsForPlanId('premium'),
      raw: const <String, dynamic>{},
      currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
    );
    await SubscriptionsController.instance.refreshMe();
    await tester.pumpAndSettle();

    expect(find.textContaining('Your trial ends'), findsNothing);
    expect(find.text('You are on Premium.'), findsOneWidget);

    // Expiry/cancel: inactive status should show inactive label.
    delegate.me = SubscriptionMe(
      planId: 'premium',
      status: 'canceled',
      entitlements: Entitlements.defaultsForPlanId('premium'),
      raw: const <String, dynamic>{},
      currentPeriodEnd: DateTime.now().subtract(const Duration(days: 1)),
    );
    await SubscriptionsController.instance.refreshMe();
    await tester.pumpAndSettle();

    expect(find.text('Your subscription is inactive.'), findsOneWidget);

    // Grace / payment issue: past_due should show retry banner.
    delegate.me = SubscriptionMe(
      planId: 'premium',
      status: 'past_due',
      entitlements: Entitlements.defaultsForPlanId('premium'),
      raw: const <String, dynamic>{},
      gracePeriodEnd: DateTime.now().add(const Duration(days: 2)),
    );
    await SubscriptionsController.instance.refreshMe();
    await tester.pumpAndSettle();

    expect(find.textContaining('Payment failed'), findsOneWidget);
    expect(find.text('Retry payment'), findsOneWidget);
  });
}
