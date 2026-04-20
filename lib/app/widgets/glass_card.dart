import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.onTap,
    this.borderRadius = 16,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final double borderRadius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashColor: AppColors.stageGold.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Container(
              width: width,
              height: height,
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surface2.withValues(alpha: 0.55),
                    AppColors.surface.withValues(alpha: 0.25),
                  ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: (borderColor ?? AppColors.stageGold).withValues(alpha: 0.18),
                  width: 0.7,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

