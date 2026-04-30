import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';
import 'analytics_ad_service.dart';

/// WeAfrica Music Interstitial Ad Service
/// 
/// Manages interstitial ads shown between songs
/// Features: Cooldown, Smart timing, Analytics, Fail-safe
class InterstitialAdService {
  InterstitialAdService._();
  static final InterstitialAdService instance = InterstitialAdService._();

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;
  int _songsPlayedCount = 0;
  static const int _songsBeforeAd = 4; // Show ad after every 4 songs
  
  // Cooldown to prevent spam
  DateTime? _lastAdShown;
  static const Duration _minCooldown = Duration(minutes: 3);

  /// Load an interstitial ad
  Future<bool> loadAd() async {
    if (!AdMobService.instance.isSupported) {
      debugPrint('Interstitial ads not supported on web');
      return false;
    }

    if (_isLoading) return false;
    if (_interstitialAd != null) return true;

    _isLoading = true;

    try {
      await InterstitialAd.load(
        adUnitId: AdMobService.instance.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('✅ Interstitial ad loaded');
            _interstitialAd = ad;
            _isLoading = false;
          },
          onAdFailedToLoad: (error) {
            debugPrint('⚠️ Interstitial ad failed to load: $error');
            _interstitialAd = null;
            _isLoading = false;
            
            // Track failure
            AnalyticsAdService.instance.logAdFailed(
              adType: 'interstitial',
              error: error.message,
            );
            
            // Retry after delay
            Future.delayed(const Duration(seconds: 30), loadAd);
          },
        ),
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ Error loading interstitial ad: $e');
      _isLoading = false;
      
      AnalyticsAdService.instance.logAdFailed(
        adType: 'interstitial',
        error: e.toString(),
      );
      
      return false;
    }
  }

  /// Check if we can show ad (cooldown check)
  bool get canShowAd {
    if (_lastAdShown == null) return true;
    return DateTime.now().difference(_lastAdShown!) > _minCooldown;
  }

  /// Increment song play count and show ad if needed
  /// Returns true if ad was shown
  Future<bool> maybeShowAd({
    void Function()? onAdShowed,
    void Function()? onAdDismissed,
    bool forceShow = false,
  }) async {
    if (!AdMobService.instance.isSupported) return false;

    _songsPlayedCount++;

    // Check cooldown and song count
    if (!forceShow) {
      if (_songsPlayedCount < _songsBeforeAd) return false;
      if (!canShowAd) {
        debugPrint('⏳ Interstitial on cooldown');
        return false;
      }
    }

    // Reset counter
    _songsPlayedCount = 0;

    // FAIL-SAFE: Load ad if needed
    if (_interstitialAd == null) {
      final loaded = await loadAd();
      if (!loaded || _interstitialAd == null) {
        debugPrint('⚠️ Interstitial not ready, will retry');
        // Auto-retry for next time
        Future.delayed(const Duration(seconds: 5), loadAd);
        return false;
      }
    }

    final completer = Completer<bool>();

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('📺 Interstitial ad showed');
        _lastAdShown = DateTime.now();
        onAdShowed?.call();
        
        // Track analytics
        AnalyticsAdService.instance.logInterstitialShown(
          adUnitId: ad.adUnitId,
          songsPlayed: _songsBeforeAd,
        );
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('📺 Interstitial ad dismissed');
        ad.dispose();
        _interstitialAd = null;
        onAdDismissed?.call();
        
        if (!completer.isCompleted) {
          completer.complete(true);
        }
        
        // Preload next ad immediately
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('⚠️ Interstitial ad failed to show: $error');
        ad.dispose();
        _interstitialAd = null;
        
        AnalyticsAdService.instance.logAdFailed(
          adType: 'interstitial_show',
          error: error.message,
        );
        
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        
        // Retry load
        loadAd();
      },
    );

    _interstitialAd!.show();
    return completer.future;
  }

  /// Force show interstitial ad immediately (respects cooldown)
  Future<bool> showAd({
    void Function()? onAdShowed,
    void Function()? onAdDismissed,
  }) async {
    return maybeShowAd(
      onAdShowed: onAdShowed,
      onAdDismissed: onAdDismissed,
      forceShow: true,
    );
  }

  /// Reset song counter
  void resetCounter() {
    _songsPlayedCount = 0;
  }

  /// Get current song count
  int get songsPlayedCount => _songsPlayedCount;

  /// Get songs remaining before next ad
  int get songsUntilNextAd => _songsBeforeAd - _songsPlayedCount;

  /// Get time until next ad allowed
  Duration? get timeUntilNextAd {
    if (_lastAdShown == null) return null;
    final elapsed = DateTime.now().difference(_lastAdShown!);
    if (elapsed >= _minCooldown) return null;
    return _minCooldown - elapsed;
  }

  /// Check if ad is ready
  bool get isAdReady => _interstitialAd != null;

  /// Dispose
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
