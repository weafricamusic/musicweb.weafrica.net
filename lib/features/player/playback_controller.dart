import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/config/debug_flags.dart';
import '../../app/utils/user_facing_error.dart';
import '../../audio/audio.dart';
import '../../services/content_access_gate.dart';
import '../../services/liked_tracks_store.dart';
import '../../services/playback_interstitial_ads.dart';
import '../../services/playback_skips_gate.dart';
import '../../services/recent_contexts_service.dart';
import '../library/services/library_download_service.dart';
import '../tracks/track.dart';

export '../tracks/track.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController._();

  static final PlaybackController instance = PlaybackController._();

  Track? _current;
  bool _isPlaying = false;
  bool _isLoading = false;
  String? _errorMessage;
  final List<Track> _upNext = <Track>[];
  final List<Track> _history = <Track>[];
  final List<StreamSubscription<dynamic>> _subs = [];
  final LibraryDownloadService _downloads = LibraryDownloadService();
  bool _isBound = false;
  bool _autoAdvanceInFlight = false;
  int _autoAdvanceToken = 0;
  Timer? _errorDebounceTimer;
  int _errorDebounceToken = 0;
  String? _pendingErrorMessage;
  int? _pendingErrorIndex;
  List<Track> _queueTracks = const [];
  int _queueIndex = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  Track? get current => _current;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Track> get upNext => List.unmodifiable(_upNext);
  List<Track> get history => List.unmodifiable(_history);
  Duration get position => _position;
  Duration get duration => _duration;
  AudioServiceShuffleMode get shuffleMode => _shuffleMode;
  AudioServiceRepeatMode get repeatMode => _repeatMode;
  bool get shuffleEnabled => _shuffleMode == AudioServiceShuffleMode.all;
  bool get repeatEnabled => _repeatMode != AudioServiceRepeatMode.none;
  bool get canSkipNext => _upNext.isNotEmpty;
  bool get canSkipPrevious => _queueIndex > 0;
  int get historyCount => _history.length;
  double get progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return _position.inMilliseconds / total;
  }

  void _cancelPendingError() {
    _errorDebounceToken++;
    _errorDebounceTimer?.cancel();
    _errorDebounceTimer = null;
    _pendingErrorMessage = null;
    _pendingErrorIndex = null;
  }

  static String format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _ensureBound() {
    if (_isBound) return;
    _isBound = true;

    final handler = weafricaAudioHandler;

    _subs.add(
      handler.customEvent.listen((event) {
        if (event is! Map) return;
        final type = event['type'];
        if (type == 'playback_error') {
          final message = event['message'];
          if (message is String && message.trim().isNotEmpty) {
            // Stop any stuck "loading" UI quickly, but delay surfacing the
            // actual error so fast auto-skip/recovery remains silent.
            _isLoading = false;
            _isPlaying = false;

            _pendingErrorMessage = message;
            final idxAny = event['index'];
            final idx = idxAny is int ? idxAny : int.tryParse(idxAny?.toString() ?? '');
            _pendingErrorIndex = idx;

            _errorDebounceTimer?.cancel();
            final token = ++_errorDebounceToken;
            _errorDebounceTimer = Timer(const Duration(milliseconds: 900), () {
              if (token != _errorDebounceToken) return;
              _errorDebounceTimer = null;

              // If we already advanced to another track, keep it silent.
              final pendingIndex = _pendingErrorIndex;
              if (pendingIndex != null && pendingIndex != _queueIndex) {
                _pendingErrorMessage = null;
                _pendingErrorIndex = null;
                return;
              }

              final pendingMessage = _pendingErrorMessage;
              _pendingErrorMessage = null;
              _pendingErrorIndex = null;
              if (pendingMessage == null || pendingMessage.trim().isEmpty) return;

              _errorMessage = pendingMessage;
              notifyListeners();
            });

            notifyListeners();
          }
        }
        if (type == 'playback_auto_skipped') {
          // Keep recovery silent.
          _cancelPendingError();
          if (_errorMessage != null) {
            _errorMessage = null;
            notifyListeners();
          }
        }
        if (type == 'playback_recovered') {
          _cancelPendingError();
          if (_errorMessage != null) {
            _errorMessage = null;
            notifyListeners();
          }
        }
      }),
    );

    _subs.add(
      handler.positionStream.listen((pos) {
        _position = pos;
        notifyListeners();
      }),
    );

    _subs.add(
      handler.durationStream.listen((dur) {
        if (dur != null) {
          _duration = dur;
          notifyListeners();
        }
      }),
    );

    _subs.add(
      handler.playerStateStream.listen((state) {
        _isPlaying = state.playing;

        final wasLoading = _isLoading;
        final processingLoading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;

        if (!processingLoading) {
          _isLoading = false;
        } else {
          // While processing is loading/buffering, only keep the loading UI if
          // we're actively trying to play (or we were already loading and
          // haven't surfaced an error yet).
          _isLoading = state.playing || (wasLoading && _errorMessage == null);
        }

        if (!state.playing && _errorMessage != null) {
          _isLoading = false;
        }

        if (state.processingState == ProcessingState.completed) {
          if (_upNext.isEmpty) {
            _position = _duration;
            _isPlaying = false;
          } else {
            // If the handler's queue only contains the current item (or it got
            // out of sync), it won't auto-advance. Add a short grace period so
            // we don't double-skip when the handler *does* advance.
            unawaited(_maybeAutoAdvanceAfterCompletion());
          }
        }

        notifyListeners();
      }),
    );

    _subs.add(
      handler.playbackState.listen((state) {
        _shuffleMode = state.shuffleMode;
        _repeatMode = state.repeatMode;
        notifyListeners();
      }),
    );

    _subs.add(
      handler.currentIndexStream.listen((index) {
        if (index == null) return;
        if (_queueTracks.isEmpty) return;
        if (index < 0 || index >= _queueTracks.length) return;

        // If playback advanced (manual or auto-skip), keep prior errors silent.
        if (_pendingErrorMessage != null || _errorMessage != null) {
          _cancelPendingError();
          _errorMessage = null;
        }

        if (_queueIndex != index) {
          final prev = _current;
          final next = _queueTracks[index];
          if (prev != null && prev.id != next.id) {
            _history.add(prev);
          }
        }

        _queueIndex = index;
        _current = _queueTracks[index];

        _upNext
          ..clear()
          ..addAll(_queueTracks.skip(index + 1));

        notifyListeners();
      }),
    );
  }

  Future<void> _maybeAutoAdvanceAfterCompletion() async {
    if (_autoAdvanceInFlight) return;
    if (_upNext.isEmpty) return;

    final handler = maybeWeafricaAudioHandler;
    if (handler == null) return;

    _autoAdvanceInFlight = true;
    final token = ++_autoAdvanceToken;
    final currentIdBefore = _current?.id;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (token != _autoAdvanceToken) return;

      // If something else already advanced/resumed, do nothing.
      if (_current?.id != currentIdBefore) return;

      final ps = handler.player.playerState;
      if (ps.playing) return;
      if (ps.processingState != ProcessingState.completed) return;
      if (_upNext.isEmpty) return;

      // Interstitial ads: show after N completed songs (Free plan), before
      // starting the next track.
      await PlaybackInterstitialAds.instance.maybeShowAfterSongCompleted();
      if (token != _autoAdvanceToken) return;
      if (_current?.id != currentIdBefore) return;

      final next = _upNext.first;
      final rest = _upNext.length > 1 ? _upNext.sublist(1) : const <Track>[];
      await _playInternal(next, queue: rest);
    } finally {
      _autoAdvanceInFlight = false;
    }
  }

  static List<Track> _normalizeQueue(Track current, List<Track> queue) {
    final currentUri = current.audioUri;
    final currentKey = current.id ?? currentUri?.toString() ?? '${current.title}:${current.artist}';
    final seen = <String>{};
    seen.add(currentKey);

    final out = <Track>[];
    for (final t in queue) {
      final uri = t.audioUri;

      // Avoid repeating the currently playing item.
      if (current.id != null && t.id != null && current.id == t.id) {
        continue;
      }
      if (currentUri != null && uri != null && uri.toString() == currentUri.toString()) {
        continue;
      }

      final key = t.id ?? uri?.toString() ?? '${t.title}:${t.artist}';
      if (!seen.add(key)) continue;
      out.add(t);
    }
    return out;
  }

  Uri? _resolvePlayableUri(Track track, Map<String, String> downloadedIndex) {
    final id = track.id?.trim();
    if (id != null && id.isNotEmpty) {
      final localPath = downloadedIndex[id]?.trim();
      if (localPath != null && localPath.isNotEmpty) {
        return Uri.file(localPath);
      }
    }
    return track.audioUri;
  }

  Future<void> _playInternal(Track track, {List<Track>? queue}) async {
    final contentId = (track.id ?? track.audioUri?.toString() ?? '${track.title}:${track.artist}').trim();
    if (contentId.isNotEmpty) {
      final allowed = ContentAccessGate.instance.ensureNotifiedBlocked(
        contentId: contentId,
        isExclusive: track.isExclusive,
      );
      if (!allowed) {
        _isLoading = false;
        _isPlaying = false;
        _errorMessage = track.isExclusive
            ? 'This track is exclusive. Upgrade to unlock it.'
            : 'This track is locked on your plan. Upgrade to unlock it.';
        notifyListeners();
        return;
      }
    }

    _ensureBound();

    // Android 13+ requires runtime notification permission for the media
    // playback notification to show. Request it when the user starts playback.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      } catch (_) {
        // Ignore (some devices/ROMs may behave differently).
      }
    }

    if (_current != null) _history.add(_current!);

    _current = track;
    _isPlaying = false;
    _isLoading = true;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = track.duration ?? Duration.zero;

    // Always normalize the queue to avoid "Next"/autoplay breaking when
    // some tracks are missing audio URLs or when the current track is included.
    final queueInput = queue ?? List<Track>.from(_upNext);
    final normalizedUpNext = _normalizeQueue(track, queueInput);
    _upNext
      ..clear()
      ..addAll(normalizedUpNext);

    _queueTracks = [track, ..._upNext];
    _queueIndex = 0;

    Map<String, String> downloadedIndex = const <String, String>{};
    try {
      downloadedIndex = await _downloads.listDownloadedTrackPaths();
    } catch (_) {
      // Best-effort fallback to remote streaming.
    }

    final source = _resolvePlayableUri(track, downloadedIndex);
    if (source == null) {
      _isLoading = false;
      _isPlaying = false;
      _errorMessage = 'Audio is unavailable for this track.';
      notifyListeners();
      return;
    }

    try {
      notifyListeners();

      final handler = weafricaAudioHandler;
      final uris = <Uri>[];
      final items = <MediaItem>[];
      for (final t in _queueTracks) {
        final uri = _resolvePlayableUri(t, downloadedIndex);
        if (uri == null) continue;
        uris.add(uri);
        items.add(
          MediaItem(
            id: uri.toString(),
            title: t.title,
            artist: t.artist,
            artUri: t.artworkUri,
            duration: t.duration,
          ),
        );
      }

      if (uris.isEmpty) {
        throw StateError('Missing audio URL(s) for this queue.');
      }

      if (uris.length == 1) {
        await handler.playSingle(item: items.first, uri: uris.first);
      } else {
        await handler.playQueue(items: items, uris: uris, initialIndex: 0);
      }

      unawaited(
        RecentContextsService.instance.recordTrackPlay(track).catchError(
          (e, st) {
            if (kDebugMode) {
              debugPrint('recent_contexts recordTrackPlay failed: $e');
              debugPrintStack(stackTrace: st, maxFrames: 40);
            }
          },
        ),
      );
      _errorMessage = null;
    } catch (e) {
      _isLoading = false;
      _isPlaying = false;
      _errorMessage = _friendlyPlaybackError(e, source: source);
      if (kDebugMode) {
        debugPrint('Playback error for ${source.toString()}: $e');
      }
      notifyListeners();
    }
  }

  String _friendlyPlaybackError(Object error, {required Uri source}) {
    if (error is TimeoutException) {
      return 'Audio took too long to load. Check your connection and try again.';
    }

    if (error is PlayerException) {
      final code = error.code;
      final message = (error.message ?? '').trim();
      final lower = message.toLowerCase();

      // Prefer friendly, non-technical messages.
      if (lower.contains('403') || lower.contains('forbidden') || lower.contains('permission')) {
        return 'This audio is not accessible right now.';
      }

      if (lower.contains('404') || lower.contains('not found')) {
        return 'Audio file not found.';
      }

      if (lower.contains('connectexception') ||
          lower.contains('failed to connect') ||
          lower.contains('unknownhostexception') ||
          lower.contains('no address associated with hostname') ||
          lower.contains('network is unreachable') ||
          lower.contains('connection refused') ||
          lower.contains('connection reset') ||
          lower.contains('sockettimeoutexception') ||
          lower.contains('timed out') ||
          lower.contains('timeout') ||
          lower.contains('httphostconnectexception') ||
          lower.contains('httpdatasource') ||
          lower.contains('unable to resolve host') ||
          lower.contains('failed host lookup') ||
          lower.contains('name or service not known') ||
          lower.contains('handshake') ||
          lower.contains('dns')) {
        return 'Check your internet connection and try again.';
      }

      if (DebugFlags.showDeveloperUi) {
        final details = <String>[
          'code=$code',
          if (message.isNotEmpty) message,
        ].join(' • ');
        return details.isEmpty ? 'Could not play this audio.' : 'Could not play this audio ($details)';
      }

      return 'Could not play this audio. Please try again.';
    }

    if (error is PlayerInterruptedException) {
      return 'Playback interrupted. Try again.';
    }

    return UserFacingError.message(
      error,
      fallback: 'Could not play this audio. Please try again.',
    );
  }

  void retryCurrent() {
    final track = _current;
    if (track == null) return;
    unawaited(_playInternal(track));
  }

  void play(Track track, {List<Track>? queue}) {
    unawaited(_playInternal(track, queue: queue));
  }

  void setQueue(List<Track> queue) {
    _upNext
      ..clear()
      ..addAll(queue);
    notifyListeners();
  }

  void addToUpNext(Track track, {bool toFront = false}) {
    if (toFront) {
      _upNext.insert(0, track);
    } else {
      _upNext.add(track);
    }
    notifyListeners();
    // Keep the audio handler's internal queue in sync so skip/next logic works
    // correctly without stopping playback.
    final uri = track.audioUri;
    if (uri != null) {
      final item = MediaItem(
        id: uri.toString(),
        title: track.title,
        artist: track.artist,
        artUri: track.artworkUri,
        duration: track.duration,
      );
      final handler = maybeWeafricaAudioHandler;
      if (handler != null) {
        final insertPos = toFront ? _queueIndex + 1 : null;
        unawaited(handler.insertIntoQueue(item, insertAt: insertPos));
      }
    }
  }

  void insertIntoUpNextAt(int index, Track track) {
    final clamped = index.clamp(0, _upNext.length);
    _upNext.insert(clamped, track);
    notifyListeners();
  }

  void removeFromUpNextAt(int index) {
    if (index < 0 || index >= _upNext.length) return;
    _upNext.removeAt(index);
    notifyListeners();
  }

  bool removeFromUpNext(Track track) {
    final idx = _upNext.indexWhere(
      (t) {
        if (t.id != null && track.id != null) return t.id == track.id;
        return t.title == track.title && t.artist == track.artist;
      },
    );
    if (idx == -1) return false;
    _upNext.removeAt(idx);
    notifyListeners();
    return true;
  }

  void playFromQueueIndex(int index) {
    if (index < 0 || index >= _upNext.length) return;
    final selected = _upNext.removeAt(index);
    unawaited(_playInternal(selected));
  }

  void playFromUpNextStartingAt(int index) {
    if (index < 0 || index >= _upNext.length) return;
    final selected = _upNext[index];
    final after = _upNext.sublist(index + 1);
    final before = _upNext.sublist(0, index);

    _upNext
      ..clear()
      ..addAll(after)
      ..addAll(before);

    unawaited(_playInternal(selected));
  }

  void togglePlay() {
    if (_current == null) return;

    _ensureBound();

    final handler = weafricaAudioHandler;
    unawaited(() async {
      try {
        if (handler.player.playing) {
          await handler.pause();
        } else {
          await handler.play();
        }
      } catch (_) {
        _errorMessage = 'Playback failed.';
        notifyListeners();
      }
    }());
  }

  void seek(Duration position) {
    if (_current == null) return;
    _ensureBound();
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _duration ? _duration : position);
    if (clamped == _position) return;
    _position = clamped;

    final handler = weafricaAudioHandler;
    unawaited(() async {
      try {
        await handler.seek(clamped);
      } catch (_) {
        // Ignore; keep UI position.
      }
    }());

    notifyListeners();
  }

  void seekBy(Duration delta) {
    if (_current == null) return;
    seek(_position + delta);
  }

  void skipNext() {
    if (_upNext.isEmpty) return;
    _ensureBound();
    unawaited(_skipNextRobust());
  }

  Future<void> _skipNextRobust() async {
    if (_upNext.isEmpty) return;
    final handler = maybeWeafricaAudioHandler;

    // Prefer a lightweight handler-level skip (keeps crossfade/preload).
    // If the handler doesn't advance (e.g. queue only has one item), fall back
    // to rebuilding the queue from our `_upNext`.
    final beforeTrackId = _current?.id;
    try {
      if (handler != null) {
        await handler.skipToNext();
      }
    } catch (_) {
      // Ignore and fall back below.
    }

    // Give streams a moment to propagate currentIndex updates.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    if (_current?.id != beforeTrackId) return; // advanced successfully

    // If the handler blocked the skip due to skip limit, do not fall back to
    // rebuilding the queue (which would bypass the limit).
    if (PlaybackSkipsGate.instance.wasSkipDeniedRecently()) return;

    if (_upNext.isEmpty) return;

    final next = _upNext.first;
    final rest = _upNext.length > 1 ? _upNext.sublist(1) : const <Track>[];
    await _playInternal(next, queue: rest);
  }

  void skipPrevious() {
    if (_queueIndex <= 0) return;
    _ensureBound();
    unawaited(weafricaAudioHandler.skipToPrevious());
  }

  void toggleShuffle() {
    if (_current == null) return;
    _ensureBound();
    final next = shuffleEnabled
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    _shuffleMode = next;
    unawaited(weafricaAudioHandler.setShuffleMode(next));
    notifyListeners();
  }

  void toggleRepeat() {
    if (_current == null) return;
    _ensureBound();
    final next = switch (_repeatMode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
      AudioServiceRepeatMode.group => AudioServiceRepeatMode.none,
    };
    _repeatMode = next;
    unawaited(weafricaAudioHandler.setRepeatMode(next));
    notifyListeners();
  }

  bool get isCurrentLiked {
    final track = _current;
    if (track == null) return false;
    return LikedTracksStore.instance.isLiked(track);
  }

  Future<bool> toggleLikeCurrent() async {
    final track = _current;
    if (track == null) return false;
    final liked = await LikedTracksStore.instance.toggle(track);
    notifyListeners();
    return liked;
  }

  Future<void> shareCurrent() async {
    final track = _current;
    if (track == null) return;

    final parts = <String>['${track.title} — ${track.artist}'];
    final uri = track.audioUri;
    if (uri != null) parts.add(uri.toString());
    await Share.share(parts.join('\n'));
  }

  void clearQueue() {
    _upNext.clear();
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  void restoreHistory(List<Track> history) {
    _history
      ..clear()
      ..addAll(history);
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 || oldIndex >= _upNext.length) return;
    if (newIndex < 0 || newIndex > _upNext.length) return;
    final item = _upNext.removeAt(oldIndex);
    _upNext.insert(newIndex, item);
    notifyListeners();
  }
}
