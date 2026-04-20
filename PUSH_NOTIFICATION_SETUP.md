# 🔔 WEAFRICA MUSIC - Push Notification System Setup

Complete implementation guide for the push notification flow from consumer app → Supabase → Admin dashboard → FCM backend → Consumer app.

---

## 📋 Table of Contents

1. [Database Setup](#database-setup)
2. [Flutter App Configuration](#flutter-app-configuration)
3. [FCM Token Registration](#fcm-token-registration)
4. [Admin Dashboard](#admin-dashboard)
5. [Cloud Functions Backend](#cloud-functions-backend)
6. [Notification Routing](#notification-routing)
7. [Testing](#testing)
8. [Monitoring & Analytics](#monitoring--analytics)

---

## 🗄️ Database Setup

### 1. Apply Schema

Deploy the notification system schema to your Supabase database:

```bash
# Using supabase CLI
supabase db push tool/push_notification_schema.sql

# Or manually run in Supabase SQL editor
```

**Tables created:**
- `notification_device_tokens` - Stores FCM tokens for each device
- `notifications` - Notification templates/campaigns
- `notification_recipients` - Tracks recipients for each notification
- `notification_engagement` - Tracks opens, clicks, dismissals

**Features:**
- ✅ Row-level security (RLS) policies
- ✅ Optimized indexes for fast queries
- ✅ Analytics views for reporting

### 2. Update Users Table (if needed)

Ensure your `users` table has a `role` column:

```sql
alter table public.users add column if not exists role text default 'consumer' check (role in ('consumer', 'artist', 'dj', 'admin'));
```

---

## 📱 Flutter App Configuration

### 0. Configure backend base URL (required for real devices)

The app registers the FCM token by calling `POST /api/push/register` on your admin backend.

For a physical phone, **do not use `localhost`**. Set a reachable URL via `PUSH_BACKEND_BASE_URL`, for example:

- Same Wi‑Fi (local dev): `http://<your-mac-lan-ip>:3000`
- Deployed domain: `https://<your-admin-domain>`
- Tunnel: `https://<ngrok-id>.ngrok.app`

If you run from VS Code using the existing launch configs, add these keys to `tool/supabase.env.json`:

```json
{
  "PUSH_BACKEND_BASE_URL": "http://<your-mac-lan-ip>:3000",
  "DEFAULT_COUNTRY_CODE": "mw"
}
```

### 1. Add Dependencies

Update your `pubspec.yaml`:

```yaml
dependencies:
  firebase_messaging: ^14.6.0
  supabase_flutter: ^2.0.0+
  device_info_plus: ^10.1.0
  package_info_plus: ^5.0.0
  provider: ^6.0.0
  go_router: ^13.0.0  # For navigation
```

### 2. Initialize Firebase in main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}
```

### 3. iOS-Specific Setup

**ios/Podfile:**
```ruby
# Set minimum iOS version to 11.0+
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'
    end
  end
end
```

**ios/Runner/GoogleService-Info.plist:**
- Download from Firebase console
- Add to Xcode (not via file system)

### 4. Android-Specific Setup

**android/app/build.gradle:**
```gradle
dependencies {
  // Firebase Cloud Messaging
  implementation 'com.google.firebase:firebase-messaging'
}
```

**android/build.gradle:**
```gradle
plugins {
  id 'com.google.gms.google-services' version '4.4.0' apply false
}
```

**android/app/build.gradle (apply plugin):**
```gradle
apply plugin: 'com.google.gms.google-services'
```

---

## 🔐 FCM Token Registration

### 1. Initialize in Your App

After user logs in, initialize the notification system:

```dart
// In your auth state or main app
Future<void> setupNotifications() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;

  try {
    // Create analytics service
    final analyticsService = NotificationAnalyticsService(
      Supabase.instance.client,
    );

    // Initialize FCM (registers device token automatically)
    await FCMService.initialize(
      analyticsService,
      userId: user.id,
    );

    // Set up notification callbacks
    setupNotificationHandlers();
  } catch (e) {
    print('Error setting up notifications: $e');
  }
}

void setupNotificationHandlers() {
  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('📬 Foreground: ${message.notification?.title}');
    // Show custom notification UI here
  });

  // Handle notification when app is opened from notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('👆 User tapped notification');
    routeNotification(message);
  });
}
```

### 2. Subscribe to Topics (Optional)

Subscribe users to topics for group messaging:

```dart
// Subscribe user to song updates
await FCMService.subscribeTopic('songs');

// Subscribe to artist updates
await FCMService.subscribeTopic('artist_${artistId}');

// Subscribe to live battle notifications
await FCMService.subscribeTopic('live_battles');
```

---

## 🎨 Admin Dashboard

### 1. Access Admin Dashboard

Navigate to the admin notification dashboard:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const AdminNotificationDashboard(),
  ),
);
```

### 2. Create Notification

1. **Tab 1: Create Notification**
   - Enter title and body
   - Select notification type
   - Choose target roles (consumer, artist, dj)
   - Select countries (optional, leave empty for all)
   - Set schedule time
   - Click "Create & Schedule"

2. **Tab 2: Schedule**
   - View all scheduled notifications
   - Edit or cancel as needed

3. **Tab 3: Analytics**
   - View delivery rates
   - Performance by type
   - Geographic breakdown

4. **Tab 4: Token Health**
   - Monitor active/inactive tokens
   - Platform breakdown (iOS, Android, Web)
   - Identify problematic regions

### 3. Example Notification Creation

```dart
// Programmatically create notification
final notification = await notificationRepo.createNotification(
  userId: adminUserId,
  title: 'New Song Released! 🎵',
  body: 'Check out the latest track from your favorite artist',
  type: NotificationType.newSong,
  targetRoles: ['consumer', 'artist'],
  targetCountries: ['NG', 'GH', 'KE'], // Nigeria, Ghana, Kenya
  scheduledAt: DateTime.now().add(Duration(hours: 2)),
  payload: {
    'entity_id': songId,
    'screen': 'song_detail',
  },
);

// Schedule for sending
await notificationRepo.scheduleNotification(notification.id);
```

---

## ☁️ Cloud Functions Backend

### 1. Deploy Cloud Functions

```bash
cd functions

# Install dependencies
npm install

# Deploy
firebase deploy --only functions:sendPushNotifications,functions:sendNotification,functions:handleTokenRefresh
```

### 2. Environment Variables

Create `.env.local` in functions directory:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE=your-service-role-key
```

If you are using the Supabase Edge Function API (`supabase/functions/api`) to send realtime pushes (e.g. **battle invites**), you must also configure an FCM server key:

- Local dev: add `FCM_SERVER_KEY=...` in `supabase/.env.local` (see `supabase/.env.local.example`)
- Production: `supabase secrets set FCM_SERVER_KEY=...` and redeploy the `api` function

### 3. Functions Deployed

**`sendPushNotifications`** (Pub/Sub scheduled)
- Runs every 5 minutes
- Finds scheduled notifications
- Sends to matching users
- Updates delivery status

**`sendNotification`** (Callable)
- Manual trigger via admin dashboard
- Validates admin user
- Immediately sends notification

**`handleTokenRefresh`** (Callable)
- Updates token when refreshed on device
- Called by device after token refresh

### 4. Testing Cloud Functions

```bash
# Test locally
firebase emulators:start

# Call function from Dart
final callable = FirebaseFunctions.instance.httpsCallable(
  'sendNotification',
);

try {
  final result = await callable.call({
    'notification_id': notificationId,
  });
  print('Response: ${result.data}');
} catch (e) {
  print('Error: $e');
}
```

---

## 🧭 Notification Routing

### 1. Setup GoRouter Routes

Add notification routes to your GoRouter config:

```dart
GoRoute(
  path: '/song/:id',
  name: 'song-detail',
  builder: (context, state) => SongDetailScreen(
    songId: state.pathParameters['id']!,
  ),
),
GoRoute(
  path: '/battle/:id',
  name: 'live-battle',
  builder: (context, state) => LiveBattleScreen(
    battleId: state.pathParameters['id']!,
  ),
),
GoRoute(
  path: '/profile/:id',
  name: 'profile',
  builder: (context, state) => ProfileScreen(
    userId: state.pathParameters['id']!,
  ),
),
GoRoute(
  path: '/comments/:songId',
  name: 'comments',
  builder: (context, state) => CommentsScreen(
    songId: state.pathParameters['songId']!,
  ),
),
```

### 2. Handle Notification Taps

```dart
void setupNotificationRouting() {
  final router = GoRouter(...);
  final notificationRouter = NotificationRouter(router);

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    notificationRouter.routeNotification(message);
  });
}
```

### 3. Supported Notification Types

| Type | Route | Payload |
|------|-------|---------|
| `likeUpdate` | Song detail | `entity_id: songId` |
| `commentUpdate` | Comments | `entity_id: songId` |
| `liveBattle` | Live battle | `entity_id: battleId` |
| `newSong` | Home | — |
| `followNotification` | Profile | `entity_id: userId` |
| `collaborationInvite` | Collaboration | `entity_id: collabId` |
| `systemAnnouncement` | Dialog | — |

---

## 🧪 Testing

### 1. Test Device Token Registration

```dart
// Verify token is registered
final tokens = await notificationRepo.getUserTokens(userId);
print('Registered tokens: ${tokens.length}');
for (final token in tokens) {
  print('  - ${token.platform.value}: ${token.fcmToken.substring(0, 20)}...');
}
```

### 2. Send Test Notification

```dart
// Via Firebase console
// Go to Cloud Messaging tab
// Click "Send your first message"
// Enter title, body
// Select "User segments" → Filter by custom claim

// Or via Cloud Functions
final callable = FirebaseFunctions.instance.httpsCallable(
  'sendNotification',
);
await callable.call({'notification_id': notificationId});
```

### 3. Monitor Logs

**Firebase Console:**
- Functions → Logs
- Check for errors in sendPushNotifications

**Supabase Dashboard:**
- Open notification_logs table
- Check delivery status for each token
- View engagement events

---

## 📊 Monitoring & Analytics

### 1. View Analytics

```dart
// Get overall performance
final analytics = await notificationRepo.getAnalytics();
print('Total sent: ${analytics['total_sent']}');
print('Delivery rate: ${analytics['delivery_rate_pct']}%');
print('Open rate: ${analytics['open_rate_pct']}%');
```

### 2. Monitor Token Health

```dart
final health = await notificationRepo.getTokenHealth();
print('Active tokens: ${health['active_tokens']}');
print('Active rate: ${health['active_percentage']}%');
```

### 3. Database Queries

**Get delivery stats by notification type:**
```sql
select * from public.notification_performance_by_type;
```

**Get engagement by country:**
```sql
select country_code, count(*) from notification_engagement group by country_code;
```

**Find problematic tokens:**
```sql
select platform, count(*) from notification_device_tokens 
where is_active = false 
group by platform;
```

---

## 🚀 Deployment Checklist

- [ ] Database schema applied
- [ ] Firebase & Supabase configured
- [ ] iOS & Android native setup complete
- [ ] pubspec.yaml updated with dependencies
- [ ] FCM initialization in main.dart
- [ ] Device token registration working
- [ ] Admin dashboard accessible
- [ ] Cloud Functions deployed
- [ ] Notification routing configured
- [ ] Analytics dashboard operational
- [ ] Test notifications sent successfully
- [ ] Monitoring alerts configured

---

## 📞 Troubleshooting

### Token Not Registering

```dart
// Check if FCM initialization completed
final token = await FirebaseMessaging.instance.getToken();
print('FCM Token: $token');

// Check Supabase insertion
final tokens = await supabase
    .from('notification_device_tokens')
    .select()
    .eq('user_id', userId);
print('Tokens in DB: $tokens');
```

### Notifications Not Sending

1. Check Cloud Function logs
2. Verify notification status is 'scheduled'
3. Check target_roles and target_countries match users
4. Ensure FCM service account has permissions

### High Failure Rate

1. Check device_tokens.is_active status
2. Check last_updated timestamps
3. Consider token cleanup job
4. Review failure_reason in notification_engagement

---

## 🎓 Architecture Summary

```
┌─────────────────────────┐
│  Consumer App (Flutter) │
│ ─ Firebase Auth        │
│ ─ Registers FCM token  │
│ ─ Handles messages     │
└────────────┬────────────┘
             │ 1. Token
             ▼
┌─────────────────────────┐
│  Supabase / Postgres   │
│ ─ Device tokens table  │
│ ─ Notifications table  │
│ ─ Engagement tracking  │
└────────────┬────────────┘
             │ 2. Admin creates
             ▼
┌─────────────────────────┐
│  Admin Dashboard        │
│ ─ Create notification  │
│ ─ Set targets/schedule │
│ ─ View analytics       │
└────────────┬────────────┘
             │ 3. Triggers
             ▼
┌─────────────────────────┐
│  Cloud Functions        │
│ ─ Query matching tokens│
│ ─ Send via FCM API     │
│ ─ Update status        │
└────────────┬────────────┘
             │ 4. FCM sends
             ▼
┌─────────────────────────┐
│  Consumer App (Device) │
│ ─ Receives push        │
│ ─ Routes to screen     │
│ ─ Logs engagement      │
└─────────────────────────┘
```

---

## 📚 Related Files

- `tool/push_notification_schema.sql` - Database schema
- `lib/features/notifications/models/device_token.dart` - Device token model
- `lib/features/notifications/models/push_notification.dart` - Notification model
- `lib/features/notifications/services/device_token_service.dart` - Token management
- `lib/features/notifications/services/fcm_service.dart` - FCM integration
- `lib/features/notifications/admin/notification_admin_dashboard.dart` - Admin UI
- `functions/src/notifications.ts` - Cloud Functions
- `lib/features/notifications/services/notification_router.dart` - Routing
- `lib/features/notifications/repositories/notification_repository.dart` - Repository

---

**Last Updated:** January 28, 2026  
**Status:** Production Ready
