import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../app/config/api_env.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/ad_model.dart';

class AdService {
  AdService._();

  static final AdService _instance = AdService._();

  factory AdService() => _instance;

  // Alias for readability when callers treat ads as random/rotated.
  Future<AdModel?> getRandomAd({String placement = 'interstitial'}) =>
      getNextAd(placement: placement);

  Future<AdModel?> getNextAd({String placement = 'interstitial'}) async {
    final uri = Uri.parse('${ApiEnv.baseUrl}/api/ads/next').replace(
      queryParameters: {
        if (placement.trim().isNotEmpty) 'placement': placement.trim(),
      },
    );

    try {
      final res = await FirebaseAuthedHttp.get(
        uri,
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 4),
        requireAuth: true,
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('AdService.getNextAd failed: HTTP ${res.statusCode} ${res.body}');
        }
        return null;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;

      final ok = decoded['ok'] == true;
      if (!ok) return null;

      final rawAd = decoded['ad'];
      if (rawAd == null) return null;
      if (rawAd is! Map) return null;

      return AdModel.fromJson(rawAd.map((k, v) => MapEntry(k.toString(), v)));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AdService.getNextAd error: $e');
      }
      return null;
    }
  }

  /// Get all active ads for a placement.
  ///
  /// Uses the Edge API so it works when DB tables are protected by RLS.
  Future<List<Map<String, dynamic>>> getActiveAds({String placement = 'interstitial'}) async {
    final uri = Uri.parse('${ApiEnv.baseUrl}/api/ads/active').replace(
      queryParameters: {
        if (placement.trim().isNotEmpty) 'placement': placement.trim(),
      },
    );

    try {
      final res = await FirebaseAuthedHttp.get(
        uri,
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 4),
        requireAuth: true,
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('AdService.getActiveAds failed: HTTP ${res.statusCode} ${res.body}');
        }
        return const [];
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return const [];
      if (decoded['ok'] != true) return const [];

      final raw = decoded['ads'];
      if (raw is! List) return const [];

      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          out.add(item.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AdService.getActiveAds error: $e');
      }
      return const [];
    }
  }

  Future<void> trackImpression(String adId) => _track(adId, 'impression');
  Future<void> trackClick(String adId) => _track(adId, 'click');
  Future<void> trackCompletion(String adId) => _track(adId, 'completion');

  // Aliases matching some older naming in docs/snippets.
  Future<void> recordImpression(String adId) => trackImpression(adId);
  Future<void> recordClick(String adId) => trackClick(adId);
  Future<void> recordCompletion(String adId) => trackCompletion(adId);

  Future<void> _track(String adId, String event) async {
    final id = adId.trim();
    if (id.isEmpty) return;

    final uri = Uri.parse('${ApiEnv.baseUrl}/api/ads/track');

    try {
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ad_id': id,
          'event': event,
        }),
        timeout: const Duration(seconds: 4),
        requireAuth: true,
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('AdService.track($event) failed: HTTP ${res.statusCode} ${res.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AdService.track($event) error: $e');
      }
    }
  }
}
