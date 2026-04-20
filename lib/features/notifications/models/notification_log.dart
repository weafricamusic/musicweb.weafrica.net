import 'package:flutter/foundation.dart';

/// Notification status lifecycle
enum NotificationStatus {
  sent,
  delivered,
  failed,
  opened,
  clicked;

  String toJsonString() => name;

  static NotificationStatus fromString(String value) {
    return NotificationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotificationStatus.sent,
    );
  }
}

/// Notification type categories
enum NotificationType {
  likeUpdate('like_update'),
  commentUpdate('comment_update'),
  liveBattle('live_battle'),
  liveBattleInvite('live_battle_invite'),
  liveBattleNow('live_battle_now'),
  coinReward('coin_reward'),
  dailyBonus('daily_bonus'),
  newSong('new_song'),
  artistUpdate('artist_update'),
  djLiveStart('dj_live_start'),
  contestUpdate('contest_update'),
  unknown('unknown');

  final String value;

  const NotificationType(this.value);

  String toJsonString() => value;

  static NotificationType fromString(String? value) {
    try {
      return NotificationType.values.firstWhere((e) => e.value == value);
    } catch (_) {
      return NotificationType.unknown;
    }
  }
}

/// User role for analytics segmentation
enum UserRoleAnalytics {
  consumer,
  artist,
  dj;

  String toJsonString() => name;

  static UserRoleAnalytics? fromString(String? value) {
    if (value == null) return null;
    try {
      return UserRoleAnalytics.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return null;
    }
  }
}

/// Single notification log entry
@immutable
class NotificationLog {
  final String id;
  final String userId;
  final String token;
  final NotificationType type;
  final Map<String, dynamic> payload;
  final NotificationStatus status;
  final String? countryCode;
  final UserRoleAnalytics? role;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? openedAt;
  final DateTime? clickedAt;
  final String? failureReason;

  const NotificationLog({
    required this.id,
    required this.userId,
    required this.token,
    required this.type,
    required this.payload,
    required this.status,
    this.countryCode,
    this.role,
    required this.createdAt,
    this.deliveredAt,
    this.openedAt,
    this.clickedAt,
    this.failureReason,
  });

  /// Create from Supabase row
  factory NotificationLog.fromSupabase(Map<String, dynamic> row) {
    return NotificationLog(
      id: row['id'] ?? '',
      userId: row['user_id'] ?? '',
      token: row['token'] ?? '',
      type: NotificationType.fromString(row['type']),
      payload: (row['payload'] is String)
          ? {}
          : (row['payload'] as Map<String, dynamic>? ?? {}),
      status: NotificationStatus.fromString(row['status'] ?? 'sent'),
      countryCode: row['country_code'],
      role: UserRoleAnalytics.fromString(row['role']),
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'])
          : DateTime.now(),
      deliveredAt: row['delivered_at'] != null
          ? DateTime.parse(row['delivered_at'])
          : null,
      openedAt:
          row['opened_at'] != null ? DateTime.parse(row['opened_at']) : null,
      clickedAt:
          row['clicked_at'] != null ? DateTime.parse(row['clicked_at']) : null,
      failureReason: row['failure_reason'],
    );
  }

  /// Convert to Supabase insert payload
  Map<String, dynamic> toSupabaseInsert() => {
        'user_id': userId,
        'token': token,
        'type': type.toJsonString(),
        'payload': payload,
        'status': status.toJsonString(),
        'country_code': countryCode,
        'role': role?.toJsonString(),
        'created_at': createdAt.toIso8601String(),
      };

  /// Create copy with updated fields
  NotificationLog copyWith({
    String? id,
    String? userId,
    String? token,
    NotificationType? type,
    Map<String, dynamic>? payload,
    NotificationStatus? status,
    String? countryCode,
    UserRoleAnalytics? role,
    DateTime? createdAt,
    DateTime? deliveredAt,
    DateTime? openedAt,
    DateTime? clickedAt,
    String? failureReason,
  }) {
    return NotificationLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      countryCode: countryCode ?? this.countryCode,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      openedAt: openedAt ?? this.openedAt,
      clickedAt: clickedAt ?? this.clickedAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  /// Time elapsed since sent (in seconds)
  int? get secondsToOpen {
    if (openedAt == null) return null;
    return openedAt!.difference(createdAt).inSeconds;
  }

  /// Time elapsed since sent to click
  int? get secondsToClick {
    if (clickedAt == null) return null;
    return clickedAt!.difference(createdAt).inSeconds;
  }

  @override
  String toString() =>
      'NotificationLog(id: $id, type: ${type.value}, status: ${status.name}, user: $userId)';
}

/// Analytics summary for a segment (type, country, role, etc)
@immutable
class NotificationAnalyticsSummary {
  final String? segmentName;
  final int totalSent;
  final int totalDelivered;
  final int totalOpened;
  final int totalFailed;
  final double deliveryRatePct;
  final double openRatePct;
  final int? avgTimeToOpenSec;

  const NotificationAnalyticsSummary({
    this.segmentName,
    required this.totalSent,
    required this.totalDelivered,
    required this.totalOpened,
    required this.totalFailed,
    required this.deliveryRatePct,
    required this.openRatePct,
    this.avgTimeToOpenSec,
  });

  /// Create from analytics view row
  factory NotificationAnalyticsSummary.fromSupabase(Map<String, dynamic> row) {
    return NotificationAnalyticsSummary(
      segmentName: row['type'] ?? row['country_code'] ?? row['role'],
      totalSent: (row['sent'] as num?)?.toInt() ?? 0,
      totalDelivered: (row['delivered'] as num?)?.toInt() ?? 0,
      totalOpened: (row['opened'] as num?)?.toInt() ?? 0,
      totalFailed: (row['total_failed'] as num?)?.toInt() ?? 0,
      deliveryRatePct: (row['delivery_rate_pct'] as num?)?.toDouble() ?? 0.0,
      openRatePct: (row['open_rate_pct'] as num?)?.toDouble() ?? 0.0,
      avgTimeToOpenSec: (row['avg_time_to_open_sec'] as num?)?.toInt(),
    );
  }

  @override
  String toString() =>
      'NotificationAnalyticsSummary(segment: $segmentName, sent: $totalSent, delivery: $deliveryRatePct%, open: $openRatePct%)';
}

/// Hourly trend data point
@immutable
class NotificationHourlyTrend {
  final DateTime hour;
  final int sent;
  final int delivered;
  final int opened;
  final double deliveryRatePct;

  const NotificationHourlyTrend({
    required this.hour,
    required this.sent,
    required this.delivered,
    required this.opened,
    required this.deliveryRatePct,
  });

  factory NotificationHourlyTrend.fromSupabase(Map<String, dynamic> row) {
    return NotificationHourlyTrend(
      hour: DateTime.parse(row['hour']),
      sent: (row['sent'] as num?)?.toInt() ?? 0,
      delivered: (row['delivered'] as num?)?.toInt() ?? 0,
      opened: (row['opened'] as num?)?.toInt() ?? 0,
      deliveryRatePct: (row['delivery_rate_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Token health diagnostic
@immutable
class TokenHealthDiagnostic {
  final String token;
  final int totalAttempts;
  final int failedAttempts;
  final double failureRatePct;
  final DateTime lastAttempt;
  final List<String> failureReasons;

  const TokenHealthDiagnostic({
    required this.token,
    required this.totalAttempts,
    required this.failedAttempts,
    required this.failureRatePct,
    required this.lastAttempt,
    required this.failureReasons,
  });

  factory TokenHealthDiagnostic.fromSupabase(Map<String, dynamic> row) {
    final reasons = (row['failure_reasons'] as String?)?.split(', ') ?? [];
    return TokenHealthDiagnostic(
      token: row['token'] ?? '',
      totalAttempts: (row['total_attempts'] as num?)?.toInt() ?? 0,
      failedAttempts: (row['failed_attempts'] as num?)?.toInt() ?? 0,
      failureRatePct: (row['failure_rate_pct'] as num?)?.toDouble() ?? 0.0,
      lastAttempt: DateTime.parse(row['last_attempt']),
      failureReasons: reasons,
    );
  }

  /// Should we remove this token?
  bool get shouldInvalidate => failureRatePct > 50.0 && totalAttempts >= 3;
}
