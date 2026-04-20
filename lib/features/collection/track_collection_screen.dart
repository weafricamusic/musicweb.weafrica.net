import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/gold_button.dart';
import '../../app/widgets/stage_background.dart';
import '../ads/widgets/admob_native_widget.dart';
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import '../subscriptions/subscriptions_controller.dart';
import 'widgets/collection_header.dart';
import 'widgets/track_card.dart';

enum CollectionType {
  playlist,
  album,
  artist,
  genre,
  battle;

  String get displayName {
    switch (this) {
      case CollectionType.playlist:
        return 'PLAYLIST';
      case CollectionType.album:
        return 'ALBUM';
      case CollectionType.artist:
        return 'ARTIST';
      case CollectionType.genre:
        return 'GENRE';
      case CollectionType.battle:
        return 'BATTLE';
    }
  }

  IconData get icon {
    switch (this) {
      case CollectionType.playlist:
        return Icons.playlist_play;
      case CollectionType.album:
        return Icons.album;
      case CollectionType.artist:
        return Icons.person;
      case CollectionType.genre:
        return Icons.category;
      case CollectionType.battle:
        return Icons.bolt;
    }
  }
}

enum SortOption {
  defaultOrder,
  titleAsc,
  titleDesc,
  durationAsc,
  durationDesc,
  recent;

  String get displayName {
    switch (this) {
      case SortOption.defaultOrder:
        return 'Default';
      case SortOption.titleAsc:
        return 'Title A–Z';
      case SortOption.titleDesc:
        return 'Title Z–A';
      case SortOption.durationAsc:
        return 'Duration ↑';
      case SortOption.durationDesc:
        return 'Duration ↓';
      case SortOption.recent:
        return 'Recent';
    }
  }
}

class TrackCollectionScreen extends StatefulWidget {
  const TrackCollectionScreen({
    super.key,
    required this.title,
    required this.tracks,
    this.subtitle,
    this.coverImageUrl,
    this.collectionType = CollectionType.playlist,
    this.creatorName,
    this.totalDuration,
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final String? coverImageUrl;
  final List<Track> tracks;
  final CollectionType collectionType;
  final String? creatorName;
  final Duration? totalDuration;
  final Future<void> Function()? onRefresh;

  @override
  State<TrackCollectionScreen> createState() => _TrackCollectionScreenState();
}

class _TrackCollectionScreenState extends State<TrackCollectionScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  bool _isPlayingAll = false;
  SortOption _sort = SortOption.defaultOrder;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..forward();
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  List<Track> get _sortedTracks {
    final list = List<Track>.from(widget.tracks);
    switch (_sort) {
      case SortOption.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return list;
      case SortOption.titleDesc:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        return list;
      case SortOption.durationAsc:
        list.sort((a, b) => (a.duration?.inMilliseconds ?? 0).compareTo(b.duration?.inMilliseconds ?? 0));
        return list;
      case SortOption.durationDesc:
        list.sort((a, b) => (b.duration?.inMilliseconds ?? 0).compareTo(a.duration?.inMilliseconds ?? 0));
        return list;
      case SortOption.recent:
        list.sort((a, b) {
          final aa = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bb.compareTo(aa);
        });
        return list;
      case SortOption.defaultOrder:
        return widget.tracks;
    }
  }

  Duration _computeTotalDuration(List<Track> tracks) {
    var totalMs = 0;
    for (final t in tracks) {
      final d = t.duration;
      if (d == null) continue;
      totalMs += d.inMilliseconds;
    }
    return Duration(milliseconds: totalMs);
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _playAll() {
    if (widget.tracks.isEmpty) return;
    final playable = widget.tracks.where((t) => t.audioUri != null).toList(growable: false);
    if (playable.isEmpty) {
      _showSnack('No playable tracks in this collection yet.');
      return;
    }

    setState(() => _isPlayingAll = true);
    PlaybackController.instance.play(playable.first, queue: playable.skip(1).toList(growable: false));
    openPlayer(context);

    Future<void>.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      setState(() => _isPlayingAll = false);
    });
  }

  void _shuffleAll() {
    if (widget.tracks.isEmpty) return;
    final playable = widget.tracks.where((t) => t.audioUri != null).toList(growable: false);
    if (playable.length < 2) {
      _showSnack('Not enough playable tracks to shuffle.');
      return;
    }

    final shuffled = List<Track>.from(playable)..shuffle(Random());
    PlaybackController.instance.play(shuffled.first, queue: shuffled.skip(1).toList(growable: false));
    openPlayer(context);
  }

  void _playFromSortedIndex(int sortedIndex) {
    final tracks = _sortedTracks;
    if (sortedIndex < 0 || sortedIndex >= tracks.length) return;
    final selected = tracks[sortedIndex];
    if (selected.audioUri == null) {
      _showSnack('This track is not playable yet.');
      return;
    }

    final after = <Track>[];
    for (var i = sortedIndex + 1; i < tracks.length; i++) {
      final t = tracks[i];
      if (t.audioUri == null) continue;
      after.add(t);
    }
    for (var i = 0; i < sortedIndex; i++) {
      final t = tracks[i];
      if (t.audioUri == null) continue;
      after.add(t);
    }

    PlaybackController.instance.play(selected, queue: after);
    openPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.tracks;
    final playableTracks = tracks.where((t) => t.audioUri != null).length;
    final totalDuration = widget.totalDuration ?? _computeTotalDuration(tracks);
    final effectiveCover = (widget.coverImageUrl ?? '').trim().isNotEmpty
        ? widget.coverImageUrl
        : tracks
            .map((t) => t.artworkUri?.toString().trim() ?? '')
            .firstWhere(
              (u) => u.isNotEmpty,
              orElse: () => '',
            );

    final content = CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(widget.title),
          flexibleSpace: FlexibleSpaceBar(
            background: CollectionHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              coverImageUrl: (effectiveCover ?? '').trim().isEmpty ? null : effectiveCover,
              collectionType: widget.collectionType,
              creatorName: widget.creatorName,
              trackCount: tracks.length,
              totalDuration: totalDuration,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: GoldButton(
                    onPressed: playableTracks > 0 ? _playAll : null,
                    label: 'PLAY ALL',
                    icon: Icons.play_arrow,
                    isLoading: _isPlayingAll,
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GoldButton(
                    onPressed: playableTracks > 1 ? _shuffleAll : null,
                    label: 'SHUFFLE',
                    icon: Icons.shuffle,
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Row(
              children: [
                Text(
                  'TRACKS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const Spacer(),
                PopupMenuButton<SortOption>(
                  tooltip: 'Sort',
                  initialValue: _sort,
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (context) => SortOption.values
                      .map(
                        (v) => PopupMenuItem<SortOption>(
                          value: v,
                          child: Text(v.displayName),
                        ),
                      )
                      .toList(growable: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sort, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          _sort.displayName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 120),
              child: _EmptyState(label: widget.subtitle),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
            sliver: SliverList.separated(
              itemCount: () {
                final sorted = _sortedTracks;
                final adsEnabled = SubscriptionsController.instance.entitlements.effectiveAdsEnabled;
                if (!adsEnabled) return sorted.length;

                const nativeEvery = 6;
                if (sorted.length <= nativeEvery) return sorted.length;
                final adsCount = (sorted.length - 1) ~/ nativeEvery;
                return sorted.length + adsCount;
              }(),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final sorted = _sortedTracks;
                final adsEnabled = SubscriptionsController.instance.entitlements.effectiveAdsEnabled;

                const nativeEvery = 6;
                final block = nativeEvery + 1;

                final isAdSlot = adsEnabled && sorted.length > nativeEvery && (index % block == nativeEvery);
                if (isAdSlot) {
                  return const FadeTransition(
                    opacity: AlwaysStoppedAnimation<double>(1),
                    child: AdmobNativeWidget(placement: 'feed'),
                  );
                }

                final adsBefore = (!adsEnabled || sorted.length <= nativeEvery) ? 0 : (index ~/ block);
                final sortedIndex = index - adsBefore;
                if (sortedIndex < 0 || sortedIndex >= sorted.length) {
                  return const SizedBox.shrink();
                }

                final track = sorted[sortedIndex];
                return FadeTransition(
                  opacity: _fade,
                  child: TrackCard(
                    track: track,
                    index: sortedIndex + 1,
                    onTap: () => _playFromSortedIndex(sortedIndex),
                    onAction: (action) {
                      switch (action) {
                        case TrackAction.playNext:
                          if (track.audioUri == null) {
                            _showSnack('This track is not playable yet.');
                            return;
                          }
                          PlaybackController.instance.addToUpNext(track, toFront: true);
                          _showSnack('Queued to play next.');
                          return;
                        case TrackAction.addToQueue:
                          if (track.audioUri == null) {
                            _showSnack('This track is not playable yet.');
                            return;
                          }
                          PlaybackController.instance.addToUpNext(track);
                          _showSnack('Added to Up Next.');
                          return;
                        case TrackAction.share:
                          TrackActions.shareTrack(track);
                          return;
                        case TrackAction.download:
                          _showSnack('Downloads are not available here yet.');
                          return;
                      }
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );

    final scrollable = widget.onRefresh == null
        ? content
        : RefreshIndicator(
            onRefresh: widget.onRefresh!,
            child: content,
          );

    return Scaffold(
      body: StageBackground(child: scrollable),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final subtitle = (label ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.music_off, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.75)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No tracks yet', style: TextStyle(fontWeight: FontWeight.w900)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: AppColors.textMuted)),
                ] else ...[
                  const SizedBox(height: 4),
                  Text('Add songs to build your collection.', style: TextStyle(color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
