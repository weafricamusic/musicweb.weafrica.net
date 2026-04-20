import 'dart:math';

import 'package:flutter/material.dart';

class BeatStudioKnob extends StatefulWidget {
  const BeatStudioKnob({
    super.key,
    required this.value,
    required this.onChanged,
    required this.minLabel,
    required this.maxLabel,
    this.accentColor,
  });

  /// Normalized 0..1.
  final double value;
  final void Function(double) onChanged;
  final String minLabel;
  final String maxLabel;
  final Color? accentColor;

  @override
  State<BeatStudioKnob> createState() => _BeatStudioKnobState();
}

class _BeatStudioKnobState extends State<BeatStudioKnob> {
  double _localValue = 0.5;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value.clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant BeatStudioKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _localValue = widget.value.clamp(0.0, 1.0);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _localValue = (_localValue + details.delta.dx / 220).clamp(0.0, 1.0);
      widget.onChanged(_localValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accentColor ?? scheme.primary;
    final bg = scheme.surface;

    return GestureDetector(
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanEnd: (_) => setState(() => _isDragging = false),
      onPanCancel: () => setState(() => _isDragging = false),
      onPanUpdate: _onPanUpdate,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              accent.withValues(alpha: 0.22),
              bg,
            ],
          ),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: _isDragging ? 0.28 : 0.12),
              blurRadius: 22,
              spreadRadius: 4,
            ),
          ],
        ),
        child: CustomPaint(
          painter: _KnobPainter(value: _localValue, accent: accent),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: accent),
                const SizedBox(height: 6),
                Text(
                  '${(_localValue * 120 + 60).round()}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.minLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  widget.maxLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final track = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, track);

    final indicatorPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    final angle = (value * 1.5 - 0.75) * pi;
    final x = center.dx + cos(angle) * radius * 0.72;
    final y = center.dy + sin(angle) * radius * 0.72;

    canvas.drawCircle(Offset(x, y), 4, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.accent != accent;
  }
}
