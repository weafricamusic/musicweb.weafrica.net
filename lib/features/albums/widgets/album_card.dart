import 'package:flutter/material.dart';

import '../models/album.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, this.album, this.onTap, this.compact = false});

  final Album? album;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = album;
    if (a == null) return const SizedBox.shrink();
    if (compact) {
      return ListTile(
        onTap: onTap,
        leading: a.coverUrl == null || a.coverUrl!.trim().isEmpty
            ? const Icon(Icons.album)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  a.coverUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.album),
                ),
              ),
        title: Text(
          a.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          a.artistName ?? 'Unknown Artist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      );
    } else {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: a.coverUrl == null || a.coverUrl!.trim().isEmpty
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.album, color: theme.colorScheme.onSurfaceVariant),
                        )
                      : Image.network(
                          a.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.album, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.artistName ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.audiotrack, size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            '${a.trackCount} tracks',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          if (!a.isPublished)
                            Text(
                              'DRAFT',
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
