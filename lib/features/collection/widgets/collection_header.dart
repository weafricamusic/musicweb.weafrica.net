import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/auto_artwork.dart';
import '../track_collection_screen.dart';

class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverImageUrl,
    required this.collectionType,
    required this.creatorName,
    required this.trackCount,
    required this.totalDuration,
  });

  final String title;
  final String? subtitle;
  final String? coverImageUrl;
  final CollectionType collectionType;
  final String? creatorName;
  final int trackCount;
  final Duration totalDuration;

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds <= 0) return '';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return '$hours $minutes';
    return '$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitleText = (subtitle ?? '').trim();
    final creator = (creatorName ?? '').trim();
    final cover = (coverImageUrl ?? '').trim();

    final durationText = _formatDuration(totalDuration);
    final metaBit = <String>[
      '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
      if (durationText.isNotEmpty) durationText,
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover.isNotEmpty)
          CachedNetworkImage(
            imageUrl: cover,
            fit: BoxFit.cover,
            placeholder: (context, url) => AutoArtwork(
              seed: title,
              icon: collectionType.icon,
              showInitials: false,
            ),
            errorWidget: (context, url, error) => AutoArtwork(
              seed: title,
              icon: collectionType.icon,
              showInitials: false,
            ),
          )
        else
          AutoArtwork(
            seed: title,
            icon: collectionType.icon,
            showInitials: false,
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0.15),
                AppColors.background.withValues(alpha: 0.85),
                AppColors.background,
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TypeBadge(type: collectionType),
                      const SizedBox(height: 10),
                      Text(
                        title.trim().isEmpty ? 'Collection' : title.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                      ),
                      if (creator.isNotEmpty || subtitleText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          creator.isNotEmpty ? creator : subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        metaBit.join(' • '),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final CollectionType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        color: scheme.primary.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            type.displayName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: scheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}
