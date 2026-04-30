import 'package:flutter/material.dart';
import '../../app/theme/weafrica_colors.dart';

/// Filter indicator chip that shows the active filter with a clear button
class FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;
  final String? iconData;

  const FilterChip({
    super.key,
    required this.label,
    required this.onClear,
    this.iconData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WeAfricaColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconData != null) ...[
            Text(iconData!, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
          ],
          Text(
            'Filter: $label',
            style: const TextStyle(
              color: WeAfricaColors.gold,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: WeAfricaColors.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 12,
                color: WeAfricaColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}