import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/weafrica_colors.dart';
import '../player/player_routes.dart';
import '../player/playback_controller.dart';
import '../live/screens/live_watch_screen.dart';
import '../videos/video.dart';
import '../videos/screens/video_playback_screen.dart';

class WeAfricaHomeV4 extends StatefulWidget {
  const WeAfricaHomeV4({super.key});

  @override
  State<WeAfricaHomeV4> createState() => _WeAfricaHomeV4State();
}

class _WeAfricaHomeV4State extends State<WeAfricaHomeV4> {
  List<Map<String, dynamic>> _recentlyPlayed = [];
  List<Map<String, dynamic>> _recommendedForYou = [];
  List<Map<String, dynamic>> _featured = [];
  List<Map<String, dynamic>> _top10 = [];
  List<Map<String, dynamic>> _liveStreams = [];
  List<Map<String, dynamic>> _videosList = [];
  bool _loading = true;

  final List<String> _categories = [
    "Malawi", "Nigeria", "Amapiano", "Afrobeat",
    "Love", "Gospel", "New", "Trending"
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
            .select('id, title, artist, thumbnail_url, audio_url')
            .inFilter('id', recentlyPlayedIds.take(8).toList());
        _recentlyPlayed = List<Map<String, dynamic>>.from(recent);
      } else {
        final defaultSongs = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url')
            .order('plays_count', ascending: false)
            .limit(8);
        _recentlyPlayed = List<Map<String, dynamic>>.from(defaultSongs);
      }
      
      // Fetch recommended songs
      final rec = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url')
          .order('plays_count', ascending: false)
          .limit(10);
      _recommendedForYou = List<Map<String, dynamic>>.from(rec);
      
      // Fetch featured songs
      final featured = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url')
          .order('plays_count', ascending: false)
          .limit(5);
      _featured = List<Map<String, dynamic>>.from(featured);
      
      // Fetch top 10 songs
      final top = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, plays_count')
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
      
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _loading = false);
    }
  }

  void _onCategoryTap(String category) async {
    final supabase = Supabase.instance.client;
    List<Map<String, dynamic>> categorySongs = [];
    
    try {
      switch (category) {
        case "Malawi":
          categorySongs = await supabase.from("songs").select("id, title, artist, thumbnail_url, audio_url").eq("country", "Malawi").limit(20);
          if (categorySongs.isEmpty) categorySongs = await supabase.from("songs").select("id, title, artist, thumbnail_url, audio_url").ilike("artist", "%Driemo%").limit(20);
          break;
        case "Nigeria":
          categorySongs = await supabase.from("songs").select("id, title, artist, thumbnail_url, audio_url").eq("country", "Nigeria").limit(20);
          break;
        case "Amapiano":
          categorySongs = await supabase.from("songs").select("id, title, artist, thumbnail_url, audio_url").ilike("genre", "%Amapiano%").limit(20);
          break;
        case "Afrobeat":
          categorySongs = await supabase.from("songs").select("id, title, artist, thumbnail_url, audio_url").ilike("genre", "%Afrobeat%").limit(20);
          break;
        default:
          categorySongs = await supabase.from("songs").select("id, title, artist, thumbnail_url, audio_url").ilike("genre", "%$category%").limit(20);
      }

      if (categorySongs.isNotEmpty) {
        await _playSong(categorySongs[0]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No songs found")));
      }
    } catch (e) {
      debugPrint('Error fetching category songs: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load songs")));
    }
  }

  void _onCategoryTap_old(String category) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Showing $category music")),
                          );
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

  void _joinLiveStream_old(Map<String, dynamic> live) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Joining ${live['host_name']}")),
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
      backgroundColor: const Color(0xFF0B0617),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroSection(),
              const SizedBox(height: 16),
              _buildCategoryGrid(),
              const SizedBox(height: 24),
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
      ),
    );
  }

  Widget _buildHeroSection() {
    final topSong = _top10.isNotEmpty ? _top10[0] : null;
    return Container(
      margin: const EdgeInsets.all(16),
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Colors.purple, Colors.orange]),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("🔥 Trending Now", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Text(topSong != null ? topSong['title'] ?? 'Nobody Cares' : 'Nobody Cares', 
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text(topSong != null ? topSong['artist'] ?? 'Artist' : 'Driemo', 
                  style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => topSong != null ? _playSong(topSong) : null,
              child: const Text("Play"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
        ),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _onCategoryTap(_categories[index]),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [Colors.deepPurple, Colors.orange]),
              ),
              child: Center(
                child: Text(
                  _categories[index], 
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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
                      colors: [Colors.orange.withOpacity(0.15), Colors.grey[850]!],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
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
                    try {
                      final vtmp = Video.fromSupabase(video);
                      debugPrint('HOT VIDEO[$index] id=${video['id']} videoUri=${vtmp.videoUri}');
                    } catch (e, st) {
                      debugPrint('HOT VIDEO[$index] parse error: $e\n$st');
                    }
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

