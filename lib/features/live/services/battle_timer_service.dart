import 'dart:async';

import 'package:flutter/foundation.dart';

enum BattlePhase {
  intro,
  artist1Turn,
  transition,
  artist2Turn,
  judging,
  ended,
}

enum BattleFormat {
  classic, // 8min + 8min + 4min
  roundBased, // 2min turns x 3 rounds + judging
  tournament, // 3min turns x 4 rounds + judging
  quick, // 3min + 3min + 2min
}

class BattleConfig {
  static const Map<BattleFormat, Map<String, int>> durations = {
    BattleFormat.classic: {
      'artist1': 480,
      'transition': 10,
      'artist2': 480,
      'judging': 240,
      'rounds': 1,
    },
    BattleFormat.roundBased: {
      'artist1': 120,
      'transition': 8,
      'artist2': 120,
      'judging': 240,
      'rounds': 3,
    },
    BattleFormat.tournament: {
      'artist1': 180,
      'transition': 10,
      'artist2': 180,
      'judging': 240,
      'rounds': 4,
    },
    BattleFormat.quick: {
      'artist1': 180,
      'transition': 5,
      'artist2': 180,
      'judging': 120,
      'rounds': 1,
    },
  };

  static const Map<BattleFormat, String> soundAssets = {
    BattleFormat.classic: 'assets/sounds/battle_start.mp3',
    BattleFormat.roundBased: 'assets/sounds/round_bell.mp3',
    BattleFormat.tournament: 'assets/sounds/tournament_horn.mp3',
    BattleFormat.quick: 'assets/sounds/quick_battle.mp3',
  };
}

class BattleTimerService extends ChangeNotifier {
  BattleTimerService({BattleFormat format = BattleFormat.classic}) : _format = format {
    final config = BattleConfig.durations[_format];
    _totalRounds = (config?['rounds'] ?? 1).clamp(1, 99);
  }

  final BattleFormat _format;

  Timer? _timer;

  BattlePhase _currentPhase = BattlePhase.intro;
  BattlePhase get currentPhase => _currentPhase;

  int _timeRemaining = 0;
  int get timeRemaining => _timeRemaining;

  int _currentRound = 1;
  int get currentRound => _currentRound;

  int _totalRounds = 1;
  int get totalRounds => _totalRounds;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  int _score1 = 0;
  int _score2 = 0;
  int get score1 => _score1;
  int get score2 => _score2;

  String? _artist1Id;
  String? _artist2Id;

  // UI callbacks (optional)
  ValueChanged<BattlePhase>? onPhaseChange;
  ValueChanged<int>? onTimeUpdate;
  VoidCallback? onRoundEnd;
  VoidCallback? onBattleEnd;
  ValueChanged<Map<String, bool>>? onMicPermissionChange;
  ValueChanged<Map<String, int>>? onScoreUpdate;

  void setArtistIds(String id1, String id2) {
    _artist1Id = id1.trim().isEmpty ? null : id1.trim();
    _artist2Id = id2.trim().isEmpty ? null : id2.trim();
  }

  bool isMyTurn(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return false;
    if (_currentPhase == BattlePhase.artist1Turn && id == _artist1Id) return true;
    if (_currentPhase == BattlePhase.artist2Turn && id == _artist2Id) return true;
    return false;
  }

  void startBattle({bool skipIntro = true}) {
    _timer?.cancel();
    _isPaused = false;
    _currentRound = 1;

    _currentPhase = skipIntro ? BattlePhase.artist1Turn : BattlePhase.intro;
    _timeRemaining = _phaseDurationSeconds(_currentPhase);

    _emitPhase();
    _startTicker();
  }

  void pauseTimer() {
    if (_isPaused) return;
    _isPaused = true;
    notifyListeners();
  }

  void resumeTimer() {
    if (!_isPaused) return;
    _isPaused = false;
    notifyListeners();
  }

  void forcePhaseTransition() {
    _timeRemaining = 0;
    _advancePhase();
  }

  void extendCurrentTurn(int seconds) {
    if (seconds <= 0) return;
    _timeRemaining += seconds;
    onTimeUpdate?.call(_timeRemaining);
    notifyListeners();
  }

  void endBattleEarly({int judgingSeconds = 30}) {
    _currentPhase = BattlePhase.judging;
    _timeRemaining = judgingSeconds.clamp(0, 1 << 30);
    _emitPhase();
  }

  void updateScore({required String artistId, required int points}) {
    final id = artistId.trim();
    if (id.isEmpty) return;

    if (_artist1Id != null && id == _artist1Id) {
      _score1 += points;
    } else if (_artist2Id != null && id == _artist2Id) {
      _score2 += points;
    } else {
      // If ids were not set, fall back to "artist1"/"artist2" labels.
      if (id == 'artist1') {
        _score1 += points;
      } else if (id == 'artist2') {
        _score2 += points;
      }
    }

    onScoreUpdate?.call(<String, int>{'score1': _score1, 'score2': _score2});
    notifyListeners();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPaused) return;

      if (_timeRemaining <= 0) {
        _advancePhase();
        return;
      }

      _timeRemaining -= 1;
      onTimeUpdate?.call(_timeRemaining);
      notifyListeners();
    });
  }

  int _phaseDurationSeconds(BattlePhase phase) {
    final config = BattleConfig.durations[_format] ?? const <String, int>{};
    return switch (phase) {
      BattlePhase.intro => 0,
      BattlePhase.artist1Turn => config['artist1'] ?? 480,
      BattlePhase.transition => config['transition'] ?? 10,
      BattlePhase.artist2Turn => config['artist2'] ?? 480,
      BattlePhase.judging => config['judging'] ?? 240,
      BattlePhase.ended => 0,
    };
  }

  void _advancePhase() {
    switch (_currentPhase) {
      case BattlePhase.intro:
        _currentPhase = BattlePhase.artist1Turn;
        _timeRemaining = _phaseDurationSeconds(_currentPhase);
        _emitPhase();
        return;
      case BattlePhase.artist1Turn:
        _currentPhase = BattlePhase.transition;
        _timeRemaining = _phaseDurationSeconds(_currentPhase);
        _emitPhase();
        return;
      case BattlePhase.transition:
        _currentPhase = BattlePhase.artist2Turn;
        _timeRemaining = _phaseDurationSeconds(_currentPhase);
        _emitPhase();
        return;
      case BattlePhase.artist2Turn:
        if (_currentRound < _totalRounds && (_format == BattleFormat.roundBased || _format == BattleFormat.tournament)) {
          _currentRound += 1;
          _currentPhase = BattlePhase.artist1Turn;
          _timeRemaining = _phaseDurationSeconds(_currentPhase);
          onRoundEnd?.call();
          _emitPhase();
          return;
        }

        _currentPhase = BattlePhase.judging;
        _timeRemaining = _phaseDurationSeconds(_currentPhase);
        _emitPhase();
        return;
      case BattlePhase.judging:
        _currentPhase = BattlePhase.ended;
        _timeRemaining = 0;
        _timer?.cancel();
        _timer = null;
        _emitPhase();
        onBattleEnd?.call();
        return;
      case BattlePhase.ended:
        return;
    }
  }

  void _emitPhase() {
    onPhaseChange?.call(_currentPhase);
    _notifyMicPermissions();
    notifyListeners();
  }

  void _notifyMicPermissions() {
    final permissions = <String, bool>{
      'artist1': _currentPhase == BattlePhase.artist1Turn,
      'artist2': _currentPhase == BattlePhase.artist2Turn,
    };
    onMicPermissionChange?.call(permissions);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
