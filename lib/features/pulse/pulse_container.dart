import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/pulse_widget.dart';
import '../../app/widgets/ripple_wave.dart';
import 'pulse_energy_controller.dart';
import 'pulse_particles.dart';

class PulseContainer extends StatefulWidget {
  const PulseContainer({
    super.key,
    this.energy,
    this.size = 240,
    this.color = AppColors.stageGold,
    this.baseOpacity = 1.0,
  });

  /// Provide an external energy controller when you want the Pulse to react to
  /// real signals (audio analysis, scroll state, etc).
  final PulseEnergyController? energy;
  final double size;
  final Color color;
  final double baseOpacity;

  @override
  State<PulseContainer> createState() => _PulseContainerState();
}

class _PulseContainerState extends State<PulseContainer> {
  PulseEnergyController? _ownedEnergy;

  PulseEnergyController get _effectiveEnergy => widget.energy ?? _ownedEnergy!;

  @override
  void initState() {
    super.initState();
    _syncOwnedEnergy();
  }

  @override
  void didUpdateWidget(covariant PulseContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.energy != widget.energy) {
      _syncOwnedEnergy();
    }
  }

  void _syncOwnedEnergy() {
    if (widget.energy != null) {
      _ownedEnergy?.dispose();
      _ownedEnergy = null;
      return;
    }

    // No external energy: create an internal one at a stable baseline.
    _ownedEnergy ??= PulseEnergyController();
  }

  @override
  void dispose() {
    _ownedEnergy?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final energy = _effectiveEnergy;
    return AnimatedBuilder(
      animation: energy,
      builder: (context, _) {
        final e = energy.energy;

        // Scale subtly with energy.
        final scale = 0.96 + (e * 0.08);

        // Make effects stronger with energy, but stay premium.
        final ringOpacity = (0.12 + (e * 0.22)) * widget.baseOpacity;
        final rippleOpacity = (0.10 + (e * 0.20)) * widget.baseOpacity;
        final particlesOpacity = (0.06 + (e * 0.20)) * widget.baseOpacity;

        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Layer 4: micro particles (luxury detail)
              IgnorePointer(
                child: PulseParticles(
                  energy: energy,
                  size: widget.size + 24,
                  color: widget.color,
                  opacity: particlesOpacity.clamp(0.0, 1.0),
                  count: 12,
                ),
              ),

              IgnorePointer(
                child: RippleWave(
                  size: widget.size + 20,
                  color: widget.color,
                  opacity: rippleOpacity.clamp(0.0, 1.0),
                ),
              ),
              IgnorePointer(
                child: PulseWidget(
                  size: widget.size,
                  color: widget.color,
                  opacity: ringOpacity.clamp(0.0, 1.0),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
