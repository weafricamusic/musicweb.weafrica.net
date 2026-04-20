import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/library_item.dart';
import '../models/library_track.dart';

class LibraryGridItem extends StatelessWidget {
  const LibraryGridItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.stageGold;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  width: double.infinity,
                  color: AppColors.surface,
                  child: _Cover(item: item),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                  if (item.isDownloaded) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: gold.withValues(alpha: 0.25)),
                      ),
                      child: const Text(
                        'DOWNLOADED',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.stageGold, letterSpacing: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final uri = item.artworkUri;
    if (uri != null) {
      return Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final icon = item is LibraryTrack ? Icons.music_note : Icons.library_music;
    return Center(
      child: Icon(icon, size: 34, color: AppColors.stageGold.withValues(alpha: 0.25)),
    );
  }
}
