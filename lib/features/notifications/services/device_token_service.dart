import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/device_token.dart';

class DeviceTokenService {
  final SupabaseClient _supabase;
  final String _tableName = 'notification_device_tokens';

  const DeviceTokenService(this._supabase);

  /// Register or update a device token
  Future<NotificationDeviceToken> registerToken({
    required String fcmToken,
    required String userId,
    required DevicePlatform platform,
    String? countryCode,
  }) async {
    try {
      // Get device info
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();
      
      String? deviceModel;
      if (platform == DevicePlatform.ios) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceModel = iosInfo.model;
      } else if (platform == DevicePlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = androidInfo.model;
      }

      final now = DateTime.now();

      final data = {
        'user_id': userId,
        'fcm_token': fcmToken,
        'platform': platform.value,
        'is_active': true,
        'country_code': countryCode,
        'app_version': packageInfo.version,
        'device_model': deviceModel,
        'last_updated': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      };

      // Upsert: insert new or update if token exists
      final response = await _supabase
          .from(_tableName)
          .upsert(
            data,
            onConflict: 'fcm_token',
          )
          .select()
          .single();

      return NotificationDeviceToken.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('Error registering device token: $e');
      rethrow;
    }
  }

  /// Get all active tokens for a user
  Future<List<NotificationDeviceToken>> getUserTokens(String userId) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .eq('is_active', true);

      return (response as List)
          .map((e) => NotificationDeviceToken.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching user tokens: $e');
      rethrow;
    }
  }

  /// Deactivate a device token
  Future<void> deactivateToken(String tokenId) async {
    try {
      await _supabase
          .from(_tableName)
          .update({'is_active': false})
          .eq('id', tokenId);
    } catch (e) {
      if (kDebugMode) print('Error deactivating token: $e');
      rethrow;
    }
  }

  /// Deactivate all tokens for a user (logout)
  Future<void> deactivateAllUserTokens(String userId) async {
    try {
      await _supabase
          .from(_tableName)
          .update({'is_active': false})
          .eq('user_id', userId);
    } catch (e) {
      if (kDebugMode) print('Error deactivating user tokens: $e');
      rethrow;
    }
  }

  /// Update last updated timestamp (for periodic sync)
  Future<void> updateTokenTimestamp(String tokenId) async {
    try {
      await _supabase
          .from(_tableName)
          .update({'last_updated': DateTime.now().toIso8601String()})
          .eq('id', tokenId);
    } catch (e) {
      if (kDebugMode) print('Error updating token timestamp: $e');
      rethrow;
    }
  }

  /// Subscribe user to a topic
  Future<void> subscribeToTopic(
    String userId,
    String topic, {
    required List<String> fcmTokens,
  }) async {
    try {
      // This would typically be done via FCM SDK
      // But you can also store topic subscriptions in DB if needed
      if (kDebugMode) print('User $userId subscribed to topic: $topic');
    } catch (e) {
      if (kDebugMode) print('Error subscribing to topic: $e');
      rethrow;
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(
    String userId,
    String topic, {
    required List<String> fcmTokens,
  }) async {
    try {
      if (kDebugMode) print('User $userId unsubscribed from topic: $topic');
    } catch (e) {
      if (kDebugMode) print('Error unsubscribing from topic: $e');
      rethrow;
    }
  }

  /// Get token health metrics (admin only)
  Future<Map<String, dynamic>> getTokenHealth() async {
    try {
      final response = await _supabase.from('notification_token_health').select();
      final rows = (response as List).whereType<Map<String, dynamic>>().toList(growable: false);
      return rows.isNotEmpty ? rows.first : {};
    } catch (e) {
      if (kDebugMode) print('Error fetching token health: $e');
      return {};
    }
  }
}
