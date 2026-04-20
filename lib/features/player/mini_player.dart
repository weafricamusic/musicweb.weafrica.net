import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../app/theme.dart';
import 'playback_controller.dart';
import 'queue_sheet.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double? _scrubValue;
  bool _isScrubbing = false;

  static const double _swipeUpVelocityThreshold = 600;

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final track = controller.current;
        final upNextCount = controller.upNext.length;
        final error = controller.errorMessage;
        final progress = controller.progress.clamp(0.0, 1.0);
        final sliderValue = _isScrubbing ? (_scrubValue ?? progress) : progress;
        final previewPosition = Duration(
          milliseconds:
              (controller.duration.inMilliseconds * sliderValue).round(),
        );

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onVerticalDragEnd: track == null
                ? null
                : (details) {
                    final velocityY = details.primaryVelocity ?? 0;
                    if (velocityY < -_swipeUpVelocityThreshold) {
                      widget.onTap();
                    }
                  },
            child: InkWell(
              onTap: track == null ? null : widget.onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 84,
                margin: const EdgeInsets.all(8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.surface2,
                      AppColors.surface2.withValues(alpha: 0.88),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppColors.border.withValues(alpha: 0.85)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 4,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                                activeTrackColor: AppColors.brandOrange,
                                inactiveTrackColor: AppColors.border,
                                thumbColor: AppColors.brandOrange,
                                overlayColor: AppColors.brandOrange
                                    .withValues(alpha: 0.18),
                              ),
                              child: SizedBox(
                                height: 18,
                                child: Slider(
                                  value: sliderValue,
                                  onChangeStart: track == null
                                      ? null
                                      : (_) {
                                          setState(() {
                                            _isScrubbing = true;
                                            _scrubValue = progress;
                                          });
                                        },
                                  onChanged: track == null
                                      ? null
                                      : (v) => setState(
                                            () =>
                                                _scrubValue = v.clamp(0, 1),
                                          ),
                                  onChangeEnd: track == null
                                      ? null
                                      : (v) {
                                          controller.seek(
                                            Duration(
                                              milliseconds: (controller
                                                          .duration
                                                          .inMilliseconds *
                                                      v)
                                                  .round(),
                                            ),
                                          );
                                          setState(() {
                                            _isScrubbing = false;
                                            _scrubValue = null;
                                          });
                                        },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          PlaybackController.format(
                            _isScrubbing
                                ? previewPosition
                                : controller.position,
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 360;
                        final maxH = constraints.maxHeight.isFinite
                            ? constraints.maxHeight
                            : 56.0;

                        // This layout is sometimes constrained to very small heights (e.g. ~39px).
                        // In those cases, showing both title + subtitle can overflow.
                        final showSubtitle = maxH >= 48;
                        final subtitle = error ?? (track?.artist ?? 'Tap a track to start');
                        final subtitleColor =
                            error == null ? AppColors.textMuted : const Color(0xFFFF6B6B);

                        final artworkSize = maxH.clamp(32.0, 44.0);

                        return Row(
                          children: [
                            Hero(
                              tag: 'player_artwork',
                              child: Container(
                                height: artworkSize,
                                width: artworkSize,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: track?.artworkUri != null
                                    ? CachedNetworkImage(
                                        imageUrl: track!.artworkUri.toString(),
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const Icon(
                                          Icons.music_note,
                                          color: AppColors.textMuted,
                                        ),
                                        errorWidget: (context, url, error) => const Icon(
                                          Icons.music_note,
                                          color: AppColors.textMuted,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.music_note,
                                        color: AppColors.textMuted,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track?.title ?? 'Nothing playing',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelLarge,
                                  ),
                                  if (showSubtitle) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(color: subtitleColor),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: track == null
                                  ? null
                                  : () async {
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
                              tooltip: 'Like',
                              icon: Icon(
                                controller.isCurrentLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                            ),
                            if (!isCompact)
                              IconButton(
                                onPressed:
                                    (!controller.canSkipPrevious || track == null)
                                        ? null
                                        : () => controller.skipPrevious(),
                                onLongPress: track == null
                                    ? null
                                    : () => controller.seekBy(
                                          const Duration(seconds: -10),
                                        ),
                                tooltip: 'Previous',
                                icon: const Icon(Icons.skip_previous),
                              ),
                            IconButton(
                              onPressed: track == null
                                ? null
                                : () => controller.togglePlay(),
                              tooltip: controller.isLoading
                                ? 'Loading'
                                : (controller.isPlaying ? 'Pause' : 'Play'),
                              icon: controller.isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                : Icon(
                                  controller.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                ),
                            ),
                            IconButton(
                              onPressed: (!controller.canSkipNext || track == null)
                                  ? null
                                  : () => controller.skipNext(),
                              onLongPress: track == null
                                  ? null
                                  : () => controller.seekBy(
                                        const Duration(seconds: 10),
                                      ),
                              tooltip: 'Next',
                              icon: const Icon(Icons.skip_next),
                            ),
                            IconButton(
                              onPressed: track == null
                                  ? null
                                  : () => showQueueSheet(context),
                              tooltip: 'Queue',
                              icon: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.queue_music),
                                  if (track != null && upNextCount > 0)
                                    Positioned(
                                      right: -4,
                                      top: -4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.brandOrange,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: AppColors.surface2,
                                            width: 2,
                                          ),
                                        ),
                                        child: Text(
                                          upNextCount > 99
                                              ? '99+'
                                              : upNextCount.toString(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w900,
                                                height: 1.0,
                                              ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        );
      },
    );
  }
}
