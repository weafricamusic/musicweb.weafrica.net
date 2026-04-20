enum DevicePlatform {
  ios('ios'),
  android('android'),
  web('web');

  final String value;
  const DevicePlatform(this.value);

  factory DevicePlatform.fromString(String value) {
    return DevicePlatform.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Invalid platform: $value'),
    );
  }
}

class NotificationDeviceToken {
  final String id;
  final String userId;
  final String fcmToken;
  final DevicePlatform platform;
  final bool isActive;
  final String? countryCode;
  final String? appVersion;
  final String? deviceModel;
  final DateTime lastUpdated;
  final DateTime createdAt;

  NotificationDeviceToken({
    required this.id,
    required this.userId,
    required this.fcmToken,
    required this.platform,
    required this.isActive,
    this.countryCode,
    this.appVersion,
    this.deviceModel,
    required this.lastUpdated,
    required this.createdAt,
  });

  factory NotificationDeviceToken.fromJson(Map<String, dynamic> json) {
    return NotificationDeviceToken(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      fcmToken: json['fcm_token'] as String,
      platform: DevicePlatform.fromString(json['platform'] as String),
      isActive: json['is_active'] as bool,
      countryCode: json['country_code'] as String?,
      appVersion: json['app_version'] as String?,
      deviceModel: json['device_model'] as String?,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'fcm_token': fcmToken,
    'platform': platform.value,
    'is_active': isActive,
    'country_code': countryCode,
    'app_version': appVersion,
    'device_model': deviceModel,
    'last_updated': lastUpdated.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  NotificationDeviceToken copyWith({
    String? id,
    String? userId,
    String? fcmToken,
    DevicePlatform? platform,
    bool? isActive,
    String? countryCode,
    String? appVersion,
    String? deviceModel,
    DateTime? lastUpdated,
    DateTime? createdAt,
  }) {
    return NotificationDeviceToken(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fcmToken: fcmToken ?? this.fcmToken,
      platform: platform ?? this.platform,
      isActive: isActive ?? this.isActive,
      countryCode: countryCode ?? this.countryCode,
      appVersion: appVersion ?? this.appVersion,
      deviceModel: deviceModel ?? this.deviceModel,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'NotificationDeviceToken(id: $id, userId: $userId, platform: ${platform.value})';
}
