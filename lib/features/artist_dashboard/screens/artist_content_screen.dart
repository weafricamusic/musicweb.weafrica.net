import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/config/api_env.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../../creator/add_album_tracks_screen.dart';
import '../../../app/constants/weafrica_power_voice.dart';
import '../../player/playback_controller.dart';
import '../../player/player_routes.dart';
import '../services/artist_identity_service.dart';

enum ArtistContentTab { songs, videos, albums, upload }

class ArtistContentScreen extends StatefulWidget {
  const ArtistContentScreen({super.key, this.initialTab});

  final ArtistContentTab? initialTab;

  @override
  State<ArtistContentScreen> createState() => _ArtistContentScreenState();
}

class _ArtistContentScreenState extends State<ArtistContentScreen> {
  final _identity = ArtistIdentityService();

  late ArtistContentTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab ?? ArtistContentTab.songs;
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_tab) {
      ArtistContentTab.songs => 'Songs',
      ArtistContentTab.videos => 'Videos',
      ArtistContentTab.albums => 'Albums',
      ArtistContentTab.upload => 'Upload',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Content • $title'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _TabRow(
            value: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 14),

          if (_tab == ArtistContentTab.upload) ...[
            const _UseCreateHintCard(),
          ] else if (_tab == ArtistContentTab.songs) ...[
            _SongsList(identity: _identity),
          ] else if (_tab == ArtistContentTab.videos) ...[
            _VideosList(identity: _identity),
          ] else ...[
            _AlbumsList(identity: _identity),
          ],
        ],
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({required this.value, required this.onChanged});

  final ArtistContentTab value;
  final ValueChanged<ArtistContentTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ArtistContentTab>(
      segments: const [
        ButtonSegment(value: ArtistContentTab.songs, label: Text('Songs')),
        ButtonSegment(value: ArtistContentTab.videos, label: Text('Videos')),
        ButtonSegment(value: ArtistContentTab.albums, label: Text('Albums')),
        ButtonSegment(value: ArtistContentTab.upload, label: Text('Upload')),
      ],
      selected: {value},
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

class _UseCreateHintCard extends StatelessWidget {
  const _UseCreateHintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.add_circle_outline, color: AppColors.textMuted),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Use +Create to upload songs, videos, or start live.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsList extends StatefulWidget {
  const _SongsList({required this.identity});

  final ArtistIdentityService identity;

  @override
  State<_SongsList> createState() => _SongsListState();
}

class _SongsListState extends State<_SongsList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final artistId = await widget.identity.resolveArtistIdForCurrentUser();
    if (artistId == null) return const <Map<String, dynamic>>[];

    final client = Supabase.instance.client;
    final rows = await client
        .from('songs')
        .select('*')
        .eq('artist_id', artistId)
        .order('created_at', ascending: false)
        .limit(80);

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  List<Track> _queueFromAll(List<Track> tracks, int index) {
    final queue = <Track>[];
    for (var i = index + 1; i < tracks.length; i++) {
      final t = tracks[i];
      if (t.audioUri == null) continue;
      queue.add(t);
    }
    for (var i = 0; i < index; i++) {
      final t = tracks[i];
      if (t.audioUri == null) continue;
      queue.add(t);
    }
    return queue;
  }

  void _playAndOpen(BuildContext context, Track track, List<Track> tracks, int index) {
    if (track.audioUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no audio URL yet.')),
      );
      return;
    }

    final queue = _queueFromAll(tracks, index);
    PlaybackController.instance.play(track, queue: queue);
    openPlayer(context);
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete content'),
        content: const Text('Delete this song? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await Supabase.instance.client.from('songs').delete().eq('id', id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.')));
      setState(() => _future = _load());
    } catch (e) {
      UserFacingError.log('ArtistContentScreen delete failed', e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete content. Please try again.')),
      );
    }
  }

  Future<void> _edit(BuildContext context, Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.trim().isEmpty) return;

    final titleCtrl = TextEditingController(text: (row['title'] ?? '').toString());
    final genreCtrl = TextEditingController(text: (row['genre'] ?? '').toString());
    final moodCtrl = TextEditingController(text: (row['mood'] ?? '').toString());

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit metadata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: genreCtrl, decoration: const InputDecoration(labelText: 'Genre')),
            TextField(controller: moodCtrl, decoration: const InputDecoration(labelText: 'Mood')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );

    titleCtrl.dispose();
    genreCtrl.dispose();
    moodCtrl.dispose();

    if (save != true) return;

    final payload = <String, dynamic>{
      'title': titleCtrl.text.trim(),
      'genre': genreCtrl.text.trim().isEmpty ? null : genreCtrl.text.trim(),
      'mood': moodCtrl.text.trim().isEmpty ? null : moodCtrl.text.trim(),
    };

    try {
      await Supabase.instance.client.from('songs').update(payload).eq('id', id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated.')));
      setState(() => _future = _load());
    } catch (e) {
      UserFacingError.log('ArtistContentScreen edit failed', e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save changes. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return _ErrorBox(
            text: 'Could not load songs.',
            onRetry: () => setState(() => _future = _load()),
          );
        }

        final rows = snap.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const _EmptyBox(text: WeAfricaPowerVoice.emptySongs);
        }

        final tracks = rows
            .map(Track.fromSupabase)
            .whereType<Track>()
            .toList(growable: false);

        return Column(
          children: rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final track = tracks[index];
            final plays = row['plays_count'] ?? row['plays'];
            final likes = row['likes'] ?? row['likes_count'];
            final comments = row['comments'] ?? row['comments_count'];

            String meta = '';
            if (plays != null) meta += 'Plays ${plays.toString()}';
            if (likes != null) meta += '${meta.isEmpty ? '' : ' • '}Likes ${likes.toString()}';
            if (comments != null) meta += '${meta.isEmpty ? '' : ' • '}Comments ${comments.toString()}';
            if (meta.isEmpty) meta = (track.genre ?? '').trim().isEmpty ? '—' : (track.genre ?? '—');

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: const Icon(Icons.music_note, color: AppColors.textMuted),
                  title: Text(track.title),
                  subtitle: Text(meta, style: TextStyle(color: AppColors.textMuted)),
                  onTap: () => _playAndOpen(context, track, tracks, index),
                  trailing: PopupMenuButton<int>(
                    onSelected: (v) {
                      if (v == 1) _edit(context, row);
                      if (v == 2) _delete(context, (row['id'] ?? '').toString());
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 1, child: Text('Edit metadata')),
                      PopupMenuItem(value: 2, child: Text('Delete')),
                    ],
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _VideosList extends StatefulWidget {
  const _VideosList({required this.identity});
  final ArtistIdentityService identity;

  @override
  State<_VideosList> createState() => _VideosListState();
}

class _VideosListState extends State<_VideosList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final uid = widget.identity.currentFirebaseUid();
    final artistId = await widget.identity.resolveArtistIdForCurrentUser();

    final client = Supabase.instance.client;
    if (artistId != null) {
      final rows = await client
          .from('videos')
          .select('*')
          .eq('artist_id', artistId)
          .order('created_at', ascending: false)
          .limit(80);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    }

    if (uid == null) {
      return const <Map<String, dynamic>>[];
    }

    // Schema drift safety: some deployments use `uploader_id`, others use `user_id`
    // or `firebase_uid`.
    try {
      final rows = await client
          .from('videos')
          .select('*')
          .eq('uploader_id', uid)
          .order('created_at', ascending: false)
          .limit(80);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();
      final missingUploaderId =
          (msg.contains("could not find the 'uploader_id' column") || details.contains("could not find the 'uploader_id' column")) &&
              (msg.contains("'videos'") || details.contains("'videos'"));

      if (!missingUploaderId) rethrow;
    }

    final rows = await client
        .from('videos')
        .select('*')
        .or('user_id.eq.$uid,firebase_uid.eq.$uid')
        .order('created_at', ascending: false)
        .limit(80);
    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          developer.log(
            'Artist dashboard videos failed to load',
            name: 'WEAFRICA.CreatorDashboard',
            error: snap.error,
            stackTrace: snap.stackTrace,
          );

          final debugDetails = kDebugMode
              ? (snap.error?.toString().trim().isEmpty ?? true)
                  ? null
                  : snap.error.toString()
              : null;

          return _ErrorBox(
            text: debugDetails == null ? 'Could not load videos.' : 'Could not load videos.\n\n$debugDetails',
            onRetry: () => setState(() => _future = _load()),
          );
        }

        final rows = snap.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const _EmptyBox(text: WeAfricaPowerVoice.emptyVideos);
        }

        return Column(
          children: rows.map((row) {
            final title = (row['title'] ?? 'Untitled video').toString();
            final createdAt = (row['created_at'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: const Icon(Icons.movie_outlined, color: AppColors.textMuted),
                  title: Text(title),
                  subtitle: createdAt.trim().isEmpty ? null : Text(createdAt, style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _AlbumsList extends StatefulWidget {
  const _AlbumsList({required this.identity});
  final ArtistIdentityService identity;

  @override
  State<_AlbumsList> createState() => _AlbumsListState();
}

class _AlbumsListState extends State<_AlbumsList> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  String _albumId(Map<String, dynamic> row) => (row['id'] ?? '').toString().trim();

  String _albumTitle(Map<String, dynamic> row) {
    final t = (row['title'] ?? row['name'] ?? '').toString().trim();
    return t.isEmpty ? 'Untitled album' : t;
  }

  String _albumDescription(Map<String, dynamic> row) => (row['description'] ?? '').toString();

  Future<void> _openAddTracks(Map<String, dynamic> row) async {
    final id = _albumId(row);
    if (id.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddAlbumTracksScreen(
          albumId: id,
          albumTitle: _albumTitle(row),
        ),
      ),
    );

    if (!mounted) return;
    await _refresh();
  }

  Future<void> _editAlbum(Map<String, dynamic> row) async {
    final id = _albumId(row);
    if (id.isEmpty) return;

    final titleCtrl = TextEditingController(text: _albumTitle(row));
    final descCtrl = TextEditingController(text: _albumDescription(row));
    String? error;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          var busy = false;
          return StatefulBuilder(
            builder: (ctx, setState) {
              Future<void> save() async {
                if (busy) return;
                final title = titleCtrl.text.trim();
                final desc = descCtrl.text.trim();

                if (title.isEmpty) {
                  setState(() => error = 'Enter an album title.');
                  return;
                }

                setState(() {
                  error = null;
                  busy = true;
                });
                try {
                  final uri = Uri.parse('${ApiEnv.baseUrl}/api/albums/$id');
                  final res = await FirebaseAuthedHttp.put(
                    uri,
                    headers: const {
                      'Accept': 'application/json',
                      'Content-Type': 'application/json; charset=utf-8',
                    },
                    body: jsonEncode({
                      'title': title,
                      'description': desc,
                    }),
                    timeout: const Duration(seconds: 15),
                    requireAuth: true,
                  );

                  if (res.statusCode == 404) {
                    throw StateError('Album service is temporarily unavailable. Please try again.');
                  }

                  if (res.statusCode < 200 || res.statusCode >= 300) {
                    var msg = 'Could not update album. Please try again.';
                    try {
                      final decoded = jsonDecode(res.body);
                      if (decoded is Map) {
                        msg = (decoded['message'] ?? decoded['error'] ?? msg).toString();
                      }
                    } catch (_) {
                      final t = res.body.trim();
                      if (t.isNotEmpty) msg = t;
                    }
                    throw StateError(msg);
                  }

                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(true);
                } catch (e, st) {
                  UserFacingError.log('ArtistContentScreen.editAlbum', e, st);
                  if (!ctx.mounted) return;
                  setState(() {
                    error = UserFacingError.message(
                      e,
                      fallback: 'Could not update album. Please try again.',
                    );
                  });
                } finally {
                  if (ctx.mounted) {
                    setState(() {
                      busy = false;
                    });
                  }
                }
              }

              return AlertDialog(
                title: const Text('Edit album'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        enabled: !busy,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descCtrl,
                        enabled: !busy,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!, style: const TextStyle(color: AppColors.brandBlue)),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!mounted || ok != true) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Album updated.')));
      await _refresh();
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Future<void> _deleteAlbum(Map<String, dynamic> row) async {
    final id = _albumId(row);
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete album?'),
        content: Text(_albumTitle(row)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    if (_busy) return;
    setState(() => _busy = true);

    try {
      final uri = Uri.parse('${ApiEnv.baseUrl}/api/albums/$id');
      final res = await FirebaseAuthedHttp.delete(
        uri,
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 15),
        requireAuth: true,
      );

      if (res.statusCode == 404) {
        throw StateError('Album service is temporarily unavailable. Please try again.');
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        var msg = 'Could not delete album. Please try again.';
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            msg = (decoded['message'] ?? decoded['error'] ?? msg).toString();
          }
        } catch (_) {
          final t = res.body.trim();
          if (t.isNotEmpty) msg = t;
        }
        throw StateError(msg);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Album deleted.')));
      await _refresh();
    } catch (e, st) {
      UserFacingError.log('ArtistContentScreen.deleteAlbum', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                e,
                fallback: 'Could not delete album. Please try again.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final artistId = await widget.identity.resolveArtistIdForCurrentUser();
    if (artistId == null) return const <Map<String, dynamic>>[];

    final client = Supabase.instance.client;
    final rows = await client
        .from('albums')
        .select('*')
        .eq('artist_id', artistId)
        .order('created_at', ascending: false)
        .limit(80);

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return _ErrorBox(
            text: 'Could not load albums.',
            onRetry: () => setState(() => _future = _load()),
          );
        }

        final rows = snap.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const _EmptyBox(text: WeAfricaPowerVoice.emptyAlbums);
        }

        return Column(
          children: rows.map((row) {
            final title = _albumTitle(row);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: const Icon(Icons.album_outlined, color: AppColors.textMuted),
                  title: Text(title),
                  trailing: PopupMenuButton<int>(
                    enabled: !_busy,
                    onSelected: (v) {
                      if (v == 1) _openAddTracks(row);
                      if (v == 2) _editAlbum(row);
                      if (v == 3) _deleteAlbum(row);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 1, child: Text('Add track')),
                      PopupMenuItem(value: 2, child: Text('Edit album')),
                      PopupMenuItem(value: 3, child: Text('Delete album')),
                    ],
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: TextStyle(color: AppColors.textMuted)),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 10),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
