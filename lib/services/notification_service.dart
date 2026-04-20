import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/auth/jwt_debug.dart';
import '../app/config/api_env.dart';
import '../app/navigation/app_navigator.dart';
import '../app/navigation/route_tracker.dart';
import '../features/auth/user_role.dart';
import '../features/auth/user_role_resolver.dart';
import '../features/artist/dashboard/screens/artist_stats_screen.dart';
import '../features/artist_dashboard/screens/artist_earnings_screen.dart';
import '../features/dj_dashboard/screens/dj_highlights_screen.dart';
import '../features/dj_dashboard/screens/dj_earnings_screen.dart';
import '../features/library/library_tab_real.dart';
import '../features/live/live_screen.dart';
import '../features/live/models/live_args.dart';
import '../features/live/screens/live_feed_screen.dart';
import '../features/live/services/battle_matching_api.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/notifications/services/notification_center_store.dart';
import '../features/player/playback_controller.dart';
import '../features/player/song_comments_sheet.dart';
import '../features/subscriptions/role_based_subscription_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/tracks/tracks_repository.dart';
import '../screens/full_player_screen.dart';
import 'creator_finance_api.dart';
import 'user_service.dart';

void _nsLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Top-level function required for background message handling.
/// Called when app is terminated or in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Required for plugins to work in the background isolate.
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
  } catch (_) {
    // Best-effort: background isolate may already be initialized.
  }
  _nsLog('🔔 Background message: ${message.messageId}');

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    _nsLog('⚠️ Background Firebase init failed: $e');
  }

  // Show actual system notification when app is in background/closed
  try {
    final isSilent = message.data['silent'] == 'true' || 
                     message.contentAvailable == true;
    
    if (!isSilent) {
      await NotificationService.instance._showBackgroundSystemNotification(message);
    }
    
    await NotificationService.instance.handleSilentPush(message.data);
  } catch (e) {
    _nsLog('⚠️ Background handler failed: $e');
  }
}

/// Centralized notification service handling:
/// - FCM token management
/// - Silent push notifications (badges, content refresh)
/// - Foreground notifications
/// - Background/terminated message handling
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const String _kFcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');
  static const String _kFullPlayerRouteName = '/player/full';
  static const Duration _kTapDedupeWindow = Duration(seconds: 2);
  static const AndroidNotificationChannel _battleNotificationChannel =
      AndroidNotificationChannel(
    'battle_challenges',
    'Battle Challenges',
    description: 'Live battle invites and responses.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _defaultNotificationChannel =
      AndroidNotificationChannel(
    'default_notifications',
    'Notifications',
    description: 'All app notifications.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  String? _fcmToken;
  int _unreadCount = 0;
  bool _localNotificationsReady = false;

  static const List<Duration> _fcmTokenRetryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 8),
  ];

  /// In-app observable unread count (for bell badges, etc).
  ///
  /// This is separate from the OS/app-icon badge but kept in sync.
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  DateTime? _lastPushRegisterAttemptAt;
  String? _lastPushRegisterFcmToken;

  StreamSubscription<fb_auth.User?>? _firebaseAuthSub;

  Future<void> _tapHandlingQueue = Future<void>.value();
  String? _lastTapKey;
  DateTime? _lastTapAt;
  String? _activeBattleInviteDialogId;

  static String _s(Object? v) => (v ?? '').toString().trim();

  void _toast(String message) {
    final ctx = AppNavigator.context;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<NavigatorState?> _waitForNavigatorState({Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (AppNavigator.key.currentState == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return AppNavigator.key.currentState;
  }

  Map<String, dynamic> _flattenPayload(Map<String, dynamic> raw) {
    // Some backends send nested JSON strings (e.g. { payload: "{...}" }).
    final out = <String, dynamic>{...raw};

    final payloadStr = _s(raw['payload']);
    if (payloadStr.startsWith('{') && payloadStr.endsWith('}')) {
      try {
        final decoded = jsonDecode(payloadStr);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            out.putIfAbsent(entry.key.toString(), () => entry.value);
          }
        }
      } catch (_) {
        // ignore
      }
    }

    return out;
  }

  String _normalizeAction(Map<String, dynamic> data) {
    final raw = _s(
      data['type'] ??
          data['screen'] ??
          data['action'] ??
          data['notification_type'] ??
          data['event'],
    );

    var a = raw.toLowerCase();
    a = a.replaceAll('-', '_');
    a = a.replaceAll(' ', '_');
    return a.trim();
  }

  String _extractTrackId(Map<String, dynamic> data) {
    return _s(
      data['entity_id'] ??
          data['entityId'] ??
          data['track_id'] ??
          data['trackId'] ??
          data['song_id'] ??
          data['songId'] ??
          data['id'] ??
          data['track'] ??
          data['song'],
    );
  }

  String _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final text = _s(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _battleInviteSenderName(Map<String, dynamic> data) {
    return _firstNonEmpty([
      data['from_name'],
      data['from_display_name'],
      data['from_user_name'],
      data['from_handle'],
      data['from_username'],
    ]);
  }

  String _battleInviteResponderName(Map<String, dynamic> data) {
    return _firstNonEmpty([
      data['to_name'],
      data['to_display_name'],
      data['to_user_name'],
      data['to_handle'],
      data['to_username'],
    ]);
  }

  String _tapKeyFor(
    RemoteMessage message, {
    required String action,
    required String entityId,
  }) {
    final messageId = _s(message.messageId);
    if (messageId.isNotEmpty) return 'mid:$messageId';

    final sent = message.sentTime?.millisecondsSinceEpoch ?? 0;
    final collapseKey = _s(message.collapseKey);
    return '$action|$entityId|$sent|$collapseKey';
  }

  bool _isDuplicateTap(String tapKey) {
    final key = tapKey.trim();
    if (key.isEmpty) return false;

    final now = DateTime.now();
    final lastAt = _lastTapAt;
    if (_lastTapKey == key && lastAt != null && now.difference(lastAt) < _kTapDedupeWindow) {
      return true;
    }

    _lastTapKey = key;
    _lastTapAt = now;
    return false;
  }

  void _queueNotificationTap(RemoteMessage message) {
    _tapHandlingQueue = _tapHandlingQueue.then((_) async {
      await _handleNotificationTap(message);
    }).catchError((e) {
      _nsLog('⚠️ Notification tap handler failed: $e');
    });
  }

  Future<BuildContext?> _waitForNavigatorContext({Duration timeout = const Duration(seconds: 3)}) async {
    final deadline = DateTime.now().add(timeout);
    while (AppNavigator.context == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return AppNavigator.context;
  }

  void _setUnreadCount(int value) {
    final next = value < 0 ? 0 : value;
    _unreadCount = next;
    if (unreadCountNotifier.value != next) unreadCountNotifier.value = next;

    // Keep the new Notification Center bell badge (server-backed UI) in sync
    // with push-driven badge updates (best-effort).
    NotificationCenterStore.instance.setUnreadCount(next);
  }

  void _incrementUnreadCount() {
    _setUnreadCount(_unreadCount + 1);
  }

  String? get _webVapidKey => _kFcmVapidKey.isEmpty ? null : _kFcmVapidKey;

  String _platformLabel() {
    if (kIsWeb) return 'web';

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  Future<bool> _isWebServiceWorkerScriptReachable() async {
    if (!kIsWeb) return true;

    try {
      final swUris = <Uri>{
        Uri.base.resolve('firebase-messaging-sw.js'),
        Uri.base.resolve('/firebase-messaging-sw.js'),
      }.toList();

      for (final swUri in swUris) {
        final headResponse = await http
            .head(swUri)
            .timeout(const Duration(seconds: 5));
        if (headResponse.statusCode == 200) return true;

        final getResponse = await http
            .get(
              swUri,
              headers: const {
                'Range': 'bytes=0-0',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(const Duration(seconds: 5));

        if (getResponse.statusCode == 200 || getResponse.statusCode == 206) {
          return true;
        }
      }

      _nsLog(
        '⚠️ firebase-messaging-sw.js is not reachable (checked relative and root URLs). Skipping FCM web token init.',
      );
      return false;
    } catch (e) {
      // This check is best-effort only. On some dev servers / slow devices,
      // the HEAD/GET can time out even though the service worker is served.
      // Proceed with initialization and let FirebaseMessaging surface the
      // real error if the service worker truly is missing.
      _nsLog(
        '⚠️ Could not verify firebase-messaging-sw.js reachability: $e. Proceeding with FCM web init anyway.',
      );
      return true;
    }
  }

  /// Returns the current FCM token (optionally forcing a refresh).
  ///
  /// On Web, you may need to pass a VAPID key via:
  /// `--dart-define=FCM_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY`
  Future<String?> getFcmToken({bool refresh = false}) async {
    // Best-effort check only; do not block token retrieval on flaky dev servers.
    if (kIsWeb) {
      await _isWebServiceWorkerScriptReachable();
    }

    // Ensure permissions are requested (iOS/Android 13+/Web).
    NotificationSettings settings;
    try {
      settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      _nsLog('⚠️ FCM permission request failed: $e');
      return null;
    }

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return null;
    }

    if (refresh) {
      try {
        await _messaging.deleteToken();
      } catch (_) {
        // Best-effort; proceed to fetch anyway.
      }
      _fcmToken = null;
    }

    try {
      final token = await _messaging.getToken(vapidKey: _webVapidKey);
      _fcmToken = token;
      return token;
    } catch (e) {
      _nsLog('⚠️ Failed to obtain FCM token: $e');
      return null;
    }
  }

  Future<String?> _getFcmTokenWithRetry({bool logFailures = true}) async {
    String? lastError;

    for (var attempt = 0; attempt < _fcmTokenRetryDelays.length; attempt++) {
      try {
        final token = await _messaging.getToken(vapidKey: _webVapidKey);
        if (token != null && token.trim().isNotEmpty) {
          return token;
        }
      } catch (e) {
        lastError = e.toString();
      }

      if (attempt < _fcmTokenRetryDelays.length - 1) {
        await Future<void>.delayed(_fcmTokenRetryDelays[attempt]);
      }
    }

    if (logFailures) {
      _nsLog('⚠️ Failed to obtain FCM token after retries: ${lastError ?? 'unknown error'}');
    }
    return null;
  }

  /// Initialize FCM and register handlers.
  Future<void> initialize() async {
    try {
      await _messaging.setAutoInitEnabled(true);
    } catch (e) {
      _nsLog('⚠️ Failed to enable FCM auto-init: $e');
    }

    // Android 13+ requires runtime notification permission.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final result = await Permission.notification.request();
        _nsLog('🔔 Notification permission (Android): $result');
      }
    }

    // Request permission (iOS/Android 13+/Web).
    NotificationSettings settings;
    try {
      settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      _nsLog('⚠️ FCM permission request failed: $e');
      return;
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      _nsLog('✅ FCM permission granted');
    } else {
      _nsLog('⚠️ FCM permission denied');
      return;
    }

    await _initializeLocalNotifications();

    // Best-effort check only; do not abort init on flaky dev servers.
    if (kIsWeb) {
      await _isWebServiceWorkerScriptReachable();
    }

    // Get FCM token, but do not abort initialization if Google services are
    // temporarily unavailable on device startup.
    _fcmToken = await _getFcmTokenWithRetry();

    if (kDebugMode && _fcmToken != null && _fcmToken!.isNotEmpty) {
      final t = _fcmToken!;
      final head = t.length <= 20 ? t : t.substring(0, 20);
      _nsLog('📱 FCM Token: $head...');
    }

    // Persist token locally in Supabase and attempt backend registration.
    if (_fcmToken != null) {
      await _saveFcmTokenToSupabase(_fcmToken!);
      await _registerTokenWithBackendIfAuthed(_fcmToken!);
    }

    // Listen for token refresh (avoid letting async errors escape into the Zone).
    _messaging.onTokenRefresh.listen((token) async {
      try {
        await _saveFcmTokenToSupabase(token);
        await _registerTokenWithBackendIfAuthed(token);
      } catch (e) {
        _nsLog('⚠️ Token refresh handler failed: $e');
      }
    });

    // Register on login as well (initialize() runs before user signs in).
    _firebaseAuthSub ??= fb_auth.FirebaseAuth.instance.userChanges().listen((user) async {
      if (user == null) {
        return;
      }

      try {
        final token = _fcmToken ?? await _getFcmTokenWithRetry(logFailures: false);
        if (token == null || token.isEmpty) return;
        _fcmToken = token;

        await _saveFcmTokenToSupabase(token);
        await _registerTokenWithBackendIfAuthed(token);
      } catch (e) {
        _nsLog('⚠️ Push register-on-login failed: $e');
      }
    });

    // Foreground messages (ensure handler errors do not escape into the Zone).
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(
        _handleForegroundMessage(message).catchError((e) {
          _nsLog('⚠️ Foreground message handler failed: $e');
        }),
      );
    });

    // Background/terminated messages:
    // - Android/iOS: handled via a top-level background handler.
    // - Web: handled by the service worker (`web/firebase-messaging-sw.js`).
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (e) {
        // This can throw if already registered (main.dart registers early).
        _nsLog('⚠️ onBackgroundMessage registration failed (ignored): $e');
      }
    }

    // Handle notification tap (when app opens from notification)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _queueNotificationTap(message);
    });

    // Check if app was opened from a terminated state via notification.
    try {
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _queueNotificationTap(initialMessage);
      }
    } catch (e) {
      // On some platforms (notably Web), this may not be supported.
      _nsLog('⚠️ getInitialMessage() failed (ignored): $e');
    }

    _nsLog('✅ NotificationService initialized');
  }

  /// Handle foreground messages (app is open).
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _nsLog('🔔 Foreground message: ${message.messageId}');

    final data = _flattenPayload(message.data);
    final action = _normalizeAction(data);

    final isSilent = message.data['silent'] == 'true' || 
                     message.contentAvailable == true;

    if (isSilent) {
      // Silent notification - no UI
      unawaited(handleSilentPush(message.data));
    } else {
      if (action.startsWith('live_battle_invite')) {
        await _showSystemForegroundNotification(message);
      }

      if (action == 'live_battle_invite') {
        await _showBattleInviteDialog(data);
        return;
      }

      if (action == 'live_battle_invite_accepted') {
        await _showBattleInviteAcceptedDialog(data);
        return;
      }

      if (action == 'live_battle_invite_declined') {
        _showBattleInviteDeclinedBanner(data);
        return;
      }

      _showNotificationBanner(message);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady || kIsWeb) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload?.trim() ?? '';
          if (payload.isEmpty) {
            unawaited(_navigateToNotifications());
            return;
          }

          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map<String, dynamic>) {
              final action = _normalizeAction(decoded);
              if (action == 'live_battle_invite') {
                unawaited(_showBattleInviteDialog(decoded));
                return;
              }
            }
          } catch (_) {
            // ignore and use default navigation below
          }

          unawaited(_navigateToNotifications());
        },
      );

      final androidImpl = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.createNotificationChannel(_battleNotificationChannel);
      await androidImpl?.createNotificationChannel(_defaultNotificationChannel);

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _localNotificationsReady = true;
    } catch (e) {
      _nsLog('⚠️ Local notifications init failed: $e');
    }
  }

  Future<void> _showBackgroundSystemNotification(RemoteMessage message) async {
    if (kIsWeb) return;

    try {
      final title = message.notification?.title?.trim().isNotEmpty == true
          ? message.notification!.title!.trim()
          : (message.data['title']?.toString().trim().isNotEmpty == true
              ? message.data['title']!.toString().trim()
              : 'WeAfrica Music');
      final body = message.notification?.body?.trim().isNotEmpty == true
          ? message.notification!.body!.trim()
          : (message.data['body']?.toString().trim() ?? 'New notification');

      final payload = <String, dynamic>{..._flattenPayload(message.data)};
      if (title.isNotEmpty) payload['title'] = title;
      if (body.isNotEmpty) payload['body'] = body;

      final androidDetails = AndroidNotificationDetails(
        _defaultNotificationChannel.id,
        _defaultNotificationChannel.name,
        channelDescription: _defaultNotificationChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/launcher_icon',
        channelShowBadge: true,
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 30);
      await _localNotifications.show(
        id,
        title,
        body.isEmpty ? null : body,
        details,
        payload: jsonEncode(payload),
      );
      
      _nsLog('✅ Background notification displayed: $title');
    } catch (e) {
      _nsLog('⚠️ Failed to show background notification: $e');
    }
  }

  Future<void> _showSystemForegroundNotification(RemoteMessage message) async {
    if (kIsWeb) return;

    if (!_localNotificationsReady) {
      await _initializeLocalNotifications();
    }
    if (!_localNotificationsReady) return;

    final title = message.notification?.title?.trim().isNotEmpty == true
        ? message.notification!.title!.trim()
        : (message.data['title']?.toString().trim().isNotEmpty == true
            ? message.data['title']!.toString().trim()
            : 'WeAfrica Music');
    final body = message.notification?.body?.trim().isNotEmpty == true
        ? message.notification!.body!.trim()
        : (message.data['body']?.toString().trim() ?? '');

    final payload = <String, dynamic>{..._flattenPayload(message.data)};
    if (title.isNotEmpty) payload['title'] = title;
    if (body.isNotEmpty) payload['body'] = body;

    final androidDetails = AndroidNotificationDetails(
      _battleNotificationChannel.id,
      _battleNotificationChannel.name,
      channelDescription: _battleNotificationChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/launcher_icon',
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 30);
    await _localNotifications.show(
      id,
      title,
      body.isEmpty ? null : body,
      details,
      payload: jsonEncode(payload),
    );
  }

  /// Handle user tapping on notification.
  Future<void> _handleNotificationTap(RemoteMessage message) async {
    try {
      final data = _flattenPayload(message.data);
      final action = _normalizeAction(data);
      final entityId = _extractTrackId(data);

      final tapKey = _tapKeyFor(message, action: action, entityId: entityId);
      if (_isDuplicateTap(tapKey)) {
        _nsLog('🔁 Duplicate notification tap ignored ($tapKey)');
        return;
      }

      _nsLog('👆 Notification tapped ($tapKey): $data');

      // Cold start/background: wait for navigator to mount.
      await _waitForNavigatorState();

      switch (action) {
        case 'live_now':
        case 'dj_live_start':
          await _navigateToLiveFeed();
          break;

        case 'live_battle':
        case 'live_battle_now':
          await _navigateToLiveBattle(data);
          break;

        case 'live_battle_invite':
          await _showBattleInviteDialog(data);
          break;

        case 'live_battle_invite_accepted':
          await _openAcceptedBattleFromNotification(data);
          break;

        case 'live_battle_invite_declined':
          _toast(_battleInviteDeclinedMessage(data));
          await _navigateToNotifications();
          break;

        case 'new_like':
        case 'like_update':
        case 'track_detail':
          await _navigateToTrack(entityId);
          break;

        case 'new_comment':
        case 'comment_update':
        case 'track_comments':
          await _navigateToTrack(entityId, openComments: true);
          break;

        case 'daily_bonus':
        case 'coin_reward':
        case 'earnings':
        case 'earnings_update':
          await _navigateToRewards();
          break;

        case 'creator_growth':
        case 'creator_stats':
        case 'plays_milestone':
        case 'followers_milestone':
          await _navigateToCreatorGrowth();
          break;

        case 'subscriptions':
        case 'subscription':
        case 'upgrade':
        case 'upgrade_now':
          await _navigateToSubscriptions();
          break;

        default:
          await _navigateToNotifications();
      }
    } catch (e) {
      _nsLog('⚠️ Notification tap handler failed: $e');
      unawaited(_navigateToNotifications());
    }
  }

  /// Handle silent push notifications.
  /// Updates local state without showing UI.
  Future<void> handleSilentPush(Map<String, dynamic> data) async {
    try {
      final type = data['type'];

      _nsLog('🔕 Silent push: $type');

      switch (type) {
        case 'coin_update':
          await _handleCoinUpdate(data);
          break;
        case 'like_update':
          await _handleLikeUpdate(data);
          break;
        case 'comment_update':
          await _handleCommentUpdate(data);
          break;
        case 'daily_bonus':
          await _handleDailyBonus(data);
          break;
        case 'content_refresh':
          await _handleContentRefresh(data);
          break;
        case 'badge_update':
          await _handleBadgeUpdate(data);
          break;
        default:
          _nsLog('⚠️ Unknown silent push type: $type');
      }
    } catch (e) {
      _nsLog('⚠️ Silent push handler failed: $e');
    }

    // Always update badge (best-effort)
    await _updateAppBadge();
  }

  /// Update user's coin balance from silent push.
  Future<void> _handleCoinUpdate(Map<String, dynamic> data) async {
    final amount = int.tryParse(data['amount']?.toString() ?? '0') ?? 0;
    final reason = data['reason']?.toString() ?? 'reward';

    _nsLog('💰 Coin update: +$amount ($reason)');

    await _refreshCoinBalanceFromBackend();

    // Increment unread count for badge
    _incrementUnreadCount();
  }

  /// Update like count on a track/post.
  Future<void> _handleLikeUpdate(Map<String, dynamic> data) async {
    final entityId = data['entity_id']?.toString();
    final newCount = int.tryParse(data['count']?.toString() ?? '0') ?? 0;

    _nsLog('❤️ Like update: $entityId = $newCount');

    // Update cached data (if using provider/riverpod)
    // TracksCache.updateLikeCount(entityId, newCount);

    _incrementUnreadCount();
  }

  /// Update comment count on a track/post.
  Future<void> _handleCommentUpdate(Map<String, dynamic> data) async {
    final entityId = data['entity_id']?.toString();
    final newCount = int.tryParse(data['count']?.toString() ?? '0') ?? 0;

    _nsLog('💬 Comment update: $entityId = $newCount');

    _incrementUnreadCount();
  }

  /// Handle daily bonus notification.
  Future<void> _handleDailyBonus(Map<String, dynamic> data) async {
    final amount = int.tryParse(data['amount']?.toString() ?? '50') ?? 50;

    _nsLog('🎁 Daily bonus: +$amount coins');

    await _refreshCoinBalanceFromBackend();
    _incrementUnreadCount();
  }

  Future<void> _refreshCoinBalanceFromBackend() async {
    try {
      final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
      await UserService.instance.setCoins(summary.coinBalance.round());
    } catch (e) {
      _nsLog('⚠️ Failed to refresh wallet summary after silent push: $e');
    }
  }

  /// Refresh content silently (home feed, trending, etc).
  Future<void> _handleContentRefresh(Map<String, dynamic> data) async {
    final section = data['section']?.toString() ?? 'all';

    _nsLog('🔄 Content refresh: $section');

    // Trigger refresh via provider/riverpod
    // HomeProvider.refresh();
    // TrendingProvider.refresh();
  }

  /// Update badge count from server.
  Future<void> _handleBadgeUpdate(Map<String, dynamic> data) async {
    final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
    
    _nsLog('🔢 Badge update: $count');
    
    _setUnreadCount(count);
  }

  /// Update app icon badge.
  Future<void> _updateAppBadge() async {
    try {
      final isSupported = await FlutterAppBadger.isAppBadgeSupported();
      if (!isSupported) return;

      if (_unreadCount > 0) {
        await FlutterAppBadger.updateBadgeCount(_unreadCount);
        _nsLog('🔢 Badge updated: $_unreadCount');
      } else {
        await FlutterAppBadger.removeBadge();
      }
    } catch (e) {
      _nsLog('⚠️ Failed to update badge: $e');
    }
  }

  /// Base URL for the admin backend that serves `/api/push/register`.
  ///
  /// Prefer the hosted Supabase Functions origin configured via
  /// `--dart-define-from-file=tool/supabase.env.json`.
  /// You can override just push with `--dart-define=PUSH_BACKEND_BASE_URL=...`.
  String _backendBaseUrl() {
    final explicit = const String.fromEnvironment('PUSH_BACKEND_BASE_URL', defaultValue: '').trim();
    if (explicit.isNotEmpty) return explicit;
    return ApiEnv.baseUrl;
  }

  /// Exposed for debug UIs.
  String get pushBackendBaseUrl => _backendBaseUrl();

  /// Manually registers the current FCM token (useful for debug screens).
  Future<({bool ok, String message})> registerDeviceTokenNow() async {
    final firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return (ok: false, message: 'Not logged in to Firebase yet.');
    }

    final token = _fcmToken ?? await _messaging.getToken(vapidKey: _webVapidKey);
    if (token == null || token.isEmpty) {
      return (ok: false, message: 'Failed to obtain an FCM token.');
    }
    _fcmToken = token;

    return _registerTokenWithBackendIfAuthed(token);
  }

  Future<({bool ok, String message})> _registerTokenWithBackendIfAuthed(String token) async {
    try {
      final now = DateTime.now();
      if (_lastPushRegisterAttemptAt != null && _lastPushRegisterFcmToken == token) {
        final elapsed = now.difference(_lastPushRegisterAttemptAt!);
        if (elapsed < const Duration(seconds: 30)) {
          // Not an error: we intentionally skip repeated registrations.
          return (ok: true, message: 'Already registered recently.');
        }
      }
      _lastPushRegisterAttemptAt = now;
      _lastPushRegisterFcmToken = token;

      final firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        _nsLog('⚠️ Skipping /api/push/register (Firebase user not logged in)');
        return (ok: false, message: 'Not logged in to Firebase.');
      }

      final baseUrl = _backendBaseUrl();
      // ApiEnv.baseUrl always provides a default, but that default may not be
      // reachable from a physical device without `WEAFRICA_API_BASE_URL`.

      final uid = firebaseUser.uid.trim();
      final topics = <String>['all'];
      if (uid.isNotEmpty) {
        topics.add('user_$uid');
      }

      const defaultCountryCode = String.fromEnvironment(
        'DEFAULT_COUNTRY_CODE',
        defaultValue: 'mw',
      );

      String idToken = (await firebaseUser.getIdToken())?.trim() ?? '';
      if (idToken.isEmpty) {
        throw Exception('Could not obtain Firebase ID token.');
      }

      final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$normalizedBase/api/push/register');

      if (kDebugMode) {
        _nsLog('🌐 POST $uri (topics=${topics.join(',')})');
      }

      final body = {
        // Endpoint accepts `token` or `fcm_token`.
        'token': token,
        'fcm_token': token,
        'platform': _platformLabel(),
        'topics': topics,
        'country_code': defaultCountryCode,
      };

      http.Response response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Request timeout'),
          );

      // If auth fails, force-refresh the token and retry once.
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (kDebugMode) {
          _nsLog('⚠️ /api/push/register auth failed. Firebase JWT (safe): ${firebaseJwtSummary(idToken)}');
          _nsLog('⚠️ Ensure Edge Function FIREBASE_PROJECT_ID matches your Firebase project_id (android/app/google-services.json).');
        }

        try {
          final refreshed = (await firebaseUser.getIdToken(true))?.trim() ?? '';
          if (refreshed.isNotEmpty && refreshed != idToken) {
            idToken = refreshed;
            response = await http
                .post(
                  uri,
                  headers: {
                    'Authorization': 'Bearer $idToken',
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                  body: jsonEncode(body),
                )
                .timeout(
                  const Duration(seconds: 10),
                  onTimeout: () => throw Exception('Request timeout'),
                );
          }
        } catch (_) {
          // ignore
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        String message = 'Token registered.';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            final serverMessage = decoded['message']?.toString().trim();
            if (serverMessage != null && serverMessage.isNotEmpty) {
              message = serverMessage;
            }
          }
        } catch (_) {
          // Ignore JSON parse errors; keep default message.
        }

        await _saveFcmTokenToSupabase(token);

        if (kDebugMode) {
          _nsLog('✅ Registered FCM token via /api/push/register (${_platformLabel()}, $defaultCountryCode)');
        }
        return (ok: true, message: message);
      }

      if (kDebugMode) {
        final bodyPreview = response.body.length > 800 ? '${response.body.substring(0, 800)}…' : response.body;
        _nsLog('⚠️ /api/push/register failed: ${response.statusCode} $bodyPreview');
      }
      return (
        ok: false,
        message: 'Push register failed (HTTP ${response.statusCode}).',
      );
    } catch (e) {
      if (kDebugMode) {
        _nsLog('⚠️ Failed to register FCM token: $e');
      }
      return (ok: false, message: 'Push notifications are unavailable right now.');
    }
  }

  Future<void> _saveFcmTokenToSupabase(String token) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) return;

    try {
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        _nsLog('⚠️ No user logged in, cannot save FCM token to Supabase');
        return;
      }

      final uid = user.uid.trim();
      if (uid.isEmpty) return;

      final supabase = Supabase.instance.client;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Offline guard: skip if no connectivity (temp comment - missing import)
      // try {
      //   final connectivity = ConnectivityService.instance;
      //   if (!(await connectivity.isOnline())) {
      //     _nsLog('🌐 Offline - skipping FCM token save to Supabase');
      //     return;
      //   }
      // } catch (_) {
      //   // Connectivity service unavailable; proceed anyway
      // }

      try {
        await supabase.from('users').update({
          'fcm_token': trimmedToken,
          'updated_at': nowIso,
        }).eq('id', uid);
      } catch (e) {
        _nsLog('⚠️ Failed to mirror FCM token to users table: $e');
      }

      // Best-effort profile mirror for environments where profile writes are preferred.
      try {
        await supabase.from('profiles').update({
          'fcm_token': trimmedToken,
          'updated_at': nowIso,
        }).eq('id', uid);
      } catch (_) {
        // Ignore profile mirror errors.
      }
    } catch (e) {
      _nsLog('❌ Failed to save FCM token in Supabase: $e');
    }
  }

  /// Show in-app notification banner (for foreground messages).
  void _showNotificationBanner(RemoteMessage message) {
    if (!kIsWeb) {
      unawaited(_showSystemForegroundNotification(message));
      return;
    }

    final ctx = AppNavigator.context;
    if (ctx == null) {
      _nsLog('📢 Foreground notification (no context yet): ${message.notification?.title}');
      return;
    }

    final title = message.notification?.title?.trim().isNotEmpty == true
        ? message.notification!.title!.trim()
        : (message.data['title']?.toString().trim().isNotEmpty == true
            ? message.data['title']!.toString().trim()
            : 'Notification');
    final body = message.notification?.body?.trim().isNotEmpty == true
        ? message.notification!.body!.trim()
        : (message.data['body']?.toString().trim() ?? '');

    final snack = SnackBar(
      content: Text(body.isEmpty ? title : '$title\n$body'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () {
          _queueNotificationTap(message);
        },
      ),
    );

    ScaffoldMessenger.of(ctx)
      ..clearSnackBars()
      ..showSnackBar(snack);
  }

  Future<void> _showBattleInviteDialog(Map<String, dynamic> data) async {
    final inviteId = _s(data['invite_id'] ?? data['inviteId'] ?? data['id']);
    if (inviteId.isEmpty) {
      _toast('Invite id missing');
      return;
    }
    if (_activeBattleInviteDialogId != null) {
      return;
    }

    final ctx = await _waitForNavigatorContext(timeout: const Duration(seconds: 8));
    if (ctx == null || !ctx.mounted) {
      _nsLog('⚠️ Battle invite dialog skipped: no navigator context');
      return;
    }

    final fromUid = _s(data['from_uid'] ?? data['fromUid']);
    final battleId = _s(data['battle_id'] ?? data['battleId']);
    final channelId = _s(data['channel_id'] ?? data['channelId']);
    final fromName = _battleInviteSenderName(data);
    final inviteMessage = fromName.isNotEmpty
      ? '$fromName invited you to a battle${battleId.isNotEmpty ? ' (battle: $battleId)' : ''}.'
      : 'You have a new battle invite${battleId.isNotEmpty ? ' (battle: $battleId)' : ''}.';

    _activeBattleInviteDialogId = inviteId;
    try {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: true,
        builder: (dialogCtx) {
          var busy = false;

          return StatefulBuilder(
            builder: (dialogCtx, setState) {
              Future<void> respond(String action) async {
                if (busy) return;

                final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
                final uid = currentUser?.uid.trim() ?? '';
                if (uid.isEmpty) {
                  _toast('Please log in to respond to invites.');
                  return;
                }

                setState(() {
                  busy = true;
                });

                try {
                  final battle = await const BattleMatchingApi().respondToInvite(
                    inviteId: inviteId,
                    action: action,
                  );

                  if (!dialogCtx.mounted) return;
                  Navigator.of(dialogCtx).pop();

                  if (action == 'accept') {
                    final role = await UserRoleResolver.resolveCurrentUser();
                    final displayName = (fb_auth.FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
                    await _openBattleRoom(
                      channelId: _s(battle.channelId).isNotEmpty
                          ? battle.channelId
                          : (channelId.isNotEmpty ? channelId : (battleId.isNotEmpty ? 'weafrica_battle_$battleId' : '')),
                      battleId: _s(battle.battleId).isNotEmpty ? battle.battleId : battleId,
                      role: role,
                      hostId: uid,
                      hostName: displayName.isNotEmpty ? displayName : role.label,
                      battleArtists: <String>{
                        _s(battle.hostAId),
                        _s(battle.hostBId),
                        fromUid,
                        uid,
                      }.where((s) => s.isNotEmpty).toList(growable: false),
                    );
                  }
                } catch (e) {
                  _toast('Could not respond to invite. Please try again.');
                  _nsLog('⚠️ Battle invite response failed: $e');
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
                content: Text(inviteMessage),
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
    } finally {
      if (_activeBattleInviteDialogId == inviteId) {
        _activeBattleInviteDialogId = null;
      }
    }
  }

  String _battleInviteAcceptedMessage(Map<String, dynamic> data) {
    final explicitBody = _s(data['body']);
    if (explicitBody.isNotEmpty) return explicitBody;

    final responder = _battleInviteResponderName(data);
    if (responder.isNotEmpty) {
      return '$responder accepted your battle invite.';
    }

    final responderUid = _s(data['to_uid'] ?? data['toUid']);
    if (responderUid.isNotEmpty) {
      return 'Your battle invite was accepted.';
    }

    return 'A creator accepted your battle invite.';
  }

  String _battleInviteDeclinedMessage(Map<String, dynamic> data) {
    final explicitBody = _s(data['body']);
    if (explicitBody.isNotEmpty) return explicitBody;
    final responder = _battleInviteResponderName(data);
    if (responder.isNotEmpty) {
      return '$responder declined your battle invite.';
    }
    return 'Your battle invite was declined.';
  }

  Future<void> _showBattleInviteAcceptedDialog(Map<String, dynamic> data) async {
    final ctx = await _waitForNavigatorContext(timeout: const Duration(seconds: 8));
    if (ctx == null || !ctx.mounted) {
      _nsLog('⚠️ Battle invite accepted dialog skipped: no navigator context');
      return;
    }

    final message = _battleInviteAcceptedMessage(data);

    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Battle invite accepted'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await _openAcceptedBattleFromNotification(data);
              },
              child: const Text('Open battle'),
            ),
          ],
        );
      },
    );
  }

  void _showBattleInviteDeclinedBanner(Map<String, dynamic> data) {
    final ctx = AppNavigator.context;
    if (ctx == null) {
      _nsLog('📢 Battle invite declined: ${_battleInviteDeclinedMessage(data)}');
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(_battleInviteDeclinedMessage(data)),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _openAcceptedBattleFromNotification(Map<String, dynamic> data) async {
    final channelId = _s(data['channel_id'] ?? data['channelId']);
    final battleId = _s(data['battle_id'] ?? data['battleId'] ?? data['entity_id']);
    final hostAId = _s(data['host_a_id'] ?? data['hostAId'] ?? data['from_uid'] ?? data['fromUid']);
    final hostBId = _s(data['host_b_id'] ?? data['hostBId'] ?? data['to_uid'] ?? data['toUid']);

    final ch = channelId.isNotEmpty
        ? channelId
        : (battleId.isNotEmpty ? 'weafrica_battle_$battleId' : '');

    if (ch.isEmpty) {
      _toast('Battle channel missing');
      await _navigateToNotifications();
      return;
    }

    final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid.trim() ?? 'guest';
    final displayName = (currentUser?.displayName ?? '').trim();
    final role = await UserRoleResolver.resolveCurrentUser();

    await _openBattleRoom(
      channelId: ch,
      battleId: battleId.isNotEmpty ? battleId : ch,
      role: role,
      hostId: uid,
      hostName: displayName.isNotEmpty ? displayName : role.label,
      battleArtists: <String>{hostAId, hostBId, uid}
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Navigation helpers (implement based on your routing).

  Future<void> _navigateToTrack(String? trackId, {bool openComments = false}) async {
    final id = _s(trackId);
    if (id.isEmpty) {
      _toast('Missing track id in notification.');
      await _navigateToNotifications();
      return;
    }

    Track? track;
    Object? loadError;
    try {
      track = await TracksRepository().getById(id);
    } catch (e) {
      loadError = e;
      _nsLog('⚠️ Failed to load track for notification: $e');
    }

    if (track == null) {
      if (loadError == null) {
        _toast('This song is no longer available.');
      } else {
        _toast('Could not load this song right now.');
      }
      await _navigateToLibrary();
      return;
    }

    final bool canPlay = track.audioUri != null;
    if (canPlay) {
      PlaybackController.instance.play(track);
      final didPushPlayer = await _openFullPlayer();

      if (openComments) {
        unawaited(_openCommentsSheet(track, afterPlayerTransition: didPushPlayer));
      }
      return;
    } else if (!openComments) {
      _toast('This track is not playable yet.');
      await _navigateToNotifications();
      return;
    }

    // Track exists but isn't playable; allow comments-only view.
    if (openComments) {
      unawaited(_openCommentsSheet(track, afterPlayerTransition: false));
    }
  }

  Future<void> _openCommentsSheet(Track track, {required bool afterPlayerTransition}) async {
    if (afterPlayerTransition) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
    }

    final ctx = await _waitForNavigatorContext();
    if (ctx == null) return;
    if (!ctx.mounted) return;

    try {
      await showSongCommentsSheet(ctx, track: track);
    } catch (e) {
      _nsLog('⚠️ Failed to open comments sheet: $e');
    }
  }

  /// Opens the full player, reusing an existing player route if present.
  ///
  /// Returns `true` when we pushed a new route (animation delay needed).
  Future<bool> _openFullPlayer() async {
    final nav = await _waitForNavigatorState();
    if (nav == null) return false;

    final tracker = AppRouteTracker.instance;
    if (tracker.currentName == _kFullPlayerRouteName) return false;

    if (tracker.containsName(_kFullPlayerRouteName)) {
      nav.popUntil((route) => route.settings.name == _kFullPlayerRouteName || route.isFirst);
      if (tracker.currentName == _kFullPlayerRouteName) return false;
    }

    await nav.push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: _kFullPlayerRouteName),
        pageBuilder: (context, animation, secondaryAnimation) => const FullPlayerScreen(),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));

          return SlideTransition(
            position: animation.drive(slide),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
    return true;
  }

  Future<void> _navigateToLiveFeed() async {
    _nsLog('📡 Navigate to live feed');
    final nav = await _waitForNavigatorState();
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const LiveFeedScreen(),
      ),
    );
  }

  Future<void> _navigateToLiveBattle(Map<String, dynamic> data) async {
    final channelId = _s(data['channel_id'] ?? data['channelId']);
    final battleId = _s(data['battle_id'] ?? data['battleId'] ?? data['entity_id']);
    final hostAId = _s(data['host_a_id'] ?? data['hostAId']);
    final hostBId = _s(data['host_b_id'] ?? data['hostBId']);

    final ch = channelId.isNotEmpty
        ? channelId
        : (battleId.isNotEmpty ? 'weafrica_battle_$battleId' : '');

    if (ch.isEmpty) {
      await _navigateToLiveFeed();
      return;
    }

    final user = fb_auth.FirebaseAuth.instance.currentUser;
    final viewerId = (user?.uid ?? 'guest').trim();
    final viewerName = (user?.displayName ?? '').trim();

    final nav = await _waitForNavigatorState();
    if (nav == null) return;

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => LiveScreen(
          args: LiveArgs(
            liveId: ch,
            channelId: ch,
            role: UserRole.consumer,
            hostId: viewerId.isNotEmpty ? viewerId : 'guest',
            hostName: viewerName.isNotEmpty ? viewerName : 'Viewer',
            isBattle: true,
            battleId: battleId.isNotEmpty ? battleId : null,
            battleArtists: <String>{hostAId, hostBId}
                .where((s) => s.trim().isNotEmpty)
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Future<void> _openBattleRoom({
    required String channelId,
    required String battleId,
    required UserRole role,
    required String hostId,
    required String hostName,
    required List<String> battleArtists,
  }) async {
    final ch = channelId.trim();
    if (ch.isEmpty) {
      _toast('Battle channel missing');
      return;
    }

    final nav = await _waitForNavigatorState();
    if (nav == null) return;

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => LiveScreen(
          args: LiveArgs(
            liveId: ch,
            channelId: ch,
            role: role,
            hostId: hostId,
            hostName: hostName,
            isBattle: true,
            battleId: battleId.trim().isEmpty ? null : battleId.trim(),
            battleArtists: battleArtists,
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToRewards() async {
    _nsLog('🎁 Navigate to rewards/wallet');

    UserRole role = UserRole.consumer;
    try {
      role = await UserRoleResolver.resolveCurrentUser();
    } catch (_) {
      // ignore; fall back to consumer
    }

    final Widget dest = switch (role) {
      UserRole.artist => const ArtistEarningsScreen(),
      UserRole.dj => const DjEarningsScreen(),
      UserRole.consumer => WalletScreen(roleOverride: role),
    };

    final nav = await _waitForNavigatorState();
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(builder: (_) => dest),
    );
  }

  Future<void> _navigateToCreatorGrowth() async {
    UserRole role = UserRole.consumer;
    try {
      role = await UserRoleResolver.resolveCurrentUser();
    } catch (_) {
      // ignore; fall back to consumer notifications
    }

    final Widget dest = switch (role) {
      UserRole.artist => const ArtistStatsScreen(),
      UserRole.dj => const DjHighlightsScreen(),
      UserRole.consumer => const NotificationsScreen(),
    };

    final nav = await _waitForNavigatorState();
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(builder: (_) => dest),
    );
  }

  Future<void> _navigateToNotifications() async {
    _nsLog('🔔 Navigate to notifications');
    final nav = await _waitForNavigatorState();
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }

  Future<void> _navigateToSubscriptions() async {
    _nsLog('💳 Navigate to subscriptions');
    final nav = await _waitForNavigatorState();
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const RoleBasedSubscriptionScreen(),
      ),
    );
  }

  Future<void> _navigateToLibrary() async {
    final nav = await _waitForNavigatorState();
    if (nav == null) return;

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const LibraryTab(),
      ),
    );
  }

  // Live navigation removed — Live UI is disabled.

  /// Clear badge count.
  Future<void> clearBadge() async {
    _setUnreadCount(0);
    await _updateAppBadge();
  }

  /// Get current FCM token.
  String? get fcmToken => _fcmToken;

  /// Get current unread count.
  int get unreadCount => _unreadCount;
}
