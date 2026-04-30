import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../app/utils/app_result.dart';
import '../services/battle_status_service.dart';

class BattleController extends ChangeNotifier {
  BattleController({
    required int durationSeconds,
    VoidCallback? onBattleEnd,
  })  : _durationSeconds = math.max(1, durationSeconds),
        _onBattleEnd = onBattleEnd {
    _timeRemaining = _durationSeconds;
  }

  final VoidCallback? _onBattleEnd;
  Timer? _tick;
  bool _endedNotified = false;

  String? _battleId;

  int _durationSeconds;
  int _timeRemaining = 0;

  int _competitor1Score = 0;
  int _competitor2Score = 0;

  String? _winnerUid;
  bool _isDraw = false;

  int get durationSeconds => _durationSeconds;
  int get timeRemaining => _timeRemaining;

  int get competitor1Score => _competitor1Score;
  int get competitor2Score => _competitor2Score;

  String? get winnerUid => _winnerUid;
  bool get isDraw => _isDraw;

  double get progress {
    if (_durationSeconds <= 0) return 0;
    final elapsed = (_durationSeconds - _timeRemaining).clamp(0, _durationSeconds);
    return elapsed / _durationSeconds;
  }

  bool get isUrgent => _timeRemaining <= 10;

  Future<void> connectToBattle(String battleId) async {
    final bid = battleId.trim();
    _battleId = bid.isEmpty ? null : bid;

    if (_battleId == null) {
      startLocalCountdown();
      return;
    }

    try {
      final res = await BattleStatusService().fetchStatus(battleId: _battleId!);
      switch (res) {
        case AppSuccess(:final data):
          _competitor1Score = data.hostAScore;
          _competitor2Score = data.hostBScore;
          _winnerUid = data.winnerUid;
          _isDraw = data.isDraw;

          final nextDuration = data.durationSeconds;
          if (nextDuration != null && nextDuration > 0) {
            _durationSeconds = nextDuration;
          }

          final endsAt = data.endsAt;
          if (endsAt != null) {
            final now = DateTime.now().toUtc();
            _timeRemaining = math.max(0, endsAt.difference(now).inSeconds);
          } else {
            _timeRemaining = _durationSeconds;
          }
          break;
        default:
          _timeRemaining = _durationSeconds;
      }
    } catch (_) {
      _timeRemaining = _durationSeconds;
    }

    notifyListeners();
    _startTicking();
  }

  void startLocalCountdown() {
    _winnerUid = null;
    _isDraw = false;
    _endedNotified = false;
    _timeRemaining = _durationSeconds;
    notifyListeners();
    _startTicking();
  }

  void applyRealtimeScores(Map<String, int> scores) {
    final s1 = scores['competitor1'];
    final s2 = scores['competitor2'];

    var changed = false;
    if (s1 != null && s1 != _competitor1Score) {
      _competitor1Score = s1;
      changed = true;
    }
    if (s2 != null && s2 != _competitor2Score) {
      _competitor2Score = s2;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  void resetForWaitingOpponent({required int competitor1Score}) {
    _tick?.cancel();
    _tick = null;
    _endedNotified = false;

    _competitor1Score = competitor1Score;
    _competitor2Score = 0;
    _winnerUid = null;
    _isDraw = false;
    _timeRemaining = _durationSeconds;

    notifyListeners();
  }

  void _startTicking() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timeRemaining <= 0) {
        _finishBattleIfNeeded();
        return;
      }
      _timeRemaining = math.max(0, _timeRemaining - 1);
      notifyListeners();
      if (_timeRemaining == 0) {
        _finishBattleIfNeeded();
      }
    });
  }

  void _finishBattleIfNeeded() {
    if (_endedNotified) return;
    _endedNotified = true;
    _tick?.cancel();
    _tick = null;

    if (_winnerUid == null) {
      if (_competitor1Score == _competitor2Score) {
        _isDraw = true;
      }
    }

    notifyListeners();
    _onBattleEnd?.call();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }
}