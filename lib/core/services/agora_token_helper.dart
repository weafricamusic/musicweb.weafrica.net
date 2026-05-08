import 'package:crypto/crypto.dart';
import 'dart:convert';

class AgoraTokenHelper {
  static String generateToken({
    required String appId,
    required String certificate,
    required String channelName,
    required int uid,
    required int expireSeconds,
  }) {
    // For now, return empty string - we'll implement proper token generation
    // Agora now requires dynamic tokens from your server
    // But for testing with App ID only (no certificate enabled), empty string works
    return '';
  }
}
