import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app/theme/weafrica_colors.dart';

class HomeTabNew extends StatefulWidget {
  const HomeTabNew({super.key});

  @override
  State<HomeTabNew> createState() => _HomeTabNewState();
}

class _HomeTabNewState extends State<HomeTabNew> {
  List<Map<String, dynamic>> _trendingSongs = [];
  List<Map<String, dynamic>> _liveStreams = [];
  List<Map<String, dynamic>> _hotVideos = [];
  final List<Map<String, dynamic>> _picks = [];
  bool _loading = true;
  String _selectedCountry = 'Malawi';
  String _selectedGenre = 'All';

  final List<String> _countries = ['Malawi', 'Nigeria', 'Ghana', 'South Africa', 'Kenya'];
  final List<String> _genres = ['All', 'Amapiano', 'Afrobeat', 'Hits', 'Love Songs', 'Gospel', 'New Artists'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final supabase = Supabase.instance.client;
      
      // Load trending songs
      final songs = await supabase
          .from('songs')
          .select('title, artist, plays_count, likes_count')
          .order('plays_count', ascending: false)
          .limit(5);
      
      // Load live streams
      final live = await supabase
          .from('live_sessions')
          .select('host_name, title, viewer_count')
          .eq('is_live', true)
          .limit(2);
      
      // Load hot videos
      final videos = await supabase
          .from('videos')
          .select('title, artist, views_count, thumbnail_url')
          .order('views_count', ascending: false)
          .limit(4);
      
      setState(() {
        _trendingSongs = List<Map<String, dynamic>>.from(songs);
        _liveStreams = List<Map<String, dynamic>>.from(live);
        _hotVideos = List<Map<String, dynamic>>.from(videos);
        _loading = false;
      });
    } catch (e) {
      print('Error loading home data: $e');
      setState(() {
        _loading = false;
        _hotVideos = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: WeAfricaColors.gold))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // Trending Section
                  _buildSectionHeader('TRENDING IN MALAWI', 'See All'),
                  const SizedBox(height: 12),
                  _buildTrendingList(),
                  const SizedBox(height: 24),
                  
                  // Country Chips
                  _buildCountryChips(),
                  const SizedBox(height: 16),
                  
                  // Genre Chips
                  _buildGenreChips(),
                  const SizedBox(height: 24),
                  
                  // Live Now Section
                  _buildSectionHeader('LIVE NOW', 'See All'),
                  const SizedBox(height: 12),
                  _buildLiveStreams(),
                  const SizedBox(height: 24),
                  
                  // Hot Videos Section
                  _buildSectionHeader('HOT VIDEOS', 'See All'),
                  const SizedBox(height: 12),
                  _buildHotVideos(),
                  const SizedBox(height: 24),
                  
                  // WeAfrica Picks
                  _buildSectionHeader('WEAFRICA PICKS', 'See All'),
                  const SizedBox(height: 12),
                  _buildPicks(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            action,
            style: TextStyle(
              color: WeAfricaColors.gold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingList() {
    return SizedBox(
      height: 280,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _trendingSongs.length,
        itemBuilder: (context, index) {
          final song = _trendingSongs[index];
          return Container(
            width: 160,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(16),
                    image: song['thumbnail_url'] != null
                        ? DecorationImage(image: NetworkImage(song['thumbnail_url']), fit: BoxFit.cover)
                        : null,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: WeAfricaColors.gold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.play_arrow, size: 12, color: Colors.black),
                              SizedBox(width: 4),
                              Text('Play', style: TextStyle(color: Colors.black, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  song['title'] ?? 'Untitled',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 1,
                ),
                Text(
                  song['artist'] ?? 'Unknown',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.play_circle_outline, size: 12, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      '${song['plays_count'] ?? 0}K Plays',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.favorite_border, size: 10, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      '${song['likes_count'] ?? 0}K Likes',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _countries.map((country) {
          final isSelected = _selectedCountry == country;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(country),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedCountry = country);
                _loadData();
              },
              backgroundColor: Colors.grey[850],
              selectedColor: WeAfricaColors.gold.withOpacity(0.3),
              labelStyle: TextStyle(
                color: isSelected ? WeAfricaColors.gold : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: isSelected ? BorderSide(color: WeAfricaColors.gold) : BorderSide(color: Colors.grey[800]!),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGenreChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _genres.map((genre) {
          final isSelected = _selectedGenre == genre;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(genre),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedGenre = genre);
                _loadData();
              },
              backgroundColor: Colors.grey[850],
              selectedColor: WeAfricaColors.gold.withOpacity(0.3),
              labelStyle: TextStyle(
                color: isSelected ? WeAfricaColors.gold : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: isSelected ? BorderSide(color: WeAfricaColors.gold) : BorderSide(color: Colors.grey[800]!),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLiveStreams() {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _liveStreams.length,
        itemBuilder: (context, index) {
          final stream = _liveStreams[index];
          return Container(
            width: 300,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.red, Colors.redAccent],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              const Icon(Icons.visibility, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                '${stream['viewer_count'] ?? 0}K watching',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        stream['host_name'] ?? 'Artist',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        stream['title'] ?? 'Live Stream',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: WeAfricaColors.gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Join',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHotVideos() {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _hotVideos.length,
        itemBuilder: (context, index) {
          final video = _hotVideos[index];
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                    image: video['thumbnail_url'] != null
                        ? DecorationImage(image: NetworkImage(video['thumbnail_url']), fit: BoxFit.cover)
                        : null,
                  ),
                  child: video['thumbnail_url'] == null
                      ? const Center(
                          child: Icon(Icons.play_circle_filled, size: 40, color: WeAfricaColors.gold),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  video['title'] ?? 'Untitled',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  maxLines: 1,
                ),
                Text(
                  video['artist'] ?? 'Unknown',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${video['views_count'] ?? 0}K views',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPicks() {
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            width: 280,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 100,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                  ),
                  child: const Center(
                    child: Icon(Icons.music_note, size: 40, color: WeAfricaColors.gold),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'WeAfrica Picks',
                          style: TextStyle(color: WeAfricaColors.gold, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _trendingSongs.isNotEmpty ? _trendingSongs[index % _trendingSongs.length]['title'] ?? 'Featured Track' : 'Featured Track',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'New Release',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
