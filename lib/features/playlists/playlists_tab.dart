import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/section_header.dart';
import '../subscriptions/role_based_subscription_screen.dart';
import '../subscriptions/subscriptions_controller.dart';
import 'playlist.dart';
import 'playlist_detail_screen.dart';
import 'playlists_repository.dart';

class PlaylistsTab extends StatefulWidget {
  const PlaylistsTab({super.key});

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  final PlaylistsRepository _repo = PlaylistsRepository();

  late Future<List<Playlist>> _future = _repo.fetchMyPlaylists();

  Future<void> _refresh() async {
    setState(() {
      _future = _repo.fetchMyPlaylists();
    });
    await _future;
  }

  Future<void> _createPlaylist() async {
    if (!SubscriptionsController.instance.canCreatePlaylists) {
      final upgrade = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Playlists require a subscription'),
            content: const Text('Upgrade to Premium Listener (or VIP Listener) to create playlists.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Upgrade'),
              ),
            ],
          );
        },
      );

      if (upgrade == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoleBasedSubscriptionScreen()),
        );
      }
      return;
    }

    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Playlist name',
              hintText: 'e.g. My Favorites',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name == null || name.trim().isEmpty) return;

    try {
      final created = await _repo.createPlaylist(name: name.trim());
      await _refresh();

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlist: created),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create playlist.')),
      );
    }
  }

  Future<void> _confirmDelete(Playlist playlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text('“${playlist.name}” will be removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await _repo.deletePlaylist(playlist.id);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete playlist.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Playlist>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                SectionHeader(
                  title: 'Playlists',
                  subtitle: 'Your playlists',
                  trailing: TextButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Could not load playlists. Please try again.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add),
                  label: const Text('Create playlist'),
                ),
              ],
            );
          }

          final playlists = snapshot.data ?? const <Playlist>[];

          if (playlists.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                SectionHeader(
                  title: 'Playlists',
                  subtitle: 'Your playlists',
                  trailing: TextButton(
                    onPressed: _createPlaylist,
                    child: const Text('New'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No playlists yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add),
                  label: const Text('Create playlist'),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            itemCount: playlists.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return SectionHeader(
                  title: 'Playlists',
                  subtitle: 'Your playlists',
                  trailing: TextButton(
                    onPressed: _createPlaylist,
                    child: const Text('New'),
                  ),
                );
              }

              final playlist = playlists[index - 1];

              return DecoratedBox(
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
                child: ListTile(
                  tileColor: AppColors.surface2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  leading: Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.queue_music,
                      color: AppColors.textMuted,
                    ),
                  ),
                  title: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    playlist.createdAt == null
                        ? 'Playlist'
                        : 'Created ${playlist.createdAt!.toLocal().toIso8601String().split('T').first}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(playlist),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaylistDetailScreen(playlist: playlist),
                      ),
                    );
                    await _refresh();
                  },
                  onLongPress: () => _confirmDelete(playlist),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
