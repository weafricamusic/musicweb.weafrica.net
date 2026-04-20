import 'package:flutter/services.dart';

class FlutterAppBadger {
  static const MethodChannel _channel = MethodChannel('flutter_app_badger');

  static Future<bool> isAppBadgeSupported() async {
    final result = await _channel.invokeMethod<bool>('isAppBadgeSupported');
    return result ?? false;
  }

  static Future<void> updateBadgeCount(int count) async {
    await _channel.invokeMethod<void>('updateBadgeCount', <String, dynamic>{
      'count': count,
    });
  }

  static Future<void> removeBadge() async {
    await _channel.invokeMethod<void>('removeBadge');
  }
}
