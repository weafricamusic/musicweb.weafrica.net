// Notification system configuration and constants
//
// Usage:
//   import 'notification_config.dart';
//
//   final maxTokensPerBatch = NotificationConfig.maxDeviceTokensPerRequest;

class NotificationConfig {
  NotificationConfig._(); // Private constructor

  // ============================================================================
  // DATABASE TABLES
  // ============================================================================
  
  static const String tableDeviceTokens = 'notification_device_tokens';
  static const String tableNotifications = 'notifications';
  static const String tableRecipients = 'notification_recipients';
  static const String tableEngagement = 'notification_engagement';
  
  // Analytics views
  static const String viewPerformanceSummary = 'notification_performance_summary';
  static const String viewPerformanceByType = 'notification_performance_by_type';
  static const String viewTokenHealth = 'notification_token_health';

  // ============================================================================
  // NOTIFICATION TYPES
  // ============================================================================

  static const List<String> allNotificationTypes = [
    'like_update',
    'comment_update',
    'coin_reward',
    'new_song',
    'new_video',
    'follow_notification',
    'collaboration_invite',
    'system_announcement',
  ];

  // ============================================================================
  // USER ROLES
  // ============================================================================

  static const String roleConsumer = 'consumer';
  static const String roleArtist = 'artist';
  static const String roleDJ = 'dj';
  static const String roleAdmin = 'admin';

  static const List<String> allRoles = [roleConsumer, roleArtist, roleDJ];
  static const List<String> allRolesIncludingAdmin = [
    roleConsumer,
    roleArtist,
    roleDJ,
    roleAdmin,
  ];

  // ============================================================================
  // NOTIFICATION STATUS
  // ============================================================================

  static const String statusDraft = 'draft';
  static const String statusScheduled = 'scheduled';
  static const String statusSent = 'sent';
  static const String statusFailed = 'failed';

  static const List<String> allStatuses = [
    statusDraft,
    statusScheduled,
    statusSent,
    statusFailed,
  ];

  // ============================================================================
  // ENGAGEMENT EVENT TYPES
  // ============================================================================

  static const String eventDelivered = 'delivered';
  static const String eventOpened = 'opened';
  static const String eventClicked = 'clicked';
  static const String eventDismissed = 'dismissed';

  static const List<String> allEventTypes = [
    eventDelivered,
    eventOpened,
    eventClicked,
    eventDismissed,
  ];

  // ============================================================================
  // DEVICE PLATFORMS
  // ============================================================================

  static const String platformIOS = 'ios';
  static const String platformAndroid = 'android';
  static const String platformWeb = 'web';

  static const List<String> allPlatforms = [platformIOS, platformAndroid, platformWeb];

  // ============================================================================
  // RECIPIENT STATUS
  // ============================================================================

  static const String recipientPending = 'pending';
  static const String recipientSent = 'sent';
  static const String recipientDelivered = 'delivered';
  static const String recipientFailed = 'failed';
  static const String recipientOpened = 'opened';

  // ============================================================================
  // FCM TOPICS
  // ============================================================================

  static const String topicAnnouncements = 'announcements';
  static const String topicSongs = 'songs';
  static const String topicArtistUpdates = 'artist_updates';
  static const String topicDJUpdates = 'dj_updates';

  static String topicForArtist(String artistId) => 'artist_$artistId';
  static String topicForDJ(String djId) => 'dj_$djId';
  static String topicForUser(String userId) => 'user_$userId';

  // ============================================================================
  // LIMITS & RATES
  // ============================================================================

  // FCM has a limit of ~500 devices per request
  static const int maxDeviceTokensPerRequest = 500;

  // Cloud Function scheduling interval (minutes)
  static const int sendingCheckIntervalMinutes = 5;

  // Token refresh check interval (hours)
  static const int tokenHealthRefreshIntervalHours = 24;

  // Maximum notification size (bytes) - FCM limit
  static const int maxFCMPayloadBytes = 4096;

  // Dashboard pagination
  static const int dashboardItemsPerPage = 20;

  // Analytics look-back period (days)
  static const int analyticsLookbackDays = 30;

  // ============================================================================
  // TIMEOUTS
  // ============================================================================

  static const Duration fcmInitTimeout = Duration(seconds: 30);
  static const Duration fcmSendTimeout = Duration(seconds: 10);
  static const Duration supabaseQueryTimeout = Duration(seconds: 5);

  // ============================================================================
  // ANALYTICS METRICS
  // ============================================================================

  /// Calculate delivery rate
  static double calculateDeliveryRate(int delivered, int sent) {
    if (sent == 0) return 0;
    return (delivered / sent) * 100;
  }

  /// Calculate open rate
  static double calculateOpenRate(int opened, int delivered) {
    if (delivered == 0) return 0;
    return (opened / delivered) * 100;
  }

  /// Calculate click-through rate (CTR)
  static double calculateCTR(int clicked, int opened) {
    if (opened == 0) return 0;
    return (clicked / opened) * 100;
  }

  // ============================================================================
  // COUNTRY CODES (ISO 3166-1 Alpha-2)
  // ============================================================================

  static const List<String> africanCountries = [
    'DZ', // Algeria
    'AO', // Angola
    'BJ', // Benin
    'BW', // Botswana
    'BF', // Burkina Faso
    'BI', // Burundi
    'CM', // Cameroon
    'CV', // Cape Verde
    'CF', // Central African Republic
    'TD', // Chad
    'KM', // Comoros
    'CG', // Congo
    'CD', // Democratic Republic of Congo
    'CI', // Côte d'Ivoire
    'DJ', // Djibouti
    'EG', // Egypt
    'GQ', // Equatorial Guinea
    'ER', // Eritrea
    'ET', // Ethiopia
    'GA', // Gabon
    'GM', // Gambia
    'GH', // Ghana
    'GN', // Guinea
    'GW', // Guinea-Bissau
    'KE', // Kenya
    'LS', // Lesotho
    'LR', // Liberia
    'LY', // Libya
    'MG', // Madagascar
    'MW', // Malawi
    'ML', // Mali
    'MR', // Mauritania
    'MU', // Mauritius
    'YT', // Mayotte
    'MA', // Morocco
    'MZ', // Mozambique
    'NA', // Namibia
    'NE', // Niger
    'NG', // Nigeria
    'RE', // Réunion
    'RW', // Rwanda
    'SH', // Saint Helena
    'ST', // São Tomé and Príncipe
    'SN', // Senegal
    'SC', // Seychelles
    'SL', // Sierra Leone
    'SO', // Somalia
    'ZA', // South Africa
    'SS', // South Sudan
    'SD', // Sudan
    'SZ', // Eswatini
    'TZ', // Tanzania
    'TG', // Togo
    'TN', // Tunisia
    'UG', // Uganda
    'ZM', // Zambia
    'ZW', // Zimbabwe
  ];

  static const Map<String, String> countryNames = {
    'NG': 'Nigeria',
    'GH': 'Ghana',
    'KE': 'Kenya',
    'ZA': 'South Africa',
    'EG': 'Egypt',
    'TZ': 'Tanzania',
    'UG': 'Uganda',
    'RW': 'Rwanda',
    'SN': 'Senegal',
    'MA': 'Morocco',
    'ET': 'Ethiopia',
    'CI': 'Côte d\'Ivoire',
    'CM': 'Cameroon',
    'CD': 'Democratic Republic of Congo',
    'MZ': 'Mozambique',
    'MW': 'Malawi',
    'ZM': 'Zambia',
    'ZW': 'Zimbabwe',
    'NA': 'Namibia',
    'BW': 'Botswana',
    'LS': 'Lesotho',
    'SZ': 'Eswatini',
  };

  // ============================================================================
  // ERROR MESSAGES
  // ============================================================================

  static const String errorNotAuthenticated = 'User not authenticated';
  static const String errorNotAdmin = 'Only admins can perform this action';
  static const String errorTokenNotFound = 'Device token not found';
  static const String errorNotificationNotFound = 'Notification not found';
  static const String errorInvalidNotificationType = 'Invalid notification type';
  static const String errorInvalidRole = 'Invalid user role';
  static const String errorScheduleTimeInPast = 'Schedule time must be in the future';
  static const String errorNoRecipientsMatched = 'No users matched the target criteria';

  // ============================================================================
  // SUCCESS MESSAGES
  // ============================================================================

  static const String successTokenRegistered = 'Device token registered successfully';
  static const String successTokenDeactivated = 'Device token deactivated';
  static const String successNotificationCreated = 'Notification created successfully';
  static const String successNotificationScheduled = 'Notification scheduled for sending';
  static const String successNotificationSent = 'Notification sent to {count} devices';
  static const String successTopicSubscribed = 'Subscribed to topic successfully';
  static const String successTopicUnsubscribed = 'Unsubscribed from topic successfully';

  // ============================================================================
  // LOG MESSAGES
  // ============================================================================

  static const String logInitializingFCM = '📱 Initializing FCM...';
  static const String logRegistringToken = '📝 Registering device token...';
  static const String logReceivingForeground = '📬 Receiving foreground message';
  static const String logReceivingBackground = '🔔 Receiving background message';
  static const String logUserTappedNotification = '👆 User tapped notification';
  static const String logRoutingToScreen = '🧭 Routing to screen';
  static const String logDatabaseUpdate = '💾 Updating database';
  static const String logAnalyticEvent = '📊 Logging analytic event';

  // ============================================================================
  // PAYLOAD KEYS (for custom data in notifications)
  // ============================================================================

  static const String payloadKeyType = 'type';
  static const String payloadKeyEntityId = 'entity_id';
  static const String payloadKeyScreen = 'screen';
  static const String payloadKeyNotificationId = 'notification_id';
  static const String payloadKeyDeviceToken = 'device_token';
  static const String payloadKeyTimestamp = 'timestamp';
  static const String payloadKeyUserId = 'user_id';

  // ============================================================================
  // NOTIFICATION TYPE GROUPS
  // ============================================================================

  static const List<String> coinRewardTypes = [
    'coin_reward',
  ];

  static const List<String> engagementTypes = [
    'like_update',
    'comment_update',
    'follow_notification',
  ];

  static const List<String> contentTypes = [
    'new_song',
    'new_video',
    'collaboration_invite',
  ];

  static const List<String> liveTypes = [];

  // ============================================================================
  // DEFAULT VALUES
  // ============================================================================

  static const String defaultCountryCode = 'NG'; // Nigeria
  static const List<String> defaultTargetRoles = [
    'consumer',
    'artist',
    'dj',
  ];

  // ============================================================================
  // VALIDATION REGEX
  // ============================================================================

  static final RegExp fcmTokenRegex = RegExp(
    r'^[a-zA-Z0-9_-]+$',
    multiLine: false,
  );

  static final RegExp countryCodeRegex = RegExp(
    r'^[A-Z]{2}$',
    multiLine: false,
  );

  static final RegExp uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
}

/// Helper extension for string validation
extension NotificationValidation on String {
  bool get isValidCountryCode =>
      RegExp(r'^[A-Z]{2}$').hasMatch(this);

  bool get isValidFCMToken =>
      NotificationConfig.fcmTokenRegex.hasMatch(this) && length > 100;

  bool get isValidUUID =>
      NotificationConfig.uuidRegex.hasMatch(this);
}
