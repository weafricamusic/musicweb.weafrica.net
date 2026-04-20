import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/notification_log.dart';
import '../services/notification_analytics_service.dart';

/// Repository for notification analytics queries
class NotificationAnalyticsRepository {
  final NotificationAnalyticsService _service;

  NotificationAnalyticsRepository(this._service);

  /// Get overall stats for the last N days
  Future<NotificationAnalyticsSummary?> getOverallStats({
    int? daysBack,
  }) async {
    try {
      return await _service.getOverallStats();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting overall stats: $e');
      return null;
    }
  }

  /// Get stats for all notification types
  Future<List<NotificationAnalyticsSummary>> getTypeAnalytics() async {
    try {
      return await _service.getStatsByType();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting type analytics: $e');
      return [];
    }
  }

  /// Get stats for a specific notification type
  Future<NotificationAnalyticsSummary?> getTypeAnalytics$(
    NotificationType type,
  ) async {
    try {
      final allStats = await _service.getStatsByType();
      return allStats.firstWhere(
        (s) => (s.segmentName ?? '') == type.toJsonString(),
        orElse: () =>
            NotificationAnalyticsSummary(
              totalSent: 0,
              totalDelivered: 0,
              totalOpened: 0,
              totalFailed: 0,
              deliveryRatePct: 0.0,
              openRatePct: 0.0,
            ),
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error getting type analytics: $e');
      return null;
    }
  }

  /// Get geographic analytics
  Future<List<NotificationAnalyticsSummary>> getGeographicAnalytics() async {
    try {
      return await _service.getStatsByCountry();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting geographic analytics: $e');
      return [];
    }
  }

  /// Get analytics by user role
  Future<List<NotificationAnalyticsSummary>> getRoleAnalytics() async {
    try {
      return await _service.getStatsByRole();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting role analytics: $e');
      return [];
    }
  }

  /// Get hourly trends for visualization
  Future<List<NotificationHourlyTrend>> getHourlyTrends({
    int daysBack = 7,
  }) async {
    try {
      final trends = await _service.getHourlyTrends();
      // Filter by days if needed
      return trends;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting hourly trends: $e');
      return [];
    }
  }

  /// Get optimal send times based on open rate patterns
  Future<Map<int, double>> getOptimalSendTimes() async {
    try {
      final trends = await getHourlyTrends();
      final byHour = <int, List<double>>{};

      for (final trend in trends) {
        final hour = trend.hour.hour;
        byHour.putIfAbsent(hour, () => []).add(trend.deliveryRatePct);
      }

      final averages = <int, double>{};
      for (final entry in byHour.entries) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        averages[entry.key] = avg;
      }

      return averages;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting optimal send times: $e');
      return {};
    }
  }

  /// Get token health status
  Future<List<TokenHealthDiagnostic>> getTokenHealth() async {
    try {
      return await _service.getTokenHealth();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting token health: $e');
      return [];
    }
  }

  /// Get count of tokens that should be invalidated
  Future<int> getInvalidTokenCount() async {
    try {
      final tokens = await _service.getTokensToInvalidate();
      return tokens.length;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting invalid token count: $e');
      return 0;
    }
  }

  /// Perform cleanup of invalid tokens
  Future<void> cleanupInvalidTokens() async {
    try {
      final tokens = await _service.getTokensToInvalidate();
      for (final token in tokens) {
        await _service.invalidateToken(token);
      }

      if (kDebugMode) {
        print('🧹 Cleaned up ${tokens.length} invalid tokens');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error cleaning up tokens: $e');
    }
  }

  /// Get user's notification history
  Future<List<NotificationLog>> getUserNotificationHistory(
    String userId, {
    int limit = 20,
  }) async {
    try {
      return await _service.getUserNotifications(userId, limit: limit);
    } catch (e) {
      if (kDebugMode) print('❌ Error getting user history: $e');
      return [];
    }
  }

  /// Get engagement metrics for a notification type
  Future<NotificationEngagementMetrics> getEngagementMetrics(
    NotificationType type,
  ) async {
    try {
      final stats = await getTypeAnalytics$(type);
      final notifications = await _service.getNotificationsByType(type, limit: 100);

        final withOpen = notifications.where((n) => n.secondsToOpen != null).toList();
        final avgTimeToOpen = withOpen.isEmpty
          ? 0.0
          : withOpen.fold<double>(0, (sum, n) => sum + (n.secondsToOpen ?? 0)) / withOpen.length;

      return NotificationEngagementMetrics(
        type: type,
        totalSent: stats?.totalSent ?? 0,
        totalOpened: stats?.totalOpened ?? 0,
        openRate: stats?.openRatePct ?? 0.0,
        avgTimeToOpenSeconds: avgTimeToOpen.toInt(),
        bestPerformingCountry: null, // Would need more data to determine
        bestPerformingRole: null,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error getting engagement metrics: $e');
      return NotificationEngagementMetrics(
        type: type,
        totalSent: 0,
        totalOpened: 0,
        openRate: 0.0,
        avgTimeToOpenSeconds: 0,
      );
    }
  }

  /// Get recommendations for improving engagement
  Future<List<NotificationRecommendation>> getRecommendations() async {
    try {
      final recommendations = <NotificationRecommendation>[];

      // Recommendation 1: Check token health
      final invalidCount = await getInvalidTokenCount();
      if (invalidCount > 0) {
        recommendations.add(
          NotificationRecommendation(
            title: 'Remove Invalid Tokens',
            description:
                'You have $invalidCount tokens with >50% failure rate. Consider removing them.',
            priority: Priority.high,
            action: 'Cleanup',
          ),
        );
      }

      // Recommendation 2: Check overall delivery rate
      final overallStats = await getOverallStats();
      if (overallStats != null && overallStats.deliveryRatePct < 85) {
        recommendations.add(
          NotificationRecommendation(
            title: 'Low Delivery Rate',
            description:
                'Your delivery rate is ${overallStats.deliveryRatePct}%. Check token health.',
            priority: Priority.medium,
            action: 'Check Tokens',
          ),
        );
      }

      // Recommendation 3: Optimal send time
      final optimalTimes = await getOptimalSendTimes();
      if (optimalTimes.isNotEmpty) {
        final bestHour = optimalTimes.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
        recommendations.add(
          NotificationRecommendation(
            title: 'Optimal Send Time',
            description: 'Users are most engaged at $bestHour:00 UTC',
            priority: Priority.low,
            action: 'Schedule',
          ),
        );
      }

      return recommendations;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting recommendations: $e');
      return [];
    }
  }
}

/// Engagement metrics for a specific notification type
class NotificationEngagementMetrics {
  final NotificationType type;
  final int totalSent;
  final int totalOpened;
  final double openRate;
  final int avgTimeToOpenSeconds;
  final String? bestPerformingCountry;
  final String? bestPerformingRole;

  NotificationEngagementMetrics({
    required this.type,
    required this.totalSent,
    required this.totalOpened,
    required this.openRate,
    required this.avgTimeToOpenSeconds,
    this.bestPerformingCountry,
    this.bestPerformingRole,
  });

  String get formattedOpenRate => '${openRate.toStringAsFixed(2)}%';

  String get formattedAvgTime {
    if (avgTimeToOpenSeconds < 60) {
      return '$avgTimeToOpenSeconds';
    } else if (avgTimeToOpenSeconds < 3600) {
      return '${(avgTimeToOpenSeconds / 60).toStringAsFixed(1)}min';
    } else {
      return '${(avgTimeToOpenSeconds / 3600).toStringAsFixed(1)}h';
    }
  }
}

/// Recommendation for improving notification performance
enum Priority { low, medium, high }

class NotificationRecommendation {
  final String title;
  final String description;
  final Priority priority;
  final String action;

  NotificationRecommendation({
    required this.title,
    required this.description,
    required this.priority,
    required this.action,
  });

  Color get priorityColor {
    switch (priority) {
      case Priority.low:
        return const Color(0xFF4CAF50);
      case Priority.medium:
        return const Color(0xFFFFC107);
      case Priority.high:
        return const Color(0xFFF44336);
    }
  }

  String get priorityLabel {
    switch (priority) {
      case Priority.low:
        return 'LOW';
      case Priority.medium:
        return 'MEDIUM';
      case Priority.high:
        return 'HIGH';
    }
  }
}
