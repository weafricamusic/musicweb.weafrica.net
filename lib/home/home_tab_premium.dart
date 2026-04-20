import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/theme/weafrica_colors.dart';
import '../features/player/player_routes.dart';
import '../features/player/playback_controller.dart';
import '../features/live/screens/live_watch_screen.dart';
import '../features/pulse/reels/feed_screen.dart';

class HomeTabPremium extends StatefulWidget {
  const HomeTabPremium({super.key});

  @override
  State<HomeTabPremium> createState() => _HomeTabPremiumState();
}

class _HomeTabPremiumState extends State<HomeTabPremium> {
  List<Map<String, dynamic>> _recentlyPlayed = [];
  List<Map<String, dynamic>> _recommendedForYou = [];
  List<Map<String, dynamic>> _trendingSongs = [];
  List<Map<String, dynamic>> _liveBattles = [];
  List<Map<String, dynamic>> _hotVideos = [];
  List<Map<String, dynamic>> _top10 = [];
  List<Map<String, dynamic>> _featured = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      
      // Load recently played from local storage
      List<String> recentlyPlayedIds = prefs.getStringList('recently_played') ?? [];
      
      if (recentlyPlayedIds.isNotEmpty) {
        final recent = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, plays_count, audio_url')
            .inFilter('id', recentlyPlayedIds.take(8).toList());
        _recentlyPlayed = List<Map<String, dynamic>>.from(recent);
      } else {
        final defaultSongs = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, plays_count, audio_url')
            .order('plays_count', ascending: false)
            .limit(8);
        _recentlyPlayed = List<Map<String, dynamic>>.from(defaultSongs);
      }
      
      // Load recommended for you
      if (recentlyPlayedIds.isNotEmpty) {
        final recentArtists = await supabase
            .from('songs')
            .select('artist')
            .inFilter('id', recentlyPlayedIds.take(5).toList());
        
        final artistNames = (recentArtists as List)
            .map((a) => a['artist'])
            .where((a) => a != null)
            .toList();
        
        if (artistNames.isNotEmpty) {
          final recommended = await supabase
              .from('songs')
              .select('id, title, artist, thumbnail_url, plays_count, audio_url')
              .inFilter('artist', artistNames)
              .limit(10);
          _recommendedForYou = List<Map<String, dynamic>>.from(recommended);
        }
      }
      
      if (_recommendedForYou.isEmpty) {
        final rec = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, plays_count, audio_url')
            .order('plays_count', ascending: false)
            .limit(10);
        _recommendedForYou = List<Map<String, dynamic>>.from(rec);
      }
      
      // Load trending songs
      final songs = await supabase
          .from('songs')
          .select('id, title, artist, plays_count, likes_count, thumbnail_url, audio_url')
          .order('plays_count', ascending: false)
          .limit(10);
      _trendingSongs = List<Map<String, dynamic>>.from(songs);
      
      // Load live battles
      final live = await supabase
          .from('live_sessions')
          .select('channel_id, host_name, title, viewer_count, host_id')
          .eq('is_live', true)
          .limit(5);
      _liveBattles = List<Map<String, dynamic>>.from(live);
      
      // Load hot videos
      final videos = await supabase
          .from('videos')
          .select('id, title, artist, views_count, thumbnail_url, video_url')
          .order('views_count', ascending: false)
          .limit(6);
      _hotVideos = List<Map<String, dynamic>>.from(videos);
      
      // Load top 10
      _top10 = List<Map<String, dynamic>>.from(_trendingSongs.take(10));
      
      // Load featured
      final featured = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, plays_count, audio_url')
          .eq('is_featured', true)
          .limit(5);
      _featured = List<Map<String, dynamic>>.from(featured);
      
      if (_featured.isEmpty) {
        _featured = List<Map<String, dynamic>>.from(_trendingSongs.take(5));
      }
      
      setState(() => _loading = false);
    } catch (e) {
      print('Error loading premium home data: $e');
      setState(() {
        _loading = false;
        _hotVideos = [];
      });
    }
  }

  Future<void> _playSong(Map<String, dynamic> song) async {
    final track = Track(
      id: song['id'].toString(),
      title: song['title'].toString(),
      artist: song['artist'].toString(),
      audioUrl: song['audio_url']?.toString() ?? '',
      artworkUrl: song['thumbnail_url']?.toString(),
    );
    
    // Save to recently played
    final prefs = await SharedPreferences.getInstance();
    List<String> recent = prefs.getStringList('recently_played') ?? [];
    recent.remove(song['id'].toString());
    recent.insert(0, song['id'].toString());
    if (recent.length > 8) recent = recent.take(8).toList();
    await prefs.setStringList('recently_played', recent);
    
    if (mounted) {
      await PlaybackController.instance.playTrack(track);
      openPlayer(context);
    }
  }

  void _joinLiveStream(Map<String, dynamic> live) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveWatchScreen(
          channelId: live['channel_id'].toString(),
          hostName: live['host_name'].toString(),
          title: live['title']?.toString() ?? 'Live Stream',
        ),
      ),
    );
  }

  void _watchVideo(Map<String, dynamic> video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReelFeedScreen(initialVideoId: video['id']?.toString()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: WeAfricaColors.stageBlack,
        body: Center(child: CircularProgressIndicator(color: WeAfricaColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      body: CustomScrollView(
        slivers: [
          // NO APP BAR - using existing top bar from app shell
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          
          // Hero Live Section (only if there are live battles)
          if (_liveBattles.isNotEmpty)
            SliverToBoxAdapter(child: _buildHeroSection()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          
          // Recently Played - SMALL SQUARE CARDS (Spotify style)
          if (_recentlyPlayed.isNotEmpty)
            SliverToBoxAdapter(child: _buildRecentlyPlayedSection()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
          // Recommended For You
          if (_recommendedForYou.isNotEmpty)
            SliverToBoxAdapter(child: _buildRecommendedSection()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
          // Live Battles
          if (_liveBattles.isNotEmpty)
            SliverToBoxAdapter(child: _buildLiveBattlesSection()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
          // Hot Videos
          if (_hotVideos.isNotEmpty)
            SliverToBoxAdapter(child: _buildHotVideosSection()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
          // Top 10
          if (_top10.isNotEmpty)
            SliverToBoxAdapter(child: _buildTop10Section()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          
          // Featured / WeAfrica Picks
          if (_featured.isNotEmpty)
            SliverToBoxAdapter(child: _buildFeaturedSection()),
          
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    final battle = _liveBattles.first;
    return GestureDetector(
      onTap: () => _joinLiveStream(battle),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7C3AED), Color(0xFFEF4444)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(3)),
                          child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 5),
                        const Text('🔥 TRENDING', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      battle['host_name'] ?? 'Live Battle',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.visibility, size: 10, color: Colors.white70),
                        const SizedBox(width: 3),
                        Text('${battle['viewer_count'] ?? 0} watching', style: const TextStyle(color: Colors.white70, fontSize: 9)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                      child: const Text('JOIN', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.mic, color: Colors.white, size: 25),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Spotify-style Recently Played - SMALL SQUARE CARDS (80x80)
  Widget _buildRecentlyPlayedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('🎧 Recently Played', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentlyPlayed.length,
            itemBuilder: (context, index) {
              final song = _recentlyPlayed[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                              : null,
                        ),
                        child: song['thumbnail_url'] == null
                            ? Icon(Icons.music_note, color: WeAfricaColors.gold, size: 30)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        song['title'] ?? 'Untitled',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song['artist'] ?? 'Artist',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
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

  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('✨ Recommended For You', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
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
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                              : null,
                        ),
                        child: song['thumbnail_url'] == null
                            ? Icon(Icons.music_note, color: WeAfricaColors.gold, size: 30)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        song['title'] ?? 'Untitled',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song['artist'] ?? 'Artist',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
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

  Widget _buildLiveBattlesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('🔴 LIVE NOW', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _liveBattles.length,
            itemBuilder: (context, index) {
              final battle = _liveBattles[index];
              return GestureDetector(
                onTap: () => _joinLiveStream(battle),
                child: Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(3)),
                                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 5),
                                Row(
                                  children: [
                                    const Icon(Icons.visibility, size: 9, color: Colors.white70),
                                    const SizedBox(width: 2),
                                    Text('${battle['viewer_count'] ?? 0}', style: const TextStyle(color: Colors.white70, fontSize: 8)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              battle['host_name'] ?? 'DJ Battle',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: WeAfricaColors.gold, borderRadius: BorderRadius.circular(12)),
                              child: const Text('JOIN', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
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

  Widget _buildHotVideosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('🔥 HOT VIDEOS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _hotVideos.length,
            itemBuilder: (context, index) {
              final video = _hotVideos[index];
              return GestureDetector(
                onTap: () => _watchVideo(video),
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 110,
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(8),
                              image: video['thumbnail_url'] != null
                                  ? DecorationImage(image: NetworkImage(video['thumbnail_url']), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: const Center(
                              child: Icon(Icons.play_circle_filled, size: 25, color: WeAfricaColors.gold),
                            ),
                          ),
                          Positioned(
                            bottom: 5,
                            right: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                              child: const Text('▶', style: TextStyle(color: Colors.white, fontSize: 7)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        video['title'] ?? 'Video',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        video['artist'] ?? 'Artist',
                        style: const TextStyle(color: Colors.white70, fontSize: 9),
                        maxLines: 1,
                      ),
                      Row(
                        children: [
                          const Icon(Icons.favorite, size: 8, color: Colors.red),
                          const SizedBox(width: 2),
                          Text('${video['views_count'] ?? 0}K', style: const TextStyle(color: Colors.white54, fontSize: 8)),
                        ],
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('🏆 TOP 10', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _top10.length,
          itemBuilder: (context, index) {
            final song = _top10[index];
            final isTop3 = index < 3;
            return GestureDetector(
              onTap: () => _playSong(song),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isTop3 ? WeAfricaColors.gold.withOpacity(0.1) : Colors.grey[850],
                  borderRadius: BorderRadius.circular(8),
                  border: isTop3 ? Border.all(color: WeAfricaColors.gold, width: 0.5) : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isTop3 ? WeAfricaColors.gold : Colors.grey[800],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: isTop3 ? Colors.black : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                song['title'] ?? 'Untitled',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              if (index == 0) ...[
                                const SizedBox(width: 5),
                                const Icon(Icons.trending_up, size: 10, color: Colors.green),
                              ],
                              if (index == 2) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(color: WeAfricaColors.gold, borderRadius: BorderRadius.circular(2)),
                                  child: const Text('NEW', style: TextStyle(color: Colors.black, fontSize: 6, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            song['artist'] ?? 'Unknown',
                            style: const TextStyle(color: Colors.white70, fontSize: 8),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: WeAfricaColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${song['plays_count'] ?? 0}K',
                        style: const TextStyle(color: WeAfricaColors.gold, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeaturedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('⭐ WeAfrica Picks', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _featured.length,
            itemBuilder: (context, index) {
              final song = _featured[index];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: Container(
                  width: 180,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [WeAfricaColors.gold.withOpacity(0.15), Colors.grey[850]!],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: WeAfricaColors.gold.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 90,
                        decoration: BoxDecoration(
                          color: WeAfricaColors.gold.withOpacity(0.1),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                          image: song['thumbnail_url'] != null
                              ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                              : null,
                        ),
                        child: song['thumbnail_url'] == null
                            ? Icon(Icons.album, size: 25, color: WeAfricaColors.gold)
                            : null,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('PICK', style: TextStyle(color: WeAfricaColors.gold, fontSize: 7, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text(
                                song['title'] ?? 'Featured Track',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                maxLines: 1,
                              ),
                              Text(
                                song['artist'] ?? 'Artist',
                                style: const TextStyle(color: Colors.white54, fontSize: 9),
                                maxLines: 1,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: WeAfricaColors.gold, borderRadius: BorderRadius.circular(10)),
                                child: const Text('PLAY', style: TextStyle(color: Colors.black, fontSize: 7, fontWeight: FontWeight.bold)),
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
}
