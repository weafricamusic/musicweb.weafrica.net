import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../shared/theme/app_colors.dart';

class BattleResultScreen extends StatefulWidget {
  final bool isWinner;
  final bool isForfeit;
  final int myScore;
  final int opponentScore;
  final String opponentName;
  final int duration; // in minutes

  const BattleResultScreen({
    super.key,
    required this.isWinner,
    required this.isForfeit,
    required this.myScore,
    required this.opponentScore,
    required this.opponentName,
    required this.duration,
  });

  @override
  State<BattleResultScreen> createState() => _BattleResultScreenState();
}

class _BattleResultScreenState extends State<BattleResultScreen>
    with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _animationController.forward();

    if (widget.isWinner && !widget.isForfeit) {
      _confettiController.play();
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.isWinner
                    ? [
                        AppColors.grassDark,
                        AppColors.grassMint.withValues(alpha: ),
                        Colors.black,
                      ]
                    : [
                        Colors.black,
                        AppColors.liveRed.withValues(alpha: ),
                        Colors.black,
                      ],
              ),
            ),
          ),

          // Confetti (for winner)
          if (widget.isWinner && !widget.isForfeit)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                particleDrag: 0.05,
                emissionFrequency: 0.05,
                numberOfParticles: 30,
                gravity: 0.1,
                colors: const [
                  AppColors.grassMint,
                  AppColors.battleAmber,
                  Colors.pink,
                  Colors.blue,
                  Colors.orange,
                  Colors.purple,
                ],
              ),
            ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Result icon and text
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Column(
                        children: [
                          // Trophy or Sad icon
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: widget.isWinner
                                  ? AppColors.battleAmber.withValues(alpha: )
                                  : Colors.white.withValues(alpha: ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.isWinner
                                    ? AppColors.battleAmber
                                    : Colors.white24,
                                width: 3,
                              ),
                              boxShadow: widget.isWinner
                                  ? [
                                      BoxShadow(
                                        color: AppColors.battleAmber
                                            .withValues(alpha: ),
                                        blurRadius: 30,
                                        spreadRadius: 5,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Icon(
                              widget.isWinner
                                  ? Icons.emoji_events
                                  : Icons.sentiment_dissatisfied,
                              size: 60,
                              color: widget.isWinner
                                  ? AppColors.battleAmber
                                  : Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Result text
                          Text(
                            widget.isWinner
                                ? (widget.isForfeit
                                    ? 'OPPONENT FORFEITED'
                                    : 'VICTORY!')
                                : (widget.isForfeit
                                    ? 'YOU FORFEITED'
                                    : 'DEFEAT'),
                            style: TextStyle(
                              color: widget.isWinner
                                  ? AppColors.battleAmber
                                  : AppColors.liveRed,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Score card
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: ),
                        ),
                      ),
                      child: Column(
                        children: [
                          // My score
                          _scoreRow(
                            label: 'Your Score',
                            value: widget.myScore.toString(),
                            isWinner: widget.isWinner,
                            isMe: true,
                          ),
                          const SizedBox(height: 16),

                          // VS divider
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.battleAmber.withValues(alpha: ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'VS',
                              style: TextStyle(
                                color: AppColors.battleAmber,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Opponent score
                          _scoreRow(
                            label: widget.opponentName,
                            value: widget.opponentScore.toString(),
                            isWinner: !widget.isWinner,
                            isMe: false,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Stats
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _statCard(
                          icon: Icons.timer,
                          label: 'Duration',
                          value: '${widget.duration}m',
                        ),
                        _statCard(
                          icon: Icons.star,
                          label: 'Total Score',
                          value: '${widget.myScore + widget.opponentScore}',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Buttons
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        // Share button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Share result
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Share feature coming soon!'),
                                  backgroundColor: AppColors.grassMint,
                                ),
                              );
                            },
                            icon: const Icon(Icons.share, size: 24),
                            label: const Text(
                              'Share Result',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.battleAmber,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Go back home button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/home',
                                (route) => false,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: Colors.white24,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Go Home',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
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
          ),
        ],
      ),
    );
  }

  Widget _scoreRow({
    required String label,
    required String value,
    required bool isWinner,
    required bool isMe,
  }) {
    return Row(
      children: [
        // Avatar placeholder
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isWinner ? AppColors.grassMint : Colors.white24,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isMe ? Icons.person : Icons.person_outline,
            color: isWinner ? Colors.black : Colors.white70,
          ),
        ),
        const SizedBox(width: 16),

        // Label and score
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: ),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: isWinner ? AppColors.grassMint : Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),

        // Winner crown
        if (isWinner)
          const Icon(
            Icons.emoji_events,
            color: AppColors.battleAmber,
            size: 32,
          ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: )),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.grassMint, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: ),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}