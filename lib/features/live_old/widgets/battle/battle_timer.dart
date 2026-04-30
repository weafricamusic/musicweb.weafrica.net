import 'package:flutter/material.dart';
import '../../../../app/theme/weafrica_colors.dart';
import '../../../../app/widgets/glass_card.dart';

class BattleTimer extends StatelessWidget {
  const BattleTimer({
    super.key,
    required this.timeRemaining,
    required this.progress,
    required this.isUrgent,
  });

  final int timeRemaining;
  final double progress;
  final bool isUrgent;

  // Format seconds into mm:ss
  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 30,
      child: Row(
        children: [
          // Circular timer indicator
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(
                    isUrgent ? WeAfricaColors.error : WeAfricaColors.gold,
                  ),
                ),
              ),
              Icon(
                Icons.timer,
                color: isUrgent ? WeAfricaColors.error : WeAfricaColors.gold,
                size: 20,
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Time remaining display
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(timeRemaining),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isUrgent ? WeAfricaColors.error : WeAfricaColors.gold,
                  ),
                ),
                Text(
                  isUrgent ? 'FINAL SECONDS!' : 'REMAINING',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}