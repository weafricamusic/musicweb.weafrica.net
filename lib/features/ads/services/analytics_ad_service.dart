import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// WeAfrica Music Ads Analytics Service
/// 
/// Tracks all ad-related events for monetization insights
class AnalyticsAdService {
  AnalyticsAdService._();
  static final AnalyticsAdService instance = AnalyticsAdService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Track rewarded ad watched
  Future<void> logRewardedAdWatched({
    required int rewardAmount,
    required String adUnitId,
    bool success = true,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'rewarded_ad_watched',
        parameters: {
          'reward_amount': rewardAmount,
          'ad_unit_id': adUnitId,
          'success': success,
          'platform': _getPlatform(),
        },
      );
      debugPrint('📊 Analytics: rewarded_ad_watched');
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  /// Track interstitial ad shown
  Future<void> logInterstitialShown({
    required String adUnitId,
    required int songsPlayed,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'interstitial_shown',
        parameters: {
          'ad_unit_id': adUnitId,
          'songs_played': songsPlayed,
          'platform': _getPlatform(),
        },
      );
      debugPrint('📊 Analytics: interstitial_shown');
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  /// Track coins earned from ads
  Future<void> logCoinsEarned({
    required int amount,
    required String source,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'coins_earned',
        parameters: {
          'amount': amount,
          'source': source, // 'rewarded_ad', 'daily_bonus', etc
          'platform': _getPlatform(),
        },
      );
      debugPrint('📊 Analytics: coins_earned - $amount coins');
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  /// Track banner ad impression
  Future<void> logBannerImpression({required String adUnitId}) async {
    try {
      await _analytics.logEvent(
        name: 'banner_impression',
        parameters: {
          'ad_unit_id': adUnitId,
          'platform': _getPlatform(),
        },
      );
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  /// Track ad failed to load
  Future<void> logAdFailed({
    required String adType,
    required String error,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'ad_failed_to_load',
        parameters: {
          'ad_type': adType,
          'error': error,
          'platform': _getPlatform(),
        },
      );
      debugPrint('📊 Analytics: ad_failed_to_load - $adType');
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  /// Track soft paywall shown
  Future<void> logSoftPaywallShown({required String context}) async {
    try {
      await _analytics.logEvent(
        name: 'soft_paywall_shown',
        parameters: {
          'context': context,
          'platform': _getPlatform(),
        },
      );
      debugPrint('📊 Analytics: soft_paywall_shown - $context');
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  /// Track user clicked watch ad from paywall
  Future<void> logPaywallWatchAdClicked() async {
    try {
      await _analytics.logEvent(
        name: 'paywall_watch_ad_clicked',
        parameters: {
          'platform': _getPlatform(),
        },
      );
    } catch (e) {
      debugPrint('⚠️ Analytics error: $e');
    }
  }

  String _getPlatform() {
    if (kIsWeb) return 'web';
    return 'mobile';
  }
}