import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../models/battle_status.dart';

/// Battle Result Screen - Shows winner announcement with confetti animation
/// Used by both performers and viewers after battle ends
class BattleResultScreen extends StatefulWidget {
  const BattleResultScreen({
    super.key,
    required this.status,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.onShare,
    required this.onContinue,
    this.isHost = false,
  });

  final BattleStatus status;
  final String competitor1Name;
  final String competitor2Name;
  final VoidCallback onShare;
  final VoidCallback onContinue;
  final bool isHost;

  @override
  State<BattleResultScreen> createState() => _BattleResultScreenState();
}

class _BattleResultScreenState extends State<BattleResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Start scale animation after a short delay
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _scaleController.forward();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  String get _winnerName {
    if (widget.status.isDraw == true) return 'It\'s a Draw!';
    final winnerId = widget.status.winnerUid?.trim();
    if (winnerId == null) return 'Battle Ended';
    if (winnerId == widget.status.competitor1Id?.trim()) return widget.competitor1Name;
    return widget.competitor2Name;
  }

  String get _winnerLabel {
    if (widget.status.isDraw == true) return 'DRAW';
    return 'WINNER';
  }

  Color get _winnerColor {
    if (widget.status.isDraw == true) return WeAfricaColors.gold;
    return const Color(0xFF4CAF50);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      body: Stack(
        children: [
          // Confetti animation
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _ConfettiPainter(
                    progress: _confettiController.value,
                  ),
                );
              },
            ),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Trophy icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _winnerColor,
                              _winnerColor.withValues(alpha: 0.7),
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _winnerColor.withValues(alpha: 0.4),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Winner label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _winnerColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _winnerColor.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _winnerLabel,
                          style: TextStyle(
                            color: _winnerColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Winner name
                      Text(
                        _winnerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      // Score display
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildScoreColumn(
                              widget.competitor1Name,
                              widget.status.competitor1Score ?? 0,
                              widget.status.winnerUid == widget.status.competitor1Id,
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: WeAfricaColors.gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'VS',
                                style: TextStyle(
                                  color: WeAfricaColors.gold,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _buildScoreColumn(
                              widget.competitor2Name,
                              widget.status.competitor2Score ?? 0,
                              widget.status.winnerUid == widget.status.competitor2Id,
                              isRight: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Top supporter (if available)
                      if (widget.status.topSupporterName?.isNotEmpty == true)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                WeAfricaColors.gold.withValues(alpha: 0.2),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: WeAfricaColors.gold.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.favorite,
                                color: WeAfricaColors.gold,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Top Supporter',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    widget.status.topSupporterName!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 40),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: widget.onShare,
                              icon: const Icon(Icons.share),
                              label: const Text('Share Result'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: widget.onContinue,
                              icon: const Icon(Icons.arrow_forward),
                              label: Text(widget.isHost ? 'Continue' : 'Keep Watching'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WeAfricaColors.gold,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreColumn(String name, int score, bool isWinner, {bool isRight = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWinner && !isRight) ...[
              const Icon(
                Icons.emoji_events,
                color: WeAfricaColors.gold,
                size: 16,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              score.toString(),
              style: TextStyle(
                color: isWinner ? WeAfricaColors.gold : Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (isWinner && isRight) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.emoji_events,
                color: WeAfricaColors.gold,
                size: 16,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Custom painter for confetti animation
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // Fixed seed for consistent animation
    const confettiCount = 50;
    
    for (int i = 0; i < confettiCount; i++) {
      final x = random.nextDouble() * size.width;
      final y = (random.nextDouble() * size.height * 1.5) - (size.height * 0.5);
      final rotation = random.nextDouble() * math.pi * 2;
      final fallProgress = (progress + random.nextDouble()) % 1.0;
      final currentY = y + (fallProgress * size.height);
      
      if (currentY > size.height || currentY < 0) continue;
      
      final colors = [
        WeAfricaColors.gold,
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.purple,
        Colors.orange,
      ];
      final color = colors[i % colors.length];
      
      final rect = Rect.fromCenter(
        center: Offset(x, currentY),
        width: 8,
        height: 8,
      );
      
      canvas.save();
      canvas.translate(x, currentY);
      canvas.rotate(rotation + (fallProgress * math.pi));
      
      final paint = Paint()..color = color.withValues(alpha: 1 - fallProgress);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 8, height: 8), paint);
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}