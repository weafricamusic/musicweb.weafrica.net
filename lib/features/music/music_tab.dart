import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:glass_kit/glass_kit.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/config/api_env.dart';
import '../../app/network/firebase_authed_http.dart';
import '../../app/utils/user_facing_error.dart';
import '../../app/widgets/section_header.dart';
import '../../app/widgets/auto_artwork.dart';
import '../../app/widgets/gold_button.dart';
import '../albums/album.dart';
import '../albums/albums_repository.dart';
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import '../tracks/tracks_repository.dart';

class MusicTab extends StatefulWidget {
  const MusicTab({super.key});

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldLight = Color(0xFFF2D572);
  
  late Future<List<Track>> _tracksFuture = TracksRepository().latest(limit: 120);
  late Future<List<Album>> _albumsFuture = AlbumsRepository().latestPublished(limit: 12);
  List<Track> _latestTracks = const <Track>[];
  
  final _searchController = TextEditingController();
  String _query = '';
  final bool _showAlbums = true;
  int _selectedGenreIndex = -1;
  
  final List<String> _genres = [
    'ALL',
    'AFROBEATS',
    'AMAPIANO',
    'HIP HOP',
    'GOSPEL',
    'REGGAE',
    'DANCE',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    setState(() {
      _tracksFuture = _query.trim().isEmpty
          ? TracksRepository().latest(limit: 120)
          : TracksRepository().search(_query, limit: 120);
      _albumsFuture = AlbumsRepository().latestPublished(limit: 12);
    });
    await _tracksFuture;
  }

  List<Track> _filterByGenre(List<Track> tracks) {
    if (_selectedGenreIndex <= 0) return tracks;
    final genre = _genres[_selectedGenreIndex].toLowerCase();
    return tracks.where((t) => 
        (t.genre?.toLowerCase().contains(genre) ?? false)
    ).toList();
  }

  Future<List<Track>> _fetchAlbumTracks(String albumId) async {
    final id = albumId.trim();
    if (id.isEmpty) return const <Track>[];

    final uri = Uri.parse('${ApiEnv.baseUrl}/api/albums/$id/tracks?limit=200');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 8),
      includeAuthIfAvailable: true,
      requireAuth: false,
    );

    if (res.statusCode != 200) {
      throw Exception('Album tracks request failed (HTTP ${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['ok'] != true) {
      throw Exception('Album tracks response was invalid.');
    }

    final raw = decoded['tracks'];
    if (raw is! List) {
      throw Exception('Album tracks payload is missing tracks list.');
    }

    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map(Track.fromSupabase)
        .toList(growable: false);
  }

  void _applyQuery(String value) {
    final trimmed = value.trim();
    if (trimmed == _query) return;
    setState(() {
      _query = trimmed;
      _tracksFuture = trimmed.isEmpty
          ? TracksRepository().latest(limit: 120)
          : TracksRepository().search(trimmed, limit: 120);
    });
  }

  void _playAll(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return;
    final playable = tracks.where((t) => t.audioUri != null).toList();
    if (playable.isEmpty) {
      _showErrorSnackBar(context, 'No playable tracks');
      return;
    }
    final controller = PlaybackController.instance;
    controller.play(playable.first, queue: playable.skip(1).toList());
    openPlayer(context);
  }

  void _shuffle(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return;
    final playable = tracks.where((t) => t.audioUri != null).toList();
    if (playable.isEmpty) {
      _showErrorSnackBar(context, 'No playable tracks');
      return;
    }
    final shuffled = List<Track>.from(playable);
    shuffled.shuffle(Random());
    final controller = PlaybackController.instance;
    controller.play(shuffled.first, queue: shuffled.skip(1).toList());
    openPlayer(context);
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: _gold,
        backgroundColor: const Color(0xFF1A1A28),
        child: CustomScrollView(
          slivers: [
            // Header with gradient
            SliverAppBar(
              expandedHeight: 100,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_gold, _goldLight],
                  ).createShader(bounds),
                  child: const Text(
                    'MUSIC',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _gold.withAlpha(26),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Search Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: GlassContainer(
                  width: double.infinity,
                  height: 50,
                  borderRadius: BorderRadius.circular(25),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1A1A28).withAlpha(128),
                      const Color(0xFF12121C).withAlpha(77),
                    ],
                  ),
                  borderColor: _gold.withAlpha(77),
                  blur: 10,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _applyQuery,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, albums...',
                      hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
                      prefixIcon: const Icon(Icons.search, color: _gold),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: _gold),
                              onPressed: () {
                                _searchController.clear();
                                _applyQuery('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ),

            // Genre Chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _genres.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedGenreIndex;
                    return FilterChip(
                      label: Text(_genres[index]),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedGenreIndex = selected ? index : -1;
                        });
                      },
                      backgroundColor: Colors.transparent,
                      selectedColor: _gold.withAlpha(51),
                      checkmarkColor: _gold,
                      side: BorderSide(
                        color: isSelected ? _gold : _gold.withAlpha(77),
                        width: isSelected ? 1.5 : 1,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? _gold : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Main Content
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Albums Section
                  if (_showAlbums) ...[
                    SectionHeader(
                      title: 'ALBUMS',
                      subtitle: 'Latest releases',
                      trailing: TextButton(
                        onPressed: () {
                          // Navigate to all albums
                        },
                        child: const Text('VIEW ALL'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildAlbumsSection(),
                    const SizedBox(height: 24),
                  ],

                  // Songs Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TRACKS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _gold,
                          letterSpacing: 1,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _playAll(context, _filterByGenre(_latestTracks)),
                            icon: const Icon(Icons.play_arrow, color: _gold),
                            label: const Text('PLAY', style: TextStyle(color: _gold)),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _shuffle(context, _filterByGenre(_latestTracks)),
                            icon: const Icon(Icons.shuffle, color: _gold),
                            label: const Text('SHUFFLE', style: TextStyle(color: _gold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tracks List
                  _buildTracksSection(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsSection() {
    return FutureBuilder<List<Album>>(
      future: _albumsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return Shimmer.fromColors(
                  baseColor: Colors.white.withAlpha(26),
                  highlightColor: Colors.white.withAlpha(51),
                  child: Container(
                    width: 140,
                    height: 190,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              },
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: _gold, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Failed to load albums',
                  style: TextStyle(color: Colors.white.withAlpha(179)),
                ),
                const SizedBox(height: 8),
                GoldButton(
                  onPressed: _refresh,
                  label: 'RETRY',
                  icon: Icons.refresh,
                ),
              ],
            ),
          );
        }

        final albums = snapshot.data ?? const <Album>[];
        if (albums.isEmpty) {
          return Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'No albums available',
                style: TextStyle(color: Colors.white.withAlpha(77)),
              ),
            ),
          );
        }

        return SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final a = albums[index];
              return _buildAlbumCard(a);
            },
          ),
        );
      },
    );
  }

  Widget _buildAlbumCard(Album album) {
    return GestureDetector(
      onTap: () => _openAlbum(album),
      child: GlassContainer(
        width: 140,
        height: 190,
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A28).withAlpha(128),
            const Color(0xFF12121C).withAlpha(77),
          ],
        ),
        borderColor: _gold.withAlpha(51),
        blur: 10,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Art
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: album.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: album.coverUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: Colors.white.withAlpha(26),
                        ),
                      )
                    : Container(
                        color: _gold.withAlpha(26),
                        child: const Icon(Icons.album, color: _gold),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artist ?? 'Various Artists',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withAlpha(128),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracksSection() {
    return FutureBuilder<List<Track>>(
      future: _tracksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: List.generate(8, (index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Shimmer.fromColors(
                baseColor: Colors.white.withAlpha(26),
                highlightColor: Colors.white.withAlpha(51),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            )),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: _gold, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load tracks',
                    style: TextStyle(color: Colors.white.withAlpha(179)),
                  ),
                ],
              ),
            ),
          );
        }

        final allTracks = snapshot.data ?? const <Track>[];
        _latestTracks = allTracks;
        final tracks = _filterByGenre(allTracks);

        if (tracks.isEmpty) {
          return Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_off, color: _gold, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _query.isEmpty
                        ? 'No tracks in this genre'
                        : 'No results for "$_query"',
                    style: TextStyle(color: Colors.white.withAlpha(128)),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: List.generate(tracks.length, (index) {
            final track = tracks[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PremiumTrackRow(
                track: track,
                onTap: () => _playFromIndex(context, tracks, index),
                isPlaying: PlaybackController.instance.current?.id == track.id,
              ),
            );
          }),
        );
      },
    );
  }

  void _openAlbum(Album album) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Loading album...'),
        backgroundColor: _gold,
      ),
    );

    List<Track> albumTracks;
    try {
      albumTracks = await _fetchAlbumTracks(album.id);
    } catch (e, st) {
      UserFacingError.log('MusicTab._openAlbum', e, st);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              e,
              fallback: 'Could not load album tracks. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final playable = albumTracks
        .where((t) => t.audioUri != null)
        .toList(growable: false);
    
    if (playable.isEmpty) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This album has no playable tracks yet.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    messenger.removeCurrentSnackBar();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PremiumAlbumDetailScreen(
          album: album,
          tracks: playable,
        ),
      ),
    );
  }

  void _playFromIndex(BuildContext context, List<Track> tracks, int index) {
    if (index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    if (track.audioUri == null) {
      _showErrorSnackBar(context, 'This track has no audio URL yet.');
      return;
    }

    final playback = PlaybackController.instance;
    final queue = List<Track>.from(tracks)..removeAt(index);
    playback.play(track, queue: queue);
    openPlayer(context);
  }
}

// Premium Track Row with Now Playing Indicator
class _PremiumTrackRow extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final bool isPlaying;

  const _PremiumTrackRow({
    required this.track,
    required this.onTap,
    this.isPlaying = false,
  });

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final durationText = _formatDuration(track.duration);
    final artworkUrl = track.artworkUri?.toString().trim() ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPlaying
              ? [
                  _gold.withAlpha(51),
                  const Color(0xFF1A1A28),
                ]
              : [
                  const Color(0xFF1A1A28).withAlpha(128),
                  const Color(0xFF12121C),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPlaying ? _gold : _gold.withAlpha(51),
          width: isPlaying ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Artwork
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 50,
                    height: 50,
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
                              color: Colors.white.withAlpha(26),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Track Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isPlaying)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _gold,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              track.title.trim().isEmpty ? 'Untitled' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: isPlaying ? _gold : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist.trim().isEmpty ? 'Unknown artist' : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isPlaying 
                              ? _gold.withAlpha(204)
                              : Colors.white.withAlpha(128),
                        ),
                      ),
                    ],
                  ),
                ),

                // Duration & Play Icon
                Row(
                  children: [
                    if (durationText.isNotEmpty)
                      Text(
                        durationText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withAlpha(77),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Icon(
                      isPlaying ? Icons.equalizer : Icons.play_arrow,
                      color: isPlaying ? _gold : Colors.white.withAlpha(77),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration? d) {
  if (d == null) return '';
  final totalSeconds = d.inSeconds;
  if (totalSeconds <= 0) return '';
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

// Premium Album Detail Screen
class _PremiumAlbumDetailScreen extends StatelessWidget {
  final Album album;
  final List<Track> tracks;

  const _PremiumAlbumDetailScreen({
    required this.album,
    required this.tracks,
  });

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // Album Header with Art
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Album Art
                  if (album.coverUrl != null)
                    CachedNetworkImage(
                      imageUrl: album.coverUrl!,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(
                      color: _gold.withAlpha(26),
                      child: const Icon(Icons.album, color: _gold, size: 80),
                    ),
                  
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withAlpha(204),
                        ],
                      ),
                    ),
                  ),

                  // Title Overlay
                  Positioned(
                    bottom: 20,
                    left: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album.artist ?? 'Various Artists',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${tracks.length} tracks',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.play_arrow,
                      label: 'PLAY ALL',
                      onTap: () => _playAll(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.shuffle,
                      label: 'SHUFFLE',
                      onTap: () => _shuffle(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tracks List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = tracks[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PremiumTrackRow(
                      track: track,
                      onTap: () => _playFromIndex(context, index),
                      isPlaying: PlaybackController.instance.current?.id == track.id,
                    ),
                  );
                },
                childCount: tracks.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _gold.withAlpha(51),
              _gold.withAlpha(13),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _gold.withAlpha(77),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _gold, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playAll(BuildContext context) {
    if (tracks.isEmpty) return;
    final controller = PlaybackController.instance;
    controller.play(tracks.first, queue: tracks.skip(1).toList());
    openPlayer(context);
  }

  void _shuffle(BuildContext context) {
    if (tracks.isEmpty) return;
    final shuffled = List<Track>.from(tracks);
    shuffled.shuffle(Random());
    final controller = PlaybackController.instance;
    controller.play(shuffled.first, queue: shuffled.skip(1).toList());
    openPlayer(context);
  }

  void _playFromIndex(BuildContext context, int index) {
    if (index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    if (track.audioUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This track has no audio URL yet.')),
      );
      return;
    }

    final playback = PlaybackController.instance;
    final queue = List<Track>.from(tracks)..removeAt(index);
    playback.play(track, queue: queue);
    openPlayer(context);
  }
}