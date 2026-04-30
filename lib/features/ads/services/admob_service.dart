import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// WeAfrica Music AdMob Service
/// 
/// Manages AdMob initialization and provides ad unit IDs
class AdMobService {
  AdMobService._();
  static final AdMobService instance = AdMobService._();

  bool _initialized = false;

  /// Test ad unit IDs (use these during development)
  static const String _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const String _testInterstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  /// Production ad unit IDs (replace with your actual IDs)
  static const String _androidRewardedAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx';
  static const String _androidInterstitialAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx';
  static const String _androidBannerAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx';

  static const String _iosRewardedAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx';
  static const String _iosInterstitialAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx';
  static const String _iosBannerAdUnitId = 'ca-app-pub-xxxxxxxxxxxxxxxx/xxxxxxxxxx';

  /// Initialize AdMob SDK
  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      debugPrint('AdMob not supported on web');
      return;
    }

    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint('✅ AdMob initialized');
    } catch (e) {
      debugPrint('⚠️ AdMob initialization failed: $e');
    }
  }

  /// Get rewarded ad unit ID
  String get rewardedAdUnitId {
    if (kDebugMode) return _testRewardedAdUnitId;
    
    if (Platform.isAndroid) return _androidRewardedAdUnitId;
    if (Platform.isIOS) return _iosRewardedAdUnitId;
    
    return _testRewardedAdUnitId;
  }

  /// Get interstitial ad unit ID
  String get interstitialAdUnitId {
    if (kDebugMode) return _testInterstitialAdUnitId;
    
    if (Platform.isAndroid) return _androidInterstitialAdUnitId;
    if (Platform.isIOS) return _iosInterstitialAdUnitId;
    
    return _testInterstitialAdUnitId;
  }

  /// Get banner ad unit ID
  String get bannerAdUnitId {
    if (kDebugMode) return _testBannerAdUnitId;
    
    if (Platform.isAndroid) return _androidBannerAdUnitId;
    if (Platform.isIOS) return _iosBannerAdUnitId;
    
    return _testBannerAdUnitId;
  }

  /// Check if ads are supported on current platform
  bool get isSupported => !kIsWeb;

  /// Check if initialized
  bool get isInitialized => _initialized;
}