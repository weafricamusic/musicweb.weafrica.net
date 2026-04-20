import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/song_model.dart';

class PlayerProvider extends ChangeNotifier {
  Song? _currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Timer? _ticker;

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;

  void playSong(Song song) {
    _currentSong = song;
    _isPlaying = true;
    _position = Duration.zero;
    _startTicker();
    notifyListeners();
  }

  void togglePlayPause() {
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      _startTicker();
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  void seek(Duration position) {
    _position = position;
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPlaying) return;
      final song = _currentSong;
      if (song == null) return;

      final next = _position + const Duration(seconds: 1);
      if (next >= song.duration) {
        _position = song.duration;
        _isPlaying = false;
        _ticker?.cancel();
        _ticker = null;
      } else {
        _position = next;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
