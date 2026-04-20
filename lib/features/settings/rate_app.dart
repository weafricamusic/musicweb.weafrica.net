import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the store review page (or a reasonable fallback).
///
/// Notes:
/// - Uses HTTPS pages so the flow can remain in-app.
/// - iOS needs an App Store numeric ID for a direct review link; if not
///   provided we fall back to an App Store search.
Future<bool> rateApp({String? iosAppStoreId}) async {
  final info = await PackageInfo.fromPlatform();
  final packageName = info.packageName;

  Uri primary;

  if (kIsWeb) {
    primary = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
  } else {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        primary = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
        break;
      case TargetPlatform.iOS:
        final id = iosAppStoreId?.trim();
        if (id != null && id.isNotEmpty) {
          primary = Uri.parse('https://apps.apple.com/app/id$id?action=write-review');
        } else {
          primary = Uri.parse(
            'https://apps.apple.com/us/search?term=${Uri.encodeComponent(info.appName)}',
          );
        }
        break;
      default:
        primary = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
        break;
    }
  }

  return launchUrl(primary, mode: LaunchMode.inAppBrowserView);
}
