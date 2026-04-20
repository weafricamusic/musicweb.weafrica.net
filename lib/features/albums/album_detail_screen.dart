import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';
import '../../app/theme.dart';
import '../../app/widgets/auto_artwork.dart';
import '../../app/widgets/stage_background.dart';
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import 'models/album.dart';

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({super.key, required this.album});

  final Album album;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late Future<List<Track>> _tracksFuture = _fetchAlbumTracks(widget.album.id);

  Future<void> _refresh() async {
    setState(() {
      _tracksFuture = _fetchAlbumTracks(widget.album.id);
    });

    try {
      await _tracksFuture;
    } catch (e) {
      // Do not let refresh errors escape into the Zone on web.
      debugPrint('⚠️ Album refresh failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not refresh album. Please try again.')),
        );
    }
  }

  Future<void> _playAll({required bool shuffle}) async {
    try {
      final tracks = await _tracksFuture;
      final playable = tracks.where((t) => t.audioUri != null).toList();

      if (playable.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('This album has no playable tracks yet.')),
          );
        return;
      }

      final ordered = List<Track>.from(playable);
      if (shuffle) ordered.shuffle();

      final first = ordered.first;
      final queue = ordered.length > 1 ? ordered.sublist(1) : const <Track>[];

      PlaybackController.instance.play(first, queue: queue);
      if (!mounted) return;
      openPlayer(context);
    } catch (e) {
      // Called from a button callback; never allow async errors to be unhandled.
      debugPrint('⚠️ Play-all failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not start playback. Please try again.')),
        );
    }
  }

  void _playFromIndex(List<Track> tracks, int index) {
    if (index < 0 || index >= tracks.length) return;
    final track = tracks[index];

    if (track.audioUri == null) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This track has no audio URL yet.')),
        );
      return;
    }

    final queue = <Track>[
      ...tracks.skip(index + 1),
      ...tracks.take(index),
    ];

    final playableQueue = queue.where((t) => t.audioUri != null).toList();
    PlaybackController.instance.play(track, queue: playableQueue);
    openPlayer(context);
  }

  static Future<List<Track>> _fetchAlbumTracks(String albumId) async {
    final id = albumId.trim();
    if (id.isEmpty) return const <Track>[];

    // Try Edge API first.
    try {
      final uri = Uri.parse('${ApiEnv.baseUrl}/api/albums/$id/tracks?limit=200');
      final res = await FirebaseAuthedHttp.get(
        uri,
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 8),
        includeAuthIfAvailable: true,
        requireAuth: false,
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['ok'] == true) {
          final raw = decoded['tracks'];
          if (raw is List) {
            return raw
                .whereType<Map>()
                .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
                .map(Track.fromSupabase)
                .toList(growable: false);
          }
        }
      }
    } catch (_) {
      // Fall back to direct query.
    }

    // Fallback to direct Supabase query.
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('songs')
          .select('*,artists(name,stage_name,artist_name)')
          .eq('album_id', id)
          .order('created_at', ascending: true)
          .limit(200);

      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Track.fromSupabase)
          .toList(growable: false);
    } catch (_) {
      return const <Track>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final artist = (album.artistName ?? 'Unknown artist').trim().isEmpty
        ? 'Unknown artist'
        : (album.artistName ?? '').trim();
    final coverUrl = album.coverUrl?.trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(album.title.trim().isEmpty ? 'Album' : album.title.trim()),
      ),
      body: StageBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Track>>(
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
                      'Could not load album tracks. Please try again.',
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

              final tracks = snapshot.data ?? const <Track>[];
              final playableCount = tracks.where((t) => t.audioUri != null).length;

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
                itemCount: 1 + tracks.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 72,
                              height: 72,
                              child: coverUrl.isEmpty
                                  ? AutoArtwork(
                                      seed: album.title,
                                      icon: Icons.album,
                                      showInitials: false,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.white.withAlpha(18),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          AutoArtwork(
                                        seed: album.title,
                                        icon: Icons.album,
                                        showInitials: false,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  album.title.trim().isEmpty
                                      ? 'Untitled album'
                                      : album.title.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${tracks.length} tracks • $playableCount playable',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: playableCount == 0
                                ? null
                                : () => _playAll(shuffle: false),
                            child: const Text('Play'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: playableCount == 0
                                ? null
                                : () => _playAll(shuffle: true),
                            child: const Text('Shuffle'),
                          ),
                        ],
                      ),
                    );
                  }

                  final track = tracks[index - 1];
                  final artworkUrl = track.artworkUri?.toString().trim() ?? '';
                  final duration = track.duration;
                  final durationText =
                      duration == null ? '' : PlaybackController.format(duration);

                  return ListTile(
                    tileColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: artworkUrl.isEmpty
                            ? AutoArtwork(
                                seed: '${track.title} ${track.artist}',
                                icon: Icons.music_note,
                                showInitials: false,
                              )
                            : CachedNetworkImage(
                                imageUrl: artworkUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.white.withAlpha(18),
                                ),
                                errorWidget: (context, url, error) => AutoArtwork(
                                  seed: '${track.title} ${track.artist}',
                                  icon: Icons.music_note,
                                  showInitials: false,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      track.title.trim().isEmpty ? 'Untitled' : track.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artist.trim().isEmpty ? 'Unknown artist' : track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                    trailing: durationText.isEmpty
                        ? null
                        : Text(
                            durationText,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                    onTap: track.audioUri == null
                        ? null
                        : () => _playFromIndex(tracks, index - 1),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
