import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';

import 'package:weafrica_music/app/config/supabase_env.dart';
import 'package:weafrica_music/app/config/api_env.dart';
import 'package:weafrica_music/app/network/firebase_authed_http.dart';
import 'package:weafrica_music/app/navigation/app_navigator.dart';
import 'package:weafrica_music/app/utils/user_facing_error.dart';
import 'package:weafrica_music/features/auth/user_role.dart';
import 'package:weafrica_music/features/live/live_screen.dart';
import 'package:weafrica_music/features/live/models/live_args.dart';
import 'package:weafrica_music/features/live/models/live_battle.dart';
import '../models/notification_log.dart';
import 'notification_analytics_service.dart';

/// Global handler for FCM background messages
/// Must be top-level function
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseEnv.load();
  // Avoid throwing during background handling; if config is missing the call
  // below will still fail, but without crashing the isolate on validate().
  await Supabase.initialize(
    url: SupabaseEnv.supabaseUrl,
    anonKey: SupabaseEnv.supabaseAnonKey,
  );

  await _handleSilentNotification(message.data);
}

/// Handle silent push notifications (background + terminated)
Future<void> _handleSilentNotification(Map<String, dynamic> data) async {
  final isSilent = data['silent'] == 'true';

  if (kDebugMode) {
    debugPrint('🔔 Background notification: silent=$isSilent, type=${data['type']}');
  }

  if (!isSilent) return;

  final type = NotificationType.fromString(data['type']);

  switch (type) {
    case NotificationType.coinReward:
    case NotificationType.dailyBonus:
      // Silent coin update - refresh user balance in the background
      await _refreshUserBalance(data);
      break;

    case NotificationType.likeUpdate:
    case NotificationType.commentUpdate:
      // Update badge count silently
      await _updateBadgeCount(data);
      break;

    case NotificationType.newSong:
      // Refresh home feed silently
      await _refreshHomeFeed();
      break;

    case NotificationType.djLiveStart:
      // Refresh live events list
      await _refreshLiveEvents();
      break;

    default:
      if (kDebugMode) debugPrint('⚠️ Unknown silent notification type: $type');
  }
}

Future<void> _refreshUserBalance(Map<String, dynamic> data) async {
  // Implement user balance refresh from Supabase
  if (kDebugMode) debugPrint('💰 Refreshing user balance...');
}

Future<void> _updateBadgeCount(Map<String, dynamic> data) async {
  // Implement badge update using flutter_app_badger or similar
  if (kDebugMode) debugPrint('🔢 Updating badge count...');
}

Future<void> _refreshHomeFeed() async {
  // Implement home feed refresh
  if (kDebugMode) debugPrint('🏠 Refreshing home feed...');
}

Future<void> _refreshLiveEvents() async {
  // Implement live events refresh
  if (kDebugMode) debugPrint('📡 Refreshing live events...');
}

/// Initialize FCM with analytics
class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static NotificationAnalyticsService? _analyticsService;
  static String? _currentUserId;

  /// Initialize FCM and set up message handlers
  static Future<void> initialize(
    NotificationAnalyticsService analyticsService, {
    required String userId,
  }) async {
    _analyticsService = analyticsService;
    _currentUserId = userId;

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request user permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      carPlay: false,
      criticalAlert: false,
      announcement: false,
    );

    if (kDebugMode) {
      debugPrint('📱 FCM Permission: ${settings.authorizationStatus.name}');
    }

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen to message opens
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Get initial message (if app was terminated)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }

    // Register device token in Supabase
    await _registerDeviceTokenInDatabase(userId);

    // Listen to token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      _registerDeviceTokenInDatabase(userId);
    });

    if (kDebugMode) debugPrint('✅ FCM initialized');
  }

  /// Register or update device token in Supabase
  static Future<void> _registerDeviceTokenInDatabase(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      String? deviceModel;
      String platform = 'android';

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceModel = iosInfo.model;
        platform = 'ios';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = androidInfo.model;
        platform = 'android';
      }

      final now = DateTime.now();

      final uri = Uri.parse('${ApiEnv.baseUrl}/api/push/register');
      final res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fcm_token': token,
          'platform': platform,
          'app_version': packageInfo.version,
          'device_model': deviceModel,
          'last_updated': now.toIso8601String(),
          'created_at': now.toIso8601String(),
        }),
        timeout: const Duration(seconds: 10),
        requireAuth: true,
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Push token registration failed (HTTP ${res.statusCode})');
      }

      if (kDebugMode) {
        debugPrint('✅ Device token registered: $platform');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error registering device token: $e');
    }
  }

  /// Handle foreground messages
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint('📬 Foreground message received');
      debugPrint('   Type: ${message.data['type']}');
      debugPrint('   Silent: ${message.data['silent']}');
    }

    final isSilent = message.data['silent'] == 'true';

    // Log delivery if analytics service is ready
    if (_analyticsService != null) {
      final type = NotificationType.fromString(message.data['type']);
      // In foreground, we can assume it's delivered since we're receiving it
      await _logDelivery(message, type);
    }

    // Handle silent notification
    if (isSilent) {
      await _handleSilentNotification(message.data);
    } else {
      // Show visible notification UI if needed
      _showNotificationUI(message);
    }
  }

  /// Handle message opened (user tapped notification)
  static Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint('👆 User tapped notification');
    }

    final notificationId = message.data['notif_id'];
    final type = NotificationType.fromString(message.data['type']);

    // Log the open
    if (_analyticsService != null) {
      final userId = _getCurrentUserId();
      if (userId != null) {
        await _analyticsService!.logNotificationOpened(
          userId: userId,
          notificationId: notificationId,
        );
      }
    }

    // Navigate to relevant screen
    await _handleNotificationNavigation(message.data, type);
  }

  /// Log delivery status after sending
  static Future<void> logDelivery({
    required String userId,
    required String token,
    required NotificationType type,
    required Map<String, dynamic> payload,
    String? countryCode,
    UserRoleAnalytics? role,
  }) async {
    if (_analyticsService == null) return;

    try {
      // Log as sent first
      await _analyticsService!.logNotificationSent(
        userId: userId,
        token: token,
        type: type,
        payload: payload,
        countryCode: countryCode,
        role: role,
      );

      if (kDebugMode) {
        debugPrint('📊 Logged notification: type=${type.value}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error logging notification: $e');
    }
  }

  /// Log delivery from received message
  static Future<void> _logDelivery(
      RemoteMessage message, NotificationType type) async {
    if (_analyticsService == null) return;

    final userId = _getCurrentUserId();
    if (userId == null) return;

    try {
      final token = message.data['device_token'] ?? 'unknown';
      await _analyticsService!.logNotificationDelivered(
        userId: userId,
        token: token,
        type: type,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error logging delivery: $e');
    }
  }

  /// Show notification UI (can be customized)
  static void _showNotificationUI(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('🎨 Showing notification UI');
    }

    final ctx = AppNavigator.context;
    if (ctx == null) return;

    final title = (message.notification?.title ?? message.data['title']?.toString() ?? '').trim();
    final body = (message.notification?.body ?? message.data['body']?.toString() ?? '').trim();
    final text = [title, body].where((s) => s.trim().isNotEmpty).join(' — ');

    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;

    final type = NotificationType.fromString(message.data['type']);

    messenger.showSnackBar(
      SnackBar(
        content: Text(text.isNotEmpty ? text : 'New notification'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            // Best-effort; ignore async.
            _handleNotificationNavigation(message.data, type);
          },
        ),
      ),
    );
  }

  /// Handle navigation based on notification type
  static Future<void> _handleNotificationNavigation(
      Map<String, dynamic> data, NotificationType type) async {
    if (kDebugMode) {
      debugPrint('🧭 Navigating to: $type');
    }

    switch (type) {
      case NotificationType.likeUpdate:
        // Navigate to song detail
        break;

      case NotificationType.commentUpdate:
        // Navigate to comments
        break;

      case NotificationType.liveBattleInvite:
        await _openBattleInviteDialog(data);
        break;

      case NotificationType.liveBattleNow:
      case NotificationType.liveBattle:
        await _openLiveBattleNow(data);
        break;

      case NotificationType.djLiveStart:
        // Navigate to DJ live
        break;

      case NotificationType.newSong:
        // Navigate to home feed
        break;

      case NotificationType.coinReward:
      case NotificationType.dailyBonus:
        // Show reward dialog
        break;

      default:
        if (kDebugMode) debugPrint('⚠️ No navigation handler for: $type');
    }
  }

  static String _s(Object? v) => (v ?? '').toString().trim();

  static void _toast(String message) {
    final ctx = AppNavigator.context;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<UserRole> _resolveCurrentUserRole(String uid) async {
    try {
      final row = await Supabase.instance.client.from('profiles').select('role').eq('id', uid).maybeSingle();
      final roleId = _s(row?['role']).toLowerCase();
      final role = UserRoleX.fromId(roleId);
      return role == UserRole.consumer ? UserRole.artist : role;
    } catch (_) {
      return UserRole.artist;
    }
  }

  static Future<void> _openBattleInviteDialog(Map<String, dynamic> data) async {
    final ctx = AppNavigator.context;
    if (ctx == null) return;

    final inviteId = _s(data['invite_id'] ?? data['inviteId'] ?? data['id']);
    final fromUid = _s(data['from_uid'] ?? data['fromUid']);
    final battleId = _s(data['battle_id'] ?? data['battleId']);
    final channelId = _s(data['channel_id'] ?? data['channelId']);

    if (inviteId.isEmpty) {
      _toast('Invite id missing');
      return;
    }

    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) {
        var busy = false;

        return StatefulBuilder(
          builder: (dialogCtx, setState) {
            Future<void> respond(String action) async {
              if (busy) return;

              final uid = _getCurrentUserId();
              if (uid == null || uid.trim().isEmpty) {
                _toast('Please log in to respond to invites.');
                return;
              }

              setState(() {
                busy = true;
              });

              try {
                final battle = await _respondToInvite(inviteId: inviteId, action: action);
                if (!dialogCtx.mounted) return;
                Navigator.of(dialogCtx).pop();

                if (action == 'accept') {
                  final role = await _resolveCurrentUserRole(uid);
                  await _openBattleRoom(
                    channelId: _s(battle.channelId).isNotEmpty
                        ? battle.channelId
                        : (channelId.isNotEmpty ? channelId : (battleId.isNotEmpty ? 'weafrica_battle_$battleId' : '')),
                    battleId: _s(battle.battleId).isNotEmpty ? battle.battleId : battleId,
                    role: role,
                    viewerId: uid,
                    battleArtists: <String>{
                      _s(battle.hostAId),
                      _s(battle.hostBId),
                      fromUid,
                      uid,
                    }.where((s) => s.isNotEmpty).toList(growable: false),
                  );
                }
              } catch (e, st) {
                UserFacingError.log('FCMService._showBattleInvite.respond', e, st);
                _toast(
                  UserFacingError.message(
                    e,
                    fallback: 'Could not respond to invite. Please try again.',
                  ),
                );
              } finally {
                if (dialogCtx.mounted) {
                  setState(() {
                    busy = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('Battle invite'),
              content: const Text('You have a new battle invite.'),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => respond('decline'),
                  child: const Text('Decline'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => respond('accept'),
                  child: const Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<LiveBattle> _respondToInvite({required String inviteId, required String action}) async {
    final act = action.trim().toLowerCase();
    if (act != 'accept' && act != 'decline') {
      throw ArgumentError('action must be accept or decline');
    }

    final uri = Uri.parse('${ApiEnv.baseUrl}/api/battle/invite/respond');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(<String, Object?>{
        'invite_id': inviteId,
        'action': act,
      }),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    final decoded = jsonDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (decoded is Map ? (decoded['message'] ?? decoded['error']) : null)?.toString();
      throw StateError(msg ?? 'Failed to respond to invite');
    }

    if (decoded is Map) {
      final raw = decoded['battle'] ?? decoded['data'] ?? decoded['result'];
      if (raw is Map) {
        final map = raw.map((k, v) => MapEntry(k.toString(), v));
        return LiveBattle.fromMap(Map<String, dynamic>.from(map));
      }
    }

    throw StateError('Invite response returned no battle data');
  }

  static Future<void> _openLiveBattleNow(Map<String, dynamic> data) async {
    final channelId = _s(data['channel_id'] ?? data['channelId']);
    final battleId = _s(data['battle_id'] ?? data['battleId']);
    final hostAId = _s(data['host_a_id'] ?? data['hostAId']);
    final hostBId = _s(data['host_b_id'] ?? data['hostBId']);

    final ch = channelId.isNotEmpty
        ? channelId
        : (battleId.isNotEmpty ? 'weafrica_battle_$battleId' : '');

    if (ch.isEmpty) {
      _toast('Battle channel missing');
      return;
    }

    final viewerId = (_getCurrentUserId() ?? '').trim();
    final viewer = viewerId.isNotEmpty ? viewerId : 'guest';

    await _openBattleRoom(
      channelId: ch,
      battleId: battleId.isNotEmpty ? battleId : ch,
      role: UserRole.consumer,
      viewerId: viewer,
      battleArtists: <String>{hostAId, hostBId}.where((s) => s.isNotEmpty).toList(growable: false),
    );
  }

  static Future<void> _openBattleRoom({
    required String channelId,
    required String battleId,
    required UserRole role,
    required String viewerId,
    required List<String> battleArtists,
  }) async {
    final ch = channelId.trim();
    if (ch.isEmpty) return;

    final hostName = role == UserRole.consumer ? 'Viewer' : role.label;

    await AppNavigator.push(
      MaterialPageRoute<void>(
        builder: (_) => LiveScreen(
          args: LiveArgs(
            liveId: ch,
            channelId: ch,
            role: role,
            hostId: viewerId,
            hostName: hostName,
            isBattle: true,
            battleId: battleId.trim().isEmpty ? null : battleId.trim(),
            battleArtists: battleArtists,
          ),
        ),
      ),
    );
  }

  /// Get current user ID from auth
  static String? _getCurrentUserId() {
    // Return the user ID set during initialization
    if (_currentUserId != null) return _currentUserId;

    // Canonical auth source for app runtime.
    return FirebaseAuth.instance.currentUser?.uid;
  }

  /// Handle logout - deactivate device tokens
  static Future<void> handleLogout(String userId) async {
    try {
      await Supabase.instance.client
          .from('notification_device_tokens')
          .update({'is_active': false})
          .eq('user_id', userId);

      _currentUserId = null;

      if (kDebugMode) debugPrint('✅ Device tokens deactivated for logout');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error deactivating tokens on logout: $e');
    }

  }

  /// Get current user's country code
  static Future<String?> getCurrentUserCountry() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('country_code')
          .eq('id', user.id)
          .limit(1)
          .maybeSingle();

      return profile?['country_code'];
    } catch (_) {
      return null;
    }
  }

  /// Get current FCM device token
  static Future<String?> getDeviceToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe device to a topic
  static Future<void> subscribeTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      if (kDebugMode) debugPrint('✅ Subscribed to topic: $topic');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe device from a topic
  static Future<void> unsubscribeTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      if (kDebugMode) debugPrint('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error unsubscribing from topic: $e');
    }
  }

  /// Handle token refresh (when FCM token changes)
  static void onTokenRefresh(Function(String token) callback) {
    _messaging.onTokenRefresh.listen(callback);
  }
}
