import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.badge,
    this.trend,
    this.trendUp,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? badge;
  final String? trend;
  final bool? trendUp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final showTrend = trend != null && trend!.trim().isNotEmpty;
    final isTrendUp = trendUp ?? true;
    final trendColor = isTrendUp ? cs.primary : cs.error;
    final trendIcon = isTrendUp ? Icons.arrow_drop_up : Icons.arrow_drop_down;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const Spacer(),
                if (badge != null && badge!.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 31),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: cs.primary.withValues(alpha: 64)),
                    ),
                    child: Text(
                      badge!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showTrend) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(trendIcon, size: 18, color: trendColor),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      trend!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: trendColor,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
