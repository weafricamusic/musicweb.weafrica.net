import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../providers/ads_provider.dart';

/// WeAfrica Music Watch Ad Button
/// 
/// Styled button to watch ads and earn coins
class WatchAdButton extends StatelessWidget {
  const WatchAdButton({
    super.key,
    required this.onPressed,
    this.coins = 10,
    this.isLoading = false,
    this.isEnabled = true,
  });

  final VoidCallback onPressed;
  final int coins;
  final bool isLoading;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled && !isLoading ? onPressed : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFD4AF37), // Gold
                Color(0xFFE5C158), // Light gold
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1A2F1A)),
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                const Icon(
                  Icons.play_circle_outline,
                  color: Color(0xFF1A2F1A),
                  size: 24,
                ),
                const SizedBox(width: 12),
              ],
              const Text(
                'Watch Ad',
                style: TextStyle(
                  color: Color(0xFF1A2F1A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2F1A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Color(0xFF1A2F1A),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '+$coins',
                      style: const TextStyle(
                        color: Color(0xFF1A2F1A),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}