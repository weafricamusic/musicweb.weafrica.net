import 'package:flutter/material.dart';

import '../services/gift_service.dart';

/// WeAfrica Send Gift Dialog
/// 
/// Allows fans to send virtual gifts to artists during battles/live
class SendGiftDialog extends StatelessWidget {
  const SendGiftDialog({
    super.key,
    required this.artistName,
    required this.userCoins,
    required this.onGiftSent,
  });

  final String artistName;
  final int userCoins;
  final Function(GiftItem gift)? onGiftSent;

  @override
  Widget build(BuildContext context) {
    final gifts = GiftService.instance.availableGifts;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A2F1A),
              Color(0xFF0F1F0F),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              'Send Gift to $artistName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Balance: $userCoins coins',
              style: TextStyle(
                color: const Color(0xFFD4AF37),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),

            // Gift Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: gifts.length,
              itemBuilder: (context, index) {
                final gift = gifts[index];
                final canAfford = userCoins >= gift.coinCost;

                return GestureDetector(
                  onTap: canAfford
                      ? () {
                          Navigator.of(context).pop();
                          onGiftSent?.call(gift);
                        }
                      : null,
                  child: Opacity(
                    opacity: canAfford ? 1.0 : 0.4,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            gift.emoji,
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            gift.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${gift.coinCost}',
                              style: const TextStyle(
                                color: Color(0xFFD4AF37),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Close button
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show the dialog
  static Future<void> show({
    required BuildContext context,
    required String artistName,
    required int userCoins,
    Function(GiftItem gift)? onGiftSent,
  }) {
    return showDialog(
      context: context,
      builder: (context) => SendGiftDialog(
        artistName: artistName,
        userCoins: userCoins,
        onGiftSent: onGiftSent,
      ),
    );
  }
}