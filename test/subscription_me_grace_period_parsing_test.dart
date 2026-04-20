import 'package:flutter_test/flutter_test.dart';

import 'package:weafrica_music/features/subscriptions/models/subscription_me.dart';

void main() {
  test('SubscriptionMe.fromJson parses grace_period_end when present', () {
    final me = SubscriptionMe.fromJson({
      'plan_id': 'premium',
      'status': 'past_due',
      'grace_period_end': '2026-03-25T12:00:00Z',
      'entitlements': const <String, dynamic>{},
    });

    expect(me.status.toLowerCase(), 'past_due');
    expect(me.gracePeriodEnd, isNotNull);
    expect(me.gracePeriodEnd!.toUtc().toIso8601String(), '2026-03-25T12:00:00.000Z');
  });
}
