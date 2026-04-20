import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'supabase_env.dart';

/// Environment/config for non-Supabase HTTP APIs (local dev server, etc.).
///
/// Override at build/run time:
/// `--dart-define=WEAFRICA_API_BASE_URL=https://<project-ref>.functions.supabase.co`
class ApiEnv {
  static const String _repoHostedBaseUrl = 'https://nxkutpjdoidfwpkjbwcm.functions.supabase.co';

  static const String _definedBaseUrl = String.fromEnvironment(
    'WEAFRICA_API_BASE_URL',
    defaultValue: '',
  );

  static String? _loadedBaseUrl;

  /// The raw configured base URL from `--dart-define=WEAFRICA_API_BASE_URL=...`.
  ///
  /// Empty means "not explicitly configured".
  static String get definedBaseUrl => _definedBaseUrl;

  /// Optionally load `WEAFRICA_API_BASE_URL` from an asset JSON file.
  ///
  /// This is a fallback for builds/runs that don't pass `--dart-define`.
  /// Default path matches the existing Supabase env asset.
  static Future<void> load({String assetPath = 'assets/config/supabase.env.json'}) async {
    if (_definedBaseUrl.isNotEmpty) return;
    if (_loadedBaseUrl != null && _loadedBaseUrl!.isNotEmpty) return;

    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final url = decoded['WEAFRICA_API_BASE_URL'];
      if (url is String && url.trim().isNotEmpty) {
        _loadedBaseUrl = url.trim();
      }
    } catch (_) {
      // Ignore: baseUrl will fall back to platform defaults.
    }
  }

  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) return _resolveConfiguredBaseUrl(_definedBaseUrl);
    final loaded = _loadedBaseUrl;
    if (loaded != null && loaded.isNotEmpty) return _resolveConfiguredBaseUrl(loaded);

    // Prefer Supabase Edge Functions when Supabase is configured.
    // This avoids accidental 404s or local-only URLs leaking into hosted builds.
    final derived = _tryDeriveSupabaseFunctionsBaseUrl();
    if (derived != null) return _normalizeForPlatform(derived);

    // Repository default: hosted Supabase Edge Functions.
    return _normalizeForPlatform(_repoHostedBaseUrl);
  }

  static String _resolveConfiguredBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (_looksLocalOrigin(trimmed)) {
      final derived = _tryDeriveSupabaseFunctionsBaseUrl();
      if (derived != null) return _normalizeForPlatform(derived);
      return _normalizeForPlatform(_repoHostedBaseUrl);
    }
    return _normalizeForPlatform(trimmed);
  }

  static void debugWarnIfProjectMismatch() {
    if (!kDebugMode) return;

    final supabaseRef = SupabaseEnv.projectRef;
    if (supabaseRef.isEmpty) return;

    final apiRef = _tryExtractSupabaseRefFromUrl(baseUrl);
    if (apiRef == null || apiRef.isEmpty) return;

    if (apiRef != supabaseRef) {
      debugPrint(
        '⚠️ Supabase project mismatch: SUPABASE_URL ref="$supabaseRef" but WEAFRICA_API_BASE_URL ref="$apiRef". '
        'This often causes “Bucket not found” because uploads hit a different project than you are inspecting in the dashboard.',
      );
    }
  }

  static String? _tryExtractSupabaseRefFromUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;

    final host = uri.host;
    if (host.endsWith('.functions.supabase.co')) {
      return host.replaceFirst('.functions.supabase.co', '').split('.').first;
    }
    if (host.endsWith('.supabase.co')) {
      return host.replaceFirst('.supabase.co', '').split('.').first;
    }
    return null;
  }

  static String? _tryDeriveSupabaseFunctionsBaseUrl() {
    final raw = SupabaseEnv.supabaseUrl.trim();
    if (raw.isEmpty) return null;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;

    // Common shape: https://<project-ref>.supabase.co
    // Edge Functions origin: https://<project-ref>.functions.supabase.co
    final host = uri.host;
    if (!host.endsWith('.supabase.co')) return null;
    final functionsHost = host.replaceFirst('.supabase.co', '.functions.supabase.co');
    // NOTE: do not use `query: ''` / `fragment: ''` here.
    // Dart will emit a trailing `?`/`#`, which later corrupts path concatenation.
    return uri.replace(host: functionsHost, path: '').toString();
  }

  static bool _looksLocalOrigin(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return false;
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host == '10.0.2.2';
  }

  static String _normalizeForPlatform(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    // Prefer origin-style URLs (no trailing slash) to avoid `//api/...`.
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    // If the base URL is a Supabase project origin, prefer the Edge Functions origin.
    // This avoids accidental 404s when hitting /api/* endpoints.
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final host = uri.host;
      final path = uri.path;
      if (host.endsWith('.supabase.co') && !host.endsWith('.functions.supabase.co')) {
        final hasPath = path.isNotEmpty && path != '/';
        if (!hasPath) {
          final functionsHost = host.replaceFirst('.supabase.co', '.functions.supabase.co');
          trimmed = uri.replace(host: functionsHost, path: '').toString();
        }
      }
    }
    return trimmed;
  }
}
