import 'package:flutter/foundation.dart';

/// Central environment configuration for WeAfrica Music.
///
/// **SECURITY RULES:**
/// 1. App ID (non-secret) — safe to embed, but prefer build-time injection.
/// 2. App Certificate (SECRET) — NEVER put in client code. Keep server-only.
/// 3. Supabase keys — anon key is safe for client; service_role key is server-only.
///
/// **Build-time injection (recommended):**
///   flutter run --dart-define=AGORA_APP_ID=your_app_id
///   flutter build web --dart-define=AGORA_APP_ID=your_app_id
class AppEnv {
  // ── Agora ────────────────────────────────────────────────

  /// Agora App ID (32-char string, non-secret).
  /// Injected at build time via --dart-define or falls back to compile-time const.
  static String get agoraAppId {
    const fromEnv = String.fromEnvironment('AGORA_APP_ID',
        defaultValue: '21a9549ec323484ca5983aadbd3839af');
    return fromEnv.trim();
  }

  /// Backend token server URL for fetching short-lived RTC tokens.
  static String get agoraTokenServerUrl {
    const fromEnv = String.fromEnvironment('AGORA_TOKEN_SERVER_URL',
        defaultValue: '');
    return fromEnv.trim();
  }

  // ── Supabase ─────────────────────────────────────────────

  static const String supabaseUrl =
      "https://nxkutpjdoidfwpkjbwcm.supabase.co";
  static const String supabaseAnonKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U";

  // ── PayChangu ────────────────────────────────────────────

  static const String payChanguStartPath = "";

  // ── Defaults ─────────────────────────────────────────────

  static const String defaultPlanId = "";
  static const String defaultCountryCode = "NG";

  static Future<void> load() async {}

  // ── Deprecated getters (kept for backward compatibility) ─
  // These previously returned hardcoded "demo" values which were NEVER safe.
  // Use AgoraTokenService to fetch real tokens from your backend.

  @Deprecated('Use AgoraTokenService.fetchRtcToken() instead. This returns empty string.')
  static String get agoraToken => '';

  @Deprecated('Use AgoraTokenService.fetchRtcToken() instead. This returns empty string.')
  static String get testToken => '';

  @Deprecated('Pass channel name dynamically. This returns empty string.')
  static String get agoraChannel => '';

  static String get vercelProtectionBypassToken => "";

  // ── Validation helpers ───────────────────────────────────

  /// Validates the Agora App ID format (32 chars, no whitespace).
  /// Throws [StateError] if invalid. Call before every SDK init.
  static void validateAgoraAppId() {
    final id = agoraAppId;
    if (id.isEmpty) {
      throw StateError(
        'AGORA_APP_ID is empty. '
        'Pass it at build time: flutter run --dart-define=AGORA_APP_ID=YOUR_APP_ID',
      );
    }
    if (id.length != 32) {
      throw StateError(
        'AGORA_APP_ID has invalid length (${id.length}), expected 32. '
        'Value: "${id.substring(0, id.length > 4 ? 4 : id.length)}..."',
      );
    }
    if (kDebugMode) {
      final redacted = '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
      debugPrint('✅ AppEnv — Agora App ID validated: $redacted');
    }
  }
}
