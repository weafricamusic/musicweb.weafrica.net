import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/battle_bloc.dart';

class BattleResultScreen extends StatelessWidget {
  final BattleEnded result;

  const BattleResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isDraw = result.winnerName == null;
    final isArtistAWinner = result.winnerName == result.artistAName;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              _buildResultBadge(isDraw, isArtistAWinner),
              const SizedBox(height: 40),
              Row(
                children: [
                  _buildScoreCard(
                    result.artistAName,
                    result.artistAScore,
                    isArtistAWinner && !isDraw,
                  ),
                  const SizedBox(width: 16),
                  _buildScoreCard(
                    result.artistBName,
                    result.artistBScore,
                    !isArtistAWinner && !isDraw,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildStatsGrid(),
              const Spacer(),
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultBadge(bool isDraw, bool isArtistAWinner) {
    String title;
    IconData icon;
    Color color;

    if (isDraw) {
      title = 'DRAW';
      icon = Icons.handshake;
      color = AppTheme.accentCyan;
    } else if (isArtistAWinner) {
      title = '🏆 WINNER';
      icon = Icons.emoji_events;
      color = AppTheme.accentGold;
    } else {
      title = 'CLOSE ONE!';
      icon = Icons.military_tech;
      color = Colors.white70;
    }

    return Column(
      children: [
        Icon(icon, size: 64, color: color)
            .animate()
            .scale(duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 2,
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),
      ],
    );
  }

  Widget _buildScoreCard(String name, int score, bool isWinner) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: isWinner
              ? Border.all(color: AppTheme.accentGold, width: 2)
              : null,
          boxShadow: isWinner
              ? [
                  BoxShadow(
                    color: AppTheme.accentGold.withValues(alpha: ),
                    blurRadius: 20,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            if (isWinner)
              const Icon(Icons.emoji_events, color: AppTheme.accentGold, size: 28)
                  .animate()
                  .shake(),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '$score',
              style: TextStyle(
                color: isWinner ? AppTheme.accentGold : Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'points',
              style: TextStyle(
                color: Colors.white.withValues(alpha: ),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ).animate().fadeIn().slideX(
            begin: isWinner ? -0.3 : 0.3,
            delay: 300.ms,
          ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      {'label': 'Duration', 'value': '20:00'},
      {'label': 'Total Gifts', 'value': '${result.artistAScore + result.artistBScore}'},
      {'label': 'Peak Viewers', 'value': '3.2K'},
      {'label': 'New Followers', 'value': '+45'},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stats[index]['label']!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: ),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stats[index]['value']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: (400 + index * 100).ms);
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        _actionButton(
          'Continue Live Solo',
          Icons.videocam,
          () {},
          isPrimary: true,
        ),
        const SizedBox(height: 12),
        _actionButton(
          'Share Result',
          Icons.share,
          () {},
        ),
        const SizedBox(height: 12),
        _actionButton(
          'End Live',
          Icons.call_end,
          () => Navigator.pop(context),
          color: AppTheme.dangerRed,
        ),
      ],
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool isPrimary = false,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [AppTheme.primaryPurple, AppTheme.accentPink],
                )
              : null,
          color: color ?? (isPrimary ? null : AppTheme.surfaceColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.5);
  }
}