import 'package:flutter/material.dart';
import '../../../../app/theme/weafrica_colors.dart';

class GiftComboIndicator extends StatelessWidget {
  const GiftComboIndicator({
    super.key,
    required this.comboCount,
  });

  final int comboCount;

  @override
  Widget build(BuildContext context) {
    // Only show indicator for combos of 3 or more
    if (comboCount < 3) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.5, end: 1.2),
      duration: const Duration(milliseconds: 200),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [WeAfricaColors.gold, WeAfricaColors.goldLight],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: WeAfricaColors.gold.withValues(alpha: 0.5),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars, color: Colors.black),
            const SizedBox(width: 8),
            Text(
              'x$comboCount COMBO!',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}