# FCM Integration - Copy & Paste Code Snippets

**Everything you need to integrate Firebase FCM into your Flutter app**

---

## 1️⃣ Login/Auth Flow Integration

**File:** `lib/main.dart` or `lib/features/auth/login_screen.dart`

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _handleLogin() async {
    try {
      // 1. Authenticate with Firebase
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final user = userCredential.user;
      if (user == null) return;

      // 2. Get Firebase ID token
      final idToken = await user.getIdToken();

      // 3. Get FCM token
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        print('⚠️ Could not get FCM token');
        return;
      }

      // 4. Register device token with backend
      await _registerDeviceToken(fcmToken, idToken, user.uid);

      // 5. Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _registerDeviceToken(newToken, idToken, user.uid);
      });

      // 6. Navigate to home
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }

    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.message}')),
      );
    }
  }

  Future<void> _registerDeviceToken(
    String fcmToken,
    String idToken,
    String userId,
  ) async {
    try {
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      String? deviceId;
      String? deviceModel;

      if (platform == 'ios') {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor;
        deviceModel = iosInfo.model;
      } else {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        deviceModel = androidInfo.model;
      }

      // Get user's country (from profile, or use device locale)
      String? countryCode = 'ng'; // Default to Nigeria
      try {
        // Try to get from user profile if stored in Firestore
        // final profile = await FirebaseFirestore.instance
        //   .collection('users').doc(userId).get();
        // countryCode = profile.data()?['country_code'] ?? 'ng';
      } catch (e) {
        print('Could not fetch user country: $e');
      }

      // Get user role (from SharedPreferences)
      final userRole = await UserRoleStore.getRole();
      final topics = _getTopicsForRole(userRole);

      // Send registration request
      final response = await http.post(
        Uri.parse('https://your-backend.com/api/push/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'platform': platform,
          'device_id': deviceId,
          'country_code': countryCode.toLowerCase(),
          'topics': topics,
          'app_version': packageInfo.version,
          'device_model': deviceModel,
          'locale': Intl.systemLocale,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Device token registered');
      } else {
        print('❌ Failed to register token: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error registering device token: $e');
    }
  }

  List<String> _getTopicsForRole(UserRole role) {
    switch (role) {
      case UserRole.artist:
        return ['artist', 'likes', 'comments', 'collaborations'];
      case UserRole.dj:
        return ['dj', 'live_battles', 'followers'];
      case UserRole.consumer:
        return ['consumers', 'likes', 'comments', 'trending', 'recommendations'];
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _handleLogin,
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 2️⃣ Message Handlers (Foreground & Background)

**File:** `lib/main.dart` - in `initState()` of your main app widget

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Set background message handler BEFORE running app
  FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
  
  runApp(const MyApp());
}

// Handle messages when app is in background or terminated
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  print('📬 Background message: ${message.messageId}');
  // App will resume to foreground when user taps notification
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _setupMessageHandlers();
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/song/:id',
          builder: (context, state) {
            final songId = state.pathParameters['id']!;
            return SongDetailPage(songId: songId);
          },
        ),
        GoRoute(
          path: '/song/:id/comments',
          builder: (context, state) {
            final songId = state.pathParameters['id']!;
            return CommentsPage(songId: songId);
          },
        ),
        GoRoute(
          path: '/profile/:id',
          builder: (context, state) {
            final userId = state.pathParameters['id']!;
            return ProfilePage(userId: userId);
          },
        ),
        GoRoute(
          path: '/battle/:id',
          builder: (context, state) {
            final battleId = state.pathParameters['id']!;
            return LiveBattleDetailPage(battleId: battleId);
          },
        ),
      ],
    );
  }

  void _setupMessageHandlers() {
    // Handle message when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📬 Foreground message: ${message.messageId}');
      print('   Title: ${message.notification?.title}');
      print('   Body: ${message.notification?.body}');
      print('   Data: ${message.data}');

      // Extract notification data
      final data = message.data;
      final type = data['type'] ?? 'unknown';
      final title = message.notification?.title ?? 'Notification';
      final body = message.notification?.body ?? '';
      final imageUrl = data['image_url'];

      // Show custom notification UI
      _showForegroundNotification(
        title: title,
        body: body,
        type: type,
        data: data,
        imageUrl: imageUrl,
      );
    });

    // Handle message opened (user tapped notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 Notification opened: ${message.messageId}');

      final data = message.data;
      final screen = data['screen'] ?? 'home';
      final entityId = data['entity_id'];

      // Navigate to appropriate screen
      _handleNotificationNavigation(screen, entityId);
    });

    // Handle initial message (app was terminated when notification arrived)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print('🚀 Initial message (app was terminated): ${message.messageId}');
        final data = message.data;
        final screen = data['screen'] ?? 'home';
        final entityId = data['entity_id'];
        _handleNotificationNavigation(screen, entityId);
      }
    });
  }

  void _showForegroundNotification({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
    String? imageUrl,
  }) {
    // Option 1: Use local_notifications package
    // _showLocalNotification(title, body, imageUrl);

    // Option 2: Show custom overlay
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageUrl != null)
                Image.network(imageUrl, height: 100),
              const SizedBox(height: 8),
              Text(body),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleNotificationNavigation(data['screen'], data['entity_id']);
              },
              child: const Text('View'),
            ),
          ],
        ),
      );
    }
  }

  void _handleNotificationNavigation(String? screen, String? entityId) {
    if (screen == null) return;

    switch (screen) {
      case 'song_detail':
        if (entityId != null) {
          _router.push('/song/$entityId');
        }
        break;
      case 'comments':
        if (entityId != null) {
          _router.push('/song/$entityId/comments');
        }
        break;
      case 'profile':
        if (entityId != null) {
          _router.push('/profile/$entityId');
        }
        break;
      case 'live_battle_detail':
        if (entityId != null) {
          _router.push('/battle/$entityId');
        }
        break;
      case 'home':
      default:
        _router.push('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'WEAFRICA Music',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
    );
  }
}
```

---

## 3️⃣ Logout Flow

**File:** `lib/features/auth/auth_service.dart` or similar

```dart
Future<void> logout() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user != null) {
      // Get current FCM token and deactivate it on backend
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      if (fcmToken != null) {
        try {
          await http.post(
            Uri.parse('https://your-backend.com/api/push/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await user.getIdToken()}',
            },
            body: jsonEncode({'fcm_token': fcmToken}),
          );
        } catch (e) {
          print('Warning: Could not notify backend of logout: $e');
        }
      }
    }
    
    // Sign out from Firebase
    await FirebaseAuth.instance.signOut();
    
  } catch (e) {
    print('Error logging out: $e');
  }
}
```

---

## 4️⃣ Role Change Handling

**File:** `lib/features/auth/user_role_store.dart` - when user upgrades to artist/dj

```dart
Future<void> changeRole(UserRole newRole) async {
  try {
    // Save new role
    await UserRoleStore.setRole(newRole);
    
    // Re-register device token with new topics
    final user = FirebaseAuth.instance.currentUser;
    final fcmToken = await FirebaseMessaging.instance.getToken();
    
    if (user != null && fcmToken != null) {
      final idToken = await user.getIdToken();
      
      // Send registration request with new topics
      await http.post(
        Uri.parse('https://your-backend.com/api/push/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'fcm_token': fcmToken,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'topics': _getTopicsForRole(newRole),
          // ... other fields
        }),
      );
      
      print('✅ Role changed to ${newRole.label}, topics updated');
    }
  } catch (e) {
    print('Error changing role: $e');
  }
}

List<String> _getTopicsForRole(UserRole role) {
  switch (role) {
    case UserRole.artist:
      return ['artist', 'likes', 'comments', 'collaborations'];
    case UserRole.dj:
      return ['dj', 'live_battles', 'followers'];
    case UserRole.consumer:
      return ['consumers', 'likes', 'comments', 'trending', 'recommendations'];
  }
}
```

---

## 5️⃣ Optional: Custom Preferences

**File:** `lib/features/notifications/notification_preferences.dart`

```dart
class NotificationPreferences {
  static const String _keyMarketingOptIn = 'marketing_opt_in';
  static const String _keyNewsletterOptIn = 'newsletter_opt_in';

  static Future<void> toggleMarketingOptIn(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMarketingOptIn, enabled);
    
    // Re-register with backend to update topics
    await _reregisterWithNewPreferences();
  }

  static Future<void> toggleNewsletterOptIn(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNewsletterOptIn, enabled);
    
    // Re-register with backend to update topics
    await _reregisterWithNewPreferences();
  }

  static Future<bool> isMarketingOptIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMarketingOptIn) ?? false;
  }

  static Future<bool> isNewsletterOptIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNewsletterOptIn) ?? false;
  }

  static Future<void> _reregisterWithNewPreferences() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      if (user != null && fcmToken != null) {
        // Reconstruct topics with preferences
        final userRole = await UserRoleStore.getRole();
        var topics = _getTopicsForRole(userRole);
        
        if (await isMarketingOptIn()) {
          topics.add('marketing');
        }
        if (await isNewsletterOptIn()) {
          topics.add('newsletter');
        }
        
        // Re-register
        await http.post(
          Uri.parse('https://your-backend.com/api/push/register'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await user.getIdToken()}',
          },
          body: jsonEncode({
            'fcm_token': fcmToken,
            'topics': topics,
            // ... other fields
          }),
        );
      }
    } catch (e) {
      print('Error updating preferences: $e');
    }
  }
}
```

---

## 6️⃣ Testing with Postman

### Test 1: Register Device Token

```
POST https://your-backend.com/api/push/register
Content-Type: application/json
Authorization: Bearer {firebase_id_token}

{
  "fcm_token": "e1k2K3N...LxA:APA91bGkL...",
  "platform": "ios",
  "device_id": "device-uuid-12345",
  "country_code": "ng",
  "topics": ["consumers", "likes", "comments"],
  "app_version": "1.2.3",
  "device_model": "iPhone 14",
  "locale": "en-NG"
}
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Token registered",
  "user_id": "firebase-uid-xyz"
}
```

### Test 2: Send Notification

```
POST https://your-backend.com/api/notifications/send
Content-Type: application/json
Authorization: Bearer {admin_token}

{
  "title": "New Like!",
  "body": "Someone liked your song",
  "type": "like_update",
  "screen": "song_detail",
  "entity_id": "song_abc123",
  "image_url": "https://cdn.example.com/image.jpg",
  "target_topics": ["likes"],
  "target_countries": ["ng"],
  "notification_id": "notif_xyz789"
}
```

**Expected Response:**
```json
{
  "success": true,
  "notification_id": "push_123",
  "sent": 1250,
  "failed": 5,
  "message": "Notification sent to 1250 users"
}
```

---

## 📦 Required Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^2.0.0
  firebase_auth: ^4.0.0
  firebase_messaging: ^14.6.0
  device_info_plus: ^10.1.0
  package_info_plus: ^5.0.0
  http: ^1.1.0
  intl: ^0.18.0
  shared_preferences: ^2.0.0
  go_router: ^13.0.0  # or your router of choice
```

Then run: `flutter pub get`

---

## ✅ Checklist

- [ ] Firebase Auth setup complete
- [ ] FCM initialized in app
- [ ] Token registration called on login
- [ ] Message handlers set up (foreground/background)
- [ ] Navigation routing working
- [ ] Backend API built and tested
- [ ] Admin dashboard ready
- [ ] Test with real devices
- [ ] Production deployment

---

**Last Updated:** January 28, 2026  
**Status:** Ready to Copy & Paste
