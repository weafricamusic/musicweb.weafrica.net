import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/beat_generation.dart';

class BeatLibraryTile extends StatelessWidget {
  const BeatLibraryTile({
    super.key,
    required this.beat,
    required this.onPlay,
    required this.onDelete,
    required this.onDownload,
    required this.isActive,
  });

  final SavedBeat beat;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: isActive ? 0.40 : 0.18)),
      ),
      child: ListTile(
        leading: Icon(Icons.audiotrack, color: accent),
        title: Text(
          beat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${beat.style} • ${beat.bpm} BPM • ${beat.durationSeconds}s',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.play_arrow, color: accent),
              onPressed: onPlay,
            ),
            IconButton(
              icon: Icon(
                Icons.download,
                color: beat.localFilePath == null ? accent : scheme.secondary,
              ),
              tooltip: beat.localFilePath == null ? 'Download' : 'Downloaded',
              onPressed: onDownload,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
