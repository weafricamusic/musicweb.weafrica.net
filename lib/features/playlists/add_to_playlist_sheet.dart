import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../subscriptions/role_based_subscription_screen.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../tracks/track.dart';
import 'playlist.dart';
import 'playlists_repository.dart';

Future<void> showAddTrackToPlaylistSheet(
  BuildContext context, {
  required Track track,
}) async {
  final rootContext = context;
  final trackId = track.id;
  if (trackId == null || trackId.trim().isEmpty) {
    final messenger = ScaffoldMessenger.of(rootContext);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('This track cannot be added to a playlist yet.')),
    );
    return;
  }

  final repo = PlaylistsRepository();

  Future<bool> ensureCanCreatePlaylist() async {
    if (SubscriptionsController.instance.canCreatePlaylists) return true;

    final upgrade = await showDialog<bool>(
      context: rootContext,
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

    if (upgrade == true && rootContext.mounted) {
      await Navigator.of(rootContext).push(
        MaterialPageRoute(builder: (_) => const RoleBasedSubscriptionScreen()),
      );
    }
    return false;
  }

  Future<String?> promptForPlaylistName(BuildContext dialogContext) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: dialogContext,
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

    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> addToPlaylist(String playlistId) async {
    await repo.addTrackToPlaylist(playlistId: playlistId, trackId: trackId);
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface2,
    builder: (sheetContext) {
      return SafeArea(
        child: FutureBuilder<List<Playlist>>(
          future: repo.fetchMyPlaylists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Could not load playlists. Please try again.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await ensureCanCreatePlaylist();
                        if (!ok) return;
                        if (!sheetContext.mounted) return;
                        final name = await promptForPlaylistName(sheetContext);
                        if (!sheetContext.mounted) return;
                        if (name == null) return;
                        try {
                          final created = await repo.createPlaylist(name: name);
                          await addToPlaylist(created.id);
                          if (!sheetContext.mounted) return;
                          Navigator.of(sheetContext).pop();
                          if (!rootContext.mounted) return;
                          final messenger = ScaffoldMessenger.of(rootContext);
                          messenger.removeCurrentSnackBar();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Added to “${created.name}”')),
                          );
                        } catch (e) {
                          if (!rootContext.mounted) return;
                          final messenger = ScaffoldMessenger.of(rootContext);
                          messenger.removeCurrentSnackBar();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Could not add to playlist.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create playlist'),
                    ),
                  ],
                ),
              );
            }

            final playlists = snapshot.data ?? const <Playlist>[];

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              shrinkWrap: true,
              children: [
                ListTile(
                  tileColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  leading: const Icon(Icons.add),
                  title: const Text('New playlist'),
                  subtitle: Text(
                    'Add “${track.title}”',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                  onTap: () async {
                    final ok = await ensureCanCreatePlaylist();
                    if (!ok) return;
                    if (!sheetContext.mounted) return;
                    final name = await promptForPlaylistName(sheetContext);
                    if (!sheetContext.mounted) return;
                    if (name == null) return;
                    try {
                      final created = await repo.createPlaylist(name: name);
                      await addToPlaylist(created.id);
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                      if (!rootContext.mounted) return;
                      final messenger = ScaffoldMessenger.of(rootContext);
                      messenger.removeCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(content: Text('Added to “${created.name}”')),
                      );
                    } catch (e) {
                      if (!rootContext.mounted) return;
                      final messenger = ScaffoldMessenger.of(rootContext);
                      messenger.removeCurrentSnackBar();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Could not add to playlist.')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'No playlists yet.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else
                  ...playlists.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        tileColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        leading: const Icon(Icons.queue_music, color: AppColors.textMuted),
                        title: Text(p.name),
                        onTap: () async {
                          try {
                            await addToPlaylist(p.id);
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                            if (!rootContext.mounted) return;
                            final messenger = ScaffoldMessenger.of(rootContext);
                            messenger.removeCurrentSnackBar();
                            messenger.showSnackBar(
                              SnackBar(content: Text('Added to “${p.name}”')),
                            );
                          } catch (e) {
                            if (!rootContext.mounted) return;
                            final messenger = ScaffoldMessenger.of(rootContext);
                            messenger.removeCurrentSnackBar();
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Could not add to playlist.')),
                            );
                          }
                        },
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      );
    },
  );
}
