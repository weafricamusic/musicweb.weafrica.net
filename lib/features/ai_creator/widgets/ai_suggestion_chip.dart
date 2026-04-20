import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class AiSuggestionChip extends StatelessWidget {
  const AiSuggestionChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.surface2,
      side: BorderSide(color: accent.withValues(alpha: 0.28)),
      labelStyle: Theme.of(context).textTheme.labelMedium,
    );
  }
}
