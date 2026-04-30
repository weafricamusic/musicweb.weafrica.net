import 'package:flutter/material.dart' hide FilterChip;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/weafrica_colors.dart';
import '../../home/providers/filter_provider.dart';
import '../../home/widgets/country_selection_modal.dart';
import '../../home/widgets/filter_chip.dart' as custom;
import '../player/player_routes.dart';
import '../player/playback_controller.dart';
import '../live/screens/live_watch_screen.dart';
import '../videos/video.dart';
import '../videos/screens/video_playback_screen.dart';

/// Enhanced home screen with 8-card filtering system
/// - Card 1 (Countries): Opens country selection modal
/// - Cards 2-8 (Genres): Direct filter by genre (Amapiano, Afrobeat, Love, Gospel, New, Trending, RNB)
class WeAfricaHomeV5 extends StatefulWidget {
  const WeAfricaHomeV5({super.key});

  @override
  State<WeAfricaHomeV5> createState() => _WeAfricaHomeV5State();
}

class _WeAfricaHomeV5State extends State<WeAfricaHomeV5> {
  List<Map<String, dynamic>> _recentlyPlayed = [];
  List<Map<String, dynamic>> _recommendedForYou = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _top10 = [];
  List<Map<String, dynamic>> _liveStreams = [];
  List<Map<String, dynamic>> _videosList = [];
  bool _loading = true;

  // 8 cards configuration
  static const List<String> cardLabels = [
    'Countries', // Card 1 - Opens modal
    'Amapiano',  // Card 2-8 - Genre filters
    'Afrobeat',
    'Love',
    'Gospel',
    'New',
    'Trending',
    'RNB',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      
      // Fetch recently played songs
      List<String> recentlyPlayedIds = prefs.getStringList('recently_played') ?? [];
      
      if (recentlyPlayedIds.isNotEmpty) {
        final recent = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url, genre, country')
            .inFilter('id', recentlyPlayedIds.take(8).toList());
        _recentlyPlayed = List<Map<String, dynamic>>.from(recent);
      } else {
        final defaultSongs = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url, genre, country')
            .order('plays_count', ascending: false)
            .limit(8);
        _recentlyPlayed = List<Map<String, dynamic>>.from(defaultSongs);
      }
      
      // Fetch recommended songs
      final rec = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, genre, country')
          .order('plays_count', ascending: false)
          .limit(10);
      _recommendedForYou = List<Map<String, dynamic>>.from(rec);
      
      // Fetch featured songs
      final featured = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, genre, country')
          .order('plays_count', ascending: false)
          .limit(5);
      _featured = List<Map<String, dynamic>>.from(featured);
      
      // Fetch top 10 songs
      final top = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, plays_count, genre, country')
          .order('plays_count', ascending: false)
          .limit(10);
      _top10 = List<Map<String, dynamic>>.from(top);
      
      // Fetch live streams
      final live = await supabase
          .from('live_sessions')
          .select('channel_id, host_name, viewer_count')
          .eq('is_live', true)
          .limit(3);
      _liveStreams = List<Map<String, dynamic>>.from(live);
      
      // Fetch videos
      final videos = await supabase
          .from('videos')
          .select('id, title, artist, thumbnail_url, views_count, video_url')
          .order('views_count', ascending: false)
          .limit(10);
      _videosList = List<Map<String, dynamic>>.from(videos);
      
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Load filtered data based on current filter state
  Future<void> _loadFilteredData(String? country, String? genre) async {
    setState(() => _loading = true);
    
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      
      // Build filter query based on country/genre
      List<Map<String, dynamic>> filteredSongs;
      List<Map<String, dynamic>> recommendedSongs;
      
      if (country != null && country.isNotEmpty) {
        // Filter by country
        final result = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url, genre, country')
            .eq('country', country)
            .limit(50);
        filteredSongs = List<Map<String, dynamic>>.from(result);
        recommendedSongs = filteredSongs;
      } else if (genre != null && genre.isNotEmpty) {
        // Filter by genre
        if (genre == 'New') {
          final result = await supabase
              .from('songs')
              .select('id, title, artist, thumbnail_url, audio_url, genre, country')
              .order('created_at', ascending: false)
              .limit(50);
          filteredSongs = List<Map<String, dynamic>>.from(result);
          recommendedSongs = filteredSongs;
        } else if (genre == 'Trending') {
          final result = await supabase
              .from('songs')
              .select('id, title, artist, thumbnail_url, audio_url, genre, country')
              .order('plays_count', ascending: false)
              .limit(50);
          filteredSongs = List<Map<String, dynamic>>.from(result);
          recommendedSongs = filteredSongs;
        } else {
          final result = await supabase
              .from('songs')
              .select('id, title, artist, thumbnail_url, audio_url, genre, country')
              .ilike('genre', '%$genre%')
              .limit(50);
          filteredSongs = List<Map<String, dynamic>>.from(result);
          recommendedSongs = filteredSongs;
        }
      } else {
        // No filter - get all songs
        final result = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url, genre, country')
            .order('plays_count', ascending: false)
            .limit(50);
        filteredSongs = List<Map<String, dynamic>>.from(result);
        recommendedSongs = filteredSongs;
      }
      
      // Fetch recently played songs (filtered)
      List<String> recentlyPlayedIds = prefs.getStringList('recently_played') ?? [];
      
      if (recentlyPlayedIds.isNotEmpty) {
        // Filter recently played by current filter
        final filteredIds = filteredSongs.map((s) => s['id'].toString()).toSet();
        final recentIds = recentlyPlayedIds.where((id) => filteredIds.contains(id)).take(8).toList();
        
        if (recentIds.isNotEmpty) {
          final recent = await supabase
              .from('songs')
              .select('id, title, artist, thumbnail_url, audio_url, genre, country')
              .inFilter('id', recentIds);
          _recentlyPlayed = List<Map<String, dynamic>>.from(recent);
        } else {
          _recentlyPlayed = filteredSongs.take(4).toList();
        }
      } else {
        _recentlyPlayed = filteredSongs.take(4).toList();
      }
      
      // Set recommended songs
      _recommendedForYou = recommendedSongs.take(10).toList();
      
      // Set featured songs
      _featured = filteredSongs.take(5).toList();
      
      // Set top 10 songs
      _top10 = filteredSongs
          .toList()
          ..sort((a, b) => (b['plays_count'] as int? ?? 0).compareTo(a['plays_count'] as int? ?? 0));
      _top10 = _top10.take(10).toList();
      
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading filtered data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Handle card tap - Card 1 opens modal, Cards 2-8 apply genre filter
  void _onCardTap(String cardLabel, FilterProvider filterProvider) {
    if (cardLabel == 'Countries') {
      // Open country selection modal
      _showCountryModal(filterProvider);
    } else {
      // Apply genre filter (toggle behavior)
      filterProvider.setGenreFilter(cardLabel);
      _loadFilteredData(null, cardLabel == filterProvider.selectedGenre ? null : cardLabel);
    }
  }

  /// Show country selection modal
  Future<void> _showCountryModal(FilterProvider filterProvider) async {
    final selectedCountry = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return CountrySelectionModal(
              selectedCountry: filterProvider.selectedCountry,
              onCountrySelected: (country) {
                Navigator.pop(context, country);
              },
            );
          },
        );
      },
    );

    if (selectedCountry != null) {
      filterProvider.setCountryFilter(selectedCountry);
      _loadFilteredData(selectedCountry, null);
    }
  }

  Future<void> _playSong(Map<String, dynamic> song) async {
    try {
      final track = Track(
        id: song['id'].toString(),
        title: song['title'] ?? 'Unknown Title',
        artist: song['artist'] ?? 'Unknown Artist',
        audioUri: Uri.tryParse(song['audio_url'] ?? ''),
        artworkUri: song['thumbnail_url'] != null ? Uri.tryParse(song['thumbnail_url']) : null,
      );

      final prefs = await SharedPreferences.getInstance();
      List<String> recent = prefs.getStringList('recently_played') ?? [];
      recent.remove(song['id'].toString());
      recent.insert(0, song['id'].toString());
      if (recent.length > 8) recent = recent.take(8).toList();
      await prefs.setStringList('recently_played', recent);

      if (mounted) {
        PlaybackController.instance.play(track);
        openPlayer(context);
      }
    } catch (e) {
      debugPrint('Error playing song: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to play song")));
    }
  }

  void _joinLiveStream(Map<String, dynamic> live) async {
    try {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LiveWatchScreen(
              channelId: live["channel_id"]?.toString() ?? '',
              hostName: live["host_name"]?.toString() ?? 'Live Stream',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error joining live stream: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to join live stream")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FilterProvider(),
      child: Consumer<FilterProvider>(
        builder: (context, filterProvider, child) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B0617),
            body: SafeArea(
              child: Stack(
                children: [
                  _loading
                      ? const Center(child: CircularProgressIndicator(color: WeAfricaColors.gold))
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(filterProvider),
                              const SizedBox(height: 16),
                              _buildCategoryCards(filterProvider),
                              // Show filter indicator if filter is active
                              if (filterProvider.hasActiveFilter)
                                custom.FilterChip(
                                  label: filterProvider.activeFilterLabel!,
                                  iconData: filterProvider.selectedCountry != null ? '🌍' : '🎵',
                                  onClear: () {
                                    filterProvider.clearFilters();
                                    _loadFilteredData(null, null);
                                  },
                                ),
                              const SizedBox(height: 16),
                              _buildRecentlyPlayed(),
                              const SizedBox(height: 24),
                              _buildRecommendedForYou(),
                              const SizedBox(height: 24),
                              _buildFeatured(),
                              const SizedBox(height: 24),
                              _buildLiveSection(),
                              const SizedBox(height: 24),
                              _buildHotVideos(),
                              const SizedBox(height: 24),
                              _buildTop10(),
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(FilterProvider filterProvider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WEAFRICA MUSIC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Discover African Music',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Filter status indicator
          if (filterProvider.hasActiveFilter)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: WeAfricaColors.gold.withValues(alpha: ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WeAfricaColors.gold.withValues(alpha: )),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    filterProvider.selectedCountry != null ? '🌍' : '🎵',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    filterProvider.activeFilterLabel!,
                    style: const TextStyle(
                      color: WeAfricaColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryCards(FilterProvider filterProvider) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cardLabels.length,
        itemBuilder: (context, index) {
          final label = cardLabels[index];
          final isCountries = label == 'Countries';
          final isActive = isCountries
              ? filterProvider.selectedCountry != null
              : filterProvider.isGenreActive(label);

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _onCardTap(label, filterProvider),
              child: Container(
                width: 100,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(colors: [WeAfricaColors.gold, Colors.orange])
                      : const LinearGradient(colors: [Colors.deepPurple, Colors.deepPurpleAccent]),
                  borderRadius: BorderRadius.circular(16),
                  border: isActive
                      ? Border.all(color: WeAfricaColors.gold, width: 2)
                      : null,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: WeAfricaColors.gold.withValues(alpha: ),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCountries)
                        const Text('🌍', style: TextStyle(fontSize: 20))
                      else
                        const Text('🎵', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentlyPlayed() {
    if (_recentlyPlayed.isEmpty) return const SizedBox.shrink();
    final items = _recentlyPlayed.take(4).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('🎧 Recently Played', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.2,
            children: items.map((song) {
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                        child: Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey[800],
                          child: song['thumbnail_url'] != null
                              ? Image.network(song['thumbnail_url'], fit: BoxFit.cover)
                              : Image.asset('assets/default_album_art.png', fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(song['title'] ?? 'Untitled', 
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                              maxLines: 1),
                            Text(song['artist'] ?? 'Artist', 
                              style: const TextStyle(color: Colors.white54, fontSize: 9), maxLines: 1),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.play_arrow, size: 14, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedForYou() {
    if (_recommendedForYou.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('✨ Recommended For You', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recommendedForYou.length,
            itemBuilder: (context, index) {
              final song = _recommendedForYou[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      Container(
                        height: 70,
                        width: 70,
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                              : DecorationImage(image: AssetImage('assets/default_album_art.png'), fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(song['title'] ?? 'Untitled', style: const TextStyle(color: Colors.white, fontSize: 10), maxLines: 1),
                      Text(song['artist'] ?? 'Artist', style: const TextStyle(color: Colors.white54, fontSize: 8), maxLines: 1),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFeatured() {
    if (_featured.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('⭐ WeAfrica Picks', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _featured.length,
            itemBuilder: (context, index) {
              final song = _featured[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.withValues(alpha: ), Colors.grey[850]!],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: )),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: ),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                              : DecorationImage(image: AssetImage('assets/default_album_art.png'), fit: BoxFit.cover),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('PICK', style: TextStyle(color: Colors.orange, fontSize: 7, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(song['title'] ?? 'Featured', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1),
                              Text(song['artist'] ?? 'Artist', style: const TextStyle(color: Colors.white54, fontSize: 8), maxLines: 1),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                                child: const Text('PLAY', style: TextStyle(color: Colors.black, fontSize: 6, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
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
    );
  }

  Widget _buildLiveSection() {
    if (_liveStreams.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("🔴 Live Now", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Colors.red, Colors.orange]),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_liveStreams[0]['host_name'] ?? 'Live Stream', 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('${_liveStreams[0]['viewer_count'] ?? 0} watching', 
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                ),
                onPressed: () => _joinLiveStream(_liveStreams[0]),
                child: const Text("Join", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHotVideos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("🔥 Hot Videos", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 160,
          child: _videosList.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_library, color: Colors.orange, size: 50),
                      SizedBox(height: 10),
                      Text("No videos available", style: TextStyle(color: Colors.white54)),
                      Text("Check back later!", style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _videosList.length,
                  itemBuilder: (context, index) {
                    final video = _videosList[index];
                    return GestureDetector(
                      onTap: () {
                        final v = Video.fromSupabase(video);
                        if (v.videoUri == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("This video has no playable URL yet.")),
                          );
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => VideoPlaybackScreen(video: v)),
                        );
                      },
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(left: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: video['thumbnail_url'] != null
                              ? DecorationImage(image: NetworkImage(video['thumbnail_url']), fit: BoxFit.cover)
                              : DecorationImage(image: AssetImage('assets/default_video_thumbnail.png'), fit: BoxFit.cover),
                          color: Colors.grey[900],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black87],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(video['title'] ?? 'Video', 
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    maxLines: 1),
                                  Text(video['artist'] ?? 'Artist', 
                                    style: const TextStyle(color: Colors.white70, fontSize: 8), maxLines: 1),
                                ],
                              ),
                            ),
                            const Center(
                              child: Icon(Icons.play_circle_filled, color: Colors.orange, size: 30),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTop10() {
    if (_top10.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("🏆 Top 10", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _top10.length,
            itemBuilder: (context, index) {
              final song = _top10[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 90,
                            width: 110,
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(12),
                              image: song['thumbnail_url'] != null
                                  ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                                  : DecorationImage(image: AssetImage('assets/default_album_art.png'), fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: Center(
                                child: Text('${index + 1}', 
                                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(song['title'] ?? 'Untitled', 
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1),
                      Text(song['artist'] ?? 'Artist', 
                        style: const TextStyle(color: Colors.white54, fontSize: 9), maxLines: 1),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
