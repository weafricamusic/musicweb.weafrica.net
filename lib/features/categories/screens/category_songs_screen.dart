import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../../player/player_routes.dart';
import '../../player/playback_controller.dart';

class CategorySongsScreen extends StatefulWidget {
  final String title;
  final String category;
  final String filterType; // 'genre' or 'country'

  const CategorySongsScreen({
    super.key,
    required this.title,
    required this.category,
    required this.filterType,
  });

  @override
  State<CategorySongsScreen> createState() => _CategorySongsScreenState();
}

class _CategorySongsScreenState extends State<CategorySongsScreen> {
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
      List<Map<String, dynamic>> songs = [];

      if (widget.filterType == 'country') {
        // Filter by country
        final response = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url, plays_count, genre')
            .eq('country', widget.category)
            .order('plays_count', ascending: false)
            .limit(50);
        songs = List<Map<String, dynamic>>.from(response);
      } else {
        // Filter by genre
        final response = await supabase
            .from('songs')
            .select('id, title, artist, thumbnail_url, audio_url, plays_count, genre')
            .ilike('genre', '%${widget.category}%')
            .order('plays_count', ascending: false)
            .limit(50);
        songs = List<Map<String, dynamic>>.from(response);
      }

      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading songs: $e');
      setState(() {
        _error = 'Failed to load songs';
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
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
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
                        Icons.music_off,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No songs found',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back later for new ${widget.category} music',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
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
                  color: Colors.white.withValues(alpha: 0.2),
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
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '${_songs.length} songs',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(Map<String, dynamic> song, int index) {
    return GestureDetector(
      onTap: () => _playSong(song),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1530),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            // Rank or Play Icon
            Container(
              width: 48,
              height: 48,
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
            const SizedBox(width: 16),
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
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song['genre'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        song['genre'],
                        style: TextStyle(
                          color: WeAfricaColors.gold.withValues(alpha: 0.3),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Play Button
            Container(
              width: 44,
              height: 44,
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
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}