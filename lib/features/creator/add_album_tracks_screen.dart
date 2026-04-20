import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';
import '../../app/theme.dart';
import '../../app/media/artwork_resolver.dart';
import '../../app/utils/user_facing_error.dart';
import 'upload_track_screen.dart';

class AddAlbumTracksScreen extends StatefulWidget {
  const AddAlbumTracksScreen({
    super.key,
    required this.albumId,
    required this.albumTitle,
  });

  final String albumId;
  final String albumTitle;

  @override
  State<AddAlbumTracksScreen> createState() => _AddAlbumTracksScreenState();
}

class _AddAlbumTracksScreenState extends State<AddAlbumTracksScreen> {
  bool _loading = false;
  String? _error;
  bool _albumIdSupported = true;

  late Future<List<Map<String, dynamic>>> _tracksFuture;

  @override
  void initState() {
    super.initState();
    _tracksFuture = _fetchTracks();
  }

  Future<List<Map<String, dynamic>>> _fetchTracks() async {
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('songs')
          .select('id,title,artwork_url,thumbnail_url,thumbnail,image_url,created_at')
          .eq('album_id', widget.albumId)
          .order('created_at', ascending: true);

      if (_albumIdSupported == false && mounted) {
        setState(() => _albumIdSupported = true);
      }

      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    } on PostgrestException catch (e) {
      UserFacingError.log('AddAlbumTracksScreen._fetchTracks(Postgrest)', e);
      final msg = e.message.toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();
      final missingAlbumId = (msg.contains('album_id') || details.contains('album_id')) &&
          (msg.contains('schema cache') || msg.contains('could not find') || msg.contains('column') || msg.contains('does not exist'));

      if (missingAlbumId) {
        if (mounted) {
          setState(() {
            _albumIdSupported = false;
            _error = 'Albums are temporarily unavailable right now.';
          });
        }
        return const <Map<String, dynamic>>[];
      }

      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _tracksFuture = _fetchTracks();
    });
  }

  String? _pickCover(Map<String, dynamic> row) {
    return pickArtworkValue(
      row,
      keys: const [
        'artwork_url',
        'artworkUrl',
        'artwork',
        'thumbnail_url',
        'thumbnailUrl',
        'thumbnail',
        'image_url',
        'imageUrl',
      ],
    );
  }

  Future<void> _addTrack() async {
    if (!_albumIdSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Albums are temporarily unavailable right now.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadTrackScreen(albumId: widget.albumId),
      ),
    );
    await _refresh();
  }

  Future<void> _publishAlbum() async {
    if (_loading) return;
    if (!_albumIdSupported) {
      setState(() {
        _error = 'Albums are temporarily unavailable right now.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tracks = await _fetchTracks();
      if (tracks.length < 2) {
        throw StateError('Add at least 2 tracks before publishing.');
      }

      final missingCover = tracks.where((t) {
        final cover = _pickCover(t);
        return cover == null || cover.trim().isEmpty;
      }).length;

      if (missingCover > 0) {
        throw StateError('All tracks must have cover art before publishing. ($missingCover missing)');
      }

      // Best-effort: use the first track's artwork as album cover.
      final coverUrl = _pickCover(tracks.first);

      final uri = Uri.parse('${ApiEnv.baseUrl}/api/albums/finalize');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'album_id': widget.albumId,
          if ((coverUrl ?? '').trim().isNotEmpty) 'cover_url': coverUrl,
        }),
        timeout: const Duration(seconds: 15),
        requireAuth: true,
      );

      if (res.statusCode == 404) {
        UserFacingError.log('AddAlbumTracksScreen._publishAlbum', 'Publish endpoint not found (HTTP 404).');
        throw StateError('Album publishing is temporarily unavailable. Please try again.');
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        UserFacingError.log('AddAlbumTracksScreen._publishAlbum', 'Publish failed (HTTP ${res.statusCode}).');
        var msg = 'Could not publish album. Please try again.';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album published.')),
      );

      Navigator.of(context).pop();
    } catch (e, st) {
      UserFacingError.log('AddAlbumTracksScreen._publishAlbum', e, st);
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not publish album. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add tracks')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              widget.albumTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload at least 2 tracks, then publish.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _loading ? null : _addTrack,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Add track'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _publishAlbum,
                icon: const Icon(Icons.public),
                label: Text(_loading ? 'Publishing…' : 'Publish album'),
              ),
            ),
            const SizedBox(height: 18),
            Text('Tracks', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _tracksFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  if (kDebugMode) debugPrint('AddAlbumTracksScreen load error: ${snapshot.error}');
                  return Text(
                    'Could not load tracks. Pull to refresh.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                  );
                }

                final items = snapshot.data ?? const <Map<String, dynamic>>[];
                if (items.isEmpty) {
                  return Text(
                    'No tracks yet. Tap “Add track”.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                  );
                }

                return Column(
                  children: [
                    for (final t in items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note, color: AppColors.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (t['title'] ?? 'Untitled').toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _pickCover(t) == null ? 'Cover: missing' : 'Cover: ok',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
