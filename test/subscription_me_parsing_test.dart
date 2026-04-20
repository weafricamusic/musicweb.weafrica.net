import 'package:flutter_test/flutter_test.dart';
import 'package:weafrica_music/features/subscriptions/models/subscription_me.dart';

void main() {
  group('SubscriptionMe.fromJson', () {
    test('parses flattened creator premium entitlements from /me', () {
      final me = SubscriptionMe.fromJson({
        'ok': true,
        'plan_id': 'artist_premium',
        'status': 'active',
        'entitlements': {
          'ads_enabled': false,
          'interstitial_every_songs': 0,
          'perks': {
            'ads': {'enabled': false, 'interstitial_every_songs': 0},
            'creator': {
              'uploads': {'songs': 'unlimited', 'videos': 'unlimited'},
              'monetization': {
                'streams': true,
                'coins': true,
                'live': true,
                'battles': true,
              },
              'withdrawals': {'access': 'unlimited'},
              'live': {'enabled': true, 'battles': true},
            },
          },
        },
      });

      expect(me.planId, 'artist_premium');
      expect(me.status, 'active');
      expect(me.isActive, isTrue);

      final entitlements = me.entitlements;
      expect(entitlements.adsEnabled, isFalse);
      expect(entitlements.effectiveAdsEnabled, isFalse);
      expect(entitlements.interstitialEverySongs, 0);
      expect(entitlements.effectiveInterstitialEverySongs, 0);

      expect(
        entitlements.creatorTrackUploadLimit(
          'artist',
          fallbackPlanId: me.planId,
        ),
        -1,
      );
      expect(
        entitlements.creatorVideoUploadLimit(
          'artist',
          fallbackPlanId: me.planId,
        ),
        -1,
      );
      expect(entitlements.creatorCanGoLive(fallbackPlanId: me.planId), isTrue);
      expect(entitlements.creatorCanBattle(fallbackPlanId: me.planId), isTrue);
      expect(
        entitlements.creatorCanMonetize(fallbackPlanId: me.planId),
        isTrue,
      );
      expect(
        entitlements.creatorWithdrawalAccess(fallbackPlanId: me.planId),
        'unlimited',
      );
      expect(
        entitlements.creatorCanWithdraw(fallbackPlanId: me.planId),
        isTrue,
      );
    });

    test(
      'supports wrapped subscription payloads with top-level entitlements',
      () {
        final me = SubscriptionMe.fromJson({
          'subscription': {'plan_id': 'dj_premium', 'status': 'trialing'},
          'entitlements': {
            'ads_enabled': false,
            'perks': {
              'creator': {
                'uploads': {'mixes': 'unlimited'},
                'withdrawals': {'access': 'unlimited'},
                'live': {'enabled': true, 'battles': true},
              },
            },
          },
        });

        expect(me.planId, 'dj_premium');
        expect(me.isActive, isTrue);
        expect(
          me.entitlements.creatorTrackUploadLimit(
            'dj',
            fallbackPlanId: me.planId,
          ),
          -1,
        );
        expect(
          me.entitlements.creatorWithdrawalAccess(fallbackPlanId: me.planId),
          'unlimited',
        );
      },
    );

    test(
      'reads plan_id from top-level plan payloads when subscription is null',
      () {
        final me = SubscriptionMe.fromJson({
          'ok': true,
          'subscription': null,
          'plan': {'plan_id': 'artist_premium', 'name': 'Artist Platinum'},
          'entitlements': {
            'features': {
              'creator': {'tier': 'platinum'},
            },
          },
        });

        expect(me.planId, 'artist_premium');
        expect(me.status, 'inactive');
        expect(me.isActive, isFalse);
        expect(me.entitlements.raw, isNotEmpty);
      },
    );

    test('parses optional audience and trial metadata from /me plan payloads', () {
      final me = SubscriptionMe.fromJson({
        'ok': true,
        'subscription': null,
        'plan': {
          'plan_id': 'dj_starter',
          'audience': 'dj',
          'trial_eligible': true,
          'trial_duration_days': 30,
        },
        'entitlements': {
          'features': {
            'creator': {
              'tier': 'free',
            },
          },
        },
      });

      expect(me.planId, 'dj_starter');
      expect(me.audience, 'dj');
      expect(me.trialEligible, isTrue);
      expect(me.trialDurationDays, 30);
      expect(me.hasTrialOffer, isTrue);
    });

    test('parses current_period_end when present', () {
      final me = SubscriptionMe.fromJson({
        'ok': true,
        'plan_id': 'premium',
        'status': 'trialing',
        'current_period_end': '2030-01-15T00:00:00.000Z',
        'entitlements': const <String, dynamic>{},
      });

      expect(me.currentPeriodEnd, isNotNull);
      expect(
        me.currentPeriodEnd!.toUtc().toIso8601String(),
        '2030-01-15T00:00:00.000Z',
      );
    });

    test(
      'uses canonical creator fallback limits when entitlements are empty',
      () {
        const entitlements = Entitlements();

        expect(
          entitlements.creatorTrackUploadLimit(
            'artist',
            fallbackPlanId: 'artist_starter',
          ),
          5,
        );
        expect(
          entitlements.creatorVideoUploadLimit(
            'artist',
            fallbackPlanId: 'artist_starter',
          ),
          5,
        );
        expect(
          entitlements.creatorTrackUploadLimit(
            'artist',
            fallbackPlanId: 'artist_pro',
          ),
          -1,
        );
        expect(
          entitlements.creatorVideoUploadLimit(
            'artist',
            fallbackPlanId: 'artist_pro',
          ),
          30,
        );
        expect(
          entitlements.creatorTrackUploadLimit(
            'dj',
            fallbackPlanId: 'dj_starter',
          ),
          5,
        );
        expect(
          entitlements.creatorTrackUploadLimit('dj', fallbackPlanId: 'dj_pro'),
          -1,
        );
      },
    );

    test('treats creator Premium tiers as battle-enabled in fallback mode', () {
      const entitlements = Entitlements();

      expect(
        entitlements.creatorCanBattle(fallbackPlanId: 'artist_pro'),
        isTrue,
      );
      expect(entitlements.creatorCanBattle(fallbackPlanId: 'dj_pro'), isTrue);
      expect(
        entitlements.creatorCanBattle(fallbackPlanId: 'artist_starter'),
        isFalse,
      );
      expect(
        entitlements.creatorCanBattle(fallbackPlanId: 'dj_starter'),
        isFalse,
      );
    });
  });
}
