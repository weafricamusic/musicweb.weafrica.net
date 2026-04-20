import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class AutoArtwork extends StatelessWidget {
  const AutoArtwork({
    super.key,
    required this.seed,
    this.icon = Icons.music_note,
    this.initials,
    this.showInitials = true,
  });

  final String seed;
  final IconData icon;
  final String? initials;
  final bool showInitials;

  @override
  Widget build(BuildContext context) {
    final effectiveSeed = seed.trim().isEmpty ? 'weafrica' : seed.trim();
    final palette = _paletteFor(effectiveSeed);

    final label = (initials ?? _initialsFrom(effectiveSeed)).trim();
    final canShowText = showInitials && label.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.a, palette.b],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxSide = math.min(constraints.maxWidth, constraints.maxHeight);
          final isCompact = boxSide.isFinite && boxSide <= 56;

          final iconSize = isCompact && canShowText ? 28.0 : 34.0;
          final gap = isCompact ? 2.0 : 6.0;
          final textStyleBase = isCompact
              ? Theme.of(context).textTheme.labelSmall
              : Theme.of(context).textTheme.labelMedium;

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: palette.foreground.withValues(alpha: 0.92),
                  size: iconSize,
                ),
                if (canShowText) ...[
                  SizedBox(height: gap),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyleBase?.copyWith(
                      color: palette.foreground.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w900,
                      letterSpacing: isCompact ? 0.4 : 0.6,
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

({Color a, Color b, Color foreground}) _paletteFor(String seed) {
  // Stable pseudo-random colors derived from seed.
  final hash = seed.codeUnits.fold<int>(0, (prev, c) => (prev * 31 + c) & 0x7fffffff);
  final rnd = math.Random(hash);

  final base = <Color>[
    AppColors.brandOrange,
    const Color(0xFF6A5CFF),
    const Color(0xFF00C2FF),
    const Color(0xFF00C853),
    const Color(0xFFFF2D55),
    const Color(0xFFFFC107),
  ];

  final c1 = base[rnd.nextInt(base.length)];
  final c2 = base[rnd.nextInt(base.length)];

  // Blend toward dark surfaces so it feels native.
  final a = Color.lerp(AppColors.surface, c1, 0.45) ?? c1;
  final b = Color.lerp(AppColors.surface2, c2, 0.45) ?? c2;

  final foreground = Colors.white;
  return (a: a, b: b, foreground: foreground);
}

String _initialsFrom(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '';
  if (parts.length == 1) {
    final p = parts.first;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.substring(0, 1).toUpperCase();
  }

  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}
