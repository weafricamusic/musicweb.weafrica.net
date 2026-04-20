import 'dart:ui';

import 'package:flutter/material.dart';

import 'weafrica_colors.dart';

class GlassEffect {
  static BoxDecoration glassDecoration({
    double borderRadius = 16,
    double blur = 8,
    double opacity = 0.4,
    Color? borderColor,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          WeAfricaColors.cardDark.withValues(alpha: opacity),
          WeAfricaColors.surfaceDark.withValues(alpha: opacity * 0.5),
        ],
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? WeAfricaColors.gold.withValues(alpha: 0.15),
        width: 0.5,
      ),
    );
  }

  static Widget wrap({
    required Widget child,
    double borderRadius = 16,
    double blur = 8,
    EdgeInsets? padding,
    Color? borderColor,
    VoidCallback? onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: glassDecoration(
            borderRadius: borderRadius,
            borderColor: borderColor,
          ),
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(borderRadius),
                  splashColor: WeAfricaColors.gold.withValues(alpha: 0.1),
                  highlightColor: Colors.transparent,
                  child: child,
                )
              : child,
        ),
      ),
    );
  }
}
