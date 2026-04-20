import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme.dart';

class AdVideoPlayer extends StatefulWidget {
  const AdVideoPlayer({
    super.key,
    required this.videoUrl,
    this.onCompleted,
    this.onSkip,
    this.isSkippable = false,
    this.autoPlay = true,
    this.looping = false,
    this.fit = BoxFit.cover,
  });

  final String videoUrl;
  final VoidCallback? onCompleted;
  final VoidCallback? onSkip;
  final bool isSkippable;
  final bool autoPlay;
  final bool looping;
  final BoxFit fit;

  @override
  State<AdVideoPlayer> createState() => _AdVideoPlayerState();
}

class _AdVideoPlayerState extends State<AdVideoPlayer> {
  VideoPlayerController? _controller;
  Object? _initError;
  bool _completed = false;
  StreamSubscription<void>? _completionPoll;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant AdVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl.trim() != widget.videoUrl.trim()) {
      _disposeController();
      _initError = null;
      _completed = false;
      _init();
    }
  }

  Future<void> _init() async {
    final url = widget.videoUrl.trim();
    if (kDebugMode) {
      debugPrint('🎬 AdVideoPlayer init videoUrl=$url');
    }
    if (url.isEmpty) {
      setState(() => _initError = StateError('Missing videoUrl'));
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      setState(() => _initError = FormatException('Invalid videoUrl'));
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;

    try {
      await controller.initialize();
      if (kDebugMode) {
        debugPrint('🎬 AdVideoPlayer initialized duration=${controller.value.duration}');
      }
      await controller.setLooping(widget.looping);
      if (!mounted) return;

      // A tiny poll loop is the most robust way to detect completion across
      // platforms without relying on exact listener semantics.
      _completionPoll?.cancel();
      _completionPoll = Stream<void>.periodic(const Duration(milliseconds: 250))
          .listen((_) => _checkCompletion());

      if (widget.autoPlay) {
        unawaited(controller.play());
      }

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  void _checkCompletion() {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized) return;

    final d = c.value.duration;
    final p = c.value.position;

    if (!_completed && d.inMilliseconds > 0 && p >= d) {
      _completed = true;
      widget.onCompleted?.call();
    }
  }

  void _disposeController() {
    _completionPoll?.cancel();
    _completionPoll = null;

    final c = _controller;
    _controller = null;
    if (c != null) {
      unawaited(c.dispose());
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final c = _controller;
    final initialized = c?.value.isInitialized == true;

    if (_initError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_disabled, size: 20),
            const SizedBox(width: 12),
            const Expanded(child: Text('Ad video unavailable')),
            if (widget.isSkippable && widget.onSkip != null)
              TextButton(onPressed: widget.onSkip, child: const Text('Skip')),
          ],
        ),
      );
    }

    if (!initialized) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final durationMs = c!.value.duration.inMilliseconds;
    final positionMs = c.value.position.inMilliseconds;
    final progress = durationMs <= 0 ? 0.0 : (positionMs / durationMs).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio,
            child: FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.black26,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandOrange),
              minHeight: 4,
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Row(
              children: [
                if (widget.isSkippable && widget.onSkip != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: widget.onSkip,
                    child: const Text('Skip'),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: c.value.isPlaying ? 'Pause' : 'Play',
                  onPressed: () {
                    if (c.value.isPlaying) {
                      unawaited(c.pause());
                    } else {
                      unawaited(c.play());
                    }
                    setState(() {});
                  },
                  icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
