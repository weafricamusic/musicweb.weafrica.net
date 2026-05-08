import 'package:flutter/foundation.dart';
import 'agora_web_adapter.dart' if (dart.library.html) 'agora_web_adapter.dart';

class AgoraUnifiedService {
  static Future<void> joinAsHost(String channel, String token, String uid) async {
    if (kIsWeb) {
      await AgoraWebAdapter.joinRTCAsHost(channel, token, uid);
    } else {
      // Use existing native implementation
      // await AgoraService.joinChannel(...)
    }
  }
  
  static Future<void> sendGift(String toUser, Map<String, dynamic> gift) async {
    if (kIsWeb) {
      await AgoraWebAdapter.sendGift(toUser, gift);
    } else {
      // Native RTM implementation
    }
  }
}
