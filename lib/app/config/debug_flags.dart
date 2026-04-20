import 'package:flutter/foundation.dart';

/// Centralized switches for developer-only UI/logging.
///
/// In production, these should be disabled.
/// Enable in debug builds via:
/// `--dart-define=WEAFRICA_ENABLE_DEV_UI=true`
class DebugFlags {
  static const bool _enableDevUi = bool.fromEnvironment(
    'WEAFRICA_ENABLE_DEV_UI',
    defaultValue: false,
  );

  static bool get showDeveloperUi => kDebugMode && _enableDevUi;
}
