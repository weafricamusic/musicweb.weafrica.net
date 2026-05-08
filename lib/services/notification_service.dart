import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Service for handling push notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  
  factory NotificationService() {
    return _instance;
  }
  
  NotificationService._internal();

  static NotificationService get instance => _instance;

  /// Initialize the notification service
  Future<void> initialize() async {
    debugPrint('NotificationService initialized');
  }

  /// Clear the app badge count
  Future<void> clearBadge() async {
    debugPrint('NotificationService badge cleared');
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    return true;
  }

  /// Get the device token for push notifications
  Future<String?> getDeviceToken() async {
    return null;
  }

  String? _fcmToken;

  /// Backwards-compatible API: get FCM token
  Future<String?> getFcmToken({bool refresh = false}) async {
    if (refresh) {
      _fcmToken = await FirebaseMessaging.instance.getToken();
    } else {
      _fcmToken ??= await getDeviceToken();
    }
    return _fcmToken;
  }

  /// Backwards-compatible getter for last-known token
  String? get fcmToken => _fcmToken;

  /// Backwards-compatible placeholder for backend base URL
  String? get pushBackendBaseUrl => null;

  /// Backwards-compatible: register/refresh device token now
  Future<void> registerDeviceTokenNow([String? token]) async {
    if (token != null) {
      _fcmToken = token;
    } else {
      _fcmToken = await getDeviceToken();
    }
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    debugPrint('Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    debugPrint('Unsubscribed from topic: $topic');
  }
}

/// Background message handler used by `main_web.dart` registration.
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Placeholder: handle background messages as needed.
  return;
}