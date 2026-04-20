import 'dart:convert';

import 'package:flutter/services.dart';

/// Environment/config loaded from bundled JSON.
///
/// This complements [ApiEnv] (which only cares about WEAFRICA_API_BASE_URL).
/// Keep it lightweight and tolerant of missing keys.
class AppEnv {
  static Map<String, dynamic>? _decoded;

  static Future<void> load({
    String assetPath = 'assets/config/supabase.env.json',
  }) async {
    if (_decoded != null) return;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        _decoded = parsed.map((k, v) => MapEntry(k.toString(), v));
      } else {
        _decoded = <String, dynamic>{};
      }
    } catch (_) {
      _decoded = <String, dynamic>{};
    }
  }

  static String _getString(String key, {String fallback = ''}) {
    final v = _decoded?[key];
    if (v is String) return v.trim();
    return fallback;
  }

  static String _definedString(String key) {
    switch (key) {
      case 'WEAFRICA_DEFAULT_PLAN_ID':
        return const String.fromEnvironment('WEAFRICA_DEFAULT_PLAN_ID').trim();
      case 'DEFAULT_COUNTRY_CODE':
        return const String.fromEnvironment('DEFAULT_COUNTRY_CODE').trim();
      case 'WEAFRICA_PAYCHANGU_START_PATH':
        return const String.fromEnvironment('WEAFRICA_PAYCHANGU_START_PATH').trim();
      case 'WEAFRICA_VERCEL_PROTECTION_BYPASS':
        return const String.fromEnvironment('WEAFRICA_VERCEL_PROTECTION_BYPASS').trim();
      case 'WEAFRICA_TEST_TOKEN':
        return const String.fromEnvironment('WEAFRICA_TEST_TOKEN').trim();
      case 'AGORA_APP_ID':
        return const String.fromEnvironment('AGORA_APP_ID').trim();
      case 'AGORA_TOKEN':
        return const String.fromEnvironment('AGORA_TOKEN').trim();
      case 'AGORA_CHANNEL':
        return const String.fromEnvironment('AGORA_CHANNEL').trim();
      default:
        return '';
    }
  }

  static String _getDefinedOrAssetString(String key, {String fallback = ''}) {
    final defined = _definedString(key);
    if (defined.isNotEmpty) return defined;
    return _getString(key, fallback: fallback);
  }

  /// Optional default plan id for UI fallbacks (source of truth is /api/subscriptions/me).
  static String get defaultPlanId =>
      _getDefinedOrAssetString('WEAFRICA_DEFAULT_PLAN_ID', fallback: 'free');

  /// Optional default country code for payments/ads.
  static String get defaultCountryCode =>
      _getDefinedOrAssetString('DEFAULT_COUNTRY_CODE', fallback: 'MW');

  /// Backend path for starting a PayChangu payment.
  ///
  /// Example: `/api/payments/paychangu/start`
  ///
  /// The Flutter app will POST to `${ApiEnv.baseUrl}$payChanguStartPath`.
  static String get payChanguStartPath =>
      _getDefinedOrAssetString('WEAFRICA_PAYCHANGU_START_PATH');

  /// Optional Vercel Deployment Protection bypass token.
  ///
  /// If your backend is deployed behind Vercel authentication, requests from
  /// a mobile app will get HTTP 401 unless you either disable protection or
  /// provide a bypass token.
  static String get vercelProtectionBypassToken =>
      _getDefinedOrAssetString('WEAFRICA_VERCEL_PROTECTION_BYPASS');

  /// Optional shared secret for test-only backend routes.
  ///
  /// Used by the Supabase Edge Function when `WEAFRICA_ENABLE_TEST_ROUTES=true`.
  static String get testToken {
    return _getDefinedOrAssetString('WEAFRICA_TEST_TOKEN');
  }

  // --- Agora (Live, Step 1+) ---

  /// Agora App ID (safe to bundle; not a secret).
  static String get agoraAppId => _getDefinedOrAssetString('AGORA_APP_ID');

  /// Optional token (required if App Certificate is enabled in Agora Console).
  /// For production, generate tokens server-side.
  static String get agoraToken => _getDefinedOrAssetString('AGORA_TOKEN');

  /// Optional default channel for diagnostics/legacy screens.
  static String get agoraChannel =>
      _getDefinedOrAssetString('AGORA_CHANNEL', fallback: 'weafrica_live');
}
