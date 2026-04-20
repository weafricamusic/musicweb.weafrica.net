import 'package:flutter_test/flutter_test.dart';
import 'package:weafrica_music/features/artist_dashboard/models/artist_subscription_tier.dart';

void main() {
  group('artistTierForPlanId', () {
    test('maps canonical artist plans to the expected dashboard tiers', () {
      expect(artistTierForPlanId('artist_starter'), ArtistSubscriptionTier.free);
      expect(artistTierForPlanId('artist_pro'), ArtistSubscriptionTier.premium);
      expect(artistTierForPlanId('artist_premium'), ArtistSubscriptionTier.platinum);
      expect(artistTierForPlanId('artist_free'), ArtistSubscriptionTier.free);
    });
  });

  group('ArtistSubscriptionCatalog', () {
    test('matches canonical creator pricing and upload limits', () {
      expect(ArtistSubscriptionCatalog.free.tierDisplayName, 'Artist Free');
      expect(ArtistSubscriptionCatalog.free.monthlyPriceMwk, 0);
      expect(ArtistSubscriptionCatalog.free.songUploadsPerMonth, 5);
      expect(ArtistSubscriptionCatalog.free.videoUploadsPerMonth, 0);

      expect(ArtistSubscriptionCatalog.premium.tierDisplayName, 'Artist Pro');
      expect(ArtistSubscriptionCatalog.premium.monthlyPriceMwk, 6000);
      expect(ArtistSubscriptionCatalog.premium.songUploadsPerMonth, 20);
      expect(ArtistSubscriptionCatalog.premium.videoUploadsPerMonth, 5);

      expect(ArtistSubscriptionCatalog.platinum.tierDisplayName, 'Artist Premium');
      expect(ArtistSubscriptionCatalog.platinum.monthlyPriceMwk, 12500);
      expect(ArtistSubscriptionCatalog.platinum.songUploadsPerMonth, isNull);
      expect(ArtistSubscriptionCatalog.platinum.videoUploadsPerMonth, isNull);
      expect(ArtistSubscriptionCatalog.platinum.bulkUploadEnabled, isTrue);
      expect(ArtistSubscriptionCatalog.platinum.monthlyBonusCoins, 200);
      expect(ArtistSubscriptionCatalog.platinum.vipBadgeEnabled, isTrue);
    });

    test('locks supporter tiers until platinum while keeping premium battle access', () {
      expect(ArtistSubscriptionCatalog.free.canUseFanClub, isFalse);
      expect(ArtistSubscriptionCatalog.premium.canUseFanClub, isFalse);
      expect(ArtistSubscriptionCatalog.platinum.canUseFanClub, isTrue);

      expect(ArtistSubscriptionCatalog.free.canJoinBattles, isFalse);
      expect(ArtistSubscriptionCatalog.premium.canJoinBattles, isTrue);
      expect(ArtistSubscriptionCatalog.platinum.canJoinBattles, isTrue);
    });
  });
}