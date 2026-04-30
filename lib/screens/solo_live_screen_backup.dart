import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../shared/theme/app_colors.dart';

// Floating heart model for animations
class FloatingHeart {
  final String emoji;
  final double startX;
  final double endX;
  final Duration duration;
  final double size;
  final Color color;

  FloatingHeart({
    required this.emoji,
    required this.startX,
    required this.endX,
    required this.duration,
    this.size = 24.0,
    this.color = Colors.red,
  });
}

class SoloLiveScreen extends StatefulWidget {
  final String? liveSessionId;
  final bool isDj; // Flag to show DJ-specific controls

  const SoloLiveScreen({
    super.key,
    this.liveSessionId = 'test-live-session',
    this.isDj = false,
  });

  @override
  State<SoloLiveScreen> createState() => _SoloLiveScreenState();
}

class _SoloLiveScreenState extends State<SoloLiveScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  int _viewerCount = 124;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _showCommentsOverlay = true;
  bool _isEndingLive = false;
  bool _isDjMode = false;

  // Earnings
  int _totalEarnings = 0;
  int _totalCoins = 0;

  // Goal system - Multiple goals
  List<LiveGoal> _goals = [
    LiveGoal(
      id: 'flowers',
      title: '🌸 Flowers',
      target: 100,
      current: 42,
      icon: '🌸',
      color: Colors.pink,
    ),
    LiveGoal(
      id: 'diamonds',
      title: '💎 Diamonds',
      target: 50,
      current: 15,
      icon: '💎',
      color: Colors.blue,
    ),
    LiveGoal(
      id: 'crowd',
      title: '🔥 Crowd Power',
      target: 200,
      current: 87,
      icon: '🔥',
      color: Colors.orange,
    ),
  ];

  // DJ Controls
  bool _isDjPlaying = false;
  double _djMasterVolume = 0.78;
  double _djMicVolume = 0.72;
  bool _djReverbEnabled = false;
  bool _djEchoEnabled = false;
  int _currentTrackIndex = 0;
  final List<String> _djQueue = [
    'Afrobeat Mix Vol. 1',
    'Amapiano Sunset',
    'House Vibes',
    'Afro House Journey',
  ];

  // Reactions
  final List<FloatingHeart> _floatingHearts = [];
  final Random _random = Random();
  final List<String> _heartEmojis = ['❤️', '🔥', '😍', '👏', '🎉', '💯'];

  // Subscriptions
  StreamSubscription? _giftSubscription;
  StreamSubscription? _goalSubscription;
  StreamSubscription? _commentsSubscription;
  StreamSubscription? _viewerSubscription;
  StreamSubscription? _earningsSubscription;
  StreamSubscription? _reactionsSubscription;

  final ScrollController _commentsScrollController = ScrollController();
  final TextEditingController _commentController = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];

  // Animations
  late AnimationController _goalAnimationController;

  @override
  void initState() {
    super.initState();
    _isDjMode = widget.isDj;
    _initializeCamera();
    _setupRealTimeSubscriptions();
    _startViewerSimulation();
    _startHeartAnimation();
  }

  void _setupRealTimeSubscriptions() {
    final sessionId = widget.liveSessionId ?? 'test-live-session';

    // Real time gifts subscription
    _giftSubscription = Supabase.instance.client
        .from('gift_transactions')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .listen((event) {
      if (event.isNotEmpty) {
        final gift = event.first;
        final coins = (gift['coins'] as num?)?.toInt() ?? 1;
        setState(() {
          _totalCoins += coins;
          _totalEarnings += coins;
        });
        // Update goals
        _updateGoalProgress('flowers', 1);
      }
    });

    // Real time goals subscription
    _goalSubscription = Supabase.instance.client
        .from('live_goals')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .listen((event) {
      if (event.isNotEmpty) {
        setState(() {
          for (final goalData in event) {
            final goalIndex = _goals.indexWhere(
                (g) => g.id == goalData['gift_type']);
            if (goalIndex != -1) {
              _goals[goalIndex].current = goalData['current'] ?? 0;
              _goals[goalIndex].target = goalData['target'] ?? 100;
            }
          }
        });
      }
    });

    // Real time comments subscription
    _commentsSubscription = Supabase.instance.client
        .from('live_comments')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .order('created_at')
        .limit(50)
        .listen((event) {
      setState(() {
        _comments.clear();
        _comments.addAll(event.reversed);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_commentsScrollController.hasClients) {
          _commentsScrollController.animateTo(
            _commentsScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });

    // Viewer count subscription
    _viewerSubscription = Supabase.instance.client
        .from('live_viewers')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .listen((event) {
      setState(() {
        _viewerCount = event.length;
      });
    });

    // Earnings subscription
    _earningsSubscription = Supabase.instance.client
        .from('live_earnings')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .listen((event) {
      if (event.isNotEmpty) {
        setState(() {
          _totalEarnings =
              (event.fold<num>(0, (sum, item) => sum + ((item['amount'] as num?) ?? 0))).toInt();
        });
      }
    });

    // Reactions subscription
    _reactionsSubscription = Supabase.instance.client
        .from('live_reactions')
        .stream(primaryKey: ['id'])
        .eq('live_session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(20)
        .listen((event) {
      if (event.isNotEmpty) {
        final reaction = event.first;
        _addFloatingHeart(reaction['emoji'] ?? '❤️');
      }
    });
  }

  void _updateGoalProgress(String goalId, int amount) {
    setState(() {
      final goalIndex = _goals.indexWhere((g) => g.id == goalId);
      if (goalIndex != -1) {
        _goals[goalIndex].current += amount;
      }
    });
  }

  void _startViewerSimulation() {
    // Simulate viewer count changes for demo
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {
          _viewerCount += _random.nextInt(5) - 2;
          if (_viewerCount < 0) _viewerCount = 0;
        });
      }
    });
  }

  void _startHeartAnimation() {
    // Periodically add random hearts for demo
    Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _random.nextBool()) {
        _addFloatingHeart(_heartEmojis[_random.nextInt(_heartEmojis.length)]);
      }
    });
  }

  void _addFloatingHeart(String emoji) {
    final startX = 50 + _random.nextDouble() * 200;
    final endX = startX + (_random.nextDouble() * 60 - 30);

    setState(() {
      _floatingHearts.add(FloatingHeart(
        emoji: emoji,
        startX: startX,
        endX: endX,
        duration: Duration(seconds: 2 + _random.nextInt(2)),
        size: 20 + _random.nextDouble() * 20,
      ));
    });

    // Remove heart after animation
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (_floatingHearts.isNotEmpty) {
            _floatingHearts.removeAt(0);
          }
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
      );

      await _cameraController?.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      // Camera error
    }
  }

  Future<void> _flipCamera() async {
    if (_cameraController == null) return;

    final cameras = await availableCameras();
    final newDirection =
        _cameraController!.description.lensDirection == CameraLensDirection.front
            ? CameraLensDirection.back
            : CameraLensDirection.front;

    final newCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == newDirection,
      orElse: () => cameras.first,
    );

    await _cameraController?.dispose();

    _cameraController = CameraController(
      newCamera,
      ResolutionPreset.high,
    );

    await _cameraController?.initialize();
    if (mounted) setState(() {});
  }

  void _toggleMic() {
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  void _toggleCamera() {
    setState(() {
      _isCameraOff = !_isCameraOff;
    });
  }

  void _toggleComments() {
    setState(() {
      _showCommentsOverlay = !_showCommentsOverlay;
    });
  }

  void _openBattleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(
            color: AppColors.grassDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'SELECT OPPONENT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: 10,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: AppColors.grassMint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Artist Name',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Online now',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _sendBattleRequest();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.battleAmber,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'CHALLENGE',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _sendBattleRequest() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Battle request sent'),
        backgroundColor: AppColors.battleAmber,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openGifts() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: AppColors.grassDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'SEND GIFT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _giftButton('🌹', 'Rose', 1),
                    _giftButton('🔥', 'Fire', 5),
                    _giftButton('💎', 'Diamond', 25),
                    _giftButton('👑', 'Crown', 100),
                    _giftButton('🚀', 'Rocket', 50),
                    _giftButton('💫', 'Star', 10),
                    _giftButton('🎵', 'Music', 15),
                    _giftButton('🎤', 'Mic', 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _giftButton(String emoji, String name, int coins) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _sendGift(emoji, name, coins);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: )),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 4),
            Text(
              '$coins',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _sendGift(String emoji, String name, int coins) {
    setState(() {
      _totalCoins += coins;
      _totalEarnings += coins;
      _updateGoalProgress('flowers', coins);
    });

    // Add floating heart animation
    _addFloatingHeart(emoji);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$emoji $name sent! +$coins'),
        backgroundColor: AppColors.grassMint,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _shareStream() async {
    try {
      await Share.share(
        'Check out my live stream on WeAfrica Music! 🎵🔥',
        subject: 'WeAfrica Music Live',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to share'),
          backgroundColor: AppColors.liveRed,
        ),
      );
    }
  }

  void _confirmEndLive() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.grassDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'End Live Stream?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to end this live session?',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            _summaryRow('Total Viewers', '$_viewerCount'),
            _summaryRow('Total Earnings', '$_totalEarnings coins'),
            _summaryRow('Gifts Received', '$_totalCoins'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _endLive();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.liveRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('End Stream'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.grassMint, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _endLive() {
    setState(() {
      _isEndingLive = true;
    });

    // Navigate back after cleanup
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  void _openInviteGuest() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: AppColors.grassDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'INVITE GUEST',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Invite someone to join your live stream',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: 8,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: AppColors.grassMint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'User Name',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  index.isEven ? 'Online' : 'Offline',
                                  style: TextStyle(
                                      color: index.isEven
                                          ? AppColors.grassMint
                                          : Colors.white38,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (index.isEven)
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invitation sent!'),
                                    backgroundColor: AppColors.grassMint,
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.battleAmber.withValues(alpha: ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'INVITE',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            )
                          else
                            const Text(
                              'Offline',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime? _lastCommentSent;

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();

    if (text.isEmpty) return;
    if (text.length > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message too long (max 200 characters)'),
          backgroundColor: AppColors.liveRed,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    if (_lastCommentSent != null &&
        DateTime.now().difference(_lastCommentSent!) <
            const Duration(seconds: 1)) {
      return;
    }
    _lastCommentSent = DateTime.now();

    try {
      await Supabase.instance.client.from('live_comments').insert({
        'live_session_id': widget.liveSessionId ?? 'test-live-session',
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'username': Supabase.instance.client.auth.currentUser?.userMetadata?['username'] ??
            'Anonymous',
        'text': text,
      }).timeout(const Duration(seconds: 5));
      _commentController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message. Retrying...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // DJ Controls
  void _toggleDjPlayback() {
    setState(() {
      _isDjPlaying = !_isDjPlaying;
    });
  }

  void _skipDjTrack() {
    setState(() {
      _currentTrackIndex = (_currentTrackIndex + 1) % _djQueue.length;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now playing: ${_djQueue[_currentTrackIndex]}'),
        backgroundColor: AppColors.grassMint,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleDjReverb() {
    setState(() {
      _djReverbEnabled = !_djReverbEnabled;
    });
  }

  void _toggleDjEcho() {
    setState(() {
      _djEchoEnabled = !_djEchoEnabled;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _giftSubscription?.cancel();
    _goalSubscription?.cancel();
    _commentsSubscription?.cancel();
    _viewerSubscription?.cancel();
    _earningsSubscription?.cancel();
    _reactionsSubscription?.cancel();
    _commentsScrollController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          _cameraController != null &&
                  _cameraController!.value.isInitialized &&
                  !_isCameraOff
              ? SizedBox.expand(
                  child: CameraPreview(_cameraController!),
                )
              : Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.grey[900],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_off, size: 80, color: Colors.white24),
                        SizedBox(height: 16),
                        Text(
                          'Camera Off',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),

          // Gradient overlay for better text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: ),
                  Colors.transparent,
                  Colors.black.withValues(alpha: ),
                ],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),

          // Floating Hearts/Reactions
          ..._floatingHearts.asMap().entries.map((entry) {
            final index = entry.key;
            final heart = entry.value;
            return Positioned(
              left: heart.startX,
              bottom: 100 + (index * 30),
              child: AnimatedContainer(
                duration: heart.duration,
                curve: Curves.easeOut,
                child: Text(
                  heart.emoji,
                  style: TextStyle(fontSize: heart.size),
                ),
              ),
            );
          }),

          // Top Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Live indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.liveRed,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.fiber_manual_record,
                                color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Viewer count
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.remove_red_eye,
                                color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '$_viewerCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Challenge battle button
                      GestureDetector(
                        onTap: _openBattleSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.battleAmber.withValues(alpha: ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.bolt, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'BATTLE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Earnings Summary (Top Right)
          Positioned(
            top: 110,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.coinGold.withValues(alpha: )),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_money,
                          color: AppColors.coinGold, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Earnings',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Text(
                    '$_totalEarnings',
                    style: const TextStyle(
                      color: AppColors.coinGold,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Goal Progress Bars (Left Side)
          Positioned(
            left: 16,
            top: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _goals.map((goal) {
                final progress = (goal.current / goal.target).clamp(0.0, 1.0);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(goal.icon, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text(
                            '${goal.current}/${goal.target}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 100,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(goal.color),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Comments Overlay (if enabled)
          if (_showCommentsOverlay && _comments.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 180,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  controller: _commentsScrollController,
                  reverse: true,
                  itemCount: _comments.take(5).length,
                  itemBuilder: (context, index) {
                    final comment = _comments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              shadows: [
                                Shadow(
                                    color: Colors.black,
                                    blurRadius: 4,
                                    offset: Offset(0, 1))
                              ]),
                          children: [
                            TextSpan(
                                text: '${comment['username']} ',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            TextSpan(text: comment['text']),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // DJ Console (if DJ mode)
          if (_isDjMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 200,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.grassMint.withValues(alpha: )),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.music_note,
                            color: AppColors.grassMint, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _djQueue[_currentTrackIndex],
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Play/Pause
                        IconButton(
                          onPressed: _toggleDjPlayback,
                          icon: Icon(
                            _isDjPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.grassMint,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Skip
                        IconButton(
                          onPressed: _skipDjTrack,
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        // Volume slider
                        Expanded(
                          child: Slider(
                            value: _djMasterVolume,
                            onChanged: (value) {
                              setState(() => _djMasterVolume = value);
                            },
                            activeColor: AppColors.grassMint,
                            min: 0,
                            max: 1,
                          ),
                        ),
                        // Reverb
                        IconButton(
                          onPressed: _toggleDjReverb,
                          icon: Icon(
                            Icons.audio_file,
                            color: _djReverbEnabled
                                ? AppColors.grassMint
                                : Colors.white54,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        // Echo
                        IconButton(
                          onPressed: _toggleDjEcho,
                          icon: Icon(
                            Icons.waves,
                            color: _djEchoEnabled
                                ? AppColors.grassMint
                                : Colors.white54,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: ),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Comment input
                    if (_showCommentsOverlay)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: TextField(
                                  controller: _commentController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Say something...',
                                    hintStyle: TextStyle(color: Colors.white54),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _sendComment(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _sendComment,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: AppColors.grassMint,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.send,
                                    color: Colors.black, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Control buttons row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Invite Guest
                        _controlButton(
                          icon: Icons.person_add,
                          label: 'Invite',
                          onTap: _openInviteGuest,
                        ),

                        // Mic Toggle
                        _controlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          label: _isMuted ? 'Unmute' : 'Mute',
                          onTap: _toggleMic,
                          isActive: !_isMuted,
                        ),

                        // Camera Toggle
                        _controlButton(
                          icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                          label: _isCameraOff ? 'Cam Off' : 'Cam On',
                          onTap: _toggleCamera,
                          isActive: !_isCameraOff,
                        ),

                        // Flip Camera
                        _controlButton(
                          icon: Icons.cameraswitch,
                          label: 'Flip',
                          onTap: _flipCamera,
                        ),

                        // Comments Toggle
                        _controlButton(
                          icon: _showCommentsOverlay
                              ? Icons.chat_bubble
                              : Icons.chat_bubble_outline,
                          label: _showCommentsOverlay ? 'Hide Chat' : 'Show Chat',
                          onTap: _toggleComments,
                          isActive: _showCommentsOverlay,
                        ),

                        // Gifts
                        _controlButton(
                          icon: Icons.card_giftcard,
                          label: 'Gifts',
                          onTap: _openGifts,
                          color: AppColors.coinGold,
                        ),

                        // End Live
                        _controlButton(
                          icon: Icons.call_end,
                          label: 'End',
                          onTap: _confirmEndLive,
                          color: AppColors.liveRed,
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Ending Live Overlay
          if (_isEndingLive)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.grassMint),
                    SizedBox(height: 20),
                    Text(
                      'Ending live stream...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool isActive = true,
    bool isDestructive = false,
  }) {
    Color buttonColor;
    if (isDestructive) {
      buttonColor = AppColors.liveRed;
    } else if (color != null) {
      buttonColor = color;
    } else {
      buttonColor = isActive ? AppColors.grassMint : Colors.white54;
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: buttonColor.withValues(alpha: ),
              shape: BoxShape.circle,
              border: Border.all(color: buttonColor.withValues(alpha: )),
            ),
            child: Icon(icon, color: buttonColor, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: buttonColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// Goal model
class LiveGoal {
  final String id;
  final String title;
  int target;
  int current;
  final String icon;
  final Color color;

  LiveGoal({
    required this.id,
    required this.title,
    required this.target,
    required this.current,
    required this.icon,
    required this.color,
  });
}
