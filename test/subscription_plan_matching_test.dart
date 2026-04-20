import 'package:flutter_test/flutter_test.dart';
import 'package:weafrica_music/features/subscriptions/models/subscription_plan.dart';

void main() {
  group('SubscriptionPlan.fromJson', () {
    test('parses audience, perks, and trial metadata from API payloads', () {
      final plan = SubscriptionPlan.fromJson({
        'plan_id': 'artist_starter',
        'audience': 'artist',
        'name': 'Artist Free',
        'price_mwk': 0,
        'billing_interval': 'month',
        'features': {
          'creator': {
            'tier': 'free',
          },
        },
        'perks': {
          'creator': {
            'uploads': {'songs': 5, 'videos': 0},
          },
        },
        'trial_eligible': true,
        'trial_duration_days': 30,
      });

      expect(plan.planId, 'artist_starter');
      expect(plan.audience, 'artist');
      expect(plan.perks['creator'], isA<Map>());
      expect(plan.trialEligible, isTrue);
      expect(plan.trialDurationDays, 30);
      expect(plan.hasTrialOffer, isTrue);
    });

    test('falls back to canonical audience and trial defaults for starter plans', () {
      final plan = SubscriptionPlan.fromJson({
        'plan_id': 'dj_starter',
        'name': 'DJ Free',
        'price_mwk': 0,
        'billing_interval': 'month',
      });

      expect(plan.audience, 'dj');
      expect(plan.trialEligible, isTrue);
      expect(plan.trialDurationDays, 30);
    });
  });

  group('normalizePlanKey', () {
    test('keeps single-token IDs', () {
      expect(normalizePlanKey('premium'), 'premium');
      expect(normalizePlanKey('Premium'), 'premium');
      expect(normalizePlanKey('  premium  '), 'premium');
    });

    test('drops interval suffix tokens', () {
      expect(normalizePlanKey('premium_weekly'), 'premium');
      expect(normalizePlanKey('premium-monthly'), 'premium');
      expect(normalizePlanKey('family month'), 'family');
      expect(normalizePlanKey('platinum_annual'), 'platinum');
    });

    test('preserves multi-token tier IDs', () {
      expect(normalizePlanKey('artist_premium'), 'artist_premium');
      expect(normalizePlanKey('artist_pro_monthly'), 'artist_pro');
      expect(normalizePlanKey('dj_plus_weekly'), 'dj_plus');
    });

    test('normalizes VIP aliases through canonicalPlanId', () {
      expect(canonicalPlanId('vip'), 'platinum');
      expect(canonicalPlanId('VIP Listener'), 'platinum');
    });
  });

  group('planIdMatches', () {
    test('matches exact IDs', () {
      expect(planIdMatches('premium', 'premium'), isTrue);
      expect(planIdMatches('artist_pro', 'artist_pro'), isTrue);
    });

    test('matches interval variants', () {
      expect(planIdMatches('premium_weekly', 'premium'), isTrue);
      expect(planIdMatches('premium_weekly', 'premium_monthly'), isTrue);
      expect(planIdMatches('platinum', 'platinum_annual'), isTrue);
      expect(planIdMatches('vip', 'platinum'), isTrue);
    });

    test('does not collide creator tiers', () {
      expect(planIdMatches('artist_premium', 'artist_pro'), isFalse);
      expect(planIdMatches('dj_plus', 'dj_pro'), isFalse);
    });

    test('empty values never match', () {
      expect(planIdMatches('', 'premium'), isFalse);
      expect(planIdMatches('premium', ''), isFalse);
      expect(planIdMatches(' ', ' '), isFalse);
    });
  });

  group('isFreeLikePlanId', () {
    test('treats starter plans as free-like', () {
      expect(isFreeLikePlanId('free'), isTrue);
      expect(isFreeLikePlanId('artist_starter'), isTrue);
      expect(isFreeLikePlanId('dj_starter'), isTrue);
      expect(isFreeLikePlanId('premium'), isFalse);
    });
  });
}
