import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import 'smart_image.dart';

class HomeMiniPlayer extends StatelessWidget {
  const HomeMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<AudioProvider>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    final progress = song.duration.inMilliseconds == 0
        ? 0.0
        : (player.position.inMilliseconds / song.duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SmartImage(
                  imagePath: song.thumbnail,
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: player.togglePlayPause,
                icon: Icon(
                  player.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: scheme.onSurface,
                ),
              ),
              IconButton(
                onPressed: player.playNext,
                icon: Icon(
                  Icons.skip_next,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
            ),
          ),
        ],
      ),
    );
  }
}
