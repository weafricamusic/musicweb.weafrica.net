import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class ReelPlaybackCoordinator {
  ReelPlaybackCoordinator._();

  static final ReelPlaybackCoordinator instance = ReelPlaybackCoordinator._();

  String? _activeReelId;
  final Map<String, Future<void> Function()> _pauseByReel = <String, Future<void> Function()>{};

  void register(String reelId, Future<void> Function() pauseHandler) {
    _pauseByReel[reelId] = pauseHandler;
  }

  void unregister(String reelId) {
    _pauseByReel.remove(reelId);
    if (_activeReelId == reelId) {
      _activeReelId = null;
    }
  }

  Future<void> activate(String reelId) async {
    if (_activeReelId == reelId) return;
    final previous = _activeReelId;
    _activeReelId = reelId;
    if (previous != null) {
      final pause = _pauseByReel[previous];
      if (pause != null) {
        await pause();
      }
    }
  }
}

class ReelVideoPlayer extends StatefulWidget {
  const ReelVideoPlayer({
    super.key,
    required this.reelId,
    required this.videoUrl,
    required this.sessionId,
    this.thumbnailUrl,
    this.isActive = false,
    this.isMuted = true,
    this.onWatchReported,
    this.onWatchMoreReels,
  });

  final String reelId;
  final String videoUrl;
  final String? thumbnailUrl;
  final bool isActive;
  final bool isMuted;
  final String sessionId;
  final void Function(int watchDuration)? onWatchReported;
  final VoidCallback? onWatchMoreReels;

  @override
  State<ReelVideoPlayer> createState() => _ReelVideoPlayerState();
}

class _ReelVideoPlayerState extends State<ReelVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _timedOut = false;
  String? _error;
  double _visibleFraction = 0;
  int _retryAttempt = 0;
  bool _completed = false;

  DateTime? _watchStartedAt;
  int _watchDurationSeconds = 0;

  @override
  void initState() {
    super.initState();
    ReelPlaybackCoordinator.instance.register(widget.reelId, _pausePlayback);
  }

  @override
  void didUpdateWidget(covariant ReelVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.reelId != widget.reelId || oldWidget.videoUrl != widget.videoUrl) {
      unawaited(_disposeController());
      _timedOut = false;
      _error = null;
      _retryAttempt = 0;
      ReelPlaybackCoordinator.instance.unregister(oldWidget.reelId);
      ReelPlaybackCoordinator.instance.register(widget.reelId, _pausePlayback);
    }

    final controller = _controller;
    if (controller != null && controller.value.isInitialized && oldWidget.isMuted != widget.isMuted) {
      unawaited(() async {
        await controller.setVolume(widget.isMuted ? 0.0 : 1.0);
        // If user unmutes while the reel is in view, ensure playback is active
        // so sound starts immediately.
        if (!widget.isMuted && _shouldBePlaying && !controller.value.isPlaying) {
          await controller.play();
          await controller.setVolume(1.0);
          _startWatchTimer();
        }
      }());
    }

    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        unawaited(_ensurePlayback());
      } else {
        unawaited(_pausePlayback());
      }
    }
  }

  @override
  void dispose() {
    ReelPlaybackCoordinator.instance.unregister(widget.reelId);
    unawaited(_flushWatchImpression());
    unawaited(_disposeController());
    super.dispose();
  }

  Future<void> _disposeController() async {
    _stopWatchTimer();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      await controller.dispose();
    }
  }

  void _onControllerTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration.inMilliseconds <= 0) return;
    final isDone = controller.value.position >= duration - const Duration(milliseconds: 250);
    if (isDone && !_completed) {
      setState(() {
        _completed = true;
      });
      _stopWatchTimer();
      unawaited(_flushWatchImpression());
    }
  }

  void _startWatchTimer() {
    _watchStartedAt ??= DateTime.now();
  }

  void _stopWatchTimer() {
    final started = _watchStartedAt;
    if (started == null) return;
    final delta = DateTime.now().difference(started).inSeconds;
    if (delta > 0) {
      _watchDurationSeconds += delta;
    }
    _watchStartedAt = null;
  }

  Future<void> _flushWatchImpression() async {
    _stopWatchTimer();
    if (_watchDurationSeconds <= 0) return;

    final controller = _controller;
    final completed = controller != null &&
        controller.value.isInitialized &&
        controller.value.duration.inMilliseconds > 0 &&
        controller.value.position.inMilliseconds >=
            controller.value.duration.inMilliseconds - 500;

    final durationToReport = _watchDurationSeconds;
    _watchDurationSeconds = 0;

    widget.onWatchReported?.call(durationToReport);

    try {
      await Supabase.instance.client.from('reel_impressions').insert({
        'reel_id': widget.reelId,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'session_id': widget.sessionId,
        'watch_duration': durationToReport,
        'completed': completed,
      });
    } catch (_) {
      // Best effort analytics write.
    }
  }

  bool get _shouldBePlaying => widget.isActive && _visibleFraction >= 0.8;

  Future<void> _initializeController() async {
    if (_loading) return;

    final videoUri = Uri.tryParse(widget.videoUrl);
    if (videoUri == null) {
      if (mounted) {
        setState(() {
          _error = 'Invalid video URL.';
          _timedOut = false;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _timedOut = false;
    });

    try {
      final controller = VideoPlayerController.networkUrl(videoUri);
      await controller.initialize().timeout(const Duration(seconds: 5));
      await controller.setLooping(false);
      await controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      controller.addListener(_onControllerTick);
      if (!mounted) {
        controller.removeListener(_onControllerTick);
        await controller.dispose();
        return;
      }

      await _disposeController();
      _controller = controller;
      _retryAttempt = 0;
      setState(() {
        _loading = false;
        _completed = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _timedOut = true;
        _error = 'Video load timed out.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _timedOut = false;
        _error = 'Network issue while loading video.';
      });
      unawaited(_retryInitializeWithBackoff());
    }
  }

  Future<void> _retryInitializeWithBackoff() async {
    if (_retryAttempt >= 3) return;
    final delayMs = (400 * (1 << _retryAttempt)).clamp(400, 4000);
    _retryAttempt += 1;
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    if (!mounted || !_shouldBePlaying) return;
    await _initializeController();
    await _ensurePlayback();
  }

  Future<void> _pausePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      _stopWatchTimer();
    }
  }

  Future<void> _ensurePlayback() async {
    if (!_shouldBePlaying) {
      await _pausePlayback();
      return;
    }

    if (_controller == null) {
      await _initializeController();
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    await controller.setVolume(widget.isMuted ? 0.0 : 1.0);

    await ReelPlaybackCoordinator.instance.activate(widget.reelId);

    if (!controller.value.isPlaying) {
      if (_completed) {
        setState(() {
          _completed = false;
        });
      }
      await controller.play();
      _startWatchTimer();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    _visibleFraction = info.visibleFraction;
    if (_shouldBePlaying) {
      unawaited(_ensurePlayback());
    } else {
      unawaited(_pausePlayback());
      unawaited(_flushWatchImpression());
    }
  }

  Widget _buildThumbnail() {
    final thumb = widget.thumbnailUrl;
    if (thumb == null || thumb.trim().isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Image.network(
      thumb,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(color: Colors.black),
    );
  }

  Widget _buildErrorOverlay() {
    if (_error == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _error = null;
                  _timedOut = false;
                });
                await _initializeController();
                await _ensurePlayback();
              },
              child: Text(_timedOut ? 'Retry' : 'Retry now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedOverlay() {
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized == true;

    return VisibilityDetector(
      key: ValueKey<String>('reel-${widget.reelId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnail(),
          if (initialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          _buildCompletedOverlay(),
          _buildErrorOverlay(),
        ],
      ),
    );
  }
}
