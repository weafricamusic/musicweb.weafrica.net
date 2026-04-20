import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../audio/audio.dart';
import '../../audio/audio_handler.dart';
import '../models/song_model.dart';

class AudioProvider extends ChangeNotifier {
  WeAfricaAudioHandler? _audioHandler;
  Song? _currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isInitialized = false;
  Future<void>? _initFuture;
  bool _listenersBound = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  Song? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isInitialized => _isInitialized;

  double get progress {
    if (_duration.inMilliseconds == 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
  }

  Future<void> init() => _ensureInitialized();

  Future<void> _ensureInitialized() {
    final existing = _initFuture;
    if (existing != null) return existing;

    final future = _initInternal();
    _initFuture = future;
    return future;
  }

  Future<void> _initInternal() async {
    try {
      // If main() already ran initWeAfricaAudio(), this is instant.
      _audioHandler = maybeWeafricaAudioHandler ?? _audioHandler;
      _audioHandler ??= await initWeAfricaAudio();

      _setupListeners();
      _isInitialized = _audioHandler != null;
      if (kDebugMode) {
        debugPrint(
          _isInitialized
              ? '✅ Audio handler initialized successfully'
              : '❌ Audio handler initialization returned null',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to initialize audio handler: $e');
      }
      _isInitialized = false;
    }

    notifyListeners();
  }

  void _setupListeners() {
    if (_audioHandler == null) return;
    if (_listenersBound) return;
    _listenersBound = true;

    _posSub = _audioHandler!.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durSub = _audioHandler!.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _stateSub = _audioHandler!.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });
  }

  Future<void> playSong(Song song) async {
    if (!_isInitialized || _audioHandler == null) {
      if (kDebugMode) debugPrint('⏳ Waiting for audio initialization...');
      await _ensureInitialized();
    }

    final handler = _audioHandler;
    if (handler == null) {
      if (kDebugMode) debugPrint('❌ Audio handler is still null');
      return;
    }

    // Get the audio URL
    String audioUrl = song.audioUrl ?? '';
    if (audioUrl.isEmpty) {
      debugPrint('❌ Error: No audio URL for ${song.title}');
      return;
    }

    // Get thumbnail URL
    Uri? artUri;
    if (song.thumbnail != null && song.thumbnail!.isNotEmpty) {
      artUri = Uri.tryParse(song.thumbnail!);
    }

    try {
      final mediaItem = MediaItem(
        id: audioUrl,
        title: song.title,
        artist: song.artist,
        artUri: artUri,
        duration: song.duration,
      );

      await handler.setQueue([mediaItem], startIndex: 0);
      _currentSong = song;
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing song: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_audioHandler == null) return;
    if (_isPlaying) {
      await _audioHandler!.pause();
    } else {
      await _audioHandler!.play();
    }
  }

  Future<void> playNext() async {
    if (_audioHandler == null) return;
    debugPrint('▶️ Playing next song');
    try {
      await _audioHandler!.skipToNext();
    } catch (e) {
      debugPrint('Error playing next: $e');
    }
  }

  Future<void> playPrevious() async {
    if (_audioHandler == null) return;
    await _audioHandler!.skipToPrevious();
  }

  Future<void> seek(Duration position) async {
    if (_audioHandler == null) return;
    await _audioHandler!.seek(position);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

}
