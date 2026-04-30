import 'package:flutter/material.dart';
import '../../../app/theme/weafrica_colors.dart';

class BottomActionRail extends StatelessWidget {
  const BottomActionRail({
    super.key,
    required this.onGift,
    required this.onChatToggle,
    required this.showChat,
    this.onChallenge,
    this.isChallenging = false,
    this.showChallenge = false,
  });

  final VoidCallback onGift;
  final VoidCallback onChatToggle;
  final VoidCallback? onChallenge;
  final bool showChat;
  final bool isChallenging;
  final bool showChallenge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.22),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              icon: Icons.card_giftcard,
              label: 'Gift',
              onTap: onGift,
              color: Colors.pinkAccent,
            ),
            _ActionButton(
              icon: showChat ? Icons.chat : Icons.chat_bubble_outline,
              label: showChat ? 'Hide Chat' : 'Show Chat',
              onTap: onChatToggle,
              color: WeAfricaColors.gold,
            ),
            if (showChallenge)
              _ActionButton(
                icon: Icons.sports_mma,
                label: 'Challenge',
                onTap: onChallenge,
                color: WeAfricaColors.error,
                isLoading: isChallenging,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}