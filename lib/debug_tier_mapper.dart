import 'package:flutter/material.dart';

import 'features/artist_dashboard/models/artist_subscription_tier.dart';
import 'features/subscriptions/subscriptions_controller.dart';

class TierMapperDebug extends StatefulWidget {
  const TierMapperDebug({super.key, required this.child});

  final Widget child;

  @override
  State<TierMapperDebug> createState() => _TierMapperDebugState();
}

class _TierMapperDebugState extends State<TierMapperDebug> {
  late final SubscriptionsController _controller;
  String? _lastSnapshot;

  @override
  void initState() {
    super.initState();
    _controller = SubscriptionsController.instance;
    _controller.addListener(_logTierInfo);
    WidgetsBinding.instance.addPostFrameCallback((_) => _logTierInfo());
  }

  @override
  void dispose() {
    _controller.removeListener(_logTierInfo);
    super.dispose();
  }

  void _logTierInfo() {
    final me = _controller.me;
    final rawPlanId = me?.planId ?? 'none';
    final effectivePlanId = _controller.effectivePlanId;
    final status = me?.status ?? (_controller.loadingMe ? 'loading' : 'none');
    final tier = artistTierForPlanId(effectivePlanId);
    final spec = ArtistSubscriptionCatalog.specForTier(tier);
    final snapshot =
        '$status|$rawPlanId|$effectivePlanId|${tier.name}|${spec.tierDisplayName}';
    if (_lastSnapshot == snapshot) return;
    _lastSnapshot = snapshot;

    debugPrint(
      'Tier mapping: status=$status raw_plan=$rawPlanId '
      'effective_plan=$effectivePlanId tier=${tier.name} '
      'display=${spec.tierDisplayName}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 160,
          right: 10,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final me = _controller.me;
                final rawPlanId = me?.planId ?? 'none';
                final effectivePlanId = _controller.effectivePlanId;
                final status =
                    me?.status ?? (_controller.loadingMe ? 'loading' : 'none');
                final tier = artistTierForPlanId(effectivePlanId);
                final spec = ArtistSubscriptionCatalog.specForTier(tier);

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xE61A1A1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4FD1C5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'TIER DEBUG',
                              style: TextStyle(
                                color: Color(0xFF4FD1C5),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('status: $status'),
                            Text('raw: $rawPlanId'),
                            Text('effective: $effectivePlanId'),
                            Text(
                              'tier: ${tier.name}',
                              style: TextStyle(
                                color: tier == ArtistSubscriptionTier.platinum
                                    ? const Color(0xFF68D391)
                                    : const Color(0xFFF6AD55),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text('display: ${spec.tierDisplayName}'),
                            Text(
                              'entitlements: ${me?.entitlements.raw.isNotEmpty == true ? 'present' : 'empty'}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
