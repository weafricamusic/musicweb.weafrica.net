import 'dart:convert';

import '../../app/network/api_uri_builder.dart';
import '../../app/network/firebase_authed_http.dart';
import 'ads_models.dart';

class AdsApi {
  const AdsApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  static Map<String, dynamic>? _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<AdsCreative?> fetchNext({AdPlacement placement = AdPlacement.interstitial}) async {
    final uri = _uriBuilder.build(
      '/api/ads/next',
      queryParameters: {'placement': placement.value},
    );

    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 8),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString();
      throw Exception('Ads next failed (HTTP ${res.statusCode}): $msg');
    }

    return AdsCreative.fromJson(decoded?['ad']);
  }

  Future<void> track({required String adId, required AdTrackEvent event}) async {
    final uri = _uriBuilder.build('/api/ads/track');

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'ad_id': adId, 'event': event.value}),
      timeout: const Duration(seconds: 8),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString();
      throw Exception('Ads track failed (HTTP ${res.statusCode}): $msg');
    }
  }

  Future<double> rewardCoins({String? adId, String? source}) async {
    final uri = _uriBuilder.build('/api/ads/reward');

    final body = <String, Object?>{};
    if ((adId ?? '').trim().isNotEmpty) body['ad_id'] = adId!.trim();
    if ((source ?? '').trim().isNotEmpty) body['source'] = source!.trim();

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString();
      throw Exception('Reward failed (HTTP ${res.statusCode}): $msg');
    }

    final awarded = decoded?['coins_awarded'] ?? decoded?['coinsAwarded'] ?? 0;
    if (awarded is num) return awarded.toDouble();
    return double.tryParse(awarded.toString()) ?? 0;
  }
}
