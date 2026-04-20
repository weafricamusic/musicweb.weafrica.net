import '../../subscriptions/subscriptions_controller.dart';
import '../models/artist_subscription_tier.dart';

/// Lightweight adapter that maps the current backend subscription into
/// the UX-facing artist tier model (Free / Premium / Platinum).
class ArtistSubscriptionService {
  ArtistSubscriptionService({SubscriptionsController? subscriptions})
      : _subscriptions = subscriptions ?? SubscriptionsController.instance;

  final SubscriptionsController _subscriptions;

  String get effectivePlanId => _subscriptions.effectivePlanId;

  ArtistSubscriptionTier get tier => artistTierForPlanId(effectivePlanId);

  ArtistSubscriptionPlanSpec get spec => ArtistSubscriptionCatalog.specForTier(tier);
}
