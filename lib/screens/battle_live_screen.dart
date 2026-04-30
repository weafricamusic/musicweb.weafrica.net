import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../shared/theme/app_colors.dart';
import 'battle_result_screen.dart';

// Floating heart model for animations
class FloatingHeart {
  final String emoji;
  final double startX;
  final Duration duration;
  final double size;

  FloatingHeart({
    required this.emoji,
    required this.startX,
    required this.duration,
    this.size = 24.0,
  });
}

// Goal model
class BattleGoal {
  final String id;
  final String title;
  int target;
  int current;
  final String icon;
  final Color color;

  BattleGoal({
    required this.id,
    required this.title,
    required this.target,
    required this.current,
    required this.icon,
    required this.color,
  });
}

class BattleLiveScreen extends StatefulWidget {
  final String? liveSessionId;
  final String? channelId;
  final String? battleId;
  final String opponentName;
  final String opponentId;
  final bool isHost; // True if current user is the battle host
  final bool isDj; // Flag to show DJ-specific controls

  const BattleLiveScreen({
    super.key,
    this.liveSessionId,
    this.channelId,
    this.battleId,
    this.opponentName = 'DJ Mike',
    this.opponentId = 'opponent-123',
    this.isHost = true,
    this.isDj = false,
  });

  @override
  State<BattleLiveScreen> createState() => _BattleLiveScreenState();
}

class _BattleLiveScreenState extends State<BattleLiveScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isOpponentBig = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _showCommentsOverlay = true;
  bool _isEndingBattle = false;
  bool _isDjMode = false;

  // Scores
  int _myScore = 1200;
  int _opponentScore = 890;
  int _timeRemaining = 1200;
  int _totalEarnings = 0;
  int _totalCoins = 0;

  // Goals
  List<BattleGoal> _goals = [
    BattleGoal(
      id: 'flowers',
      title: '🌸 Flowers',
      target: 500,
      current: 210,
      icon: '🌸',
      color: Colors.pink,
    ),
    BattleGoal(
      id: 'diamonds',
      title: '💎 Diamonds',
      target: 100,
      current: 45,
      icon: '💎',
      color: Colors.blue,
    ),
    BattleGoal(
      id: 'crowd',
      title: '🔥 Crowd Power',
      target: 1000,
      current: 650,
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
    'Afrobeat Battle Mix',
    'Amapiano War',
    'House Clash',
    'Afro House Duel',
  ];

  // Viewer count
  int _viewerCount = 1542;

  // Reactions
  final List<FloatingHeart> _floatingHearts = [];
  final Random _random = Random();
  final List<String> _heartEmojis = ['❤️', '🔥', '😍', '👏', '🎉', '💯', '⚡'];

  // Subscriptions
  StreamSubscription? _scoreSubscription;
  StreamSubscription? _giftSubscription;
  StreamSubscription? _commentsSubscription;
  StreamSubscription? _viewerSubscription;
  StreamSubscription? _reactionsSubscription;

  final TextEditingController _commentController = TextEditingController();
  final ScrollController _commentsScrollController = ScrollController();
  final List<Map<String, dynamic>> _comments = [];

  DateTime? _lastCommentSent;

  String get _timerText {
    final mins = _timeRemaining ~/ 60;
    final secs = _timeRemaining % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double get _myScoreRatio =>
      _myScore / (_myScore + _opponentScore > 0 ? _myScore + _opponentScore : 1);
  double get _opponentScoreRatio =>
      _opponentScore / (_myScore + _opponentScore > 0 ? _myScore + _opponentScore : 1);

  @override
  void initState() {
    super.initState();
    _isDjMode = widget.isDj;
    _initializeCamera();
    _setupRealTimeSubscriptions();
    _startTimer();
    _startHeartAnimation();
    _startViewerSimulation();
  }

  void _setupRealTimeSubscriptions() {
    final sessionId = widget.liveSessionId ?? 'test-battle-session';

    // Score subscription
    _scoreSubscription = Supabase.instance.client
        .from('battle_scores')
        .stream(primaryKey: ['id'])
        .eq('battle_id', widget.battleId ?? 'test-battle')
        .listen((event) {
      if (event.isNotEmpty) {
        setState(() {
          for (final scoreData in event) {
            if (scoreData['user_id'] == Supabase.instance.client.auth.currentUser?.id) {
              _myScore = scoreData['score'] ?? _myScore;
            } else {
              _opponentScore = scoreData['score'] ?? _opponentScore;
            }
          }
        });
      }
    });

    // Gifts subscription
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
          _myScore += coins;
        });
        _updateGoalProgress('flowers', coins);
        _addFloatingHeart('🎁');
      }
    });

    // Comments subscription
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

  void _startTimer() {
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_timeRemaining > 0) _timeRemaining--;
      });
    });
  }

  void _startViewerSimulation() {
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {
          _viewerCount += _random.nextInt(10) - 5;
          if (_viewerCount < 0) _viewerCount = 0;
        });
      }
    });
  }

  void _startHeartAnimation() {
    Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _random.nextBool()) {
        _addFloatingHeart(_heartEmojis[_random.nextInt(_heartEmojis.length)]);
      }
    });
  }

  void _addFloatingHeart(String emoji) {
    final startX = 50 + _random.nextDouble() * 200;

    setState(() {
      _floatingHearts.add(FloatingHeart(
        emoji: emoji,
        startX: startX,
        duration: Duration(seconds: 2 + _random.nextInt(2)),
        size: 20 + _random.nextDouble() * 20,
      ));
    });

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

  void _swapVideos() {
    setState(() => _isOpponentBig = !_isOpponentBig);
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

  void _sendComment() async {
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
        DateTime.now().difference(_lastCommentSent!) < const Duration(seconds: 1)) {
      return;
    }
    _lastCommentSent = DateTime.now();

    try {
      await Supabase.instance.client.from('live_comments').insert({
        'live_session_id': widget.liveSessionId ?? 'test-battle-session',
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
      _myScore += coins;
      _updateGoalProgress('flowers', coins);
    });

    _addFloatingHeart(emoji);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$emoji $name sent! +$coins'),
        backgroundColor: AppColors.grassMint,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _shareBattle() async {
    try {
      await Share.share(
        'Watch this epic battle on WeAfrica Music! 🎵🔥 ${widget.opponentName} vs Me!',
        subject: 'WeAfrica Music Battle',
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

  void _showEndBattleDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.grassDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('End Battle?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ending now will forfeit the battle. Your opponent wins automatically.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            _summaryRow('Your Score', '$_myScore'),
            _summaryRow('Opponent Score', '$_opponentScore'),
            _summaryRow('Total Earnings', '$_totalEarnings coins'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _forfeitBattle();
            },
            child: const Text('Forfeit', style: TextStyle(color: AppColors.liveRed)),
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

  Future<void> _forfeitBattle() async {
      setState(() {
        _isEndingBattle = true;
      });

      try {
        debugPrint('🔴 END BATTLE liveSessionId=${widget.liveSessionId}');

        if (widget.liveSessionId != null && widget.liveSessionId!.isNotEmpty) {
          final now = DateTime.now().toUtc().toIso8601String();

          final updated = await Supabase.instance.client
              .from('live_sessions')
              .update({
                'is_live': false,
                'status': 'ended',
                'ended_at': now,
                'updated_at': now,
              })
              .eq('id', widget.liveSessionId!)
              .select('id,is_live,status,ended_at');

          debugPrint('✅ Battle ended: $updated');
        } else {
          debugPrint('❌ liveSessionId missing in battle');
        }
      } catch (e) {
        debugPrint('❌ Failed to end battle: $e');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BattleResultScreen(
              isWinner: false,
              isForfeit: true,
              myScore: _myScore,
              opponentScore: _opponentScore,
              opponentName: widget.opponentName,
              duration: 20 - (_timeRemaining ~/ 60),
            ),
          ),
        );
      }
    }

  void _showBattleWonDialog() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BattleResultScreen(
              isWinner: true,
              isForfeit: false,
              myScore: _myScore,
              opponentScore: _opponentScore,
              opponentName: widget.opponentName,
              duration: 20 - (_timeRemaining ~/ 60),
            ),
          ),
        );
      }
    });
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
    _scoreSubscription?.cancel();
    _giftSubscription?.cancel();
    _commentsSubscription?.cancel();
    _viewerSubscription?.cancel();
    _reactionsSubscription?.cancel();
    _commentController.dispose();
    _commentsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main video (self or opponent)
          GestureDetector(
            onTap: _swapVideos,
            child: _isOpponentBig
                ? Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.grey[900],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: const BoxDecoration(
                              color: AppColors.battleAmber,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person,
                                size: 50, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.opponentName,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.grassMint.withValues(alpha: ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                  color: AppColors.grassMint,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _cameraController != null && _cameraController!.value.isInitialized && !_isCameraOff
                    ? SizedBox.expand(child: CameraPreview(_cameraController!))
                    : Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.grey[900],
                        child: const Center(
                          child: Icon(Icons.videocam_off, size: 80, color: Colors.white24),
                        ),
                      ),
          ),

          // Gradient overlay
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
              bottom: 200 + (index * 30),
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

          // Floating PiP video
          Positioned(
            top: 100,
            right: 16,
            child: GestureDetector(
              onTap: _swapVideos,
              child: Hero(
                tag: 'pip-video',
                child: Container(
                  width: 130,
                  height: 170,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.battleAmber.withValues(alpha: ),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: ),
                        blurRadius: 25,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        _isOpponentBig
                            ? (_cameraController != null &&
                                    _cameraController!.value.isInitialized
                                ? CameraPreview(_cameraController!)
                                : Container(color: Colors.grey[900]))
                            : Container(
                                color: Colors.grey[900],
                                child: const Center(
                                  child: Icon(Icons.person,
                                      color: Colors.white24, size: 28),
                                ),
                              ),
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _isOpponentBig ? 'You' : widget.opponentName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top battle bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Battle header
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
                      // Share button
                      GestureDetector(
                        onTap: _shareBattle,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.share,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Score bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: )),
                    ),
                    child: Row(
                      children: [
                        // My score
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'YOU',
                                style: TextStyle(
                                  color: AppColors.grassMint,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_myScore',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: _myScoreRatio,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppColors.grassBright,
                                          AppColors.grassMint
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // VS + Timer
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.battleAmber.withValues(alpha: ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'VS',
                                style: TextStyle(
                                  color: AppColors.battleAmber,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.liveRed.withValues(alpha: ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.liveRed.withValues(alpha: )),
                              ),
                              child: Text(
                                _timerText,
                                style: const TextStyle(
                                  color: AppColors.liveRed,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        // Opponent score
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                widget.opponentName.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.battleAmberLight,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_opponentScore',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: _opponentScoreRatio,
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppColors.battleAmberLight,
                                          AppColors.battleAmber
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Goal Progress Bars (Left Side)
          Positioned(
            left: 16,
            top: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _goals.map((goal) {
                final progress = (goal.current / goal.target).clamp(0.0, 1.0);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(goal.icon, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            '${goal.current}/${goal.target}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 80,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(goal.color),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Earnings Summary (Top Right, below PiP)
          Positioned(
            top: 160,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.coinGold.withValues(alpha: )),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_money, color: AppColors.coinGold, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '$_totalEarnings',
                    style: const TextStyle(
                      color: AppColors.coinGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Comments Overlay (if enabled)
          if (_showCommentsOverlay && _comments.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 220,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 100),
                child: ListView.builder(
                  controller: _commentsScrollController,
                  reverse: true,
                  itemCount: _comments.take(4).length,
                  itemBuilder: (context, index) {
                    final comment = _comments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
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
              bottom: 240,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.grassMint.withValues(alpha: )),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.music_note,
                            color: AppColors.grassMint, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _djQueue[_currentTrackIndex],
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _toggleDjPlayback,
                          icon: Icon(
                            _isDjPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.grassMint,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          onPressed: _skipDjTrack,
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
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
                        IconButton(
                          onPressed: _toggleDjReverb,
                          icon: Icon(
                            Icons.audio_file,
                            color: _djReverbEnabled
                                ? AppColors.grassMint
                                : Colors.white54,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          onPressed: _toggleDjEcho,
                          icon: Icon(
                            Icons.waves,
                            color: _djEchoEnabled
                                ? AppColors.grassMint
                                : Colors.white54,
                            size: 18,
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

          // Bottom section
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
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
                        margin: const EdgeInsets.only(bottom: 10),
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
                                    hintText: 'Cheer them on...',
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
                                    color: Colors.black, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Control buttons row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
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

                        // End Battle
                        _controlButton(
                          icon: Icons.flag,
                          label: 'End',
                          onTap: _showEndBattleDialog,
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

          // Ending Battle Overlay
          if (_isEndingBattle)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.battleAmber),
                    SizedBox(height: 20),
                    Text(
                      'Ending battle...',
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: buttonColor.withValues(alpha: ),
              shape: BoxShape.circle,
              border: Border.all(color: buttonColor.withValues(alpha: )),
            ),
            child: Icon(icon, color: buttonColor, size: 20),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: buttonColor,
              fontSize: 9,
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