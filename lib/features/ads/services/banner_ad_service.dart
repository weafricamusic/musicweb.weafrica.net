import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';

/// WeAfrica Music Banner Ad Service
/// 
/// Manages banner ads for home, search, library screens
class BannerAdService {
  BannerAdService._();
  static final BannerAdService instance = BannerAdService._();

  BannerAd? _bannerAd;
  bool _isLoading = false;

  /// Create and load a banner ad
  /// Returns the banner ad widget when ready
  Future<BannerAd?> createBannerAd() async {
    if (!AdMobService.instance.isSupported) {
      debugPrint('Banner ads not supported on web');
      return null;
    }

    if (_isLoading) return _bannerAd;
    if (_bannerAd != null) return _bannerAd;

    _isLoading = true;

    final completer = Completer<BannerAd?>();

    try {
      BannerAd(
        adUnitId: AdMobService.instance.bannerAdUnitId,
        request: const AdRequest(),
        size: AdSize.banner,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('✅ Banner ad loaded');
            _bannerAd = ad as BannerAd;
            _isLoading = false;
            completer.complete(_bannerAd);
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('⚠️ Banner ad failed to load: $error');
            ad.dispose();
            _bannerAd = null;
            _isLoading = false;
            completer.complete(null);
          },
        ),
      ).load();
    } catch (e) {
      debugPrint('⚠️ Error loading banner ad: $e');
      _isLoading = false;
      completer.complete(null);
    }

    return completer.future;
  }

  /// Get banner ad size
  AdSize get bannerSize => AdSize.banner;

  /// Get banner height
  double get bannerHeight => 50.0;

  /// Get banner width (full width)
  double getBannerWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Dispose current banner
  void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoading = false;
  }

  /// Check if banner is ready
  bool get isBannerReady => _bannerAd != null;
}