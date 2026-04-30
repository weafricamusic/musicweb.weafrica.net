import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../../player/player_routes.dart';
import '../../player/playback_controller.dart';

class TrendingSongsScreen extends StatefulWidget {
  const TrendingSongsScreen({super.key});

  @override
  State<TrendingSongsScreen> createState() => _TrendingSongsScreenState();
}

class _TrendingSongsScreenState extends State<TrendingSongsScreen> {
  List<Map<String, dynamic>> _songs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final supabase = Supabase.instance.client;
      
      // Fetch trending songs (most played/liked)
      final response = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, plays_count, likes_count, genre')
          .order('plays_count', ascending: false)
          .limit(50);

      setState(() {
        _songs = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading trending songs: $e');
      setState(() {
        _error = 'Failed to load trending songs';
        _isLoading = false;
      });
    }
  }

  Future<void> _playSong(Map<String, dynamic> song) async {
    try {
      HapticFeedback.mediumImpact();
      
      final track = Track(
        id: song['id'].toString(),
        title: song['title'] ?? 'Unknown Title',
        artist: song['artist'] ?? 'Unknown Artist',
        audioUri: Uri.tryParse(song['audio_url'] ?? ''),
        artworkUri: song['thumbnail_url'] != null ? Uri.tryParse(song['thumbnail_url']) : null,
      );

      if (mounted) {
        PlaybackController.instance.play(track);
        openPlayer(context);
      }
    } catch (e) {
      debugPrint('Error playing song: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to play song')),
      );
    }
  }

  String _formatNumber(int? number) {
    if (number == null) return '0';
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0617),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App Bar
            SliverToBoxAdapter(
              child: _buildAppBar(),
            ),

            // Content
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: WeAfricaColors.gold),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSongs,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WeAfricaColors.gold,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_songs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.trending_down,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No trending songs',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start listening to build trends',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = _songs[index];
                      return _buildSongTile(song, index);
                    },
                    childCount: _songs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1B1530),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trending Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '${_songs.length} hot tracks',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF6A5CFF).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF6A5CFF).withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.trending_up,
              color: Color(0xFF6A5CFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(Map<String, dynamic> song, int index) {
    final plays = song['plays_count'] ?? 0;
    final likes = song['likes_count'] ?? 0;
    final rank = index + 1;
    final isTop3 = rank <= 3;
    
    return GestureDetector(
      onTap: () => _playSong(song),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1530),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTop3 
                ? WeAfricaColors.gold.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.05),
          ),
          gradient: isTop3
              ? LinearGradient(
                  colors: [
                    const Color(0xFF1B1530),
                    const Color(0xFF1B1530),
                    WeAfricaColors.gold.withValues(alpha: 0.1),
                  ],
                  stops: const [0.0, 0.7, 1.0],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
        ),
        child: Row(
          children: [
            // Rank Number
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isTop3 ? WeAfricaColors.gold : const Color(0xFF2D2545),
                borderRadius: BorderRadius.circular(10),
                boxShadow: isTop3
                    ? [
                        BoxShadow(
                          color: WeAfricaColors.gold.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: isTop3 ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Thumbnail
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF2D2545),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: song['thumbnail_url'] != null
                    ? Image.network(
                        song['thumbnail_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.music_note,
                            color: Colors.white54,
                          );
                        },
                      )
                    : const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Song Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song['title'] ?? 'Untitled',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song['artist'] ?? 'Unknown Artist',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.play_arrow,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatNumber(plays),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.favorite,
                        size: 14,
                        color: Colors.red.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatNumber(likes),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Play Button
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isTop3 ? WeAfricaColors.gold : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                boxShadow: isTop3
                    ? [
                        BoxShadow(
                          color: WeAfricaColors.gold.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.play_arrow,
                color: isTop3 ? Colors.black : Colors.white,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}