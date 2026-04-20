import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class CreatorTierBadge extends StatelessWidget {
  const CreatorTierBadge({super.key, this.label = 'CREATOR'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.stageGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.stageGold.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: AppColors.stageGold,
        ),
      ),
    );
  }
}
