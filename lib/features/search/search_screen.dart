import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme/weafrica_colors.dart';
import '../../features/player/playback_controller.dart';
import '../../features/player/player_routes.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _searchDebounce;

  static const _prefsRecentKey = 'recent_searches';
  static const _maxRecent = 8;

  List<String> _recent = [];
  bool _loadingRecent = true;
  bool _isSearching = false;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsRecentKey) ?? [];
      if (!mounted) return;
      setState(() {
        _recent = list.where((e) => e.trim().isNotEmpty).toList();
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = [];
        _loadingRecent = false;
      });
    }
  }

  Future<void> _runSearch(String query, {bool saveRecent = false}) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final supabase = Supabase.instance.client;
      final searchQuery = '%$q%';
      
      final response = await supabase
          .from('songs')
          .select('id, title, artist, thumbnail_url, audio_url, plays_count, genre')
          .or('title.ilike.$searchQuery,artist.ilike.$searchQuery')
          .order('plays_count', ascending: false)
          .limit(40);

      if (!mounted) return;

      setState(() {
        _results = List<Map<String, dynamic>>.from(response);
        _isSearching = false;
        _error = null;
      });

      if (saveRecent && _results.isNotEmpty) {
        _saveRecent(q);
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Search failed. Please try again.';
        _isSearching = false;
      });
    }
  }

  void _scheduleAutoSearch(String query) {
    _searchDebounce?.cancel();
    final q = query.trim();

    if (q.isEmpty) {
      _runSearch('');
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _runSearch(q, saveRecent: false);
    });
  }

  Future<void> _saveRecent(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final next = [q, ..._recent.where((e) => e.toLowerCase() != q.toLowerCase())]
        .take(_maxRecent)
        .toList();

    setState(() => _recent = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsRecentKey, next);
    } catch (_) {}
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsRecentKey);
    } catch (_) {}
  }

  void _applyQueryAndSearch(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    _runSearch(value, saveRecent: true);
  }

  Future<void> _playSong(Map<String, dynamic> song) async {
    try {
      HapticFeedback.mediumImpact();

      final track = Track(
        id: song['id'].toString(),
        title: song['title'] ?? 'Unknown Title',
        artist: song['artist'] ?? 'Unknown Artist',
        audioUri: Uri.tryParse(song['audio_url'] ?? ''),
        artworkUri: song['thumbnail_url'] != null
            ? Uri.tryParse(song['thumbnail_url'])
            : null,
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
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0617),
      body: SafeArea(
        child: Column(
          children: [
            // Search Header
            _buildSearchHeader(),
            
            // Content
            Expanded(
              child: hasQuery || _results.isNotEmpty
                  ? _buildSearchResults()
                  : _buildRecentSearches(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0617),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Back Button
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
          const SizedBox(width: 12),
          
          // Search Field
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1B1530),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) => _runSearch(value, saveRecent: true),
                onChanged: (v) {
                  setState(() {});
                  _scheduleAutoSearch(v);
                },
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white54,
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _controller.clear();
                            _searchDebounce?.cancel();
                            _runSearch('');
                            _focusNode.requestFocus();
                          },
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white54,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_loadingRecent) {
      return const Center(
        child: CircularProgressIndicator(color: WeAfricaColors.gold),
      );
    }

    if (_recent.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.2),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Search for songs and artists',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Searches',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(
              onPressed: _clearRecent,
              style: TextButton.styleFrom(
                foregroundColor: WeAfricaColors.gold,
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recent.map((query) => _buildRecentItem(query)),
      ],
    );
  }

  Widget _buildRecentItem(String query) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1530),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.history,
          color: Colors.white.withValues(alpha: 0.2),
          size: 20,
        ),
      ),
      title: Text(
        query,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        Icons.north_west,
        color: Colors.white.withValues(alpha: 0.2),
        size: 18,
      ),
      onTap: () => _applyQueryAndSearch(query),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: WeAfricaColors.gold),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.white.withValues(alpha: 0.2),
              size: 64,
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
              onPressed: () => _runSearch(_controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: WeAfricaColors.gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty && _controller.text.trim().isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              color: Colors.white.withValues(alpha: 0.2),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final song = _results[index];
        return _buildSongTile(song, index);
      },
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (song['genre'] != null)
                        Text(
                          song['genre'],
                          style: TextStyle(
                            color: WeAfricaColors.gold.withValues(alpha: 0.3),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (song['genre'] != null)
                        const SizedBox(width: 8),
                      Icon(
                        Icons.play_arrow,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatNumber(song['plays_count']),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 12,
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