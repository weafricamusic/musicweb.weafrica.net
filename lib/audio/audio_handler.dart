import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../app/bootstrap/bootstrap_connectivity.dart';
import '../services/playback_ad_gate.dart';
import '../services/playback_skips_gate.dart';

class WeAfricaAudioHandler extends BaseAudioHandler with SeekHandler {
  WeAfricaAudioHandler() {
    _ready = _init();
    unawaited(_ready);

    _bindActivePlayer();
  }

  AudioPlayer _active = AudioPlayer();
  AudioPlayer _inactive = AudioPlayer();

  static const Duration _defaultCrossFadeDuration = Duration(seconds: 5);

  late final Future<void> _ready;
  bool _crossFadeEnabled = true;
  Duration _crossFadeDuration = _defaultCrossFadeDuration;

  /// Configure crossfade (Spotify-style overlap between tracks).
  ///
  /// Note: just_audio does not provide a built-in crossfade API; we implement
  /// it by mixing two AudioPlayers and fading their volumes.
  Future<void> configureCrossfade({bool? enabled, Duration? duration}) async {
    if (enabled != null) _crossFadeEnabled = enabled;
    if (duration != null) _crossFadeDuration = duration;
    await _ready;

    // Ensure volumes are sane if crossfade is disabled mid-play.
    if (!_crossFadeEnabled) {
      await _cancelCrossfade();
    }
  }

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationCtrl =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _playerStateCtrl =
      StreamController<PlayerState>.broadcast();
  final StreamController<int?> _currentIndexCtrl =
      StreamController<int?>.broadcast();

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;

  int _loadToken = 0;
  static const int _maxLoadAttempts = 2;  // OPTIMIZED: Reduced from 3
  static const Duration _initialRetryDelay = Duration(milliseconds: 300);  // OPTIMIZED: Reduced from 1 second
  static const Duration _preloadInterval = Duration(milliseconds: 500);  // OPTIMIZED: New constant

  // Some streams can enter ProcessingState.buffering indefinitely even after
  // the initial setAudioSource succeeds (e.g. CDN stalls, 403/404 mid-stream,
  // network drops without a hard error). Add a watchdog so the UI doesn't spin
  // forever; we surface an error and attempt a recover/retry.
  static const Duration _bufferingStallTimeout = Duration(seconds: 20);  // OPTIMIZED: Reduced from 35 seconds
  Timer? _bufferingStallTimer;
  int _bufferingStallToken = 0;
  Duration _bufferingStallPosition = Duration.zero;

  // If we hit a corrupted/unsupported stream, try advancing instead of getting
  // stuck on one broken item forever.
  int _consecutiveAutoSkips = 0;
  bool _autoSkipInProgress = false;

  Timer? _xfadeMonitor;
  Timer? _xfadeFader;
  Timer? _positionUpdateTimer;
  bool _isCrossfading = false;
  int? _pendingCrossfadeToIndex;

  Timer? _preloadTimer;

  // If set, the inactive player has been preloaded with this index.
  int? _preloadedIndex;

  // Enable with: `--dart-define=WEAFRICA_AUDIO_LOGS=true`
  static const bool _audioLogsEnabled = bool.fromEnvironment(
    'WEAFRICA_AUDIO_LOGS',
    defaultValue: false,
  );

  List<MediaItem> _items = const [];
  List<int> _order = const [];
  int _orderPos = 0;
  int _currentIndex = 0;

  bool _shuffleEnabled = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );
  }

  AudioPlayer get player => _active;

  Stream<Duration> get positionStream => _positionCtrl.stream;
  Stream<Duration?> get durationStream => _durationCtrl.stream;
  Stream<PlayerState> get playerStateStream => _playerStateCtrl.stream;
  Stream<int?> get currentIndexStream => _currentIndexCtrl.stream;

  Duration get position => _active.position;
  Duration get bufferedPosition => _active.bufferedPosition;
  Duration get duration => _active.duration ?? Duration.zero;

  void _bindActivePlayer() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _eventSub?.cancel();
    _cancelBufferingStallWatchdog();

    _posSub = _active.positionStream.listen(_positionCtrl.add);
    _durSub = _active.durationStream.listen((dur) {
      _durationCtrl.add(dur);

      // Some Bluetooth head unit only show an animating seek bar when the
      // MediaItem has a non-null duration.
      final current = mediaItem.valueOrNull;
      if (dur != null && current != null && current.duration != dur) {
        // Prefer copyWith when available.
        try {
          // ignore: invaliduse_of_protected_member
          mediaItem.add(current.copyWith(duration: dur));
        } catch (_) {
          mediaItem.add(
            MediaItem(
              id: current.id,
              title: current.title,
              artist: current.artist,
              album: current.album,
              artUri: current.artUri,
              duration: dur,
              genre: current.genre,
              extras: current.extras,
            ),
          );
        }
      }
    });

    _stateSub = _active.playerStateStream.listen((state) {
      _playerStateCtrl.add(state);

      if (_audioLogsEnabled && kDebugMode) {
        debugPrint(
          '[audio] state=${state.processingState} playing=${state.playing} '
          'pos=${_active.position.inMilliseconds}ms buffered=${_active.bufferedPosition.inMilliseconds}ms '
          'idx=$_currentIndex',
        );
      }

      // Head unit often need periodic PlaybackState updates to animate the
      // progress bar over Bluetooth AVRCP.
      if (state.playing && state.processingState != ProcessingState.idle) {
        _startPositionUpdates();
      } else {
        _stopPositionUpdates();
      }

      // Keep a lightweight retry loop so preloading still happens even if the
      // first attempt fails due to transient network / DNS / TLS setup.
      if (state.playing && state.processingState == ProcessingState.ready) {
        _startPreloadRetries();
      } else {
        _stopPreloadRetries();
      }

      _updateBufferingStallWatchdog(state);

      if (state.processingState == ProcessingState.completed) {
        unawaited(_handleCompleted());
      }
    }, onError: (Object e, StackTrace st) {
      unawaited(_handlePlaybackError(e, st));
    });
    _eventSub = _active.playbackEventStream.listen(
      (event) {
        if (_audioLogsEnabled && kDebugMode) {
          debugPrint(
            '[audio] event state=${_active.processingState} '
            'pos=${event.updatePosition.inMilliseconds}ms '
            'buffered=${event.bufferedPosition.inMilliseconds}ms '
            'idx=$_currentIndex',
          );
        }
        playbackState.add(_transformEvent(event));
      },
      onError: (Object e, StackTrace st) {
        unawaited(_handlePlaybackError(e, st));
      },
    );

    _currentIndexCtrl.add(_currentIndex);
    if (_items.isNotEmpty) {
      mediaItem.add(_items[_currentIndex]);
    }

    _startCrossfadeMonitor();
  }

  void _cancelBufferingStallWatchdog() {
    _bufferingStallTimer?.cancel();
    _bufferingStallTimer = null;
  }

  void _updateBufferingStallWatchdog(PlayerState state) {
    final isLoading = state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering;

    // Only watchdog when we are actively trying to play.
    if (!state.playing || !isLoading) {
      _cancelBufferingStallWatchdog();
      return;
    }

    if (_bufferingStallTimer != null) return;

    final token = ++_bufferingStallToken;
    _bufferingStallPosition = _active.position;
    _bufferingStallTimer = Timer(_bufferingStallTimeout, () {
      if (token != _bufferingStallToken) return;
      _bufferingStallTimer = null;

      final ps = _active.playerState;
      final stillLoading = ps.processingState == ProcessingState.loading ||
          ps.processingState == ProcessingState.buffering;
      if (!ps.playing || !stillLoading) return;

      final progressed = (_active.position - _bufferingStallPosition).inMilliseconds;
      if (progressed > 750) {
        // Progress resumed; restart the watchdog from the new position.
        _updateBufferingStallWatchdog(ps);
        return;
      }

      unawaited(
        _handlePlaybackError(
          TimeoutException('Playback stalled while buffering'),
          StackTrace.current,
        ),
      );
    });
  }

  // OPTIMIZED: More frequent preload checks
  void _startPreloadRetries() {
    _preloadTimer?.cancel();
    _preloadTimer = Timer.periodic(_preloadInterval, (_) {
      unawaited(_preloadNextIfNeeded());
    });
    unawaited(_preloadNextIfNeeded());
  }

  void _stopPreloadRetries() {
    _preloadTimer?.cancel();
    _preloadTimer = null;
  }

  // OPTIMIZED: More aggressive preloading with emergency preload near end
  Future<void> _preloadNextIfNeeded() async {
    if (_items.isEmpty) return;
    if (_order.isEmpty) return;
    if (_repeatMode == AudioServiceRepeatMode.one) {
      _preloadedIndex = null;
      return;
    }
    if (_items.length < 2) {
      _preloadedIndex = null;
      return;
    }
    if (_isCrossfading) return; // crossfade owns the inactive player

    final next = _computeNextIndex();
    if (next == null) {
      _preloadedIndex = null;
      return;
    }
    if (_preloadedIndex == next) return;

    // OPTIMIZED: If we're close to the end of current song, preload immediately with shorter timeout
    final currentPos = _active.position;
    final currentDur = _active.duration;
    if (currentDur != null && currentDur > Duration.zero) {
      final remaining = currentDur - currentPos;
      if (remaining < const Duration(seconds: 10)) {
        // Force preload now
        try {
          await _inactive.setVolume(0);
          await _inactive.stop();
          await _loadIntoPlayer(
            _inactive,
            _items[next],
            initialPosition: Duration.zero,
            preload: true,
          ).timeout(const Duration(seconds: 3));  // Shorter timeout for emergency preload
          _preloadedIndex = next;
          if (_audioLogsEnabled && kDebugMode) {
            debugPrint('[audio] emergency preloaded next idx=$next');
          }
          return;
        } catch (e) {
          // Fall through to normal preload
          if (_audioLogsEnabled && kDebugMode) {
            debugPrint('[audio] emergency preload failed: $e');
          }
        }
      }
    }

    try {
      final sw = Stopwatch()..start();
      await _inactive.setVolume(0);
      await _inactive.stop();
      await _loadIntoPlayer(
        _inactive,
        _items[next],
        initialPosition: Duration.zero,
        preload: true,
      ).timeout(const Duration(seconds: 5));  // OPTIMIZED: Shorter timeout
      _preloadedIndex = next;

      sw.stop();

      if (_audioLogsEnabled && kDebugMode) {
        debugPrint('[audio] preloaded next idx=$next in ${sw.elapsedMilliseconds}ms');
      }
    } catch (e) {
      _preloadedIndex = null;
      if (_audioLogsEnabled && kDebugMode) {
        debugPrint('[audio] preload failed: $e');
      }
    }
  }

  Future<bool> _trySwitchToPreloaded(int nextIndex) async {
    if (_preloadedIndex != nextIndex) return false;
    if (_isCrossfading) return false;

    // Swap players so the already-loaded inactive becomes active.
    try {
      await _active.stop();
    } catch (_) {}

    final oldActive = _active;
    _active = _inactive;
    _inactive = oldActive;
    _preloadedIndex = null;

    try {
      await _active.setVolume(1);
      await _inactive.setVolume(0);
    } catch (_) {}

    _bindActivePlayer();

    if (_audioLogsEnabled && kDebugMode) {
      debugPrint('[audio] switched using preloaded idx=$nextIndex');
    }
    customEvent.add(<String, dynamic>{
      'type': 'preloaded_switch',
      'index': nextIndex,
    });

    // If an interstitial is pending, block playback *before* the next song
    // starts. The UI will show the interstitial and then resume by calling
    // play().
    if (PlaybackAdGate.instance.consumePendingInterstitial(forceResumeAfter: true)) {
      _emitPlaybackState();
      return true;
    }

    await _active.play();
    _emitPlaybackState();
    unawaited(_preloadNextIfNeeded());
    return true;
  }

  void _startPositionUpdates() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emitPlaybackState();
    });
  }

  void _stopPositionUpdates() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
  }

  void _notifyError(String message) {
    customEvent.add(<String, dynamic>{
      'type': 'playback_error',
      'message': message,
      'index': _currentIndex,
    });
  }

  void _notifyRecovered() {
    _consecutiveAutoSkips = 0;
    customEvent.add(<String, dynamic>{
      'type': 'playback_recovered',
      'index': _currentIndex,
    });
  }

  bool _looksLikeNetworkFailure(Object error) {
    final msg = error.toString().toLowerCase();

    return msg.contains('connectexception') ||
        msg.contains('failed to connect') ||
        msg.contains('unknownhostexception') ||
        msg.contains('no address associated with hostname') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('sockettimeoutexception') ||
        msg.contains('timed out') ||
        msg.contains('httphostconnectexception') ||
        msg.contains('httpdatasource') ||
        msg.contains('unable to resolve host') ||
        msg.contains('name or service not known');
  }

  String? _localPathFromMediaItem(MediaItem item) {
    final extras = item.extras;
    if (extras == null) return null;
    final localPathAny = extras['localPath'] ?? extras['local_path'];
    final localPath = localPathAny is String ? localPathAny.trim() : null;
    return (localPath == null || localPath.isEmpty) ? null : localPath;
  }

  Future<bool> _autoSkipToNextAfterFailure() async {
    if (_autoSkipInProgress) return false;
    if (_items.isEmpty || _order.isEmpty) return false;
    if (_items.length < 2) return false;
    if (_repeatMode == AudioServiceRepeatMode.one) return false;

    final next = _computeNextIndex();
    if (next == null) return false;

    // Hard cap to avoid runaway loops if every item is broken.
    if (_consecutiveAutoSkips >= max(2, _items.length)) return false;

    _autoSkipInProgress = true;
    try {
      _consecutiveAutoSkips++;
      customEvent.add(<String, dynamic>{
        'type': 'playback_auto_skipped',
        'from': _currentIndex,
        'to': next,
      });

      try {
        await skipToNext();
        return true;
      } catch (_) {
        // If the next item also fails to load, let the main error recovery
        // path decide whether to pause or continue attempting.
        return false;
      }
    } finally {
      _autoSkipInProgress = false;
    }
  }

  String _friendlyErrorMessage(Object e) {
    if (e is TimeoutException) {
      return 'Audio is taking too long to buffer. Retrying…';
    }
    if (e is PlayerException) {
      final message = (e.message ?? '').trim();
      final lower = message.toLowerCase();

      if (_looksLikeNetworkFailure(e) || (message.isNotEmpty && _looksLikeNetworkFailure(message))) {
        return 'Network error. Check your internet connection and try again.';
      }

      if (lower.contains('403') || lower.contains('forbidden') || lower.contains('permission')) {
        return 'This audio is not accessible right now.';
      }

      if (lower.contains('404') || lower.contains('not found')) {
        return 'Audio file not found.';
      }

      // Avoid surfacing raw platform exceptions to users.
      return 'Could not load audio. Retrying…';
    }
    if (e is PlayerInterruptedException) {
      return 'Playback interrupted. Retrying…';
    }

    if (_looksLikeNetworkFailure(e)) {
      return 'Network error. Check your internet connection and try again.';
    }

    return 'Could not load audio. Retrying…';
  }

  Future<void> _handlePlaybackError(Object e, StackTrace st) async {
    // Prevent crashes on spotty networks by attempting a recovery.
    _notifyError(_friendlyErrorMessage(e));

    if (_items.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= _items.length) return;

    // If we're not actively playing, don't auto-retry in a loop.
    if (!_active.playing) return;

    // Retry by reloading the current item from the current position.
    final pos = _active.position;

    final isNetworkFailure = _looksLikeNetworkFailure(e);

    // If we're offline, prefer a local fallback and avoid skipping the queue.
    if (isNetworkFailure) {
      final offline = await checkIsOffline();
      if (offline) {
        _notifyError('You appear to be offline. Connect to the internet and try again.');

        final localPath = _localPathFromMediaItem(_items[_currentIndex]);
        if (localPath != null) {
          try {
            await _active
                .setFilePath(
                  localPath,
                  initialPosition: pos,
                  preload: true,
                )
                .timeout(const Duration(seconds: 5));
            await _active.play();
            _notifyRecovered();
            _emitPlaybackState();
            return;
          } catch (_) {
            // fall through to a safe pause
          }
        }

        try {
          await _active.pause();
        } catch (_) {}
        _emitPlaybackState();
        return;
      }
    }

    await _retryPlayIndex(
      _currentIndex,
      resumeFrom: pos,
      allowAutoSkip: true,
    );
  }

  Future<void> _retryPlayIndex(
    int index, {
    required Duration resumeFrom,
    bool allowAutoSkip = true,
  }) async {
    final token = ++_loadToken;
    final item = _items[index];

    // Small backoff loop.
    var delay = _initialRetryDelay;
    Object? lastError;
    for (var attempt = 1; attempt <= _maxLoadAttempts; attempt++) {
      if (token != _loadToken) return; // superseded
      try {
        await _loadIntoPlayer(
          _active,
          item,
          initialPosition: resumeFrom,
          preload: true,
        );
        if (token != _loadToken) return;
        await _active.play();
        _notifyRecovered();
        _emitPlaybackState();
        return;
      } catch (e) {
        lastError = e;
        _notifyError(_friendlyErrorMessage(e));
        if (attempt >= _maxLoadAttempts) break;
        await Future.delayed(delay);
        delay *= 2;
      }
    }

    if (lastError != null) {
      if (allowAutoSkip) {
        // If the stream is corrupted/unsupported, try to continue the queue.
        final skipped = await _autoSkipToNextAfterFailure();
        if (skipped) return;
      }

      // Give up gracefully: pause playback but keep the app alive.
      try {
        await _active.pause();
      } catch (_) {}
      _emitPlaybackState();
    }
  }

  // OPTIMIZED: Reduced timeouts
  Future<void> _loadIntoPlayer(
    AudioPlayer player,
    MediaItem item, {
    required Duration initialPosition,
    required bool preload,
  }) async {
    final localPath = _localPathFromMediaItem(item);

    final uri = Uri.tryParse(item.id);
    if (uri == null) {
      throw ArgumentError('Invalid MediaItem.id URL: ${item.id}');
    }

    // OPTIMIZED: Reduced timeout for faster failover
    const loadTimeout = Duration(seconds: 8);  // Reduced from 25

    // Prefer streaming, but fall back to localPath if streaming fails.
    try {
      await player
          .setAudioSource(
            AudioSource.uri(uri, tag: item),
            initialPosition: initialPosition,
            preload: preload,
          )
          .timeout(loadTimeout);
      return;
    } catch (e) {
      if (localPath == null || localPath.isEmpty) rethrow;
    }

    // Offline fallback with shorter timeout
    await player
        .setFilePath(
          localPath,
          initialPosition: initialPosition,
          preload: preload,
        )
        .timeout(const Duration(seconds: 5));  // Reduced from 10
  }

  void _startCrossfadeMonitor() {
    _xfadeMonitor?.cancel();
    _xfadeMonitor = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_crossFadeEnabled) return;
      if (_isCrossfading) return;
      if (_repeatMode == AudioServiceRepeatMode.one) return;
      if (_items.length < 2) return;
      if (!_active.playing) return;

      final d = _active.duration;
      if (d == null || d <= Duration.zero) return;
      if (_crossFadeDuration <= Duration.zero) return;
      if (d <= _crossFadeDuration) return;

      final remaining = d - _active.position;
      if (remaining <= _crossFadeDuration) {
        final next = _computeNextIndex();
        if (next == null) return;
        unawaited(_startCrossfadeTo(next));
      }
    });
  }

  int? _computeNextIndex() {
    if (_items.isEmpty) return null;
    if (_order.isEmpty) return null;
    if (_repeatMode == AudioServiceRepeatMode.one) return _currentIndex;

    final nextPos = _orderPos + 1;
    if (nextPos < _order.length) {
      return _order[nextPos];
    }

    if (_repeatMode == AudioServiceRepeatMode.all ||
        _repeatMode == AudioServiceRepeatMode.group) {
      return _order.first;
    }

    return null;
  }

  int? _computePreviousIndex() {
    if (_items.isEmpty) return null;
    if (_order.isEmpty) return null;
    if (_repeatMode == AudioServiceRepeatMode.one) return _currentIndex;

    final prevPos = _orderPos - 1;
    if (prevPos >= 0) {
      return _order[prevPos];
    }

    if (_repeatMode == AudioServiceRepeatMode.all ||
        _repeatMode == AudioServiceRepeatMode.group) {
      return _order.last;
    }

    return null;
  }

  Future<void> _cancelCrossfade() async {
    _xfadeFader?.cancel();
    _xfadeFader = null;
    _pendingCrossfadeToIndex = null;
    _isCrossfading = false;
    await _inactive.stop();
    await _inactive.setVolume(0);
    await _active.setVolume(1);
  }

  Future<void> _startCrossfadeTo(int nextIndex) async {
    if (_isCrossfading) return;
    if (nextIndex < 0 || nextIndex >= _items.length) return;

    _isCrossfading = true;
    _pendingCrossfadeToIndex = nextIndex;

    final nextItem = _items[nextIndex];
    try {
      await _inactive.setVolume(0);
      if (_preloadedIndex != nextIndex) {
        await _inactive.stop();
        await _loadIntoPlayer(
          _inactive,
          nextItem,
          initialPosition: Duration.zero,
          preload: true,
        );
        _preloadedIndex = nextIndex;
      }
      await _inactive.play();
    } catch (_) {
      await _cancelCrossfade();
      return;
    }

    // UI-wise we move to the next track at crossfade start.
    _currentIndex = nextIndex;
    final newPos = _order.indexOf(nextIndex);
    _orderPos = newPos < 0 ? 0 : min(newPos, max(0, _order.length - 1));
    mediaItem.add(nextItem);
    _currentIndexCtrl.add(_currentIndex);
    _emitPlaybackState();

    final start = DateTime.now();
    final totalMs = max(1, _crossFadeDuration.inMilliseconds);

    _xfadeFader?.cancel();
    _xfadeFader = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final t = (elapsedMs / totalMs).clamp(0.0, 1.0);
      try {
        await _active.setVolume(1.0 - t);
        await _inactive.setVolume(t);
      } catch (_) {
        // Ignore transient platform errors.
      }

      if (t >= 1.0) {
        _xfadeFader?.cancel();
        _xfadeFader = null;
        unawaited(_completeCrossfade());
      }
    });
  }

  Future<void> _completeCrossfade() async {
    final target = _pendingCrossfadeToIndex;
    _pendingCrossfadeToIndex = null;

    try {
      await _active.stop();
      await _active.setVolume(0);
    } catch (_) {}

    // Swap players: the one that was fading in becomes the active player.
    final oldActive = _active;
    _active = _inactive;
    _inactive = oldActive;

    try {
      await _active.setVolume(1);
      await _inactive.setVolume(0);
    } catch (_) {}

    _isCrossfading = false;

    // Preload the next track after we settle.
    unawaited(_preloadNextIfNeeded());

    // Re-bind streams and playbackState to the new active player.
    _bindActivePlayer();
    if (target != null) {
      _currentIndex = target;
      _currentIndexCtrl.add(_currentIndex);
      if (_items.isNotEmpty && _currentIndex < _items.length) {
        mediaItem.add(_items[_currentIndex]);
      }
    }
  }

  /// Spotify-style queue setup.
  ///
  /// Convention: [MediaItem.id] is the audio URL.
  Future<void> setQueue(List<MediaItem> items, {int startIndex = 0}) async {
    await _ready;
    await _cancelCrossfade();

    _preloadedIndex = null;
    _stopPreloadRetries();

    _items = List<MediaItem>.from(items);
    queue.add(_items);

    final upper = max(0, _items.length - 1);
    final initial = startIndex < 0 ? 0 : (startIndex > upper ? upper : startIndex);
    _currentIndex = initial;

    _rebuildOrder(keepCurrent: true);
    mediaItem.add(_items[_currentIndex]);
    _currentIndexCtrl.add(_currentIndex);

    await _playIndex(_currentIndex);
  }

  /// Insert a [MediaItem] into the current queue at [insertAt]. If the
  /// queue is empty this behaves like `setQueue([item])` and starts playback.
  /// This method attempts to update internal state without interrupting the
  /// currently playing item.
  Future<void> insertIntoQueue(MediaItem item, {int? insertAt}) async {
    await _ready;

    // If there is no current queue, just start playing this item.
    if (_items.isEmpty) {
      await setQueue([item], startIndex: 0);
      return;
    }

    final pos = insertAt == null
        ? _items.length
        : (insertAt.clamp(0, _items.length));

    _items.insert(pos, item);
    queue.add(_items);

    // Adjust preloaded index if needed.
    final preloadedIndex = _preloadedIndex;
    if (preloadedIndex != null && pos <= preloadedIndex) {
      _preloadedIndex = preloadedIndex + 1;
    }

    // Preserve current media index by re-locating the current media id.
    final currentId = mediaItem.valueOrNull?.id;
    if (currentId != null) {
      final newIndex = _items.indexWhere((m) => m.id == currentId);
      if (newIndex >= 0) {
        _currentIndex = newIndex;
      }
    }

    // Rebuild ordering (handles shuffle state) while keeping current index.
    _rebuildOrder(keepCurrent: true);
    _currentIndexCtrl.add(_currentIndex);

    // Opportunistically ensure the next item is preloaded.
    unawaited(_preloadNextIfNeeded());
  }

  void _rebuildOrder({required bool keepCurrent}) {
    final n = _items.length;
    if (n == 0) {
      _order = const [];
      _orderPos = 0;
      return;
    }

    final indices = List<int>.generate(n, (i) => i);
    if (_shuffleEnabled) {
      final rnd = Random();
      indices.shuffle(rnd);
      if (keepCurrent) {
        // Rotate so current is at the current position.
        final curIdx = _currentIndex;
        final pos = indices.indexOf(curIdx);
        if (pos > 0) {
          final rotated = <int>[
            ...indices.sublist(pos),
            ...indices.sublist(0, pos),
          ];
          _order = rotated;
          _orderPos = 0;
          return;
        }
      }
    }

    _order = indices;
    if (keepCurrent) {
      final pos = _order.indexOf(_currentIndex);
      _orderPos = pos < 0 ? 0 : min(pos, max(0, n - 1));
    } else {
      _orderPos = 0;
    }
  }

  Future<void> _playIndex(int index) async {
    if (_items.isEmpty) return;
    if (index < 0 || index >= _items.length) return;

    await _cancelCrossfade();

    _preloadedIndex = null;
    _stopPreloadRetries();

    var targetIndex = index;
    Object? lastError;

    while (true) {
      if (_items.isEmpty) return;
      if (targetIndex < 0 || targetIndex >= _items.length) return;

      final item = _items[targetIndex];

      _currentIndex = targetIndex;
      final pos = _order.indexOf(targetIndex);
      _orderPos = pos < 0 ? 0 : min(pos, max(0, _order.length - 1));
      mediaItem.add(item);
      _currentIndexCtrl.add(_currentIndex);

      await _active.setVolume(1);
      await _inactive.setVolume(0);

      final token = ++_loadToken;
      lastError = null;
      var delay = _initialRetryDelay;
      for (var attempt = 1; attempt <= _maxLoadAttempts; attempt++) {
        if (token != _loadToken) return;
        try {
          await _loadIntoPlayer(
            _active,
            item,
            initialPosition: Duration.zero,
            preload: true,
          );
          if (token != _loadToken) return;

          // If an interstitial is pending, keep the next track loaded but paused
          // so the ad can play between songs.
          if (PlaybackAdGate.instance.consumePendingInterstitial(forceResumeAfter: true)) {
            _notifyRecovered();
            _emitPlaybackState();
            return;
          }

          await _active.play();
          _notifyRecovered();
          _emitPlaybackState();
          unawaited(_preloadNextIfNeeded());
          return;
        } catch (e) {
          lastError = e;
          _notifyError(_friendlyErrorMessage(e));
          if (attempt >= _maxLoadAttempts) break;
          await Future.delayed(delay);
          delay *= 2;
        }
      }

      if (lastError == null) {
        _emitPlaybackState();
        return;
      }

        final isNetworkFailure = _looksLikeNetworkFailure(lastError);
        final offline = isNetworkFailure ? await checkIsOffline() : false;

        final allowAutoSkip =
          _items.length >= 2 &&
          _order.isNotEmpty &&
          _repeatMode != AudioServiceRepeatMode.one &&
          (!isNetworkFailure || !offline);

      if (!allowAutoSkip) {
        throw lastError;
      }

      final next = _computeNextIndex();
      if (next == null) {
        throw lastError;
      }

      // Hard cap to avoid runaway loops if every item is broken.
      if (_consecutiveAutoSkips >= max(2, _items.length)) {
        throw lastError;
      }

      _consecutiveAutoSkips++;
      customEvent.add(<String, dynamic>{
        'type': 'playback_auto_skipped',
        'from': _currentIndex,
        'to': next,
      });
      targetIndex = next;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _ready;
    _shuffleEnabled = shuffleMode == AudioServiceShuffleMode.all;
    _rebuildOrder(keepCurrent: true);
    _emitPlaybackState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _ready;
    _repeatMode = repeatMode;
    _emitPlaybackState();
  }

  void _emitPlaybackState() {
    playbackState.add(_transformEvent(_active.playbackEvent));
  }

  Future<void> playSingle({required MediaItem item, required Uri uri}) async {
    await setQueue([item], startIndex: 0);
  }

  Future<void> playQueue({
    required List<MediaItem> items,
    required List<Uri> uris,
    int initialIndex = 0,
  }) async {
    if (items.length != uris.length) {
      throw ArgumentError('items.length must match uris.length');
    }

    await setQueue(items, startIndex: initialIndex);
  }

  @override
  Future<void> play() => _active.play();

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> stop() async {
    await _cancelCrossfade();
    _stopPreloadRetries();
    _stopPositionUpdates();
    await _active.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _cancelCrossfade();
    await _active.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _ready;
    if (_isCrossfading) {
      await _cancelCrossfade();
    }

    final next = _computeNextIndex();
    if (next == null) {
      // End of queue: do not stop playback (which feels like a bug when users
      // tap Next). Just keep state consistent.
      _emitPlaybackState();
      return;
    }

    // Ticket 2.14: consumer soft limit + enforcement for skips/hour.
    // Do not enforce skip limit for auto-recovery skips.
    if (!_autoSkipInProgress) {
      final allowed = PlaybackSkipsGate.instance.tryConsumeUserSkip();
      if (!allowed) {
        _emitPlaybackState();
        return;
      }
    }

    final nextPos = _order.indexOf(next);
    if (nextPos >= 0) {
      _orderPos = nextPos;
    }

    // If we already have the next item warm in the inactive player, switch instantly.
    _currentIndex = next;
    mediaItem.add(_items[_currentIndex]);
    _currentIndexCtrl.add(_currentIndex);
    if (await _trySwitchToPreloaded(next)) return;

    await _playIndex(next);
  }

  @override
  Future<void> skipToPrevious() async {
    await _ready;
    await _cancelCrossfade();

    // Spotify behavior: if you’re more than a few seconds in, restart.
    if (_active.position > const Duration(seconds: 3)) {
      await _active.seek(Duration.zero);
      return;
    }

    final prev = _computePreviousIndex();
    if (prev == null) {
      await _active.seek(Duration.zero);
      return;
    }

    _orderPos = max(0, _orderPos - 1);
    try {
      await _playIndex(prev);
    } catch (_) {
      _emitPlaybackState();
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _cancelCrossfade();
      _stopPreloadRetries();
      _stopPositionUpdates();
      await _active.dispose();
      await _inactive.dispose();
      await _positionCtrl.close();
      await _durationCtrl.close();
      await _playerStateCtrl.close();
      await _currentIndexCtrl.close();
    }
    return super.customAction(name, extras);
  }

  // OPTIMIZED: Faster transition handling
  Future<void> _handleCompleted() async {
    if (_isCrossfading) return;

    // Count a completed song so interstitials trigger *between* songs.
    if (_items.isNotEmpty && _currentIndex >= 0 && _currentIndex < _items.length) {
      PlaybackAdGate.instance.onSongCompleted(trackKey: _items[_currentIndex].id);
    } else {
      PlaybackAdGate.instance.onSongCompleted();
    }

    if (_repeatMode == AudioServiceRepeatMode.one) {
      await _active.seek(Duration.zero);

      // If an interstitial is pending, pause here before looping.
      if (PlaybackAdGate.instance.consumePendingInterstitial(forceResumeAfter: true)) {
        _emitPlaybackState();
        return;
      }

      await _active.play();
      return;
    }

    final next = _computeNextIndex();
    if (next == null) {
      _emitPlaybackState();
      return;
    }

    final len = _order.length;
    if (len > 0) {
      _orderPos = (_orderPos + 1) % len;
    }

    _currentIndex = next;
    mediaItem.add(_items[_currentIndex]);
    _currentIndexCtrl.add(_currentIndex);
    
    // OPTIMIZED: Try preloaded switch first
    if (await _trySwitchToPreloaded(next)) {
      if (_audioLogsEnabled && kDebugMode) {
        debugPrint('[audio] fast switch using preloaded track');
      }
      return;
    }

    // OPTIMIZED: If not preloaded, play immediately
    if (_audioLogsEnabled && kDebugMode) {
      debugPrint('[audio] playing next without preload');
    }
    try {
      await _playIndex(next);
    } catch (_) {
      _emitPlaybackState();
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _active.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(_active.processingState),
      playing: _active.playing,
      updatePosition: _active.position,
      bufferedPosition: _active.bufferedPosition,
      speed: _active.speed,
      queueIndex: _currentIndex,
      shuffleMode: _shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: _repeatMode,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}