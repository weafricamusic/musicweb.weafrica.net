enum NotificationType {
  likeUpdate('like_update'),
  commentUpdate('comment_update'),
  liveBattle('live_battle'),
  coinReward('coin_reward'),
  newSong('new_song'),
  newVideo('new_video'),
  followNotification('follow_notification'),
  collaborationInvite('collaboration_invite'),
  systemAnnouncement('system_announcement');

  final String value;
  const NotificationType(this.value);

  factory NotificationType.fromString(String value) {
    return NotificationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NotificationType.systemAnnouncement,
    );
  }
}

enum NotificationStatus {
  draft('draft'),
  scheduled('scheduled'),
  sent('sent'),
  failed('failed');

  final String value;
  const NotificationStatus(this.value);

  factory NotificationStatus.fromString(String value) {
    return NotificationStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NotificationStatus.draft,
    );
  }
}

class PushNotification {
  final String id;
  final String createdBy; // Admin user ID
  final String title;
  final String body;
  final NotificationType notificationType;
  final Map<String, dynamic> payload;
  
  // Targeting
  final List<String> targetRoles; // consumer, artist, dj
  final List<String>? targetCountries; // null = all countries
  final DateTime scheduledAt;
  
  // Status & metrics
  final NotificationStatus status;
  final int totalRecipients;
  final int totalSent;
  final int totalDelivered;
  final int totalOpened;
  final String? failureReason;
  
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime updatedAt;

  PushNotification({
    required this.id,
    required this.createdBy,
    required this.title,
    required this.body,
    required this.notificationType,
    required this.payload,
    required this.targetRoles,
    this.targetCountries,
    required this.scheduledAt,
    required this.status,
    required this.totalRecipients,
    required this.totalSent,
    required this.totalDelivered,
    required this.totalOpened,
    this.failureReason,
    required this.createdAt,
    this.sentAt,
    required this.updatedAt,
  });

  factory PushNotification.fromJson(Map<String, dynamic> json) {
    return PushNotification(
      id: json['id'] as String,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      notificationType: NotificationType.fromString(json['notification_type'] as String),
      payload: json['payload'] as Map<String, dynamic>,
      targetRoles: List<String>.from(json['target_roles'] as List? ?? []),
      targetCountries: json['target_countries'] != null
          ? List<String>.from(json['target_countries'] as List)
          : null,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      status: NotificationStatus.fromString(json['status'] as String),
      totalRecipients: json['total_recipients'] as int? ?? 0,
      totalSent: json['total_sent'] as int? ?? 0,
      totalDelivered: json['total_delivered'] as int? ?? 0,
      totalOpened: json['total_opened'] as int? ?? 0,
      failureReason: json['failure_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      sentAt: json['sent_at'] != null ? DateTime.parse(json['sent_at'] as String) : null,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_by': createdBy,
    'title': title,
    'body': body,
    'notification_type': notificationType.value,
    'payload': payload,
    'target_roles': targetRoles,
    'target_countries': targetCountries,
    'scheduled_at': scheduledAt.toIso8601String(),
    'status': status.value,
    'total_recipients': totalRecipients,
    'total_sent': totalSent,
    'total_delivered': totalDelivered,
    'total_opened': totalOpened,
    'failure_reason': failureReason,
    'created_at': createdAt.toIso8601String(),
    'sent_at': sentAt?.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  PushNotification copyWith({
    String? id,
    String? createdBy,
    String? title,
    String? body,
    NotificationType? notificationType,
    Map<String, dynamic>? payload,
    List<String>? targetRoles,
    List<String>? targetCountries,
    DateTime? scheduledAt,
    NotificationStatus? status,
    int? totalRecipients,
    int? totalSent,
    int? totalDelivered,
    int? totalOpened,
    String? failureReason,
    DateTime? createdAt,
    DateTime? sentAt,
    DateTime? updatedAt,
  }) {
    return PushNotification(
      id: id ?? this.id,
      createdBy: createdBy ?? this.createdBy,
      title: title ?? this.title,
      body: body ?? this.body,
      notificationType: notificationType ?? this.notificationType,
      payload: payload ?? this.payload,
      targetRoles: targetRoles ?? this.targetRoles,
      targetCountries: targetCountries ?? this.targetCountries,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      status: status ?? this.status,
      totalRecipients: totalRecipients ?? this.totalRecipients,
      totalSent: totalSent ?? this.totalSent,
      totalDelivered: totalDelivered ?? this.totalDelivered,
      totalOpened: totalOpened ?? this.totalOpened,
      failureReason: failureReason ?? this.failureReason,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get deliveryRate {
    if (totalSent == 0) return 0;
    return (totalDelivered / totalSent) * 100;
  }

  double get openRate {
    if (totalDelivered == 0) return 0;
    return (totalOpened / totalDelivered) * 100;
  }

  @override
  String toString() => 'PushNotification(id: $id, title: $title, status: ${status.value})';
}
