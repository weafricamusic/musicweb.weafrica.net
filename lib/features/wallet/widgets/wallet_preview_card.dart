import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class WalletPreviewCard extends StatelessWidget {
  const WalletPreviewCard({
    super.key,
    required this.balance,
    required this.onTap,
  });

  final int? balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balanceLabel = balance == null ? 'Balance unavailable' : '$balance coins';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface2.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.stageGold.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.stageGold.withValues(alpha: 0.14),
                border: Border.all(
                  color: AppColors.stageGold.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.account_balance_wallet,
                color: AppColors.stageGold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WALLET',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    balanceLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
