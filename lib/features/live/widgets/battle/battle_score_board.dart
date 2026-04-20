import 'package:flutter/material.dart';
import '../../../../app/theme/weafrica_colors.dart';
import '../../../../app/widgets/animated_count.dart';
import '../../../../app/widgets/glass_card.dart';

class BattleScoreBoard extends StatelessWidget {
  const BattleScoreBoard({
    super.key,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.score1,
    required this.score2,
    required this.competitor1Type,
    required this.competitor2Type,
    required this.isWinning1,
    required this.isWinning2,
  });

  final String competitor1Name;
  final String competitor2Name;
  final int score1;
  final int score2;
  final String competitor1Type;
  final String competitor2Type;
  final bool isWinning1;
  final bool isWinning2;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      borderRadius: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ScoreChip(
            name: competitor1Name,
            score: score1,
            type: competitor1Type,
            isWinning: isWinning1,
            align: TextDirection.ltr,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [WeAfricaColors.gold, WeAfricaColors.goldLight],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          _ScoreChip(
            name: competitor2Name,
            score: score2,
            type: competitor2Type,
            isWinning: isWinning2,
            align: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.name,
    required this.score,
    required this.type,
    required this.isWinning,
    required this.align,
  });

  final String name;
  final int score;
  final String type;
  final bool isWinning;
  final TextDirection align;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      type == 'artist' ? Icons.mic : Icons.album,
      color: isWinning ? WeAfricaColors.gold : Colors.white54,
      size: 20,
    );

    final count = AnimatedCount(
      value: score,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: isWinning ? WeAfricaColors.gold : Colors.white,
      ),
    );

    final children = <Widget>[
      count,
      const SizedBox(width: 8),
      icon,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: align,
      children: children,
    );
  }
}