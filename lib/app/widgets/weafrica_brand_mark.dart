import 'package:flutter/material.dart';

import '../theme.dart';

class WeAfricaBrandMark extends StatelessWidget {
  const WeAfricaBrandMark({
    super.key,
    this.size = 52,
    this.borderRadius = 18,
    this.iconSize,
    this.boxShadow,
  });

  final double size;
  final double borderRadius;
  final double? iconSize;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          colors: [AppColors.brandPurple, AppColors.brandPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: boxShadow,
      ),
      child: Center(
        child: Icon(
          Icons.graphic_eq,
          color: Colors.white,
          size: iconSize ?? (size * 0.52),
        ),
      ),
    );
  }
}