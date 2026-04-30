import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../subscriptions/models/gifting_tier.dart';
import '../../subscriptions/services/consumer_entitlement_gate.dart';
import '../models/live_gift.dart';

class LiveGiftSheet extends StatelessWidget {
  const LiveGiftSheet({
    super.key,
    required this.gifts,
    required this.coinBalance,
    required this.walletLoading,
  });

  final List<LiveGift> gifts;
  final int? coinBalance;
  final bool walletLoading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'SEND A GIFT',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (walletLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      'Coins: ${coinBalance ?? 0}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: gifts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final g = gifts[index];
                  final gateDecision = ConsumerEntitlementGate.instance
                      .checkGiftTier(requiredTier: g.accessTier);
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      if (!gateDecision.allowed) {
                        await ConsumerEntitlementGate.instance.ensureGiftTier(
                          context,
                          requiredTier: g.accessTier,
                        );
                        return;
                      }

                      if (!context.mounted) return;
                      Navigator.of(context).pop(g);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  g.name.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (g.accessTier != GiftAccessTier.limited)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${giftAccessTierLabel(g.accessTier)} gift',
                                      style: TextStyle(
                                        color: gateDecision.allowed
                                            ? AppColors.textMuted
                                            : AppColors.warning,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!gateDecision.allowed)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.lock,
                                size: 16,
                                color: AppColors.warning,
                              ),
                            ),
                          Text(
                            '${g.coinValue} coins',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}