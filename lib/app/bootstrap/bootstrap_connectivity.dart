import 'package:connectivity_plus/connectivity_plus.dart';

/// Best-effort offline detection.
///
/// Supports both older and newer connectivity_plus return types.
Future<bool> checkIsOffline() async {
  try {
    final dynamic result = await Connectivity().checkConnectivity();
    if (result is ConnectivityResult) {
      return result == ConnectivityResult.none;
    }
    if (result is List<ConnectivityResult>) {
      return result.isEmpty || result.every((r) => r == ConnectivityResult.none);
    }
    return false;
  } catch (_) {
    return false;
  }
}
