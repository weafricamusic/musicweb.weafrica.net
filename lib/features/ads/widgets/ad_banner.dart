import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/ad_model.dart';

class AdBanner extends StatelessWidget {
  const AdBanner({
    super.key,
    required this.ad,
    required this.progress,
    this.onAdClick,
    this.onSkip,
  });

  final AdModel ad;
  final double progress;
  final VoidCallback? onAdClick;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'ADVERTISEMENT',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              if (ad.isSkippable && onSkip != null)
                TextButton(
                  onPressed: onSkip,
                  child: const Text('Skip'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ad.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    ad.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.campaign, size: 20),
                    ),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.campaign, size: 20),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.title,
                      style: t.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ad.advertiser,
                      style: t.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (ad.clickUrl != null && onAdClick != null)
                IconButton(
                  tooltip: 'Learn more',
                  onPressed: onAdClick,
                  icon: const Icon(Icons.info_outline),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: p,
            backgroundColor: AppColors.surface2,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandOrange),
            borderRadius: BorderRadius.circular(999),
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}
