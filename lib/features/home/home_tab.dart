import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

// Models
import '../creators/creator_profile.dart';
import '../videos/video.dart';
import '../../services/recent_contexts_service.dart' show RecentContext, RecentContextsService;

// Repositories
import '../tracks/tracks_repository.dart';
import '../creators/creators_repository.dart';
import '../videos/videos_repository.dart';

// API
// Services
import '../../services/promotions_service.dart';

// Widgets
import '../../app/widgets/media_card.dart';
import '../../app/widgets/quick_access.dart';

// Screens & Controllers
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import '../playlists/add_to_playlist_sheet.dart';
import '../pulse/reels/feed_screen.dart';

import '../subscriptions/models/subscription_capabilities.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../subscriptions/widgets/contextual_upgrade_modal.dart';
import '../subscriptions/widgets/upgrade_prompt_factory.dart';
import '../../services/content_access_policy.dart';

import '../creators/public_artist_profile_screen.dart';
import '../creators/public_dj_profile_screen.dart';

// Theme
import '../../app/theme.dart';

class WeAfricaHomePage extends StatefulWidget {
  const WeAfricaHomePage({super.key});

  @override
  State<WeAfricaHomePage> createState() => _WeAfricaHomePageState();
}

class _WeAfricaHomePageState extends State<WeAfricaHomePage> {
  // Future data sources
  late Future<List<Track>> _tracksFuture;
  late Future<List<Map<String, dynamic>>> _promotionsFuture;
  late Future<List<RecentContext>> _quickAccessFuture;
  late Future<List<CreatorProfile>> _featuredArtistsFuture;
  late Future<List<CreatorProfile>> _featuredDjsFuture;
  late Future<List<Track>> _malawiSpotlightFuture;
  late Future<List<Video>> _videosFuture;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _tracksFuture = TracksRepository().latest(limit: 40);
      _promotionsFuture = _fetchPromotions();
      _quickAccessFuture = RecentContextsService.instance.fetchQuickAccess();
      _featuredArtistsFuture = _fetchFeaturedArtists();
      _featuredDjsFuture = _fetchFeaturedDjs();
      _malawiSpotlightFuture = _fetchMalawiSpotlight();
      _videosFuture = _fetchVideos();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchPromotions() async {
    return PromotionsService.fetchPromotions();
  }

  Future<List<CreatorProfile>> _fetchFeaturedArtists() async {
    return CreatorsRepository().listFeaturedArtists(limit: 18);
  }

  Future<List<CreatorProfile>> _fetchFeaturedDjs() async {
    return CreatorsRepository().list(role: CreatorRole.dj, limit: 18);
  }

  Future<List<Track>> _fetchMalawiSpotlight() async {
    // Spotlight by country (MW). Safe to return [] if country isn't populated.
    return TracksRepository().byCountry('MW', limit: 40);
  }

  Future<List<Video>> _fetchVideos() async {
    return VideosRepository().latest(limit: 20);
  }

  Future<void> _refresh() async {
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Track>>(
      future: _tracksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return _buildErrorState();
        }

        final tracks = snapshot.data ?? const <Track>[];
        if (tracks.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Main Promotions Banner
              _buildPromotionsBanner(),

              // Quick Access
              _buildQuickAccessSection(),

              // Trending Songs
              _buildSectionHeader('Trending Songs'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                sliver: SliverToBoxAdapter(
                  child: _CardsRow(
                    tracks: _takeTracks(tracks, 0, 8),
                    icon: Icons.whatshot,
                    subtitle: 'Trending',
                  ),
                ),
              ),

              // Recommended Songs
              _buildSectionHeader('Recommended Songs'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                sliver: SliverToBoxAdapter(
                  child: _CardsRow(
                    tracks: _takeTracks(tracks, 8, 8),
                    icon: Icons.auto_awesome,
                    subtitle: 'For you',
                  ),
                ),
              ),

              // Featured Artists
              _buildFeaturedArtistsSection(),

              // Featured DJs
              _buildFeaturedDJsSection(),

              // Malawi Spotlight
              _buildSectionHeader('Malawi Spotlight'),
              _buildMalawiSpotlightSection(),

              // Video Feed
              _buildSectionHeader('Video Feed'),
              _buildVideoFeedSection(),

              // Promotions Row
              _buildSectionHeader('Promotions', trailingLabel: 'Sponsored'),
              _buildPromotionsRow(),

              // New Releases
              _buildSectionHeader('New Releases'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                sliver: SliverToBoxAdapter(
                  child: _CardsRow(
                    tracks: _takeTracks(tracks, 16, 8),
                    icon: Icons.fiber_new,
                    subtitle: 'Single',
                  ),
                ),
              ),

              // Free & Featured
              _buildSectionHeader('Free & Featured'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
                sliver: SliverToBoxAdapter(
                  child: _CardsRow(
                    tracks: _takeTracks(tracks, 32, 8),
                    icon: Icons.music_note,
                    subtitle: 'Free',
                    badgeLabel: 'FREE',
                    badgeColor: Colors.amber,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Could not load tracks. Please try again.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'No songs available yet.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }

  Widget _buildPromotionsBanner() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverToBoxAdapter(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _promotionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }

            if (snapshot.hasError) {
              return const SizedBox.shrink();
            }

            final dynamicPromos = snapshot.data ?? const <Map<String, dynamic>>[];
            final cards = _PromoCardData.fromApi(dynamicPromos);
            if (cards.isEmpty) {
              return const SizedBox.shrink();
            }

            final banner = cards.firstWhere(
              (c) => c.actionUri != null,
              orElse: () => cards.first,
            );

            return InkWell(
              onTap: () {
                unawaited(banner.open(context));
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (banner.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        banner.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuickAccessSection() {
    return SliverToBoxAdapter(
      child: FutureBuilder<List<RecentContext>>(
        future: _quickAccessFuture,
        builder: (context, snapshot) {
          final items = (snapshot.data ?? const <RecentContext>[])
              .where((c) => c.contextType.trim().toLowerCase() == 'track')
              .toList(growable: false);
          if (items.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: _WeAfricaSectionHeader(
                  title: 'Quick Access',
                  trailingLabel: 'Recent',
                  onSeeAll: _refresh,
                ),
              ),
              QuickAccessGrid(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                items: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final c = entry.value;
                  return QuickAccessItem(
                    title: c.title,
                    imageUri: c.imageUri,
                    onTap: () async {
                      // Build a queue from the other Quick Access tracks so playback
                      // can auto-advance when a track ends.
                      final queueContextIds = <String>[];
                      for (var i = index + 1; i < items.length; i++) {
                        final ctx = items[i];
                        if (ctx.contextType == 'track') queueContextIds.add(ctx.contextId);
                      }
                      for (var i = 0; i < index; i++) {
                        final ctx = items[i];
                        if (ctx.contextType == 'track') queueContextIds.add(ctx.contextId);
                      }

                      final repo = TracksRepository();
                      final track = await repo.getById(c.contextId);
                      if (!context.mounted) return;
                      if (track == null || track.audioUri == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('This item is not playable yet.')),
                        );
                        return;
                      }

                      final fetched = await Future.wait(
                        queueContextIds.map(
                          (id) => repo.getById(id).catchError((_) => null),
                        ),
                      );

                      final seen = <String>{};
                      final queue = <Track>[];
                      for (final t in fetched) {
                        if (t == null) continue;
                        if (t.audioUri == null) continue;
                        final key = t.id ?? t.audioUri.toString();
                        if (!seen.add(key)) continue;
                        queue.add(t);
                      }

                      PlaybackController.instance.play(track, queue: queue);

                      // Persist quick-access history (best-effort).
                      unawaited(
                        RecentContextsService.instance.upsertContext(
                          contextType: 'track',
                          contextId: track.id ?? c.contextId,
                          title: track.title,
                          imageUri: track.artworkUri,
                          source: 'home',
                        ),
                      );
                    },
                  );
                }).toList(growable: false),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFeaturedArtistsSection() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeAfricaSectionHeader(
              title: 'Featured Artists',
              onSeeAll: _refresh,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CreatorProfile>>(
              future: _featuredArtistsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SectionLoading(height: 132);
                }

                if (snapshot.hasError) {
                  if (!kDebugMode) {
                    return Text(
                      'Could not load Featured Artists right now.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    );
                  }
                  return Text(
                    'Could not load Featured Artists right now.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  );
                }

                final items = snapshot.data ?? const <CreatorProfile>[];
                if (items.isEmpty) return const SizedBox.shrink();

                return _CreatorsRow(items: items, roleLabel: 'Artist');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedDJsSection() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeAfricaSectionHeader(
              title: 'Featured DJs',
              onSeeAll: _refresh,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CreatorProfile>>(
              future: _featuredDjsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SectionLoading(height: 132);
                }

                if (snapshot.hasError) {
                  return Text(
                    'Could not load Featured DJs right now.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  );
                }

                final items = snapshot.data ?? const <CreatorProfile>[];
                if (items.isEmpty) return const SizedBox.shrink();

                return _CreatorsRow(items: items, roleLabel: 'DJ');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMalawiSpotlightSection() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
      sliver: SliverToBoxAdapter(
        child: FutureBuilder<List<Track>>(
          future: _malawiSpotlightFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  'Could not load this section right now.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              );
            }

            final items = snapshot.data ?? const <Track>[];
            if (items.isEmpty) return const SizedBox.shrink();

            return _CardsRow(
              tracks: items.take(8).toList(growable: false),
              icon: Icons.flag,
              subtitle: 'MW',
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoFeedSection() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
      sliver: SliverToBoxAdapter(
        child: FutureBuilder<List<Video>>(
          future: _videosFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _SectionLoading(height: 200);
            }

            if (snapshot.hasError) {
              developer.log(
                'Home videos failed to load',
                name: 'WEAFRICA.Home',
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
              );

              final debugDetails = kDebugMode
                  ? (snapshot.error?.toString().trim().isEmpty ?? true)
                      ? null
                      : snapshot.error.toString()
                  : null;

              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  debugDetails == null
                      ? 'Could not load videos right now.'
                      : 'Could not load videos right now.\n\n$debugDetails',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              );
            }

            final items = snapshot.data ?? const <Video>[];
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  'No videos yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              );
            }

            return _VideosRow(videos: items);
          },
        ),
      ),
    );
  }

  Widget _buildPromotionsRow() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
      sliver: SliverToBoxAdapter(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _promotionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }

            if (snapshot.hasError) {
              return const SizedBox.shrink();
            }

            final dynamicPromos = snapshot.data ?? const <Map<String, dynamic>>[];
            final cards = _PromoCardData.fromApi(dynamicPromos);

            if (cards.isEmpty) {
              return const SizedBox.shrink();
            }

            return _PromoRow(promos: cards);
          },
        ),
      ),
    );
  }


  SliverPadding _buildSectionHeader(String title, {String? trailingLabel}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      sliver: SliverToBoxAdapter(
        child: _WeAfricaSectionHeader(
          title: title,
          trailingLabel: trailingLabel,
          onSeeAll: _refresh,
        ),
      ),
    );
  }

  List<Track> _takeTracks(List<Track> tracks, int start, int count) {
    if (tracks.isEmpty || count <= 0) return const <Track>[];
    if (start >= tracks.length) return const <Track>[];
    final end = (start + count).clamp(0, tracks.length);
    return tracks.sublist(start, end);
  }
}

// Helper Classes and Widgets

class _HomeStatusItem {
  const _HomeStatusItem({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});

  final _HomeStatusItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: AppColors.brandOrange, width: 3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            item.text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _WeAfricaSectionHeader extends StatelessWidget {
  const _WeAfricaSectionHeader({
    required this.title,
    this.onSeeAll,
    this.trailingLabel,
  });

  final String title;
  final VoidCallback? onSeeAll;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    const orange1 = Color(0xFF1DB954);
    const orange2 = Color(0xFF1ED760);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [orange1, orange2],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        if (trailingLabel != null)
          Text(
            trailingLabel!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          )
        else if (onSeeAll != null)
          InkWell(
            onTap: onSeeAll,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Text(
                    'See all',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: orange1,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: orange1),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CardsRow extends StatelessWidget {
  const _CardsRow({
    required this.tracks,
    required this.icon,
    required this.subtitle,
    this.badgeLabel,
    this.badgeColor,
  });

  final List<Track> tracks;
  final IconData icon;
  final String subtitle;
  final String? badgeLabel;
  final Color? badgeColor;

  Future<void> _showTrackActions(BuildContext context, Track track) async {
    if (track.audioUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no audio URL yet.')),
      );
      return;
    }

    final controller = PlaybackController.instance;

    final action = await showModalBottomSheet<_HomeQueueAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface2,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('Play next'),
                subtitle: Text('After: ${controller.current?.title ?? 'Nothing'}'),
                onTap: () => Navigator.of(context).pop(_HomeQueueAction.playNext),
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to queue'),
                subtitle: const Text('Add to the end of Up next'),
                onTap: () => Navigator.of(context).pop(_HomeQueueAction.addToQueue),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to playlist'),
                subtitle: const Text('Save this track to a playlist'),
                onTap: () => Navigator.of(context).pop(_HomeQueueAction.addToPlaylist),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (action == null) return;
    if (!context.mounted) return;

    if (action == _HomeQueueAction.addToPlaylist) {
      await showAddTrackToPlaylistSheet(context, track: track);
      return;
    }

    // If nothing is playing yet, queue actions are confusing — just start playback.
    if (controller.current == null) {
      controller.play(track);
      if (context.mounted) openPlayer(context);
      return;
    }

    final isPlayNext = action == _HomeQueueAction.playNext;
    controller.addToUpNext(track, toFront: isPlayNext);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isPlayNext ? 'Will play next' : 'Added to queue'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.removeFromUpNext(track),
        ),
      ),
    );
  }

  List<Track> _queueFrom(List<Track> tracks, int index) {
    final queue = <Track>[];
    for (var i = index + 1; i < tracks.length; i++) {
      final next = tracks[i];
      if (next.audioUri == null) continue;
      queue.add(next);
    }
    for (var i = 0; i < index; i++) {
      final next = tracks[i];
      if (next.audioUri == null) continue;
      queue.add(next);
    }
    return queue;
  }

  @override
  Widget build(BuildContext context) {
    final controller = PlaybackController.instance;

    if (tracks.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.centerLeft,
        child: Text(
          'No tracks',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final t = tracks[index];
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final isCurrent = Track.same(controller.current, t);
              final isPlaying = isCurrent && controller.isPlaying;
              final effectiveBadgeLabel = badgeLabel ?? t.promotionBadgeLabel;
              final effectiveBadgeColor = badgeLabel != null
                  ? badgeColor
                  : switch ((t.promotionPlan ?? '').trim().toLowerCase()) {
                      'premium' => Colors.amber,
                      'pro' => Colors.lightBlueAccent,
                      _ => AppColors.brandOrange,
                    };

              return Stack(
                children: [
                  MediaCard(
                    size: 140,
                    width: 140,
                    height: 180,
                    leadingIcon: icon,
                    title: t.title,
                    subtitle: subtitle,
                    imageUri: t.artworkUri,
                    badgeLabel: effectiveBadgeLabel,
                    badgeColor: effectiveBadgeColor,
                    onTap: () {
                      if (t.audioUri == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('This track has no audio URL yet.'),
                          ),
                        );
                        return;
                      }

                      if (!isCurrent) {
                        controller.play(t, queue: _queueFrom(tracks, index));
                      } else if (controller.current != null) {
                        controller.togglePlay();
                      }
                      openPlayer(context);
                    },
                    onLongPress: () => _showTrackActions(context, t),
                  ),
                  if (isCurrent)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brandOrange.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.brandOrange.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPlaying ? Icons.equalizer : Icons.pause,
                              size: 14,
                              color: AppColors.brandOrange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'PLAYING',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColors.brandOrange,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CreatorsRow extends StatelessWidget {
  const _CreatorsRow({required this.items, required this.roleLabel});

  final List<CreatorProfile> items;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final p = items[index];
          return _CreatorAvatarCard(profile: p, roleLabel: roleLabel);
        },
      ),
    );
  }
}

class _CreatorAvatarCard extends StatelessWidget {
  const _CreatorAvatarCard({required this.profile, required this.roleLabel});

  final CreatorProfile profile;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile.avatarUrl;

    return InkWell(
      onTap: () {
        if (profile.role == CreatorRole.artist) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PublicArtistProfileScreen(profile: profile),
            ),
          );
          return;
        }

        if (profile.role == CreatorRole.dj) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PublicDjProfileScreen(profile: profile),
            ),
          );
          return;
        }

        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          backgroundColor: AppColors.surface2,
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      roleLabel,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                    if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(profile.bio!),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        height: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              height: 76,
              width: 76,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl == null || avatarUrl.trim().isEmpty
                  ? Center(
                      child: Text(
                        profile.displayName.isEmpty
                            ? '?'
                            : profile.displayName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    )
                  : Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(Icons.person, color: AppColors.textMuted),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              profile.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _VideosRow extends StatelessWidget {
  const _VideosRow({required this.videos});

  final List<Video> videos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final v = videos[index];
          return MediaCard(
            width: 140,
            height: 180,
            size: 140,
            leadingIcon: Icons.play_circle,
            title: v.title,
            subtitle: v.category ?? 'Video',
            imageUri: v.thumbnailUri,
            onTap: () async {
              final entitlements = SubscriptionsController.instance.entitlements;
              final userKey = FirebaseAuth.instance.currentUser?.uid;
              final decision = ContentAccessPolicy.decide(
                entitlements: entitlements,
                contentId: v.id,
                isExclusive: v.isExclusive,
                userKey: userKey,
              );

              if (!decision.allowed) {
                final reason = decision.reason;
                if (reason == null) return;

                final capability = switch (reason) {
                  ContentAccessBlockReason.exclusive => ConsumerCapability.exclusiveContent,
                  ContentAccessBlockReason.ratio => ConsumerCapability.contentAccess,
                };

                final prompt = UpgradePromptFactory.forConsumerCapability(capability);
                final upgraded = await showContextualUpgradeModal(
                  context,
                  prompt: prompt,
                  source: 'home_video_tap:${reason.name}',
                );

                if (!upgraded || !context.mounted) return;
                await SubscriptionsController.instance.refreshMe();

                final refreshed = ContentAccessPolicy.decide(
                  entitlements: SubscriptionsController.instance.entitlements,
                  contentId: v.id,
                  isExclusive: v.isExclusive,
                  userKey: userKey,
                );
                if (!refreshed.allowed) return;
              }

              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReelFeedScreen(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PromoRow extends StatelessWidget {
  const _PromoRow({required this.promos});

  final List<_PromoCardData> promos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: promos.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final promo = promos[index];
          return _PromoCard(data: promo);
        },
      ),
    );
  }
}

class _PromoCardData {
  const _PromoCardData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.actionUri,
  });

  final String id;
  final String title;
  final String subtitle;
  final Color color;
  final Uri? actionUri;

  Future<void> open(BuildContext context) async {
    final uri = actionUri;
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This promo has no link yet.')),
      );
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open promo link.')),
      );
    }
  }

  static String _readString(Map<String, dynamic> p, List<String> keys) {
    for (final k in keys) {
      final v = p[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static bool _readBool(Map<String, dynamic> p, List<String> keys) {
    for (final k in keys) {
      final v = p[k];
      if (v == null) continue;
      if (v is bool) return v;
      final s = v.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return false;
  }

  static Uri? _readUri(Map<String, dynamic> p, List<String> keys) {
    final raw = _readString(p, keys);
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  static List<_PromoCardData> fromApi(List<Map<String, dynamic>> promos) {
    if (promos.isEmpty) return const <_PromoCardData>[];

    int readPriority(Map<String, dynamic> p) {
      final v = p['priority'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    bool isTestPromo(Map<String, dynamic> p) {
      if (_readBool(p, const ['is_test', 'isTest', 'test', 'debug'])) return true;
      final env = _readString(p, const ['env', 'environment', 'stage']).toLowerCase();
      if (env == 'test' || env == 'debug' || env == 'staging') return true;

      final title = _readString(p, const ['title', 'name']).toLowerCase();
      final body = _readString(p, const ['body', 'subtitle', 'description']).toLowerCase();
      final combined = '$title $body';
      // Avoid showing accidental dev content in production.
      if (RegExp(r'\btest\b').hasMatch(combined)) return true;
      if (combined.contains('[test]') || combined.contains('dummy') || combined.contains('sample')) {
        return true;
      }
      return false;
    }

    bool isActivePromo(Map<String, dynamic> p) {
      if (p.containsKey('active')) return _readBool(p, const ['active']);
      if (p.containsKey('is_active')) return _readBool(p, const ['is_active']);
      // If the backend doesn't send an active flag, assume it's active.
      return true;
    }

    final cleaned = promos
        .where((p) {
          if (!isActivePromo(p)) return false;
          if (isTestPromo(p)) return false;

          final title = _readString(p, const ['title', 'name']);
          final body = _readString(p, const ['body', 'subtitle', 'description']);
          if (title.isEmpty && body.isEmpty) return false;

          // If there's no action URL, hide it in release builds.
          final actionUri = _readUri(
            p,
            const [
              'url',
              'link',
              'cta_url',
              'ctaUrl',
              'action_url',
              'actionUrl',
              'deep_link',
              'deepLink',
              'deeplink',
              'target_url',
              'targetUrl',
            ],
          );
          if (actionUri == null && !kDebugMode) return false;
          return true;
        })
        .toList(growable: false);

    cleaned.sort((a, b) => readPriority(b).compareTo(readPriority(a)));

    return cleaned.map((p) {
      final id = _readString(p, const ['id', 'slug']);
      final title = _readString(p, const ['title', 'name']);
      final body = _readString(p, const ['body', 'subtitle', 'description']);
      final subtitle = body.isEmpty ? 'Tap to learn more' : body;

      final key = id.isNotEmpty ? id : title;
      final palette = <Color>[
        const Color(0xFFD98E1E),
        const Color(0xFFB87333),
        const Color(0xFF9C6B30),
        const Color(0xFFF59E0B),
        const Color(0xFFEF4444),
        const Color(0xFF8B5CF6),
      ];
      final color = palette[key.hashCode.abs() % palette.length];

      final actionUri = _readUri(
        p,
        const [
          'url',
          'link',
          'cta_url',
          'ctaUrl',
          'action_url',
          'actionUrl',
          'deep_link',
          'deepLink',
          'deeplink',
          'target_url',
          'targetUrl',
        ],
      );

      return _PromoCardData(
        id: key,
        title: title,
        subtitle: subtitle,
        color: color,
        actionUri: actionUri,
      );
    }).toList(growable: false);
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.data});

  final _PromoCardData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => unawaited(data.open(context)),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: data.color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              data.subtitle,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Icon(Icons.arrow_forward, color: data.color, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

enum _HomeQueueAction {
  playNext,
  addToQueue,
  addToPlaylist,
}
