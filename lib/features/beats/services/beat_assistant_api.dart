import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../../app/services/connectivity_service.dart';
import '../../../app/utils/retry_utils.dart';
import '../models/beat_models.dart';

class BeatAssistantApi {
  const BeatAssistantApi();

  static const _uriBuilder = ApiUriBuilder();

  static const Duration _presetsTtl = Duration(minutes: 10);
  static List<BeatPreset>? _presetsCache;
  static DateTime? _presetsCacheAt;

  // Small cache to avoid spamming status when multiple callers exist.
  static final Map<String, _StatusCacheEntry> _statusCache = <String, _StatusCacheEntry>{};

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    return _uriBuilder.build(path, queryParameters: queryParameters);
  }

  Future<List<BeatPreset>> presets({bool forceRefresh = false}) async {
    if (!forceRefresh && _presetsCache != null && _presetsCacheAt != null) {
      final age = DateTime.now().difference(_presetsCacheAt!);
      if (age <= _presetsTtl) return _presetsCache!;
    }

    final uri = _uri('/api/beat/presets');

    final res = await RetryUtils.withRetry(
      operation: 'Beat presets',
      maxRetries: 3,
      action: () async {
        return FirebaseAuthedHttp.get(
          uri,
          headers: const {'Accept': 'application/json'},
          timeout: const Duration(seconds: 5),
          includeAuthIfAvailable: true,
        );
      },
    );

    final decoded = _decodeBody(res);

    if (res.statusCode != 200) {
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();
      throw Exception('Failed to load presets (HTTP ${res.statusCode}): $msg');
    }

    final listRaw = decoded['presets'];
    final presets = listRaw is List
        ? listRaw
            .whereType<Map>()
            .map((m) => BeatPreset.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
            .toList(growable: false)
        : const <BeatPreset>[];

    _presetsCache = presets;
    _presetsCacheAt = DateTime.now();
    return presets;
  }

  Future<BeatCostEstimate?> estimateCost(BeatGenerateRequest data) async {
    // This endpoint may not exist yet. If so, we gracefully return null.
    if (!await ConnectivityService.instance.hasConnection) {
      return null;
    }

    final uri = _uri('/api/beat/audio/estimate');

    try {
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(data.toJson()),
        timeout: const Duration(seconds: 10),
        requireAuth: true,
      );

      if (res.statusCode == 404) return null;

      final decoded = _decodeBody(res);
      if (res.statusCode != 200) return null;

      final raw = decoded['estimate'] ?? decoded;
      if (raw is Map) {
        return BeatCostEstimate.fromJson(raw.map((k, v) => MapEntry(k.toString(), v)));
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<BeatGenerateResponse> generate(BeatGenerateRequest data) async {
    final uri = _uri('/api/beat/generate');

    http.Response res;
    try {
      res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(data.toJson()),
        timeout: const Duration(seconds: 10),
        includeAuthIfAvailable: true,
      );
    } on TimeoutException {
      throw Exception('Beat generation request timed out');
    } catch (e) {
      throw Exception('Network error calling Beat Assistant: $e');
    }

    final decoded = _decodeBody(res);

    if (res.statusCode != 200) {
      final err = (decoded['error'] ?? '').toString();
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();

      if (res.statusCode == 401) {
        throw BeatAssistantUnauthorized(msg);
      }

      if (res.statusCode == 402 && err == 'payment_required') {
        BeatPaymentRequiredDetails? details;
        final d = decoded['details'];
        if (d is Map) {
          details = BeatPaymentRequiredDetails.fromJson(d.map((k, v) => MapEntry(k.toString(), v)));
        }
        throw BeatAssistantPaymentRequired(msg, details: details);
      }

      throw BeatAssistantHttpFailure(
        statusCode: res.statusCode,
        error: err.isEmpty ? 'http_error' : err,
        message: msg,
      );
    }

    return BeatGenerateResponse.fromJson(decoded);
  }

  Future<BeatAudioStartResponse> startAudioMp3(BeatGenerateRequest data) async {
    if (!await ConnectivityService.instance.hasConnection) {
      throw const BeatAssistantOffline();
    }

    final uri = _uri('/api/beat/audio/start');

    final res = await RetryUtils.withRetry(
      operation: 'Beat MP3 start',
      maxRetries: 3,
      initialDelay: const Duration(seconds: 1),
      shouldRetry: (e) {
        if (e is BeatAssistantException) return false;
        return true;
      },
      action: () async {
        try {
          return await FirebaseAuthedHttp.post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(data.toJson()),
            timeout: const Duration(seconds: 30),
            requireAuth: true,
          );
        } on TimeoutException {
          throw Exception('Beat MP3 request timed out');
        } catch (e) {
          throw Exception('Network error generating beat MP3: $e');
        }
      },
    );

    final decoded = _decodeBody(res);

    if (res.statusCode != 200) {
      final err = (decoded['error'] ?? '').toString();
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();

      if (res.statusCode == 401 || res.statusCode == 403) throw BeatAssistantUnauthorized(msg);
      if (res.statusCode == 402 && err == 'payment_required') {
        BeatPaymentRequiredDetails? details;
        final d = decoded['details'];
        if (d is Map) {
          details = BeatPaymentRequiredDetails.fromJson(d.map((k, v) => MapEntry(k.toString(), v)));
        }
        throw BeatAssistantPaymentRequired(msg, details: details);
      }

      throw BeatAssistantHttpFailure(
        statusCode: res.statusCode,
        error: err.isEmpty ? 'http_error' : err,
        message: msg,
      );
    }

    return BeatAudioStartResponse.fromJson(decoded);
  }

  Future<BeatAudioStatusResponse> audioMp3Status(String jobId) async {
    if (!await ConnectivityService.instance.hasConnection) {
      throw const BeatAssistantOffline();
    }

    final cached = _statusCache[jobId];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(milliseconds: 900)) {
      return cached.value;
    }

    final uri = _uri('/api/beat/audio/status', queryParameters: {'job_id': jobId});

    final res = await RetryUtils.withRetry(
      operation: 'Beat MP3 status',
      maxRetries: 3,
      initialDelay: const Duration(seconds: 1),
      action: () async {
        try {
          return await FirebaseAuthedHttp.get(
            uri,
            headers: const {'Accept': 'application/json'},
            timeout: const Duration(seconds: 8),
            requireAuth: true,
          );
        } on TimeoutException {
          throw Exception('Beat MP3 status request timed out');
        } catch (e) {
          throw Exception('Network error loading beat MP3 status: $e');
        }
      },
    );

    final decoded = _decodeBody(res);

    if (res.statusCode != 200) {
      final err = (decoded['error'] ?? '').toString();
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();
      if (res.statusCode == 401 || res.statusCode == 403) throw BeatAssistantUnauthorized(msg);
      throw BeatAssistantHttpFailure(
        statusCode: res.statusCode,
        error: err.isEmpty ? 'http_error' : err,
        message: msg,
      );
    }

    final parsed = BeatAudioStatusResponse.fromJson(decoded);
    _statusCache[jobId] = _StatusCacheEntry(value: parsed, at: DateTime.now());
    return parsed;
  }

  Future<BeatAudioStartResponse> startBattleAudio120(BeatBattle120Request data) async {
    if (!await ConnectivityService.instance.hasConnection) {
      throw const BeatAssistantOffline();
    }

    final uri = _uri('/api/beat/audio/battle/start');

    final res = await RetryUtils.withRetry(
      operation: 'Battle beat 120 start',
      maxRetries: 3,
      initialDelay: const Duration(seconds: 1),
      shouldRetry: (e) {
        if (e is BeatAssistantException) return false;
        return true;
      },
      action: () async {
        try {
          return await FirebaseAuthedHttp.post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(data.toJson()),
            timeout: const Duration(seconds: 30),
            requireAuth: true,
          );
        } on TimeoutException {
          throw Exception('Battle beat generation request timed out');
        } catch (e) {
          throw Exception('Network error generating 120s battle beat: $e');
        }
      },
    );

    final decoded = _decodeBody(res);

    if (res.statusCode != 200) {
      final err = (decoded['error'] ?? '').toString();
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();

      if (res.statusCode == 401 || res.statusCode == 403) throw BeatAssistantUnauthorized(msg);
      if (res.statusCode == 402 && err == 'payment_required') {
        BeatPaymentRequiredDetails? details;
        final d = decoded['details'];
        if (d is Map) {
          details = BeatPaymentRequiredDetails.fromJson(d.map((k, v) => MapEntry(k.toString(), v)));
        }
        throw BeatAssistantPaymentRequired(msg, details: details);
      }

      throw BeatAssistantHttpFailure(
        statusCode: res.statusCode,
        error: err.isEmpty ? 'http_error' : err,
        message: msg,
      );
    }

    return BeatAudioStartResponse.fromJson(decoded);
  }

  Future<BeatAudioStatusResponse> battleAudio120Status(String jobId) async {
    if (!await ConnectivityService.instance.hasConnection) {
      throw const BeatAssistantOffline();
    }

    final cacheKey = 'battle_120::$jobId';
    final cached = _statusCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(milliseconds: 900)) {
      return cached.value;
    }

    final uri = _uri('/api/beat/audio/battle/status', queryParameters: {'job_id': jobId});

    final res = await RetryUtils.withRetry(
      operation: 'Battle beat 120 status',
      maxRetries: 3,
      initialDelay: const Duration(seconds: 1),
      action: () async {
        try {
          return await FirebaseAuthedHttp.get(
            uri,
            headers: const {'Accept': 'application/json'},
            timeout: const Duration(seconds: 8),
            requireAuth: true,
          );
        } on TimeoutException {
          throw Exception('Battle beat status request timed out');
        } catch (e) {
          throw Exception('Network error loading 120s battle beat status: $e');
        }
      },
    );

    final decoded = _decodeBody(res);

    if (res.statusCode != 200) {
      final err = (decoded['error'] ?? '').toString();
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();
      if (res.statusCode == 401 || res.statusCode == 403) throw BeatAssistantUnauthorized(msg);
      throw BeatAssistantHttpFailure(
        statusCode: res.statusCode,
        error: err.isEmpty ? 'http_error' : err,
        message: msg,
      );
    }

    final parsed = BeatAudioStatusResponse.fromJson(decoded);
    _statusCache[cacheKey] = _StatusCacheEntry(value: parsed, at: DateTime.now());
    return parsed;
  }

  Map<String, dynamic> _decodeBody(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      if (j is Map<String, dynamic>) return j;
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }
}

class _StatusCacheEntry {
  _StatusCacheEntry({required this.value, required this.at});

  final BeatAudioStatusResponse value;
  final DateTime at;
}
