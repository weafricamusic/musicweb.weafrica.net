import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_log.dart';

/// Service to log and query notification analytics
class NotificationAnalyticsService {
  final SupabaseClient _supabase;

  NotificationAnalyticsService(this._supabase);

  /// Log notification sent event
  Future<void> logNotificationSent({
    required String userId,
    required String token,
    required NotificationType type,
    required Map<String, dynamic> payload,
    String? countryCode,
    UserRoleAnalytics? role,
  }) async {
    try {
      await _supabase.from('notification_logs').insert({
        'user_id': userId,
        'token': token,
        'type': type.toJsonString(),
        'payload': payload,
        'status': NotificationStatus.sent.toJsonString(),
        'country_code': countryCode,
        'role': role?.toJsonString(),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) print('❌ Error logging notification sent: $e');
      rethrow;
    }
  }

  /// Log notification delivery confirmation
  Future<void> logNotificationDelivered({
    required String userId,
    required String token,
    required NotificationType type,
  }) async {
    try {
      await _supabase
          .from('notification_logs')
          .update({
            'status': NotificationStatus.delivered.toJsonString(),
            'delivered_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('token', token)
          .eq('type', type.toJsonString())
          .eq('status', NotificationStatus.sent.toJsonString())
          .order('created_at', ascending: false)
          .limit(1);
    } catch (e) {
      if (kDebugMode) print('❌ Error logging notification delivered: $e');
      rethrow;
    }
  }

  /// Log notification delivery failure
  Future<void> logNotificationFailed({
    required String userId,
    required String token,
    required NotificationType type,
    required String failureReason,
  }) async {
    try {
      await _supabase.from('notification_logs').insert({
        'user_id': userId,
        'token': token,
        'type': type.toJsonString(),
        'status': NotificationStatus.failed.toJsonString(),
        'failure_reason': failureReason,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) print('❌ Error logging notification failed: $e');
      // Don't rethrow - this shouldn't block the app
    }
  }

  /// Log notification opened by user (tapped)
  /// Should be called from FirebaseMessaging.onMessageOpenedApp listener
  Future<void> logNotificationOpened({
    required String userId,
    required String? notificationId,
  }) async {
    try {
      final id = (notificationId ?? '').trim();
      if (id.isEmpty) return;

      await _supabase
          .from('notification_logs')
          .update({
            'status': NotificationStatus.opened.toJsonString(),
            'opened_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);

      if (kDebugMode) print('✅ Logged notification opened for user $userId');
    } catch (e) {
      if (kDebugMode) print('❌ Error logging notification opened: $e');
      // Don't rethrow
    }
  }

  /// Log user completed action from notification (like, comment, join, etc)
  Future<void> logNotificationClicked({
    required String userId,
    required String? notificationId,
  }) async {
    try {
      if (notificationId != null) {
        await _supabase
            .from('notification_logs')
            .update({
              'status': NotificationStatus.clicked.toJsonString(),
              'clicked_at': DateTime.now().toIso8601String(),
            })
            .eq('id', notificationId);
      }

      if (kDebugMode) print('✅ Logged notification clicked for user $userId');
    } catch (e) {
      if (kDebugMode) print('❌ Error logging notification clicked: $e');
    }
  }

  /// Get overall delivery statistics
  Future<NotificationAnalyticsSummary?> getOverallStats() async {
    try {
      final result = await _supabase
          .from('notification_delivery_stats')
          .select()
          .limit(1)
          .single();

      return NotificationAnalyticsSummary.fromSupabase(result);
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching overall stats: $e');
      return null;
    }
  }

  /// Get analytics by notification type
  Future<List<NotificationAnalyticsSummary>> getStatsByType() async {
    try {
      final results = await _supabase
          .from('notification_stats_by_type')
          .select()
          .order('sent', ascending: false);

      return (results as List)
          .map((row) => NotificationAnalyticsSummary.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching stats by type: $e');
      return [];
    }
  }

  /// Get analytics by country
  Future<List<NotificationAnalyticsSummary>> getStatsByCountry() async {
    try {
      final results = await _supabase
          .from('notification_stats_by_country')
          .select()
          .order('sent', ascending: false);

      return (results as List)
          .map((row) => NotificationAnalyticsSummary.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching stats by country: $e');
      return [];
    }
  }

  /// Get analytics by user role
  Future<List<NotificationAnalyticsSummary>> getStatsByRole() async {
    try {
      final results = await _supabase
          .from('notification_stats_by_role')
          .select()
          .order('sent', ascending: false);

      return (results as List)
          .map((row) => NotificationAnalyticsSummary.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching stats by role: $e');
      return [];
    }
  }

  /// Get hourly trends for last 7 days
  Future<List<NotificationHourlyTrend>> getHourlyTrends() async {
    try {
      final results = await _supabase
          .from('notification_hourly_trends')
          .select()
          .order('hour', ascending: false);

      return (results as List)
          .map((row) => NotificationHourlyTrend.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching hourly trends: $e');
      return [];
    }
  }

  /// Get device token health diagnostics
  Future<List<TokenHealthDiagnostic>> getTokenHealth() async {
    try {
      final results = await _supabase
          .from('notification_token_health')
          .select()
          .order('failure_rate_pct', ascending: false);

      return (results as List)
          .map((row) => TokenHealthDiagnostic.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching token health: $e');
      return [];
    }
  }

  /// Get unhealthy tokens that should be invalidated
  Future<List<String>> getTokensToInvalidate() async {
    try {
      final tokens = await getTokenHealth();
      return tokens
          .where((t) => t.shouldInvalidate)
          .map((t) => t.token)
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching tokens to invalidate: $e');
      return [];
    }
  }

  /// Invalidate/remove a device token from users
  Future<void> invalidateToken(String token) async {
    try {
      await _supabase
          .from('notification_logs')
          .update({'status': 'failed', 'failure_reason': 'token_invalidated'})
          .eq('token', token)
          .filter('status', 'eq', NotificationStatus.sent.toJsonString());

      if (kDebugMode) print('🗑️ Invalidated token: $token');
    } catch (e) {
      if (kDebugMode) print('❌ Error invalidating token: $e');
    }
  }

  /// Get recent notifications for a specific user
  Future<List<NotificationLog>> getUserNotifications(
    String userId, {
    int limit = 20,
  }) async {
    try {
      final results = await _supabase
          .from('notification_logs')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (results as List)
          .map((row) => NotificationLog.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching user notifications: $e');
      return [];
    }
  }

  /// Get notifications of specific type
  Future<List<NotificationLog>> getNotificationsByType(
    NotificationType type, {
    int limit = 50,
  }) async {
    try {
      final results = await _supabase
          .from('notification_logs')
          .select()
          .eq('type', type.toJsonString())
          .order('created_at', ascending: false)
          .limit(limit);

      return (results as List)
          .map((row) => NotificationLog.fromSupabase(row))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching notifications by type: $e');
      return [];
    }
  }
}
