import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'battle_models.dart';

class BattleResultsScreen extends StatelessWidget {
  const BattleResultsScreen({super.key, required this.battle});

  final OsBattle battle;

  @override
  Widget build(BuildContext context) {
    final won = battle.result == OsBattleResult.win;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Battle Results')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: won ? cs.primary : cs.error),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  won ? 'YOU WON' : 'YOU LOST',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: won ? cs.primary : cs.error,
                        letterSpacing: 0.6,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Opponent: ${battle.opponentUsername}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track: ${battle.trackTitle}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ScoreBox(label: 'You', score: battle.yourVotes),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ScoreBox(label: 'Them', score: battle.opponentVotes),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  won ? '+${battle.prizeCoins} coins' : '0 coins',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: won ? cs.primary : AppColors.textMuted,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to War Room'),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Results are based on votes in this battle.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            score.toString(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
