import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SupabaseEnv {
  static String? _supabaseUrl;
  static String? _supabaseAnonKey;

  static bool _loadedFromAsset = false;

  static bool get loadedFromAsset => _loadedFromAsset;

  static String get supabaseUrl => _supabaseUrl ?? const String.fromEnvironment('SUPABASE_URL');
  static String get supabaseAnonKey =>
      _supabaseAnonKey ?? const String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Best-effort project ref extracted from [supabaseUrl].
  ///
  /// Example: `https://<ref>.supabase.co` -> `<ref>`
  static String get projectRef {
    final raw = supabaseUrl.trim();
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return '';

    var host = uri.host;
    if (host.endsWith('.functions.supabase.co')) {
      host = host.replaceFirst('.functions.supabase.co', '.supabase.co');
    }

    if (!host.endsWith('.supabase.co')) return '';
    final ref = host.replaceFirst('.supabase.co', '');
    return ref.split('.').first;
  }

  /// Loads Supabase config from an asset JSON file when compile-time
  /// `--dart-define` values are not provided.
  ///
  /// Expected JSON keys: `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
  static Future<void> load({String assetPath = 'assets/config/supabase.env.json'}) async {
    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      return;
    }

    if (_supabaseUrl != null && _supabaseAnonKey != null) {
      return;
    }

    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final url = decoded['SUPABASE_URL'];
      final anonKey = decoded['SUPABASE_ANON_KEY'];

      final urlStr = url is String ? url.trim() : '';
      final anonStr = anonKey is String ? anonKey.trim() : '';

      // Ignore template placeholders from the example/bundled config.
      // This makes the failure mode “missing config” instead of “placeholder”.
      final urlLower = urlStr.toLowerCase();
      final anonLower = anonStr.toLowerCase();

      final urlLooksPlaceholder = urlLower.contains('your_project_ref') || urlLower.contains('your-project-ref');
      final anonLooksPlaceholder = anonLower.contains('your_supabase_anon') ||
          anonLower.contains('your supabase anon') ||
          anonLower.contains('your_actual_anon_key_here') ||
          anonLower.contains('your actual anon key here') ||
          anonLower.contains('your_anon') ||
          anonLower.contains('your anon');

      if (urlStr.isNotEmpty && !urlLooksPlaceholder) {
        _supabaseUrl = urlStr;
      }

      if (anonStr.isNotEmpty && !anonLooksPlaceholder) {
        _supabaseAnonKey = anonStr;
      }

      _loadedFromAsset = _supabaseUrl != null || _supabaseAnonKey != null;

      if (kDebugMode && _loadedFromAsset) {
        debugPrint('ℹ️ SupabaseEnv loaded from asset ($assetPath).');
      }
    } catch (_) {
      // Ignore: we'll fail validation later with an actionable message.
    }
  }

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing Supabase config. Provide either:\n'
        '- --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...\n'
        '- or (recommended) --dart-define-from-file=tool/supabase.env.json\n'
        '- or bundle values via assets/config/supabase.env.json\n\n'
        'Note: if you rely on the asset file, make sure it contains real values (not placeholders).\n\n'
        'If you are running from the terminal, use:\n'
        'flutter run --dart-define-from-file=tool/supabase.env.json',
      );
    }

    final urlLower = supabaseUrl.toLowerCase();
    final anonLower = supabaseAnonKey.toLowerCase();

    if (urlLower.contains('your_project_ref') || urlLower.contains('your-project-ref')) {
      throw StateError(
        'Supabase URL is still the template placeholder (YOUR_PROJECT_REF).\n'
        'Set SUPABASE_URL to your real project URL (https://<ref>.supabase.co).\n\n'
        'Recommended: set values in tool/supabase.env.json and run with\n'
        '--dart-define-from-file=tool/supabase.env.json.',
      );
    }

    if (anonLower.contains('your_supabase_anon') ||
        anonLower.contains('your supabase anon') ||
        anonLower.contains('your_actual_anon_key_here') ||
        anonLower.contains('your actual anon key here') ||
        anonLower.contains('your_anon') ||
        anonLower.contains('your anon')) {
      throw StateError(
        'Supabase anon key is still the template placeholder.\n'
        'Set SUPABASE_ANON_KEY to your real anon public key.\n\n'
        'Recommended: put SUPABASE_URL + SUPABASE_ANON_KEY in tool/supabase.env.json and run with\n'
        '--dart-define-from-file=tool/supabase.env.json (see .vscode/launch.json).',
      );
    }

    if (!urlLower.startsWith('https://') || !urlLower.contains('.supabase.co')) {
      throw StateError(
        'SUPABASE_URL looks invalid: "$supabaseUrl"\n'
        'Expected format: https://<project-ref>.supabase.co',
      );
    }

    if (kDebugMode && supabaseAnonKey.contains('service_role')) {
      throw StateError(
        'Do not use the Supabase service_role key in a client app. '
        'Use the anon public key instead.',
      );
    }
  }
}
