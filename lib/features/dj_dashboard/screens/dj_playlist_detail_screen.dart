import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';

class DjPlaylistDetailScreen extends StatefulWidget {
  const DjPlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.title,
  });

  final String playlistId;
  final String title;

  @override
  State<DjPlaylistDetailScreen> createState() => _DjPlaylistDetailScreenState();
}

class _DjPlaylistDetailScreenState extends State<DjPlaylistDetailScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('dj_playlist_tracks')
        .select('id,playlist_id,song_id,position,created_at')
        .eq('playlist_id', widget.playlistId)
        .order('position', ascending: true)
        .order('created_at', ascending: true)
        .limit(500);

    return (rows as List).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> _removeTrack(String rowId) async {
    try {
      await Supabase.instance.client.from('dj_playlist_tracks').delete().eq('id', rowId);
      if (!mounted) return;
      setState(() { _future = _load(); });
    } catch (e, st) {
      UserFacingError.log('DjPlaylistDetailScreen removeTrack failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove song. Please try again.')),
      );
    }
  }

  Future<void> _addSongFlow() async {
    final pickedId = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SongPickerDialog(),
    );

    final songId = (pickedId ?? '').trim();
    if (songId.isEmpty) return;

    try {
      // Position: append.
      final existing = await Supabase.instance.client
          .from('dj_playlist_tracks')
          .select('position')
          .eq('playlist_id', widget.playlistId)
          .order('position', ascending: false)
          .limit(1);

        final existingList = (existing as List<dynamic>);

      var nextPos = 0;
      if (existingList.isNotEmpty) {
        final raw = (existingList.first as Map<String, dynamic>)['position'];
        nextPos = (raw is num) ? raw.toInt() + 1 : (int.tryParse(raw?.toString() ?? '') ?? 0) + 1;
      }

      await Supabase.instance.client.from('dj_playlist_tracks').insert({
        'playlist_id': widget.playlistId,
        'song_id': songId,
        'position': nextPos,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added.')));
      setState(() { _future = _load(); });
    } catch (e, st) {
      UserFacingError.log('DjPlaylistDetailScreen addSong failed', e, st);
      if (!mounted) return;
      final msg = e.toString();
      final friendly = msg.toLowerCase().contains('duplicate') || msg.toLowerCase().contains('unique')
          ? 'Song already in playlist.'
          : 'Could not add song. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _addSongFlow,
            child: const Text('Add song'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: 'Could not load playlist tracks.',
              onRetry: () => setState(() { _future = _load(); }),
            );
          }

          final tracks = snap.data ?? const <Map<String, dynamic>>[];
          if (tracks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No songs yet.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _addSongFlow, child: const Text('Add a song')),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = tracks[i];
              final id = (t['id'] ?? '').toString();
              final pos = (t['position'] ?? i).toString();

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Text(pos, style: const TextStyle(color: AppColors.textMuted)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Track', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('Track ${i + 1}', style: const TextStyle(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => _removeTrack(id),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SongPickerDialog extends StatefulWidget {
  const _SongPickerDialog();

  @override
  State<_SongPickerDialog> createState() => _SongPickerDialogState();
}

class _SongPickerDialogState extends State<_SongPickerDialog> {
  final _supabase = Supabase.instance.client;
  final _queryCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _songs = const [];

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final q = query.trim();
      dynamic req = _supabase
          .from('songs')
          .select('id,title,thumbnail_url,created_at');

      if (q.isNotEmpty) {
        req = req.like('title', '%$q%');
      }

      req = req.order('created_at', ascending: false).limit(30);

      final rows = await req;
      if (!mounted) return;
      setState(() {
        _songs = (rows as List).whereType<Map<String, dynamic>>().toList(growable: false);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load songs.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick a song'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _queryCtrl,
              decoration: const InputDecoration(
                labelText: 'Search by title',
              ),
              onChanged: (v) => _run(v),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else if ((_error ?? '').isNotEmpty)
              Text(_error!, style: const TextStyle(color: AppColors.textMuted))
            else if (_songs.isEmpty)
              const Text('No songs found.')
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _songs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final s = _songs[i];
                    final id = (s['id'] ?? '').toString();
                    final title = (s['title'] ?? '').toString();
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
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
                                  Text(title.isEmpty ? 'Untitled' : title, style: const TextStyle(fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
