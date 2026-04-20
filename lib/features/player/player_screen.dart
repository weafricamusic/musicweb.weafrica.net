import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_service/audio_service.dart';

import '../../app/theme.dart';
import 'playback_controller.dart';
import 'queue_sheet.dart';
import 'song_comments_sheet.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _scrubValue;
  bool _isScrubbing = false;

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Now Playing'),
        backgroundColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final track = controller.current;
          final isPlaying = controller.isPlaying;
          final isLoading = controller.isLoading;
          final error = controller.errorMessage;

          if (track == null) {
            return const Center(child: Text('Nothing playing'));
          }

          final progress = controller.progress.clamp(0.0, 1.0);
          final sliderValue = _isScrubbing ? (_scrubValue ?? progress) : progress;
          final previewPosition = Duration(
            milliseconds:
                (controller.duration.inMilliseconds * sliderValue).round(),
          );

          return SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              children: [
                if (error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFF6B6B).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFFF6B6B)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            error,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFFFF6B6B)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: controller.retryCurrent,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                Hero(
                  tag: 'player_artwork',
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: track.artworkUri != null
                          ? CachedNetworkImage(
                              imageUrl: track.artworkUri.toString(),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                child: Icon(
                                  Icons.album,
                                  size: 84,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Icon(
                                  Icons.album,
                                  size: 84,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.album,
                                size: 84,
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 18),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.brandOrange,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.brandOrange,
                    overlayColor: AppColors.brandOrange.withValues(alpha: 0.18),
                  ),
                  child: Slider(
                    value: sliderValue.clamp(0.0, 1.0),
                    onChangeStart: (_) {
                      setState(() {
                        _isScrubbing = true;
                        _scrubValue = progress;
                      });
                    },
                    onChanged: (v) {
                      setState(() => _scrubValue = v.clamp(0.0, 1.0));
                    },
                    onChangeEnd: (v) {
                      final p = Duration(
                        milliseconds:
                            (controller.duration.inMilliseconds * v).round(),
                      );
                      controller.seek(p);
                      setState(() {
                        _isScrubbing = false;
                        _scrubValue = null;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      PlaybackController.format(
                        _isScrubbing ? previewPosition : controller.position,
                      ),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                    Text(
                      PlaybackController.format(controller.duration),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: controller.toggleShuffle,
                      tooltip: 'Shuffle',
                      icon: Icon(
                        Icons.shuffle,
                        color:
                            controller.shuffleEnabled ? AppColors.brandOrange : null,
                      ),
                    ),
                    IconButton(
                      onPressed:
                          controller.canSkipPrevious ? controller.skipPrevious : null,
                      onLongPress: () => controller.seekBy(
                        const Duration(seconds: -10),
                      ),
                      tooltip: 'Previous',
                      icon: const Icon(Icons.skip_previous),
                    ),
                    Container(
                      height: 56,
                      width: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.brandOrange,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: isLoading ? null : controller.togglePlay,
                        tooltip: isLoading
                            ? 'Loading'
                            : (isPlaying ? 'Pause' : 'Play'),
                        icon: isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                              ),
                      ),
                    ),
                    IconButton(
                      onPressed: controller.canSkipNext ? controller.skipNext : null,
                      onLongPress: () => controller.seekBy(
                        const Duration(seconds: 10),
                      ),
                      tooltip: 'Next',
                      icon: const Icon(Icons.skip_next),
                    ),
                    IconButton(
                      onPressed: controller.toggleRepeat,
                      tooltip: 'Repeat',
                      icon: Icon(
                        controller.repeatMode == AudioServiceRepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color:
                            controller.repeatEnabled ? AppColors.brandOrange : null,
                      ),
                    ),
                    IconButton(
                      onPressed: () => showQueueSheet(context),
                      tooltip: 'Queue',
                      icon: const Icon(Icons.queue_music),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final liked = await controller.toggleLikeCurrent();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                liked
                                    ? 'Added to liked songs'
                                    : 'Removed from liked songs',
                              ),
                            ),
                          );
                        },
                        icon: Icon(
                          controller.isCurrentLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                        label: const Text('Like'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showSongCommentsSheet(context, track: track),
                        icon: const Icon(Icons.comment_outlined),
                        label: const Text('Comments'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.shareCurrent,
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
