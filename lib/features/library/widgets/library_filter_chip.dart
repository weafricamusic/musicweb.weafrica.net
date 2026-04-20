import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class LibraryFilterChip extends StatelessWidget {
  const LibraryFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.stageGold;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? gold.withValues(alpha: 0.12) : AppColors.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? gold : gold.withValues(alpha: 0.25),
              width: isSelected ? 1.2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              color: isSelected ? gold : AppColors.textMuted,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ),
    );
  }
}
