import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../battle/battle_models.dart';

class BattleCard extends StatelessWidget {
  const BattleCard({
    super.key,
    required this.battle,
    required this.onTap,
  });

  final OsBattle battle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color statusColor() {
      return switch (battle.status) {
        OsBattleStatus.live => cs.error,
        OsBattleStatus.pending => AppColors.brandBlue,
        OsBattleStatus.completed => battle.result == OsBattleResult.win ? cs.primary : cs.error,
      };
    }

    String statusLabel() {
      return switch (battle.status) {
        OsBattleStatus.live => 'LIVE',
        OsBattleStatus.pending => 'PENDING',
        OsBattleStatus.completed => battle.result == OsBattleResult.win ? 'WON' : 'LOST',
      };
    }

    final borderColor = battle.status == OsBattleStatus.live ? cs.error : AppColors.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor()),
                ),
                const SizedBox(width: 8),
                Text(
                  statusLabel(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: statusColor(),
                      ),
                ),
                const Spacer(),
                Text(
                  '${battle.stakeCoins} coins',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              battle.opponentName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              battle.opponentUsername,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Text(
              'Track: ${battle.trackTitle}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (battle.status == OsBattleStatus.live) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${battle.yourVotes}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${battle.opponentVotes}',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
