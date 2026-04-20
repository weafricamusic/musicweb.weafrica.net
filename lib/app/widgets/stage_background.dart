import 'package:flutter/material.dart';

import '../theme.dart';
import 'pulse_widget.dart';
import 'ripple_wave.dart';

class StageBackground extends StatelessWidget {
  const StageBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.background,
                AppColors.surface,
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        Positioned(
          right: -40,
          top: -30,
          child: IgnorePointer(
            child: PulseWidget(
              size: 180,
              color: primary,
              opacity: 0.55,
            ),
          ),
        ),
        Positioned(
          left: -30,
          bottom: -40,
          child: IgnorePointer(
            child: RippleWave(
              size: 220,
              color: primary,
              opacity: 0.45,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
