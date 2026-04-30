import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ad_reward_result.dart';
import '../services/admob_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/banner_ad_service.dart';

/// WeAfrica Music Ads Provider
/// 
/// Central state management for ads (Premium check, coin rewards, etc)
class AdsProvider extends ChangeNotifier {
  AdsProvider._();
  static final AdsProvider instance = AdsProvider._();

  bool _isPremium = false;
  bool _isLoading = false;
  int _availableRewardedAds = 5; // Daily limit
  int _coinsPerAd = 10;

  // Getters
  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;
  int get availableRewardedAds => _availableRewardedAds;
  int get coinsPerAd => _coinsPerAd;
  bool get canWatchAd => !_isPremium && _availableRewardedAds > 0;
  bool get showBannerAds => !_isPremium;
  bool get showInterstitialAds => !_isPremium;

  /// Initialize ads system
  Future<void> initialize() async {
    await AdMobService.instance.initialize();
    
    // Preload ads
    if (!kIsWeb) {
      await RewardedAdService.instance.loadAd();
      await InterstitialAdService.instance.loadAd();
    }
  }

  /// Set premium status (hide ads for premium users)
  void setPremiumStatus(bool isPremium) {
    if (_isPremium != isPremium) {
      _isPremium = isPremium;
      notifyListeners();
    }
  }

  /// Watch rewarded ad and earn coins
  Future<AdRewardResult> watchRewardedAd() async {
    if (_isPremium) {
      return AdRewardResult.failure('Premium users cannot watch ads for coins');
    }

    if (_availableRewardedAds <= 0) {
      return AdRewardResult.failure('Daily ad limit reached');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final result = await RewardedAdService.instance.showAd(
        coinReward: _coinsPerAd,
      );

      if (result.success) {
        _availableRewardedAds--;
        notifyListeners();
      }

      _isLoading = false;
      notifyListeners();

      return result;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return AdRewardResult.failure('Error showing ad: $e');
    }
  }

  /// Show interstitial ad (called automatically after songs)
  Future<bool> showInterstitialAd() async {
    if (_isPremium) return false;

    return await InterstitialAdService.instance.maybeShowAd();
  }

  /// Reset daily ad limits
  void resetDailyLimits() {
    _availableRewardedAds = 5;
    notifyListeners();
  }

  /// Set coins per ad
  void setCoinsPerAd(int coins) {
    _coinsPerAd = coins;
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    RewardedAdService.instance.dispose();
    InterstitialAdService.instance.dispose();
    BannerAdService.instance.dispose();
    super.dispose();
  }
}