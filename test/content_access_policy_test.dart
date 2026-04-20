import 'package:flutter_test/flutter_test.dart';

import 'package:weafrica_music/features/subscriptions/models/subscription_me.dart';
import 'package:weafrica_music/services/content_access_policy.dart';

void main() {
  group('ContentAccessPolicy', () {
    test('allows everything when access is standard', () {
      const entitlements = Entitlements(
        contentAccess: 'standard',
        contentLimitRatio: 0.0,
        exclusiveContentEnabled: false,
      );

      final decision = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'any',
        isExclusive: false,
      );

      expect(decision.allowed, isTrue);
      expect(decision.reason, isNull);
    });

    test('blocks exclusive content when not enabled', () {
      const entitlements = Entitlements(
        contentAccess: 'standard',
        exclusiveContentEnabled: false,
      );

      final decision = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'track_1',
        isExclusive: true,
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, ContentAccessBlockReason.exclusive);
    });

    test('allows exclusive content when enabled', () {
      const entitlements = Entitlements(
        contentAccess: 'standard',
        exclusiveContentEnabled: true,
      );

      final decision = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'track_1',
        isExclusive: true,
      );

      expect(decision.allowed, isTrue);
      expect(decision.reason, isNull);
    });

    test('ratio=0 blocks all non-exclusive when limited', () {
      const entitlements = Entitlements(
        contentAccess: 'limited',
        contentLimitRatio: 0.0,
        exclusiveContentEnabled: true,
      );

      final decision = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'track_1',
        isExclusive: false,
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, ContentAccessBlockReason.ratio);
    });

    test('ratio=1 allows all non-exclusive when limited', () {
      const entitlements = Entitlements(
        contentAccess: 'limited',
        contentLimitRatio: 1.0,
        exclusiveContentEnabled: false,
      );

      final decision = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'track_1',
        isExclusive: false,
      );

      expect(decision.allowed, isTrue);
      expect(decision.reason, isNull);
    });

    test('ratio gating is stable per user and can vary across users', () {
      const entitlements = Entitlements(
        contentAccess: 'limited',
        contentLimitRatio: 0.3,
        exclusiveContentEnabled: false,
      );

      // Stability for the same userKey.
      final d1 = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'track_123',
        isExclusive: false,
        userKey: 'user_a',
      );
      final d2 = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: 'track_123',
        isExclusive: false,
        userKey: 'user_a',
      );
      expect(d1.allowed, d2.allowed);
      expect(d1.reason, d2.reason);

      // Find at least one contentId that differs between two userKeys.
      bool foundDifference = false;
      for (var i = 0; i < 5000; i++) {
        final id = 'track_$i';
        final a = ContentAccessPolicy.decide(
          entitlements: entitlements,
          contentId: id,
          isExclusive: false,
          userKey: 'user_a',
        );
        final b = ContentAccessPolicy.decide(
          entitlements: entitlements,
          contentId: id,
          isExclusive: false,
          userKey: 'user_b',
        );
        if (a.allowed != b.allowed) {
          foundDifference = true;
          break;
        }
      }

      expect(foundDifference, isTrue);
    });
  });
}
