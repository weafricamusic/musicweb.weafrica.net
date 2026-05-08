import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/weafrica_colors.dart';
import '../player/player_routes.dart';
import '../player/playback_controller.dart';
import '../live/presentation/screens/consumer_live_screen.dart';
import '../videos/video.dart';
import '../videos/screens/video_playback_screen.dart';
import '../categories/screens/category_songs_screen.dart';
import '../categories/screens/new_songs_screen.dart';
import '../categories/screens/trending_songs_screen.dart';

class WeAfricaHomeV4 extends StatefulWidget {
  const WeAfricaHomeV4({super.key});

  @override
  State<WeAfricaHomeV4> createState() => _WeAfricaHomeV4State();
}

class _WeAfricaHomeV4State extends State<WeAfricaHomeV4>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _recentlyPlayed = [];
  List<Map<String, dynamic>> _recommendedForYou = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _top10 = [];
  List<Map<String, dynamic>> _liveStreams = [];
  List<Map<String, dynamic>> _videosList = [];
  bool _loading = true;
  bool _showRetryButton = false;
  int _selectedCategory = 0;
  Timer? _retryTimer;

  final List<Map<String, dynamic>> _categories = [
    {"name": "Malawi", "icon": Icons.public, "type": "countries"},
    {"name": "Hip-Hop", "icon": Icons.mic, "type": "genre"},
    {"name": "Amapiano", "icon": Icons.music_note, "type": "genre"},
    {"name": "Afrobeat", "icon": Icons.music_note, "type": "genre"},
    {"name": "Gospel", "icon": Icons.church, "type": "genre"},
    {"name": "Love", "icon": Icons.favorite, "type": "genre"},
    {"name": "New", "icon": Icons.fiber_new, "type": "new"},
    {"name": "Trending", "icon": Icons.trending_up, "type": "trending"},
  ];

  late AnimationController _animationController;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadData();
    
    // Show retry button after 10 seconds if still loading
    _retryTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _loading) {
        setState(() => _showRetryButton = true);
      }
    });
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();

      // Set a timeout for the entire data loading operation
      final loadDataFuture = _performDataLoad(supabase, prefs);
      final timeout = const Duration(seconds: 15);
      
      await loadDataFuture.timeout(timeout, onTimeout: () {
        debugPrint('Data loading timed out after ${timeout.inSeconds} seconds');
        // Set minimal data to unblock the UI
        _top10 = [];
        _recentlyPlayed = [];
        _recommendedForYou = [];
        _featured = [];
        _liveStreams = [];
        _videosList = [];
      });

      if (!mounted) return;
      setState(() => _loading = false);
      _animationController.forward();
    } catch (e) {
      debugPrint('Error loading data: $e');
      // Ensure loading is set to false even on error
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Initialize with empty lists to prevent null errors
        _top10 = _top10.isEmpty ? [] : _top10;
        _recentlyPlayed = _recentlyPlayed.isEmpty ? [] : _recentlyPlayed;
        _recommendedForYou = _recommendedForYou.isEmpty ? [] : _recommendedForYou;
        _featured = _featured.isEmpty ? [] : _featured;
        _liveStreams = _liveStreams.isEmpty ? [] : _liveStreams;
        _videosList = _videosList.isEmpty ? [] : _videosList;
      });
    }
  }

  Future<void> _performDataLoad(SupabaseClient supabase, SharedPreferences prefs) async {
    // Fetch recently played songs
    List<String> recentlyPlayedIds = prefs.getStringList('recently_played') ?? [];

    if (recentlyPlayedIds.isNotEmpty) {
      try {
        final recent = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url')
            .inFilter('id', recentlyPlayedIds.take(8).toList());
        _recentlyPlayed = List<Map<String, dynamic>>.from(recent);
      } catch (e) {
        debugPrint('Error fetching recently played: $e');
        _recentlyPlayed = [];
      }
    } else {
      try {
        final defaultSongs = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url')
            .order('plays_count', ascending: false)
            .limit(8);
        _recentlyPlayed = List<Map<String, dynamic>>.from(defaultSongs);
      } catch (e) {
        debugPrint('Error fetching default songs: $e');
        _recentlyPlayed = [];
      }
    }

    // Fetch recommended songs
    try {
      final rec = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url')
          .order('plays_count', ascending: false)
          .limit(10);
      _recommendedForYou = List<Map<String, dynamic>>.from(rec);
    } catch (e) {
      debugPrint('Error fetching recommended: $e');
      _recommendedForYou = [];
    }

    // Fetch featured songs
    try {
      final featured = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url')
          .order('plays_count', ascending: false)
          .limit(5);
      _featured = List<Map<String, dynamic>>.from(featured);
    } catch (e) {
      debugPrint('Error fetching featured: $e');
      _featured = [];
    }

    // Fetch top 10 songs
    try {
      final top = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, plays_count')
          .order('plays_count', ascending: false)
          .limit(10);
      _top10 = List<Map<String, dynamic>>.from(top);
    } catch (e) {
      debugPrint('Error fetching top 10: $e');
      _top10 = [];
    }

    // Fetch live streams - with extra caution as this might be the problematic query
    try {
      final live = await supabase
          .from('live_sessions')
          .select('id, channel_id, host_name, viewer_count, created_at')
          .eq('is_live', true)
          .order('created_at', ascending: false)
          .limit(3);
      _liveStreams = List<Map<String, dynamic>>.from(live);
    } catch (e) {
      debugPrint('Error fetching live streams: $e');
      _liveStreams = [];
    }

    // Fetch videos
    try {
      final videos = await supabase
          .from('videos')
          .select('id, title, artist, thumbnail_url, views_count, video_url')
          .order('views_count', ascending: false)
          .limit(10);
      _videosList = List<Map<String, dynamic>>.from(videos);
    } catch (e) {
      debugPrint('Error fetching videos: $e');
      _videosList = [];
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await _loadData();
  }

  void _onCategoryTap(int index) {
    if (!mounted) return;
    setState(() => _selectedCategory = index);
    HapticFeedback.selectionClick();
    
    final category = _categories[index];
    final String name = category['name'];
    final String type = category['type'];
    
    _navigateToCategoryScreen(name, type);
  }
  
  void _navigateToCategoryScreen(String name, String type) {
    switch (type) {
      case 'countries':
        // Navigate to African Countries Screen with Malawi as default
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategorySongsScreen(
              title: 'African Music',
              category: name,
              filterType: 'country',
            ),
          ),
        );
        break;
      case 'genre':
        // Navigate to Category Songs Screen for genres
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategorySongsScreen(
              title: name,
              category: name,
              filterType: 'genre',
            ),
          ),
        );
        break;
      case 'new':
        // Navigate to New Songs Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const NewSongsScreen(),
          ),
        );
        break;
      case 'trending':
        // Navigate to Trending Songs Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TrendingSongsScreen(),
          ),
        );
        break;
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to play song")),
      );
    }
  }

  void _joinLiveStream(Map<String, dynamic> live) async {
    try {
      if (mounted) {
        final user = Supabase.instance.client.auth.currentUser;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConsumerLiveScreen(
              liveSessionId: live["id"]?.toString() ?? '',
              channelName: live["channel_id"]?.toString() ?? '',
              userId: user?.id ?? '',
              userName: user?.userMetadata?['display_name']?.toString() ?? 'User',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error joining live stream: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to join live stream")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: WeAfricaColors.gold),
              const SizedBox(height: 24),
              const Text(
                'Loading WeAfrica Music...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This should only take a moment',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
              if (_showRetryButton) ...[
                const SizedBox(height: 32),
                Text(
                  'Taking longer than expected?',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _refreshData(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WeAfricaColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0617),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: WeAfricaColors.gold,
        backgroundColor: const Color(0xFF1B1530),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App Bar
            // Hero Section
            SliverToBoxAdapter(
              child: _buildHeroSection(),
            ),

            // Category Chips
            SliverToBoxAdapter(
              child: _buildCategoryChips(),
            ),

            // Live Now Banner
            if (_liveStreams.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildLiveBanner(),
              ),

            // Recently Played
            if (_recentlyPlayed.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildRecentlyPlayed(),
              ),

            // Featured Section
            if (_featured.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildFeaturedSection(),
              ),

            // Recommended For You
            if (_recommendedForYou.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildRecommendedSection(),
              ),

            // Hot Videos
            SliverToBoxAdapter(
              child: _buildHotVideos(),
            ),

            // Top 10
            if (_top10.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildTop10Section(),
              ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final topSong = _top10.isNotEmpty ? _top10[0] : null;
    if (topSong == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - _animationController.value)),
          child: Opacity(
            opacity: _animationController.value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF6A5CFF), Color(0xFFF28C1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A5CFF).withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
            Positioned(
              left: -20,
              bottom: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Trending',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          topSong['title'] ?? 'Nobody Cares',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topSong['artist'] ?? 'Driemo',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.2),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _playSong(topSong),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: const Color(0xFF6A5CFF),
                      backgroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 24),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      height: 64,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == index;

          return GestureDetector(
            onTap: () => _onCategoryTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFFF28C1E), Color(0xFFD04984)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF1B1530),
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    category['icon'] as IconData,
                    color: isSelected ? Colors.white : Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category['name'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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

  Widget _buildLiveBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFE53935), Color(0xFFFF7043)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.videocam,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE NOW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _liveStreams[0]['host_name'] ?? 'Live Stream',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_liveStreams[0]['viewer_count'] ?? 0} watching',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _joinLiveStream(_liveStreams[0]),
            style: ElevatedButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
              backgroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Join',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? subtitle, VoidCallback? onSeeAll) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: WeAfricaColors.gold,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See All',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 12),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayed() {
    final items = _recentlyPlayed.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Recently Played', 'Pick up where you left off', null),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final song = items[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF1B1530),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(song['thumbnail_url']),
                                  fit: BoxFit.cover,
                                )
                              : const DecorationImage(
                                  image: AssetImage('assets/default_album_art.png'),
                                  fit: BoxFit.cover,
                                ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: WeAfricaColors.gold,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: WeAfricaColors.gold.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        song['title'] ?? 'Untitled',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song['artist'] ?? 'Artist',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildFeaturedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('WeAfrica Picks', 'Handpicked just for you', null),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _featured.length,
            itemBuilder: (context, index) {
              final song = _featured[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 180,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B1530), Color(0xFF2D2545)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: WeAfricaColors.gold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 120,
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(song['thumbnail_url']),
                                  fit: BoxFit.cover,
                                )
                              : const DecorationImage(
                                  image: AssetImage('assets/default_album_art.png'),
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: WeAfricaColors.gold.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PICK',
                                style: TextStyle(
                                  color: WeAfricaColors.gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              song['title'] ?? 'Featured',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              song['artist'] ?? 'Artist',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                            ),
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
    );
  }

  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Recommended For You', 'Based on your listening', null),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _recommendedForYou.length,
            itemBuilder: (context, index) {
              final song = _recommendedForYou[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(song['thumbnail_url']),
                                  fit: BoxFit.cover,
                                )
                              : const DecorationImage(
                                  image: AssetImage('assets/default_album_art.png'),
                                  fit: BoxFit.cover,
                                ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        song['title'] ?? 'Untitled',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song['artist'] ?? 'Artist',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 12,
                        ),
                        maxLines: 1,
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

  Widget _buildHotVideos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Hot Videos', 'Trending music videos', null),
        SizedBox(
          height: 200,
          child: _videosList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.video_library_outlined,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No videos available',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _videosList.length,
                  itemBuilder: (context, index) {
                    final video = _videosList[index];
                    return GestureDetector(
                      onTap: () {
                        final v = Video.fromSupabase(video);
                        if (v.videoUri == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('This video has no playable URL yet.'),
                            ),
                          );
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => VideoPlaybackScreen(video: v),
                          ),
                        );
                      },
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          image: video['thumbnail_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(video['thumbnail_url']),
                                  fit: BoxFit.cover,
                                )
                              : const DecorationImage(
                                  image: AssetImage('assets/default_video_thumbnail.png'),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.3),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              left: 12,
                              right: 12,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    video['title'] ?? 'Video',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    video['artist'] ?? 'Artist',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 48,
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

  Widget _buildTop10Section() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Top 10', 'Most played this week', null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: _top10.take(5).map((song) {
              final index = _top10.indexOf(song);
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1530),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: index < 3 ? WeAfricaColors.gold : const Color(0xFF2D2545),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: index < 3 ? Colors.black : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 50,
                          height: 50,
                          color: const Color(0xFF2D2545),
                          child: song['thumbnail_url'] != null
                              ? Image.network(
                                  song['thumbnail_url'],
                                  fit: BoxFit.cover,
                                )
                              : Image.asset(
                                  'assets/default_album_art.png',
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song['title'] ?? 'Untitled',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song['artist'] ?? 'Artist',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.2),
                                fontSize: 13,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
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
}
