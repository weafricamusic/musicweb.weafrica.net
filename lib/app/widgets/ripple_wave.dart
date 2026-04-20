import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class RippleWave extends StatefulWidget {
  const RippleWave({
    super.key,
    required this.size,
    required this.color,
    this.opacity = 1.0,
    this.enabled = true,
    this.minInterval = const Duration(milliseconds: 900),
    this.maxInterval = const Duration(milliseconds: 2200),
    this.minDuration = const Duration(milliseconds: 1000),
    this.maxDuration = const Duration(milliseconds: 1500),
  });

  final double size;
  final Color color;
  final double opacity;
  final bool enabled;

  /// How often ripples appear (randomized in range).
  final Duration minInterval;
  final Duration maxInterval;

  /// How long each ripple lasts (randomized in range).
  final Duration minDuration;
  final Duration maxDuration;

  @override
  State<RippleWave> createState() => _RippleWaveState();
}

class _RippleWaveState extends State<RippleWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final _random = Random();

  Timer? _spawnTimer;
  final List<_Ripple> _ripples = <_Ripple>[];

  @override
  void initState() {
    super.initState();

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..repeat();

    if (widget.enabled) {
      _scheduleNextRipple();
    }
  }

  @override
  void didUpdateWidget(covariant RippleWave oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.enabled != widget.enabled) {
      _spawnTimer?.cancel();
      if (widget.enabled) {
        _scheduleNextRipple();
      }
    }
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _scheduleNextRipple() {
    if (!mounted) return;

    final minMs = widget.minInterval.inMilliseconds;
    final maxMs = widget.maxInterval.inMilliseconds;
    final delayMs = maxMs <= minMs
        ? minMs
        : (minMs + _random.nextInt(maxMs - minMs + 1));

    _spawnTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (!widget.enabled) return;

      _spawnRipple();
      _scheduleNextRipple();
    });
  }

  void _spawnRipple() {
    final nowMs = _nowMs;

    final minDur = widget.minDuration.inMilliseconds;
    final maxDur = widget.maxDuration.inMilliseconds;
    final durationMs = maxDur <= minDur
        ? minDur
        : (minDur + _random.nextInt(maxDur - minDur + 1));

    // Organic variation in scale/opacity.
    final maxScale = 1.0 + _random.nextDouble() * 0.15; // 1.00 → 1.15
    final maxOpacity = 0.28 + _random.nextDouble() * 0.14; // 0.28 → 0.42
    final blurSigma = 10 + _random.nextDouble() * 8; // 10 → 18
    final strokeWidth = 1.8 + _random.nextDouble() * 1.4; // 1.8 → 3.2

    setState(() {
      _ripples.add(
        _Ripple(
          startMs: nowMs,
          durationMs: durationMs,
          maxScale: maxScale,
          maxOpacity: maxOpacity,
          blurSigma: blurSigma,
          strokeWidth: strokeWidth,
        ),
      );
    });
  }

  int get _nowMs => _ticker.lastElapsedDuration?.inMilliseconds ?? 0;

  void _gcRipples() {
    if (_ripples.isEmpty) return;

    final nowMs = _nowMs;
    _ripples.removeWhere((r) => nowMs - r.startMs >= r.durationMs);
  }

  @override
  Widget build(BuildContext context) {
    // We rely on CustomPaint(repaint: _ticker) for smooth animation.
    // We only setState when spawning (or removing) ripples.
    return CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _RipplePainter(
        color: widget.color,
        opacity: widget.opacity,
        ripples: _ripples,
        ticker: _ticker,
        nowMs: () {
          _gcRipples();
          return _nowMs;
        },
      ),
    );
  }
}

@immutable
class _Ripple {
  const _Ripple({
    required this.startMs,
    required this.durationMs,
    required this.maxScale,
    required this.maxOpacity,
    required this.blurSigma,
    required this.strokeWidth,
  });

  final int startMs;
  final int durationMs;
  final double maxScale;
  final double maxOpacity;
  final double blurSigma;
  final double strokeWidth;
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.color,
    required this.opacity,
    required this.ripples,
    required this.ticker,
    required this.nowMs,
  }) : super(repaint: ticker);

  final Color color;
  final double opacity;
  final List<_Ripple> ripples;
  final Animation<double> ticker;
  final int Function() nowMs;

  double _easeOutCubic(double t) {
    final x = (1.0 - t).clamp(0.0, 1.0);
    return 1.0 - (x * x * x);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final now = nowMs();

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    for (final ripple in ripples) {
      final t = ((now - ripple.startMs) / ripple.durationMs).clamp(0.0, 1.0);
      final eased = _easeOutCubic(t);

      final a = ((1.0 - eased) * ripple.maxOpacity * opacity).clamp(0.0, 1.0);
      if (a <= 0) continue;

      final paint = Paint()
        ..color = color.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ripple.strokeWidth
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ripple.blurSigma);

      // Expands gently outward: 1.0 → maxScale.
      final radius = baseRadius * 0.90 * (1.0 + (ripple.maxScale - 1.0) * eased);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.ripples != ripples;
  }
}
