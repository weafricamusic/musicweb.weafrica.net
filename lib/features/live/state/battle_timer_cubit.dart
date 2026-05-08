import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants/live_constants.dart';

/// Countdown timer for battle rounds.
class BattleTimerCubit extends ValueNotifier<int> {
  Timer? _timer;

  BattleTimerCubit() : super(LiveConstants.battleRoundDuration);

  void start() {
    _timer?.cancel();
    value = LiveConstants.battleRoundDuration;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (value > 0) {
        value = value - 1;
      } else {
        _timer?.cancel();
      }
    });
  }

  void reset() {
    _timer?.cancel();
    value = LiveConstants.battleRoundDuration;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
