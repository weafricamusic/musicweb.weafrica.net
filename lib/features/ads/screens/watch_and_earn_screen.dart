import 'package:flutter/material.dart';

import '../providers/ads_provider.dart';
import '../widgets/watch_ad_button.dart';
import '../widgets/reward_success_dialog.dart';
import '../widgets/ad_loading_dialog.dart';

/// WeAfrica Music Watch and Earn Screen
/// 
/// Main screen for watching ads to earn coins
class WatchAndEarnScreen extends StatefulWidget {
  const WatchAndEarnScreen({super.key});

  @override
  State<WatchAndEarnScreen> createState() => _WatchAndEarnScreenState();
}

class _WatchAndEarnScreenState extends State<WatchAndEarnScreen> {
  bool _isLoading = false;
  int _coinsEarned = 0;

  @override
  void initState() {
    super.initState();
    // Preload ad
    AdsProvider.instance.initialize();
  }

  Future<void> _watchAd() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // Show loading dialog
    AdLoadingDialog.show(context);

    // Watch ad
    final result = await AdsProvider.instance.watchRewardedAd();

    // Hide loading dialog
    if (mounted) AdLoadingDialog.hide(context);

    if (mounted) {
      setState(() => _isLoading = false);

      if (result.success) {
        setState(() => _coinsEarned += result.coinsEarned);
        
        // Show success dialog
        RewardSuccessDialog.show(
          context,
          coinsEarned: result.coinsEarned,
        );
      } else {
        // Show error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Failed to earn reward'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = AdsProvider.instance;
    final coinsPerAd = provider.coinsPerAd;
    final availableAds = provider.availableRewardedAds;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0A), // Deep green-black
      appBar: AppBar(
        title: const Text('Watch & Earn'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              
              // Coin icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFD4AF37),
                      Color(0xFFE5C158),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.monetization_on,
                  color: Color(0xFF1A2F1A),
                  size: 64,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Earn Free Coins',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Subtitle
              Text(
                'Watch short ads to earn coins and support your favorite artists',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Reward info card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2F1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam,
                          color: Color(0xFFD4AF37),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Watch 1 Ad',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.2),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.monetization_on,
                                color: Color(0xFFD4AF37),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '+$coinsPerAd',
                                style: const TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Divider
                    Divider(
                      color: Colors.white.withValues(alpha: 0.2),
                      height: 1,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Daily limit info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.white.withValues(alpha: 0.2),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$availableAds ads remaining today',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.2),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Watch ad button
              if (provider.canWatchAd) ...[
                WatchAdButton(
                  onPressed: _watchAd,
                  coins: coinsPerAd,
                  isLoading: _isLoading,
                ),
              ] else if (provider.isPremium) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star,
                        color: Color(0xFFD4AF37),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Premium users have unlimited coins',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2F1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.hourglass_empty,
                        color: Colors.red,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Daily limit reached. Come back tomorrow!',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}