import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme.dart';
import '../video.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({super.key, required this.video});

  final Video video;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;

  bool _playWhenReady = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final uri = widget.video.videoUri;
    if (uri == null) return;

    final next = VideoPlayerController.networkUrl(uri);

    setState(() {
      _controller = next;
      _initFuture = next.initialize();
    });

    try {
      await _initFuture;
      if (!mounted) return;
      if (_playWhenReady) {
        await next.play();
      }
      setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${two(h)}:${two(m)}:${two(sec)}';
    return '${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final uri = v.videoUri;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(v.title),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
      ),
      body: uri == null
          ? const Center(
              child: Text(
                'This video has no playable URL yet.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          : FutureBuilder<void>(
              future: _initFuture,
              builder: (context, snap) {
                final controller = _controller;
                final ready = snap.connectionState == ConnectionState.done &&
                    controller != null &&
                    controller.value.isInitialized;

                if (!ready) {
                  return const Center(child: CircularProgressIndicator());
                }

                final isPlaying = controller.value.isPlaying;
                final pos = controller.value.position;
                final dur = controller.value.duration;

                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio <= 0 ? 16 / 9 : controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      color: AppColors.surface,
                      child: Column(
                        children: [
                          VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: AppColors.stageGold,
                              bufferedColor: AppColors.border,
                              backgroundColor: AppColors.surface2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              IconButton(
                                tooltip: isPlaying ? 'Pause' : 'Play',
                                onPressed: () async {
                                  if (!mounted) return;
                                  if (isPlaying) {
                                    _playWhenReady = false;
                                    await controller.pause();
                                  } else {
                                    _playWhenReady = true;
                                    await controller.play();
                                  }
                                  if (mounted) setState(() {});
                                },
                                icon: Icon(
                                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                  color: AppColors.stageGold,
                                  size: 34,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_fmt(pos)} / ${_fmt(dur)}',
                                  style: const TextStyle(color: AppColors.textMuted),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Replay',
                                onPressed: () async {
                                  await controller.seekTo(Duration.zero);
                                  await controller.play();
                                  if (mounted) setState(() {});
                                },
                                icon: const Icon(Icons.replay, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
