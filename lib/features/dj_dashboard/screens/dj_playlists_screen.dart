import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/utils/user_facing_error.dart';
import '../models/dj_dashboard_models.dart';
import '../services/dj_dashboard_service.dart';
import '../services/dj_identity_service.dart';
import 'dj_playlist_detail_screen.dart';

class DjPlaylistsScreen extends StatefulWidget {
  const DjPlaylistsScreen({super.key, this.autoOpenCreate = false});

  final bool autoOpenCreate;

  @override
  State<DjPlaylistsScreen> createState() => _DjPlaylistsScreenState();
}

class _DjPlaylistsScreenState extends State<DjPlaylistsScreen> {
  final _identity = DjIdentityService();
  final _service = DjDashboardService();

  late Future<List<DjPlaylist>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();

    if (widget.autoOpenCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_createFlow());
      });
    }
  }

  Future<List<DjPlaylist>> _load() async {
    final uid = _identity.requireDjUid();
    return _service.listPlaylists(djUid: uid);
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _createFlow() async {
    final uid = _identity.requireDjUid();
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create playlist'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
          ],
        ),
      );

      if (ok != true) return;
      final title = ctrl.text.trim();
      if (title.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a title.')));
        return;
      }

      await _service.createPlaylist(djUid: uid, title: title);
      if (!mounted) return;
      setState(() { _future = _load(); });
    } catch (e, st) {
      UserFacingError.log('DjPlaylistsScreen createPlaylist failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create playlist. Please try again.')),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _delete(DjPlaylist playlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(playlist.title),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _service.deletePlaylist(playlistId: playlist.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.')));
      setState(() { _future = _load(); });
    } catch (e, st) {
      UserFacingError.log('DjPlaylistsScreen deletePlaylist failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete playlist. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          TextButton(
            onPressed: _createFlow,
            child: const Text('Create'),
          ),
        ],
      ),
      body: FutureBuilder<List<DjPlaylist>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: 'Could not load playlists.',
              onRetry: () => setState(() { _future = _load(); }),
            );
          }

          final playlists = snap.data ?? const <DjPlaylist>[];
          if (playlists.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No playlists yet.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _createFlow, child: const Text('Create playlist')),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: playlists.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final p = playlists[i];
              return InkWell(
                onTap: () async {
                  _open(context, DjPlaylistDetailScreen(playlistId: p.id, title: p.title));
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.playlist_play, color: AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text('Created: ${p.createdAt.toLocal().toString().split('.').first}', style: const TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _delete(p),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
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
