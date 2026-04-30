import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models/ad_reward_result.dart';
import 'admob_service.dart';
import 'analytics_ad_service.dart';

/// WeAfrica Music Rewarded Ad Service
/// 
/// Manages rewarded video ads for earning coins
/// Features: Dynamic rewards, Fail-safe, Analytics, Auto-retry
class RewardedAdService {
  RewardedAdService._();
  static final RewardedAdService instance = RewardedAdService._();

  RewardedAd? _rewardedAd;
  bool _isLoading = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  /// Callback when user earns reward
  final List<void Function(int coins)> _onRewardEarned = [];

  /// Add listener for reward earned
  void addOnRewardEarnedListener(void Function(int coins) listener) {
    _onRewardEarned.add(listener);
  }

  /// Remove listener
  void removeOnRewardEarnedListener(void Function(int coins) listener) {
    _onRewardEarned.remove(listener);
  }

  /// Get dynamic reward amount based on time/events
  int getRewardAmount({int baseAmount = 10}) {
    final hour = DateTime.now().hour;
    
    // Peak hours bonus (6 PM - 11 PM)
    if (hour >= 18 && hour <= 23) {
      return (baseAmount * 1.5).round(); // 15 coins
    }
    
    // Morning bonus (6 AM - 9 AM)
    if (hour >= 6 && hour <= 9) {
      return (baseAmount * 1.2).round(); // 12 coins
    }
    
    // Weekend bonus
    final weekday = DateTime.now().weekday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return (baseAmount * 1.3).round(); // 13 coins
    }
    
    return baseAmount; // 10 coins default
  }

  /// Load a rewarded ad
  Future<bool> loadAd() async {
    if (!AdMobService.instance.isSupported) {
      debugPrint('Rewarded ads not supported on web');
      return false;
    }

    if (_isLoading) return false;
    if (_rewardedAd != null) return true;

    _isLoading = true;

    try {
      await RewardedAd.load(
        adUnitId: AdMobService.instance.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('✅ Rewarded ad loaded');
            _rewardedAd = ad;
            _isLoading = false;
            _retryCount = 0;
          },
          onAdFailedToLoad: (error) {
            debugPrint('⚠️ Rewarded ad failed to load: $error');
            _rewardedAd = null;
            _isLoading = false;
            
            // Track failure
            AnalyticsAdService.instance.logAdFailed(
              adType: 'rewarded',
              error: error.message,
            );
            
            // Retry on failure with backoff
            if (_retryCount < _maxRetries) {
              _retryCount++;
              final delay = Duration(seconds: 2 * _retryCount);
              debugPrint('Retrying rewarded ad load (attempt $_retryCount) in ${delay.inSeconds}s');
              Future.delayed(delay, loadAd);
            }
          },
        ),
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ Error loading rewarded ad: $e');
      _isLoading = false;
      
      AnalyticsAdService.instance.logAdFailed(
        adType: 'rewarded',
        error: e.toString(),
      );
      
      return false;
    }
  }

  /// Show rewarded ad and return result
  /// FAIL-SAFE: Handles all error cases gracefully
  Future<AdRewardResult> showAd({
    int? coinReward,
    void Function()? onAdShowed,
    void Function()? onAdDismissed,
  }) async {
    if (!AdMobService.instance.isSupported) {
      return AdRewardResult.failure('Ads not supported on this platform');
    }

    // Use dynamic reward if not specified
    final rewardAmount = coinReward ?? getRewardAmount();

    // FAIL-SAFE: Load ad if not loaded
    if (_rewardedAd == null) {
      final loaded = await loadAd();
      if (!loaded) {
        return AdRewardResult.failure('Unable to load ad. Please try again.');
      }
      
      // Wait for ad to load
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (_rewardedAd == null) {
        return AdRewardResult.failure('Ad not ready. Please try again.');
      }
    }

    final completer = Completer<AdRewardResult>();

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('📺 Rewarded ad showed');
        onAdShowed?.call();
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('📺 Rewarded ad dismissed');
        ad.dispose();
        _rewardedAd = null;
        onAdDismissed?.call();
        
        if (!completer.isCompleted) {
          completer.complete(AdRewardResult.failure('Ad closed before reward'));
        }
        
        // Preload next ad immediately
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('⚠️ Rewarded ad failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        
        AnalyticsAdService.instance.logAdFailed(
          adType: 'rewarded_show',
          error: error.message,
        );
        
        if (!completer.isCompleted) {
          completer.complete(AdRewardResult.failure('Failed to show ad. Please try again.'));
        }
        
        // Retry load
        loadAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        debugPrint('🎁 User earned reward: ${reward.amount} ${reward.type}');
        
        // Track analytics
        AnalyticsAdService.instance.logRewardedAdWatched(
          rewardAmount: rewardAmount,
          adUnitId: ad.adUnitId,
        );
        
        // Notify listeners
        for (final listener in _onRewardEarned) {
          listener(rewardAmount);
        }
        
        if (!completer.isCompleted) {
          completer.complete(AdRewardResult.success(
            coinsEarned: rewardAmount,
            adId: ad.adUnitId,
          ));
        }
      },
    );

    return completer.future;
  }

  /// Check if ad is ready to show
  bool get isAdReady => _rewardedAd != null;

  /// Get current reward info
  Map<String, dynamic> getRewardInfo() {
    final base = 10;
    final current = getRewardAmount(baseAmount: base);
    final now = DateTime.now();
    final hour = now.hour;
    
    String bonusReason = '';
    if (hour >= 18 && hour <= 23) {
      bonusReason = '🔥 Peak hours bonus!';
    } else if (hour >= 6 && hour <= 9) {
      bonusReason = '🌅 Morning bonus!';
    } else if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      bonusReason = '🎉 Weekend bonus!';
    }
    
    return {
      'baseAmount': base,
      'currentAmount': current,
      'bonus': current > base,
      'bonusReason': bonusReason,
    };
  }

  /// Dispose current ad
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _onRewardEarned.clear();
  }
}
