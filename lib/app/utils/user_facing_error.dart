import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/debug_flags.dart';

/// Helpers for user-facing errors.
///
/// In production UI, we should never show raw backend / exception strings.
class UserFacingError {
  static String message(
    Object? error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error == null) return fallback;

    if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    }

    // Never surface runtime/programming errors to end users.
    if (error is Error) return fallback;

    final raw = error.toString().trim();
    if (raw.isEmpty) return fallback;

    // Multi-line errors usually include stack traces or internal details.
    if (raw.contains('\n') || raw.contains('\r')) return fallback;
    final rawLower = raw.toLowerCase();

    final cleaned = raw
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^StateError:\s*'), '')
      .replaceFirst(RegExp(r'^Error:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .replaceFirst(RegExp(r'^Invalid argument\(s\):\s*'), '')
      .trim();
    final lower = cleaned.toLowerCase();

    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    // Firebase Auth often reports connectivity issues via canonical codes/phrases.
    if (lower.contains('network-request-failed') ||
        lower.contains('a network error') ||
        lower.contains('unable to establish connection')) {
      return 'Network error. Check internet access, disable VPN/proxy if enabled, and verify device date/time.';
    }

    if (lower.contains('cancelled') || lower.contains('canceled')) {
      return 'Cancelled.';
    }

    // Avoid importing dart:io here (web builds). Detect common network strings.
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('no address associated') ||
        (lower.contains('connection') && lower.contains('refused')) ||
        lower.contains('handshake') ||
        lower.contains('dns')) {
      return 'Check your internet connection and try again.';
    }

    if (lower.contains('not logged in') ||
        lower.contains('not signed in') ||
        lower.contains('unauthorized') ||
        lower.contains('unauthorised') ||
        lower.contains('forbidden') ||
        lower.contains('permission denied') ||
        lower.contains('missing firebase id token') ||
        lower.contains('missing id token') ||
        lower.contains('unauthenticated')) {
      return 'Please sign in and try again.';
    }

    if (_looksInternalOrSensitive(rawLower) || _looksInternalOrSensitive(lower)) {
      return fallback;
    }

    if (cleaned.startsWith('{') || cleaned.startsWith('[')) {
      return fallback;
    }

    // Allow short, non-technical messages through (e.g., app-thrown Exceptions).
    if (cleaned.isNotEmpty && cleaned.length <= 140) {
      return cleaned;
    }

    return fallback;
  }

  /// Returns raw error details only when developer UI is enabled.
  static String? details(Object? error) {
    if (!DebugFlags.showDeveloperUi) return null;
    final raw = (error ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return raw;
  }

  static void log(String context, Object error, [StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    debugPrint('$context: $error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static bool _looksInternalOrSensitive(String lower) {
    const keywords = <String>[
      // Provider / backend names.
      'supabase',
      'postgrest',
      'postgres',
      'firebase',
      'vercel',
      'edge function',
      'cloud function',
      'functions.',
      'backend',

      // Common crash / runtime strings.
      'null check operator used on a null value',
      'nosuchmethoderror',
      'lateinitializationerror',
      'rangeerror',
      'typeerror',
      'formatexception',
      'cast error',
      'is not a subtype of',
      'bad state: no element',
      'stream has already been listened to',
      'concurrent modification',
      'setstate() called after dispose',
      "looking up a deactivated widget's ancestor",
      'renderflex overflowed',
      'failed assertion',
      'assertion failed',

      // Common secrets / identifiers.
      'bearer ',
      'token',
      'jwt',
      'secret',
      'apikey',
      'api key',
      'key=',
      'weafrica_',
      'dart-define',

      // URLs / endpoints.
      'http://',
      'https://',
      '/api/',
      'endpoint',
      'package:',
      'dart:',
      'lib/',

      // DB / schema error terms.
      'sql',
      'schema',
      'migration',
      'table ',
      'column ',
      'constraint',
      'violates',
      'not-null',
      'null value in column',
      'rls',
      'row level security',
      'stack trace',
      'stacktrace',
    ];

    for (final k in keywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }
}
