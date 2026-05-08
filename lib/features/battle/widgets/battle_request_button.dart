import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class BattleRequestButton extends StatelessWidget {
  final VoidCallback onTap;

  const BattleRequestButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.accentGold, Colors.orange],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentGold.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'REQUEST BATTLE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}