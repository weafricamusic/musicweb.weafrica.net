import 'package:flutter/foundation.dart';
import '../../../../app/config/app_env.dart';

/// Agora configuration constants — all platforms.
///
/// IMPORTANT: This file NEVER contains the App Certificate.
/// The App ID is sourced from [AppEnv] so there is a single source of truth.
class AgoraConstants {
  /// App ID — sourced from [AppEnv.agoraAppId] for a single source of truth.
  /// Use [AppEnv.validateAgoraAppId()] before SDK initialization.
  static String get appId => AppEnv.agoraAppId;

  /// Token server URL — sourced from [AppEnv.agoraTokenServerUrl].
  static String get tokenServerUrl => AppEnv.agoraTokenServerUrl;

  /// Default UID: 0 means Agora assigns automatically.
  static const int defaultUid = 0;

  /// Heartbeat interval in seconds.
  static const int heartbeatInterval = 30;

  /// Validates the App ID at runtime. Call before any Agora SDK init.
  static void validateAppId() {
    AppEnv.validateAgoraAppId();
    final id = appId;
    if (kDebugMode) {
      final redacted = '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
      debugPrint('📋 AgoraConstants — App ID validated: $redacted (len=${id.length})');
    }
  }
}
