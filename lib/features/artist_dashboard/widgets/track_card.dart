import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../tracks/track.dart';

class TrackCard extends StatelessWidget {
  const TrackCard({
    super.key,
    required this.track,
    this.onTap,
  });

  final Track track;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final artwork = track.artworkUri?.toString();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: artwork == null || artwork.trim().isEmpty
                    ? Container(
                        color: AppColors.surface,
                        child: Center(
                          child: Icon(Icons.music_note, color: AppColors.textMuted.withValues(alpha: 179), size: 32),
                        ),
                      )
                    : Image.network(
                        artwork,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.surface,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: AppColors.textMuted.withValues(alpha: 179), size: 28),
                            ),
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
