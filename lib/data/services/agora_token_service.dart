import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../app/config/app_env.dart';

/// Service responsible for fetching short-lived Agora RTC tokens from the backend.
///
/// IMPORTANT: Never stores the App Certificate — only the App ID (non-secret)
/// is kept client-side. Tokens are always generated server-side.
///
/// Works on both Web and Native (Android/iOS) because it uses the `http` package.
class AgoraTokenService {
  static final AgoraTokenService _instance = AgoraTokenService._internal();
  factory AgoraTokenService() => _instance;
  AgoraTokenService._internal();

  /// Backend token endpoint. Override via AGORA_TOKEN_SERVER_URL env if needed.
  static const String _defaultTokenServerUrl =
      'https://weafrica-backend.vercel.app/api/agora/tokens/rtc';

  /// Cache tokens per channel+role to avoid redundant requests.
  /// Key: "${channelName}_${role}_${uid}"
  final Map<String, _TokenCacheEntry> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 45);

  String _cacheKey(String channelName, String role, int uid) =>
      '${channelName}_${role}_$uid';

  /// Validate and sanitize the App ID before any SDK operation.
  /// Throws if the App ID is missing, not a string, or has wrong length.
  static String get validatedAppId {
    String raw = AppEnv.agoraAppId;
    if (raw.isEmpty) {
      throw StateError(
        'Agora App ID is empty. Set AGORA_APP_ID in your build environment.',
      );
    }
    raw = raw.trim();
    if (raw.length != 32) {
      throw StateError(
        'Agora App ID has invalid length (${raw.length}), expected 32 chars. '
        'Value prefix: "${raw.substring(0, raw.length > 4 ? 4 : raw.length)}..."',
      );
    }
    // Redacted log for debugging (never log full App ID in production)
    if (kDebugMode) {
      final redacted =
          '${raw.substring(0, 4)}...${raw.substring(raw.length - 4)}';
      debugPrint('📋 AgoraTokenService — App ID validated: $redacted (len=${raw.length})');
    }
    return raw;
  }

  /// Fetch an RTC token from the backend for the given channel and UID.
  ///
  /// [channelName] — the Agora channel name.
  /// [uid]         — the Agora UID (0 = auto-assign by server).
  /// [role]        — 'broadcaster' or 'audience'.
  /// [authToken]   — your backend JWT / Firebase ID token for authentication.
  Future<String> fetchRtcToken({
    required String channelName,
    required int uid,
    required String role,
    required String authToken,
  }) async {
    final key = _cacheKey(channelName, role, uid);

    // 1. Return cached token if still fresh for this exact channel+role+uid
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      if (kDebugMode) {
        debugPrint('🔑 AgoraTokenService — returning cached token for $key');
      }
      return cached.token;
    }

    // 2. Build request
    final serverUrl = AppEnv.agoraTokenServerUrl.isNotEmpty
        ? AppEnv.agoraTokenServerUrl
        : _defaultTokenServerUrl;

    final uri = Uri.parse(serverUrl);
    final body = jsonEncode({
      'channelName': channelName,
      'role': role,
      'uid': uid,
      'ttlSeconds': 3600,
    });

    if (kDebugMode) {
      debugPrint('🔑 AgoraTokenService — POST $serverUrl');
      debugPrint('    body: channel=$channelName, role=$role, uid=$uid');
    }

    // 3. Execute request with auth header (works on Web + Native)
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final token = decoded['rtcToken'] ?? decoded['token'] ?? '';
      if (token.isEmpty) {
        throw StateError('Token server returned empty token');
      }
      _cache[key] = _TokenCacheEntry(token: token, fetchedAt: DateTime.now());
      if (kDebugMode) {
        debugPrint('🔑 AgoraTokenService — token fetched (${token.length} chars) for $key');
      }
      return token;
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'Token request unauthorized (HTTP ${response.statusCode}). '
        'Check your authToken / Firebase ID token.',
      );
    } else {
      throw StateError(
        'Token server error: HTTP ${response.statusCode} — ${response.body}',
      );
    }
  }

  /// Clear the cached token for a specific channel+role+uid.
  void clearCacheFor(String channelName, String role, int uid) {
    _cache.remove(_cacheKey(channelName, role, uid));
  }

  /// Clear ALL cached tokens (call when leaving a channel or signing out).
  void clearCache() {
    _cache.clear();
  }
}

class _TokenCacheEntry {
  final String token;
  final DateTime fetchedAt;
  _TokenCacheEntry({required this.token, required this.fetchedAt});
}
