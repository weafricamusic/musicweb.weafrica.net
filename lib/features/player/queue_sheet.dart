import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'playback_controller.dart';

Future<void> showQueueSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (context) {
      return const _QueueSheet();
    },
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.current;
        final upNext = controller.upNext;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Queue', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  'Now playing',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                _NowPlayingTile(track: current),
                const SizedBox(height: 16),
                Text(
                  'Up next',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                  ),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    onReorder: controller.reorderQueue,
                    itemCount: upNext.length,
                    itemBuilder: (context, index) {
                      final t = upNext[index];
                      return Dismissible(
                        key: ValueKey('q_${t.title}__${t.artist}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) {
                          final removedTrack = t;
                          final removedIndex = index;
                          controller.removeFromUpNext(removedTrack);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Removed: ${removedTrack.title}'),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () {
                                  controller.insertIntoUpNextAt(
                                    removedIndex,
                                    removedTrack,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.music_note,
                              color: AppColors.textMuted,
                            ),
                          ),
                          title: Text(t.title),
                          subtitle: Text(
                            t.artist,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (index == 0)
                                Container(
                                  margin: const EdgeInsets.only(right: 10),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandOrange
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: AppColors.brandOrange
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    'NEXT',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: AppColors.brandOrange,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () {
                                  final removedTrack = t;
                                  final removedIndex = index;
                                  controller.removeFromUpNext(removedTrack);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Removed: ${removedTrack.title}'),
                                      action: SnackBarAction(
                                        label: 'Undo',
                                        onPressed: () {
                                          controller.insertIntoUpNextAt(
                                            removedIndex,
                                            removedTrack,
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.close,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(
                                  Icons.drag_handle,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => controller.playFromQueueIndex(index),
                          onLongPress: () =>
                              controller.playFromUpNextStartingAt(index),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: upNext.isEmpty
                            ? null
                            : () {
                                final previous = List<Track>.from(controller.upNext);
                                controller.clearQueue();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Queue cleared'),
                                    action: SnackBarAction(
                                      label: 'Undo',
                                      onPressed: () => controller.setQueue(previous),
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear queue'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.historyCount == 0
                            ? null
                            : () {
                                final previous = List<Track>.from(controller.history);
                                controller.clearHistory();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('History cleared'),
                                    action: SnackBarAction(
                                      label: 'Undo',
                                      onPressed: () =>
                                          controller.restoreHistory(previous),
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.history),
                        label: const Text('Clear history'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NowPlayingTile extends StatelessWidget {
  const _NowPlayingTile({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    if (track == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'Nothing playing',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.album, color: AppColors.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  track!.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.equalizer, color: AppColors.brandOrange),
        ],
      ),
    );
  }
}
