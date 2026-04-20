import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../features/subscriptions/subscriptions_controller.dart';
import 'ads/unified_ad_service.dart';

/// Interstitial ads gate for consumer audio playback.
///
/// Behavior:
/// - Counts completed songs.
/// - Shows an interstitial when the counter reaches
///   `entitlements.interstitial_every_songs`.
/// - Disabled when `entitlements.ads_enabled` is false.
///
/// Notes:
/// - Ads only run on Android/iOS and only while the app is in foreground.
/// - Uses Google test unit IDs in debug/profile builds.
class PlaybackInterstitialAds with WidgetsBindingObserver {
  PlaybackInterstitialAds._();

  static final PlaybackInterstitialAds instance = PlaybackInterstitialAds._();

  bool _initialized = false;
  bool _foreground = true;

  int _completedSongsSinceAd = 0;

  bool get _supportsAdsPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _adsEnabled =>
      SubscriptionsController.instance.entitlements.effectiveAdsEnabled;

  int get _everySongs =>
      SubscriptionsController.instance.entitlements.effectiveInterstitialEverySongs;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!_supportsAdsPlatform) return;

    WidgetsBinding.instance.addObserver(this);

    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ MobileAds.initialize failed: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  /// Call this when a song completes and the player is about to advance.
  ///
  /// If ads are enabled and the threshold is met, this will block until the
  /// interstitial is dismissed (or fails to load/show).
  Future<void> maybeShowAfterSongCompleted() async {
    if (!_supportsAdsPlatform) return;

    if (!_adsEnabled) {
      _completedSongsSinceAd = 0;
      return;
    }

    final every = _everySongs;
    if (every <= 0) {
      _completedSongsSinceAd = 0;
      return;
    }

    _completedSongsSinceAd++;

    if (_completedSongsSinceAd < every) return;

    _completedSongsSinceAd = 0;

    // Don’t try to show an ad if the app is backgrounded.
    if (!_foreground) return;

    await UnifiedAdService.instance.showPlaybackInterstitial();
  }

  void resetCounter() {
    _completedSongsSinceAd = 0;
  }

  // Ad showing is handled by UnifiedAdService.
}
