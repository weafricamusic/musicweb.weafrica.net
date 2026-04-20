import 'package:flutter/material.dart';

import '../models/promotion_model.dart';

class PromotionCard extends StatelessWidget {
  const PromotionCard({
    super.key,
    required this.promotion,
    required this.onTap,
  });

  final Promotion promotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: promotion.gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: promotion.accent.withValues(alpha: 0.25),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(promotion.icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    promotion.badge,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.90),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    promotion.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    promotion.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
