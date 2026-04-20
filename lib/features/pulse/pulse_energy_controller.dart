import 'package:flutter/foundation.dart';

class PulseEnergyController extends ChangeNotifier {
  PulseEnergyController({double initialEnergy = 0.5})
      : _energy = initialEnergy.clamp(0.0, 1.0);

  double _energy;

  double get energy => _energy;

  /// Call this periodically or from audio/video analysis.
  void updateEnergy(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next == _energy) return;
    _energy = next;
    notifyListeners();
  }
}
