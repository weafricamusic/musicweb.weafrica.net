import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/auto_artwork.dart';
import '../../player/playback_controller.dart';

enum TrackAction {
  playNext,
  addToQueue,
  share,
  download,
}

class TrackActions {
  static Future<void> shareTrack(Track track) async {
    final title = track.title.trim().isEmpty ? 'Track' : track.title.trim();
    final artist = track.artist.trim().isEmpty ? 'Unknown Artist' : track.artist.trim();
    final parts = <String>['$title — $artist'];
    final uri = track.audioUri;
    if (uri != null) parts.add(uri.toString());
    await Share.share(parts.join('\n'));
  }
}

class TrackCard extends StatelessWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.index,
    required this.onTap,
    required this.onAction,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;
  final void Function(TrackAction action) onAction;

  bool _isDownloadedHint(Track t) {
    final uri = t.audioUri;
    if (uri == null) return false;
    if (uri.scheme == 'file') return true;
    final raw = uri.toString();
    return raw.contains('pulse_downloads');
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final s = d.inSeconds;
    if (s <= 0) return '';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _showTrackMenu(BuildContext context) async {
    final action = await showModalBottomSheet<TrackAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        final hasAudio = track.audioUri != null;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: const Text('Play next'),
                enabled: hasAudio,
                onTap: hasAudio ? () => Navigator.pop(context, TrackAction.playNext) : null,
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to queue'),
                enabled: hasAudio,
                onTap: hasAudio ? () => Navigator.pop(context, TrackAction.addToQueue) : null,
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share'),
                onTap: () => Navigator.pop(context, TrackAction.share),
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Download'),
                onTap: () => Navigator.pop(context, TrackAction.download),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null) return;
    onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAudio = track.audioUri != null;
    final artworkUrl = track.artworkUri?.toString().trim() ?? '';
    final durationText = _formatDuration(track.duration);
    final genre = (track.genre ?? '').trim();
    final downloaded = _isDownloadedHint(track);

    return AnimatedBuilder(
      animation: PlaybackController.instance,
      builder: (context, _) {
        final current = PlaybackController.instance.current;
        final isCurrent = (current?.id != null && track.id != null)
            ? current!.id == track.id
            : (current?.audioUri != null && track.audioUri != null)
                ? current!.audioUri.toString() == track.audioUri.toString()
                : false;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasAudio ? onTap : () => ScaffoldMessenger.of(context)
              ..removeCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('This track is not playable yet.'))),
            onLongPress: () => _showTrackMenu(context),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCurrent ? scheme.primary.withValues(alpha: 0.85) : AppColors.border,
                  width: isCurrent ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Center(
                      child: isCurrent
                          ? Icon(Icons.equalizer, size: 18, color: scheme.primary)
                          : Text(
                              index.toString().padLeft(2, '0'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: hasAudio
                                        ? AppColors.textMuted
                                        : AppColors.textMuted.withValues(alpha: 0.35),
                                  ),
                            ),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: artworkUrl.isEmpty
                          ? AutoArtwork(
                              seed: '${track.title} ${track.artist}',
                              icon: Icons.music_note,
                              showInitials: false,
                            )
                          : CachedNetworkImage(
                              imageUrl: artworkUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => AutoArtwork(
                                seed: '${track.title} ${track.artist}',
                                icon: Icons.music_note,
                                showInitials: false,
                              ),
                              errorWidget: (context, url, error) => AutoArtwork(
                                seed: '${track.title} ${track.artist}',
                                icon: Icons.music_note,
                                showInitials: false,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title.trim().isEmpty ? 'Untitled' : track.title.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: hasAudio ? null : AppColors.textMuted,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                track.artist.trim().isEmpty ? 'Unknown Artist' : track.artist.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (!hasAudio)
                              _MetaPill(
                                icon: Icons.block,
                                label: 'Unavailable',
                                color: Theme.of(context).colorScheme.error,
                              )
                            else if (downloaded)
                              _MetaPill(
                                icon: Icons.download_done,
                                label: 'Offline',
                                color: scheme.primary,
                              ),
                            if (genre.isNotEmpty)
                              _MetaPill(
                                icon: Icons.category,
                                label: genre,
                                color: AppColors.textMuted,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (durationText.isNotEmpty)
                        Text(
                          durationText,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      const SizedBox(height: 6),
                      Icon(
                        isCurrent
                            ? (PlaybackController.instance.isPlaying ? Icons.volume_up : Icons.pause)
                            : (hasAudio ? Icons.play_arrow : Icons.lock),
                        color: isCurrent ? scheme.primary : AppColors.textMuted,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      IconButton(
                        tooltip: 'More',
                        onPressed: () => _showTrackMenu(context),
                        icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeLabel = label.trim();
    if (safeLabel.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            safeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}
