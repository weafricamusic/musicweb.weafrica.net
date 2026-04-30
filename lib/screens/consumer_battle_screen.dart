import 'package:flutter/material.dart';
import '../shared/theme/app_colors.dart';

class ConsumerBattleScreen extends StatefulWidget {
  const ConsumerBattleScreen({super.key});

  @override
  State<ConsumerBattleScreen> createState() => _ConsumerBattleScreenState();
}

class _ConsumerBattleScreenState extends State<ConsumerBattleScreen> {
  String _selectedArtist = 'A'; // 'A' or 'B' for gift target
  int _artistAScore = 1200;
  int _artistBScore = 890;
  int _timeRemaining = 1200;
  final TextEditingController _commentController = TextEditingController();
  final List<Map<String, dynamic>> _comments = [
    {'user': 'Fan123', 'text': 'Sarah is killing it! 🔥'},
    {'user': 'MusicLvr', 'text': 'DJ Mike dropped the beat!'},
    {'user': 'BattleFan', 'text': 'This is the best battle ever'},
  ];

  String get _timerText {
    final mins = _timeRemaining ~/ 60;
    final secs = _timeRemaining % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        if (_timeRemaining > 0) _timeRemaining--;
      });
      return _timeRemaining > 0;
    });
  }

  void _selectArtist(String artist) {
    setState(() => _selectedArtist = artist);
  }

  void _sendComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _comments.add({'user': 'You', 'text': text});
      _commentController.clear();
    });
  }

  void _showGiftSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.grassMid,
              AppColors.grassDark,
            ],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Selected target indicator
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedArtist == 'A'
                      ? AppColors.grassMint.withValues(alpha: )
                      : AppColors.battleAmber.withValues(alpha: ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedArtist == 'A' ? AppColors.grassMint : AppColors.battleAmber,
                        width: 3,
                      ),
                    ),
                    child: const Center(child: Icon(Icons.person, color: Colors.white30)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sending gift to',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: ),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedArtist == 'A' ? 'Sarah Chen' : 'DJ Mike',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Switch target
                  GestureDetector(
                    onTap: () => _selectArtist(_selectedArtist == 'A' ? 'B' : 'A'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Switch',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Coins
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on, color: AppColors.coinGold, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '1,250',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ' coins',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: ),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Gift grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.count(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _giftItem('🌹', 'Rose', '1'),
                    _giftItem('☕', 'Coffee', '5'),
                    _giftItem('🎤', 'Mic', '10'),
                    _giftItem('🎸', 'Guitar', '50'),
                    _giftItem('👑', 'Crown', '100'),
                    _giftItem('💎', 'Diamond', '500'),
                    _giftItem('🚀', 'Rocket', '1000'),
                    _giftItem('🌌', 'Galaxy', '5000'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _giftItem(String emoji, String name, String price) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        setState(() {
          if (_selectedArtist == 'A') {
            _artistAScore += int.parse(price);
          } else {
            _artistBScore += int.parse(price);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent $emoji $name to ${_selectedArtist == 'A' ? 'Sarah' : 'DJ Mike'}!'),
            backgroundColor: AppColors.grassDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: )),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              price,
              style: const TextStyle(
                color: AppColors.coinGold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Split video area
          Expanded(
            child: Row(
              children: [
                // Artist A (Sarah)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectArtist('A'),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                        ),
                        border: Border.all(
                          color: _selectedArtist == 'A'
                              ? AppColors.grassMint.withValues(alpha: )
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Placeholder
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person, color: Colors.white24, size: 28),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Sarah Chen',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Top info
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 8,
                            left: 8,
                            right: 8,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.liveRed,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.visibility, size: 12, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                        '2.1K',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Score overlay
                          Positioned(
                            bottom: 12,
                            left: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.monetization_on, size: 14, color: AppColors.coinGold),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_artistAScore',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Selected indicator
                          if (_selectedArtist == 'A')
                            Positioned(
                              top: MediaQuery.of(context).padding.top + 40,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.grassMint.withValues(alpha: ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'SUPPORTING',
                                    style: TextStyle(
                                      color: AppColors.grassDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Divider
                Container(
                  width: 2,
                  color: Colors.white.withValues(alpha: ),
                ),
                // Artist B (DJ Mike)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectArtist('B'),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [Color(0xFF16213e), Color(0xFF0f172a)],
                        ),
                        border: Border.all(
                          color: _selectedArtist == 'B'
                              ? AppColors.battleAmber.withValues(alpha: )
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person, color: Colors.white24, size: 28),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'DJ Mike',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 8,
                            left: 8,
                            right: 8,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.liveRed,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.visibility, size: 12, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                        '890',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 12,
                            left: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.monetization_on, size: 14, color: AppColors.coinGold),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_artistBScore',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_selectedArtist == 'B')
                            Positioned(
                              top: MediaQuery.of(context).padding.top + 40,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.battleAmber.withValues(alpha: ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'SUPPORTING',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: ),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: )),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.battleAmber, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'BATTLE',
                  style: TextStyle(
                    color: AppColors.battleAmber,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.liveRed.withValues(alpha: ),
                    borderRadius: BorderRadius.circular(8),
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
                const Spacer(),
                Text(
                  'Total: ${_artistAScore + _artistBScore}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: ),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Comments + Input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final comment = _comments[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${comment['user']} ',
                                      style: const TextStyle(
                                        color: AppColors.coinGold,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: comment['text'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
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
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: )),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.emoji_emotions, size: 18, color: Colors.white.withValues(alpha: )),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Say something...',
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: )),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onSubmitted: (_) => _sendComment(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendComment,
                      child: const Icon(Icons.send, color: Colors.blueAccent, size: 22),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showGiftSheet,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.battleAmberLight, AppColors.battleAmber],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.card_giftcard, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.liveRed.withValues(alpha: ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}