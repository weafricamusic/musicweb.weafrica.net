import 'package:flutter/material.dart';

import '../providers/ads_provider.dart';
import '../services/analytics_ad_service.dart';
import '../screens/watch_and_earn_screen.dart';

/// WeAfrica Music Soft Paywall
/// 
/// Shows when user tries to use a premium feature without coins
/// Offers: Watch Ad OR Buy Coins
class SoftPaywall extends StatelessWidget {
  const SoftPaywall({
    super.key,
    required this.title,
    required this.message,
    required this.coinsNeeded,
    this.onWatchAd,
    this.onBuyCoins,
    this.onDismiss,
  });

  final String title;
  final String message;
  final int coinsNeeded;
  final VoidCallback? onWatchAd;
  final VoidCallback? onBuyCoins;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
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
            color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Color(0xFFD4AF37),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            
            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            
            // Coins needed
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Need $coinsNeeded coins',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Watch Ad Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  AnalyticsAdService.instance.logPaywallWatchAdClicked();
                  Navigator.of(context).pop();
                  onWatchAd?.call();
                  _openWatchAndEarn(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: const Color(0xFF1A2F1A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.videocam),
                label: const Text(
                  'Watch Ad & Earn',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Buy Coins Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onBuyCoins?.call();
                  // TODO: Navigate to coin purchase
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart),
                label: const Text(
                  'Buy Coins',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Dismiss
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDismiss?.call();
              },
              child: Text(
                'Maybe Later',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openWatchAndEarn(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WatchAndEarnScreen(),
      ),
    );
  }

  /// Show soft paywall
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    required int coinsNeeded,
    VoidCallback? onWatchAd,
    VoidCallback? onBuyCoins,
    VoidCallback? onDismiss,
  }) async {
    // Track analytics
    AnalyticsAdService.instance.logSoftPaywallShown(
      context: title,
    );

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => SoftPaywall(
        title: title,
        message: message,
        coinsNeeded: coinsNeeded,
        onWatchAd: onWatchAd,
        onBuyCoins: onBuyCoins,
        onDismiss: onDismiss,
      ),
    );
  }
}