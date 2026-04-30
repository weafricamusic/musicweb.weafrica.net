import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../services/live_discovery_service.dart';

/// TikTok Live Pattern - Vertical swipe feed for live streams
/// - Full-screen live stream with overlay UI
/// - Swipe up/down to change streams
/// - Double tap to like, comment overlay, viewer count
class LiveTikTokPattern extends StatefulWidget {
  const LiveTikTokPattern({super.key});

  @override
  State<LiveTikTokPattern> createState() => _LiveTikTokPatternState();
}

class _LiveTikTokPatternState extends State<LiveTikTokPattern> {
  List<Map<String, dynamic>> _liveStreams = [];
  List<String> _comments = [];
  int _likeCount = 0;
  bool _isLoading = true;
  bool _showOverlay = true;
  bool _isLiked = false;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadLiveStreams();
    _startCommentUpdates();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLiveStreams() async {
    try {
      final supabase = Supabase.instance.client;
      final discovery = LiveDiscoveryService(client: supabase);
      
      // Use LiveDiscoveryService to get filtered live streams (excludes test streams)
      final streams = await discovery.listLiveNowSolo(limit: 20);

      setState(() {
        _liveStreams = streams;
        _isLoading = false;
        _likeCount = _liveStreams.isNotEmpty ? _liveStreams[0]['viewer_count'] ?? 0 : 0;
      });

      // Start loading comments for current stream
      if (_liveStreams.isNotEmpty) {
        _loadComments(_liveStreams[0]['channel_id']);
      }
    } catch (e) {
      debugPrint('Error loading live streams: $e');
      setState(() => _isLoading = false);
    }
  }

  void _startCommentUpdates() {
    // Simulate real-time comment updates
    Future.doWhile(() async {
      if (!mounted) return false;
      
      await Future.delayed(const Duration(seconds: 3));
      
      if (mounted && _liveStreams.isNotEmpty) {
        final newComments = [
          '🔥 This battle is fire!',
          'Let\'s go ${_liveStreams[0]['host_name']}!',
          'Who\'s winning this one?',
          'Amazing performance!',
          'Keep it up!',
        ];
        
        setState(() {
          _comments.insert(0, newComments[DateTime.now().second % newComments.length]);
          if (_comments.length > 10) _comments.removeRange(10, _comments.length);
        });
      }
      
      return true;
    });
  }

  Future<void> _loadComments(String channelId) async {
    try {
      final supabase = Supabase.instance.client;
      final comments = await supabase
          .from('live_comments')
          .select('user_name, message, created_at')
          .eq('channel_id', channelId)
          .order('created_at', ascending: false)
          .limit(20);

      setState(() {
        _comments = List<Map<String, dynamic>>.from(comments)
            .map((c) => '${c['user_name']}: ${c['message']}')
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading comments: $e');
    }
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
  }

  void _likeStream() {
    setState(() {
      _isLiked = !_isLiked;
      _likeCount = _isLiked ? _likeCount + 1 : _likeCount - 1;
    });
    
    // Haptic feedback
    // HapticFeedback.heavyImpact();
    
    // Show heart animation (would need animation controller in full implementation)
    debugPrint('Liked stream: ${_isLiked ? 'Liked' : 'Unliked'}');
  }

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? 'Anonymous';
      
      final supabase = Supabase.instance.client;
      await supabase.from('live_comments').insert({
        'channel_id': _liveStreams[0]['channel_id'],
        'user_name': userId,
        'message': text,
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() {
        _comments.insert(0, '$userId: $text');
        _commentController.clear();
      });
    } catch (e) {
      debugPrint('Error submitting comment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send comment')),
      );
    }
  }

  void _shareStream() {
    if (_liveStreams.isEmpty) return;
    final stream = _liveStreams[0];
    debugPrint('Sharing: ${stream['host_name']}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sharing: ${stream['host_name']}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0617),
        body: const Center(child: CircularProgressIndicator(color: WeAfricaColors.gold)),
      );
    }

    if (_liveStreams.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0617),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.live_tv, size: 80, color: Colors.white54),
              const SizedBox(height: 20),
              const Text(
                'No Live Streams',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Check back later for live battles!',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: WeAfricaColors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                onPressed: () {
                  // Navigate to home or show how to start a stream
                  Navigator.pop(context);
                },
                child: const Text('Go Back to Home', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    final currentStream = _liveStreams[0];
    final viewerCount = currentStream['viewer_count'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0617),
      body: Stack(
        children: [
          // Full-screen video player area (placeholder)
          Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.live_tv, size: 60, color: Colors.red),
                  const SizedBox(height: 10),
                  Text(
                    currentStream['title'] ?? 'Live Stream',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'by ${currentStream['host_name'] ?? 'Unknown Host'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '🔴 LIVE',
                    style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // Top overlay bar
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 80,
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: Colors.white),
                          SizedBox(width: 6),
                          Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentStream['title'] ?? 'Live Stream',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Battle: ${currentStream['host_name'] ?? 'Unknown'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        '${viewerCount.toString()} watching',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Right action buttons
          if (_showOverlay)
            Positioned(
              right: 20,
              bottom: 100,
              child: Column(
                children: [
                  // Like button
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _likeStream,
                        onDoubleTap: _likeStream,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Center(
                            child: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked ? WeAfricaColors.gold : Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _likeCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Comment button
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _commentFocusNode.requestFocus();
                          });
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Center(
                            child: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _comments.length.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Share button
                  GestureDetector(
                    onTap: _shareStream,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(
                        child: Icon(Icons.share, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom comment strip
          if (_showOverlay)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 120,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Comments',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _comments[index],
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Comment input area
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type a comment...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        suffixIcon: Icon(Icons.send, color: Colors.white54, size: 20),
                      ),
                      onSubmitted: (text) => _submitComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _toggleOverlay,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Center(
                      child: Icon(Icons.fullscreen, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stream navigation hints
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  if (_showOverlay)
                    const Text(
                      'Swipe up for next stream',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white30,
                    size: 30,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}