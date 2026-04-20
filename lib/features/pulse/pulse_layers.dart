/// Barrel exports for WeAfrica Pulse visual layers.
///
/// Import this file when building Pulse feed UI components so you can access
/// the full Pulse stack (layers 1–4) plus common presets.
library;

export 'pulse_container.dart';
export 'pulse_energy_controller.dart';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

class PulsePresets {
  const PulsePresets._();

  static const Color primary = AppColors.stageGold;
  static const Color accent = Colors.deepPurpleAccent;

  static const double sizeMvp = 220;
  static const double sizeDefault = 240;
}
