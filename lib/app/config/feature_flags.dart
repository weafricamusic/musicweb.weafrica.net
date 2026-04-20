import 'package:flutter/foundation.dart';

/// Centralized feature gating.
///
/// Rule: if a feature isn't live, it must be hidden (no "coming soon/beta/test").
///
/// Enable flags at build time, e.g.:
/// `--dart-define=WEAFRICA_FEATURE_BATTLES=true`
class FeatureFlags {
  static const bool creatorInsights = bool.fromEnvironment(
    'WEAFRICA_FEATURE_CREATOR_INSIGHTS',
    defaultValue: false,
  );

  /// Battle matchmaking + invites UI.
  /// Default is false to avoid exposing incomplete/undeployed backend paths.
  static const bool battles = bool.fromEnvironment(
    'WEAFRICA_FEATURE_BATTLES',
    defaultValue: true,
  );

  /// DJ AI assist UI.
  /// Default false: current implementation is developer tooling.
  static const bool djAiAssist = bool.fromEnvironment(
    'WEAFRICA_FEATURE_DJ_AI_ASSIST',
    defaultValue: false,
  );

  /// Convenience for quickly checking if any non-core feature is on.
  static bool get anyOptionalEnabled => creatorInsights || battles || djAiAssist;

  static void debugPrintEnabledFlags() {
    if (!kDebugMode) return;
    debugPrint(
      'FeatureFlags: insights=$creatorInsights battles=$battles djAiAssist=$djAiAssist',
    );
  }
}
