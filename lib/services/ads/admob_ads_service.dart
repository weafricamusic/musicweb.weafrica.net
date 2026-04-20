import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_unit_resolver.dart';

class AdmobAdsService {
  AdmobAdsService._();

  static final AdmobAdsService instance = AdmobAdsService._();

  bool _showInFlight = false;

  bool get _supportsAdsPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  String? _testUnitId(AdMobFormat format) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      switch (format) {
        case AdMobFormat.banner:
          return 'ca-app-pub-3940256099942544/6300978111';
        case AdMobFormat.interstitial:
          return 'ca-app-pub-3940256099942544/1033173712';
        case AdMobFormat.rewarded:
          return 'ca-app-pub-3940256099942544/5224354917';
        case AdMobFormat.native:
          return 'ca-app-pub-3940256099942544/2247696110';
      }
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      switch (format) {
        case AdMobFormat.banner:
          return 'ca-app-pub-3940256099942544/2934735716';
        case AdMobFormat.interstitial:
          return 'ca-app-pub-3940256099942544/4411468910';
        case AdMobFormat.rewarded:
          return 'ca-app-pub-3940256099942544/1712485313';
        case AdMobFormat.native:
          return 'ca-app-pub-3940256099942544/3986624511';
      }
    }

    return null;
  }

  Future<String?> _resolveUnitId({required AdMobFormat format, required String placement, String? country}) async {
    if (!kReleaseMode) {
      return _testUnitId(format);
    }

    // Prefer DB-driven unit IDs (seeded via Supabase migrations).
    final fromDb = await AdMobUnitResolver.instance.resolve(
      format: format,
      placement: placement,
      country: country,
    );
    if (fromDb != null) return fromDb;

    // Last-resort: Dart defines (optional).
    if (format == AdMobFormat.interstitial) {
      final id = defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment('ADMOB_INTERSTITIAL_IOS').trim()
          : const String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID').trim();
      return id.isEmpty ? null : id;
    }

    if (format == AdMobFormat.banner) {
      final id = defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment('ADMOB_BANNER_IOS').trim()
          : const String.fromEnvironment('ADMOB_BANNER_ANDROID').trim();
      return id.isEmpty ? null : id;
    }

    if (format == AdMobFormat.rewarded) {
      final id = defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment('ADMOB_REWARDED_IOS').trim()
          : const String.fromEnvironment('ADMOB_REWARDED_ANDROID').trim();
      return id.isEmpty ? null : id;
    }

    if (format == AdMobFormat.native) {
      final id = defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment('ADMOB_NATIVE_IOS').trim()
          : const String.fromEnvironment('ADMOB_NATIVE_ANDROID').trim();
      return id.isEmpty ? null : id;
    }

    return null;
  }

  Future<void> showInterstitial({String placement = 'main', String? country}) async {
    if (!_supportsAdsPlatform) return;
    if (_showInFlight) return;

    final adUnitId = await _resolveUnitId(format: AdMobFormat.interstitial, placement: placement, country: country);
    if (adUnitId == null || adUnitId.trim().isEmpty) return;

    _showInFlight = true;
    final completer = Completer<void>();

    try {
      InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                if (!completer.isCompleted) completer.complete();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                if (!completer.isCompleted) completer.complete();
              },
            );

            try {
              ad.show();
            } catch (_) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete();
            }
          },
          onAdFailedToLoad: (error) {
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );

      await completer.future.timeout(const Duration(seconds: 12), onTimeout: () {});
    } finally {
      _showInFlight = false;
    }
  }

  Future<bool> showRewarded({
    required VoidCallback onUserEarnedReward,
    String placement = 'main',
    String? country,
  }) async {
    if (!_supportsAdsPlatform) return false;
    if (_showInFlight) return false;

    final adUnitId = await _resolveUnitId(format: AdMobFormat.rewarded, placement: placement, country: country);
    if (adUnitId == null || adUnitId.trim().isEmpty) return false;

    _showInFlight = true;
    final completer = Completer<bool>();

    try {
      RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                if (!completer.isCompleted) completer.complete(true);
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                if (!completer.isCompleted) completer.complete(false);
              },
            );

            try {
              ad.show(
                onUserEarnedReward: (_, _) {
                  onUserEarnedReward();
                },
              );
            } catch (_) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) completer.complete(false);
          },
        ),
      );

      return await completer.future.timeout(const Duration(seconds: 18), onTimeout: () => false);
    } finally {
      _showInFlight = false;
    }
  }

  Future<BannerAd?> createBanner({String placement = 'home', String? country}) async {
    if (!_supportsAdsPlatform) return null;

    final adUnitId = await _resolveUnitId(format: AdMobFormat.banner, placement: placement, country: country);
    if (adUnitId == null || adUnitId.trim().isEmpty) return null;

    return BannerAd(
      size: AdSize.banner,
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: const BannerAdListener(),
    );
  }

  Future<BannerAd?> createBannerWithListener({
    required BannerAdListener listener,
    String placement = 'home',
    String? country,
  }) async {
    if (!_supportsAdsPlatform) return null;

    final adUnitId = await _resolveUnitId(format: AdMobFormat.banner, placement: placement, country: country);
    if (adUnitId == null || adUnitId.trim().isEmpty) return null;

    return BannerAd(
      size: AdSize.banner,
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: listener,
    );
  }

  Future<NativeAd?> createNative({
    required String factoryId,
    required NativeAdListener listener,
    String placement = 'feed',
    String? country,
  }) async {
    if (!_supportsAdsPlatform) return null;

    final adUnitId = await _resolveUnitId(format: AdMobFormat.native, placement: placement, country: country);
    if (adUnitId == null || adUnitId.trim().isEmpty) return null;

    return NativeAd(
      adUnitId: adUnitId,
      factoryId: factoryId,
      request: const AdRequest(),
      listener: listener,
    );
  }
}
