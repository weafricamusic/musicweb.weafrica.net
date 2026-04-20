import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/library_item.dart';

class LibraryListItem extends StatelessWidget {
  const LibraryListItem({
    super.key,
    required this.item,
    required this.onTap,
    this.onDownload,
    this.onRemoveDownload,
    this.onPlayNext,
    this.onAddToQueue,
  });

  final LibraryItem item;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onRemoveDownload;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.stageGold;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withValues(alpha: 0.18)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gold.withValues(alpha: 0.25)),
          ),
          child: _Leading(artworkUri: item.artworkUri),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          item.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.isDownloaded)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.download_done, size: 16, color: AppColors.stageGold),
              ),
            PopupMenuButton<_ItemAction>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (action) {
                switch (action) {
                  case _ItemAction.playNext:
                    onPlayNext?.call();
                    break;
                  case _ItemAction.addToQueue:
                    onAddToQueue?.call();
                    break;
                  case _ItemAction.download:
                    onDownload?.call();
                    break;
                  case _ItemAction.removeDownload:
                    onRemoveDownload?.call();
                    break;
                }
              },
              itemBuilder: (context) {
                return <PopupMenuEntry<_ItemAction>>[
                  if (onPlayNext != null)
                    const PopupMenuItem(
                      value: _ItemAction.playNext,
                      child: Row(
                        children: [
                          Icon(Icons.playlist_play, size: 18),
                          SizedBox(width: 10),
                          Text('Play next'),
                        ],
                      ),
                    ),
                  if (onAddToQueue != null)
                    const PopupMenuItem(
                      value: _ItemAction.addToQueue,
                      child: Row(
                        children: [
                          Icon(Icons.queue_music, size: 18),
                          SizedBox(width: 10),
                          Text('Add to queue'),
                        ],
                      ),
                    ),
                  if (onDownload != null)
                    const PopupMenuItem(
                      value: _ItemAction.download,
                      child: Row(
                        children: [
                          Icon(Icons.download_for_offline, size: 18),
                          SizedBox(width: 10),
                          Text('Download'),
                        ],
                      ),
                    ),
                  if (onRemoveDownload != null)
                    const PopupMenuItem(
                      value: _ItemAction.removeDownload,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18),
                          SizedBox(width: 10),
                          Text('Remove download'),
                        ],
                      ),
                    ),
                ];
              },
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({required this.artworkUri});

  final Uri? artworkUri;

  @override
  Widget build(BuildContext context) {
    if (artworkUri == null) {
      return Icon(Icons.music_note, color: AppColors.stageGold.withValues(alpha: 0.8));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        artworkUri!.toString(),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.music_note, color: AppColors.stageGold.withValues(alpha: 0.8));
        },
      ),
    );
  }
}

enum _ItemAction {
  playNext,
  addToQueue,
  download,
  removeDownload,
}
