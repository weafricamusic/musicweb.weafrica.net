import 'dart:math';

import 'package:flutter/material.dart';

class PulseWidget extends StatefulWidget {
  const PulseWidget({
    super.key,
    required this.size,
    required this.color,
    this.opacity = 1.0,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<PulseWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  double _noise = 0.0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Organic imperfection
    _controller.addListener(() {
      _noise = sin(_controller.value * pi * 2) * 0.01;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _scale.value + _noise,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _PulseRingPainter(
              color: widget.color,
              progress: _controller.value,
              opacity: widget.opacity,
            ),
          ),
        );
      },
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({
    required this.color,
    required this.progress,
    required this.opacity,
  });

  final Color color;
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Slight breathing in opacity (kept subtle)
    final breathe = 0.85 + (sin(progress * pi * 2) * 0.15);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: (0.18 * breathe * opacity).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    final ringPaint = Paint()
      ..color = color.withValues(alpha: (0.45 * breathe * opacity).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawCircle(center, radius * 0.92, glowPaint);
    canvas.drawCircle(center, radius * 0.92, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.progress != progress ||
        oldDelegate.opacity != opacity;
  }
}
