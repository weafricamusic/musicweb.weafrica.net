import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../audio/audio.dart';
import '../../app/theme.dart';
import '../../services/recent_contexts_service.dart';
import '../player/player_routes.dart';
import '../tracks/track.dart';
import 'playlist.dart';
import 'playlists_repository.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PlaylistsRepository _repo = PlaylistsRepository();

  late Future<List<PlaylistTrackRow>> _tracksFuture =
      _repo.fetchPlaylistTracks(widget.playlist.id);

  Future<void> _refresh() async {
    setState(() {
      _tracksFuture = _repo.fetchPlaylistTracks(widget.playlist.id);
    });
    await _tracksFuture;
  }

  Future<void> _play({required bool shuffle}) async {
    final rows = await _tracksFuture;
    final tracks = rows.map((r) => r.track).toList(growable: false);

    final items = <MediaItem>[];
    Track? firstPlayable;
    for (final t in tracks) {
      final uri = t.audioUri;
      if (uri == null) continue;
      firstPlayable ??= t;
      items.add(
        MediaItem(
          id: uri.toString(),
          title: t.title,
          artist: t.artist,
          artUri: t.artworkUri,
          duration: t.duration,
        ),
      );
    }

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playable tracks in this playlist yet.')),
      );
      return;
    }

    await weafricaAudioHandler.setShuffleMode(
      shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    await weafricaAudioHandler.setQueue(items, startIndex: 0);

    final played = firstPlayable;
    if (played != null) {
      unawaited(
        RecentContextsService.instance.recordTrackPlay(played).catchError(
          (e, st) {
            if (kDebugMode) {
              debugPrint('recent_contexts recordTrackPlay failed: $e');
              debugPrintStack(stackTrace: st, maxFrames: 20);
            }
          },
        ),
      );
    }

    if (!mounted) return;
    openPlayer(context);
  }

  Future<void> _showAddTrackPicker() async {
    List<Track> choices;
    try {
      choices = await _repo.fetchTrackPickerChoices(limit: 120);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load tracks.')),
      );
      return;
    }

    if (!mounted) return;

    final pickedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface2,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            itemCount: choices.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = choices[index];
              final id = track.id;
              return ListTile(
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.border),
                ),
                leading: const Icon(Icons.music_note, color: AppColors.textMuted),
                title: Text(track.title),
                subtitle: Text(
                  track.artist,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
                onTap: id == null
                    ? null
                    : () => Navigator.of(context).pop(id),
              );
            },
          ),
        );
      },
    );

    if (pickedId == null) return;

    try {
      await _repo.addTrackToPlaylist(
        playlistId: widget.playlist.id,
        trackId: pickedId,
      );
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to playlist')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add to playlist.')),
      );
    }
  }

  Future<void> _removeTrack(String trackId) async {
    try {
      await _repo.removeTrackFromPlaylist(
        playlistId: widget.playlist.id,
        trackId: trackId,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove from playlist.')),
      );
    }
  }

  Future<void> _persistReorder(List<PlaylistTrackRow> rows) async {
    try {
      await _repo.reorderPlaylistTracks(
        playlistId: widget.playlist.id,
        orderedTrackIds: rows.map((r) => r.trackId).toList(growable: false),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reorder playlist.')),
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            tooltip: 'Add track',
            onPressed: _showAddTrackPicker,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<PlaylistTrackRow>>(
          future: _tracksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  Text(
                    'Could not load playlist tracks. Please try again.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              );
            }

            final rows = snapshot.data ?? const <PlaylistTrackRow>[];

            return ReorderableListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                // First item is the header card; keep it fixed.
                if (oldIndex == 0 || newIndex == 0) return;

                // Convert list indices -> rows indices.
                var from = oldIndex - 1;
                var to = newIndex - 1;
                if (to > from) to -= 1;

                final updated = List<PlaylistTrackRow>.from(rows);
                if (from < 0 || from >= updated.length) return;
                if (to < 0 || to >= updated.length) return;

                final moved = updated.removeAt(from);
                updated.insert(to, moved);

                setState(() {
                  _tracksFuture = Future.value(updated);
                });

                unawaited(_persistReorder(updated));
              },
              children: [
                Container(
                  key: const ValueKey('playlist_header'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.playlist.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${rows.length} tracks',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _play(shuffle: false),
                        child: const Text('Play'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => _play(shuffle: true),
                        child: const Text('Shuffle'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Padding(
                    key: const ValueKey('playlist_empty'),
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No tracks yet. Tap + to add.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < rows.length; i++)
                    Padding(
                      key: ValueKey('row_${rows[i].trackId}'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Builder(
                          builder: (context) {
                            final r = rows[i];
                            final art = r.track.artworkUri;

                            return ListTile(
                              tileColor: AppColors.surface2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  height: 46,
                                  width: 46,
                                  child: art == null
                                      ? const ColoredBox(
                                          color: AppColors.surface,
                                          child: Icon(
                                            Icons.music_note,
                                            color: AppColors.textMuted,
                                          ),
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: art.toString(),
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              const ColoredBox(
                                            color: AppColors.surface,
                                            child: Icon(
                                              Icons.music_note,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          errorWidget:
                                              (context, url, error) =>
                                                  const ColoredBox(
                                            color: AppColors.surface,
                                            child: Icon(
                                              Icons.music_note,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              title: Text(
                                r.track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                r.track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textMuted),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ReorderableDragStartListener(
                                    index: i + 1,
                                    child: const Icon(
                                      Icons.drag_handle,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove',
                                    onPressed: () => _removeTrack(r.trackId),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
