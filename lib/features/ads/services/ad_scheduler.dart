import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ad_model.dart';
import 'ad_service.dart';

class AdScheduler {
  static const String _keySongCount = 'ads.song_count_before_interstitial';
  static const String _keyLastAdId = 'ads.last_ad_id';

  static const int _songsPerAdDefault = 2;

  final AdService _adService;

  AdScheduler({AdService? adService}) : _adService = adService ?? AdService();

  /// Track song plays and return true if an interstitial ad should be shown.
  ///
  /// NOTE: This repo already uses [PlaybackAdGate] for entitlements-based
  /// interstitial timing. This method is provided for cases where you want a
  /// simple local scheduler.
  Future<bool> shouldShowAd({int songsPerAd = _songsPerAdDefault}) async {
    final prefs = await SharedPreferences.getInstance();
    final every = songsPerAd <= 0 ? _songsPerAdDefault : songsPerAd;

    var count = prefs.getInt(_keySongCount) ?? 0;
    count += 1;
    await prefs.setInt(_keySongCount, count);

    if (count >= every) {
      await prefs.setInt(_keySongCount, 0);
      return true;
    }

    return false;
  }

  /// Returns a random active ad with a 70% preference for video when available.
  ///
  /// Uses the Edge-backed `AdService.getActiveAds()` so it works even when RLS
  /// blocks direct table reads in production.
  Future<AdModel?> getRandomAd({
    String placement = 'interstitial',
    AdRequiredMedia? requiredMedia,
  }) async {
    final ads = await _adService.getActiveAds(placement: placement);
    if (ads.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final lastAdId = (prefs.getString(_keyLastAdId) ?? '').trim();

    final valid = <AdModel>[];
    for (final raw in ads) {
      final model = AdModel.fromJson(raw);
      if (model == null) continue;

      // Filter out obvious placeholder values.
      final audioUrl = (model.audioUrl ?? '').trim();
      final videoUrl = (model.videoUrl ?? '').trim();
      final hasAudio = audioUrl.isNotEmpty && !audioUrl.contains('example.com');
      final hasVideo = videoUrl.isNotEmpty && !videoUrl.contains('example.com');
      if (!hasAudio && !hasVideo) continue;

      // Enforce required media type when specified.
      if (requiredMedia == AdRequiredMedia.audio) {
        // Audio-only: must have audio and must NOT have video.
        if (!hasAudio) continue;
        if (hasVideo) continue;
      }
      if (requiredMedia == AdRequiredMedia.video) {
        // Video: must have video.
        if (!hasVideo) continue;
      }

      valid.add(model);
    }

    if (valid.isEmpty) return null;

    List<AdModel> candidates = valid;
    if (lastAdId.isNotEmpty && candidates.length > 1) {
      final filtered = candidates.where((a) => a.id.trim() != lastAdId).toList();
      if (filtered.isNotEmpty) candidates = filtered;
    }

    final videoAds = candidates.where((a) => (a.videoUrl ?? '').trim().isNotEmpty).toList();
    final audioAds = candidates.where((a) => (a.audioUrl ?? '').trim().isNotEmpty).toList();

    if (kDebugMode) {
      debugPrint('📊 Available ads - Video: ${videoAds.length}, Audio: ${audioAds.length}');
    }

    final rng = Random(DateTime.now().microsecondsSinceEpoch);

    // When a media type is required, the filtering above ensures candidates
    // match; no need for a preference split.
    final preferVideo = requiredMedia == null && rng.nextInt(100) < 70 && videoAds.isNotEmpty;

    final pool = preferVideo
      ? videoAds
      : (audioAds.isNotEmpty ? audioAds : candidates);
    if (pool.isEmpty) return null;

    final selected = pool[rng.nextInt(pool.length)];

    if (kDebugMode) {
      final label = requiredMedia == AdRequiredMedia.video
          ? 'VIDEO'
          : (requiredMedia == AdRequiredMedia.audio ? 'AUDIO' : (preferVideo ? 'VIDEO' : 'AUDIO'));
      debugPrint('🎬 Selected ad: ${selected.title} ($label)');
    }

    await prefs.setString(_keyLastAdId, selected.id.trim());
    return selected;
  }
}

enum AdRequiredMedia {
  audio,
  video,
}
