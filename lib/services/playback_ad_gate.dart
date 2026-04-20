import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/subscriptions/subscriptions_controller.dart';

/// Keeps an in-memory "songs played" counter and emit an event when an
/// interstitial should be shown.
///
/// Source of truth for ads and frequency comes from `/api/subscriptions/me`
/// via [SubscriptionsController].
class PlaybackAdGate {
  PlaybackAdGate._();

  static final PlaybackAdGate instance = PlaybackAdGate._();

  final StreamController<InterstitialDueEvent> _interstitialDue =
      StreamController<InterstitialDueEvent>.broadcast();
  Stream<InterstitialDueEvent> get interstitialDue => _interstitialDue.stream;

  static const int _audioAdEverySongs = 2;
  static const int _videoAdEverySongs = 4;

  int _completedSongsTotal = 0;
  bool _pendingInterstitial = false;
  InterstitialRequiredMedia? _pendingRequiredMedia;

  bool _interstitialShowing = false;
  String? _lastCompletionTrackKey;
  DateTime? _lastCompletionAt;

  void reset() {
    _completedSongsTotal = 0;
    _pendingInterstitial = false;
    _pendingRequiredMedia = null;
  }

  /// Called by the UI when an interstitial is currently on screen.
  ///
  /// While true, the gate ignores new song-start signals to avoid rapid
  /// re-triggering when playback resumes.
  void setInterstitialShowing(bool showing) {
    _interstitialShowing = showing;
  }

  /// Call this when a song finishes playing.
  ///
  /// When the threshold is reached, the gate becomes "pending" and the
  /// interstitial is emitted right before the *next* song starts.
  void onSongCompleted({String? trackKey}) {
    if (_interstitialShowing) return;

    // Defensive de-dupe: the underlying player can emit multiple "completed"
    // signals during rapid state changes.
    final now = DateTime.now();
    if (trackKey != null && trackKey.isNotEmpty) {
      final lastAt = _lastCompletionAt;
      if (_lastCompletionTrackKey == trackKey && lastAt != null) {
        final deltaMs = now.difference(lastAt).inMilliseconds;
        if (deltaMs >= 0 && deltaMs < 1200) {
          return;
        }
      }
      _lastCompletionTrackKey = trackKey;
      _lastCompletionAt = now;
    }

    final entitlements = SubscriptionsController.instance.entitlements;
    if (!entitlements.effectiveAdsEnabled) {
      if (kDebugMode) {
        debugPrint('🎵 Song completed (ads disabled)');
      }
      _completedSongsTotal = 0;
      _pendingInterstitial = false;
      _pendingRequiredMedia = null;
      return;
    }

    // Only schedule a new interstitial when one isn't already pending.
    if (_pendingInterstitial) return;

    _completedSongsTotal += 1;

    if (kDebugMode) {
      debugPrint('🎵 Song completed. Total: $_completedSongsTotal');
    }

    // Rotation rules:
    // - Audio ad after every 2 completed songs
    // - Video ad after every 4 completed songs
    // This yields: 2=AUDIO, 4=VIDEO, 6=AUDIO, 8=VIDEO...
    if (_completedSongsTotal % _videoAdEverySongs == 0) {
      _pendingInterstitial = true;
      _pendingRequiredMedia = InterstitialRequiredMedia.video;
    } else if (_completedSongsTotal % _audioAdEverySongs == 0) {
      _pendingInterstitial = true;
      _pendingRequiredMedia = InterstitialRequiredMedia.audio;
    }

    if (_pendingInterstitial && kDebugMode) {
      if (_pendingRequiredMedia == InterstitialRequiredMedia.video) {
        debugPrint('🎬 Interstitial due: VIDEO');
      } else if (_pendingRequiredMedia == InterstitialRequiredMedia.audio) {
        debugPrint('🔊 Interstitial due: AUDIO');
      }
      debugPrint(
        '🎯 Interstitial pending (songs_total=$_completedSongsTotal media=${_pendingRequiredMedia?.name})',
      );
    }
  }

  /// Debug helper used by the temporary "TEST AD" button.
  ///
  /// Returns a small map so UI code can mirror the quick snippet:
  /// `{ requiredMedia: 'audio' | 'video' | null }`.
  Future<Map<String, dynamic>> getNextAdType() async {
    final entitlements = SubscriptionsController.instance.entitlements;
    if (!entitlements.effectiveAdsEnabled) {
      return <String, dynamic>{
        'requiredMedia': null,
        'adsEnabled': false,
        'songsCompletedTotal': _completedSongsTotal,
      };
    }

    final nextTotal = _completedSongsTotal + 1;
    String? required;
    if (nextTotal % _videoAdEverySongs == 0) {
      required = InterstitialRequiredMedia.video.name;
    } else if (nextTotal % _audioAdEverySongs == 0) {
      required = InterstitialRequiredMedia.audio.name;
    }

    return <String, dynamic>{
      'requiredMedia': required,
      'adsEnabled': true,
      'songsCompletedTotal': _completedSongsTotal,
      'nextSongsTotal': nextTotal,
    };
  }

  /// Debug helper: emit an interstitial immediately (bypasses the
  /// song-completion threshold) so you can verify end-to-end wiring.
  void debugEmitInterstitialNow({InterstitialRequiredMedia? requiredMedia}) {
    if (!kDebugMode) return;
    if (_interstitialShowing) return;
    if (_interstitialDue.isClosed) return;

    _interstitialDue.add(
      InterstitialDueEvent(
        forceResumeAfter: true,
        reason: 'debug_manual_trigger',
        requiredMedia: requiredMedia,
      ),
    );

    if (requiredMedia == InterstitialRequiredMedia.video) {
      debugPrint('🎬 Interstitial due: VIDEO');
    } else if (requiredMedia == InterstitialRequiredMedia.audio) {
      debugPrint('🔊 Interstitial due: AUDIO');
    } else {
      debugPrint('🎬 Interstitial due');
    }
  }

  /// Consumes a pending interstitial and emit the event.
  ///
  /// Returns true when an interstitial was emitted and playback should be
  /// paused/blocked until the interstitial finishes.
  bool consumePendingInterstitial({bool forceResumeAfter = false}) {
    if (_interstitialShowing) return false;

    final entitlements = SubscriptionsController.instance.entitlements;
    if (!entitlements.effectiveAdsEnabled) {
      _completedSongsTotal = 0;
      _pendingInterstitial = false;
      _pendingRequiredMedia = null;
      return false;
    }

    if (!_pendingInterstitial) return false;

    final required = _pendingRequiredMedia;
    _pendingInterstitial = false;
    _pendingRequiredMedia = null;

    if (!_interstitialDue.isClosed) {
      _interstitialDue.add(
        InterstitialDueEvent(
          forceResumeAfter: forceResumeAfter,
          reason: 'songs_completed',
          requiredMedia: required,
        ),
      );
    }

    if (kDebugMode) {
      if (required == InterstitialRequiredMedia.video) {
        debugPrint('🎬 Interstitial due: VIDEO');
      } else if (required == InterstitialRequiredMedia.audio) {
        debugPrint('🔊 Interstitial due: AUDIO');
      }
      debugPrint('🎯 Interstitial due (pending consumed)');
    }
    return true;
  }

  Future<void> dispose() async {
    await _interstitialDue.close();
  }
}

class InterstitialDueEvent {
  const InterstitialDueEvent({
    this.forceResumeAfter = false,
    this.reason,
    this.requiredMedia,
  });

  final bool forceResumeAfter;
  final String? reason;
  final InterstitialRequiredMedia? requiredMedia;
}

enum InterstitialRequiredMedia {
  audio,
  video,
}
