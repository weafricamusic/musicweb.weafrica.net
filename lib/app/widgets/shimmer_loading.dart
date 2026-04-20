import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme.dart';

class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface2.withValues(alpha: 0.55),
      highlightColor: AppColors.surface.withValues(alpha: 0.65),
      child: child,
    );
  }
}
