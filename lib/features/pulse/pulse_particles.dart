import 'dart:math';

import 'package:flutter/material.dart';

import 'pulse_energy_controller.dart';

/// WEAFRICA PULSE — LAYER 4 (MICRO PARTICLES)
/// Luxury detail — subtle drifting dots that react to energy.
///
/// Designed to be low-CPU:
/// - Uses CustomPainter with a repaint Listenable.
/// - No per-frame setState().
class PulseParticles extends StatefulWidget {
  const PulseParticles({
    super.key,
    required this.energy,
    required this.size,
    required this.color,
    this.opacity = 1.0,
    this.count = 12,
  });

  final PulseEnergyController energy;
  final double size;
  final Color color;
  final double opacity;
  final int count;

  @override
  State<PulseParticles> createState() => _PulseParticlesState();
}

class _PulseParticlesState extends State<PulseParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late List<_ParticleSeed> _seeds;

  @override
  void initState() {
    super.initState();

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    _seeds = List.generate(widget.count, (i) {
      // Stable pseudo-random per index (not per frame)
      final r = Random(1000 + (i * 97));
      return _ParticleSeed(
        phase: r.nextDouble() * pi * 2,
        speed: 0.25 + (r.nextDouble() * 0.55),
        orbit: 0.22 + (r.nextDouble() * 0.36),
        radius: 0.9 + (r.nextDouble() * 2.4),
        alpha: 0.10 + (r.nextDouble() * 0.20),
        wobble: 0.4 + (r.nextDouble() * 1.0),
      );
    });
  }

  @override
  void didUpdateWidget(covariant PulseParticles oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If count changes, rebuild seeds.
    if (oldWidget.count != widget.count) {
      _seeds = List.generate(widget.count, (i) {
        final r = Random(1000 + (i * 97));
        return _ParticleSeed(
          phase: r.nextDouble() * pi * 2,
          speed: 0.25 + (r.nextDouble() * 0.55),
          orbit: 0.22 + (r.nextDouble() * 0.36),
          radius: 0.9 + (r.nextDouble() * 2.4),
          alpha: 0.10 + (r.nextDouble() * 0.20),
          wobble: 0.4 + (r.nextDouble() * 1.0),
        );
      });
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Repaint when either time moves or energy updates.
    final repaint = Listenable.merge([_ticker, widget.energy]);

    return CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _ParticlesPainter(
        color: widget.color,
        energy: widget.energy,
        opacity: widget.opacity,
        seeds: _seeds,
        repaint: repaint,
        time: _ticker,
      ),
    );
  }
}

@immutable
class _ParticleSeed {
  const _ParticleSeed({
    required this.phase,
    required this.speed,
    required this.orbit,
    required this.radius,
    required this.alpha,
    required this.wobble,
  });

  final double phase;
  final double speed;
  final double orbit;
  final double radius;
  final double alpha;
  final double wobble;
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({
    required this.color,
    required this.energy,
    required this.opacity,
    required this.seeds,
    required this.time,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Color color;
  final PulseEnergyController energy;
  final double opacity;
  final List<_ParticleSeed> seeds;
  final Animation<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final e = energy.energy;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    // Energy increases subtle motion + brightness.
    final energyBoost = 0.65 + (e * 0.75);

    for (final seed in seeds) {
      // Time 0..1
      final t = time.value;

      // Orbit radius scales slightly with energy.
      final orbitRadius = baseRadius * seed.orbit * (0.92 + (e * 0.18));

      // Angular velocity.
      final angle = seed.phase + (t * pi * 2 * seed.speed * energyBoost);

      // Small organic wobble.
      final wobble = sin((t * pi * 2 * seed.wobble) + seed.phase) * (0.06 + e * 0.08);

      final dx = cos(angle) * orbitRadius * (1.0 + wobble);
      final dy = sin(angle) * orbitRadius * (1.0 - wobble);

      // Opacity increases with energy but stays premium.
      final a = (seed.alpha * (0.55 + e * 0.85) * opacity).clamp(0.0, 0.55);

      final paint = Paint()
        ..color = color.withValues(alpha: a)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center.translate(dx, dy), seed.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.seeds != seeds;
  }
}
