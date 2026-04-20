import 'package:flutter/material.dart';

import '../../app/theme.dart';

class StudioCard extends StatelessWidget {
  const StudioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveGradient = gradient ??
        LinearGradient(
          colors: <Color>[
            AppColors.surface2,
            Color.lerp(AppColors.surface2, AppColors.surface, 0.55) ?? AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    final radius = BorderRadius.circular(20);

    final ink = Ink(
      decoration: BoxDecoration(gradient: effectiveGradient),
      child: Padding(padding: padding, child: child),
    );

    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borderColor ?? AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? ink
          : InkWell(
              onTap: onTap,
              borderRadius: radius,
              mouseCursor: SystemMouseCursors.click,
              child: ink,
            ),
    );
  }
}

class StudioMetricCard extends StatelessWidget {
  const StudioMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tooltip,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? tooltip;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxHeight.isFinite && constraints.maxHeight < 170;

        final iconPadding = isCompact ? 8.0 : 10.0;
        final iconSize = isCompact ? 16.0 : 18.0;
        final iconRadius = isCompact ? 12.0 : 14.0;
        final topGap = isCompact ? 10.0 : 14.0;
        final valueFont = isCompact ? 22.0 : 26.0;
        final midGap = isCompact ? 4.0 : 6.0;
        final labelFont = isCompact ? 10.0 : 11.0;
        final padding = isCompact ? 16.0 : 18.0;

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    color: effectiveAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(iconRadius),
                    border: Border.all(color: effectiveAccent.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icon, size: iconSize, color: effectiveAccent),
                ),
                const Spacer(),
                if (tooltip != null && tooltip!.trim().isNotEmpty)
                  Tooltip(
                    message: tooltip!,
                    child: const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
                  ),
              ],
            ),
            SizedBox(height: topGap),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: valueFont,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            SizedBox(height: midGap),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: labelFont,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        );

        return StudioCard(
          padding: EdgeInsets.all(padding),
          gradient: LinearGradient(
            colors: <Color>[
              AppColors.surface2,
              effectiveAccent.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: body,
        );
      },
    );
  }
}
