# 🔔 FCM + API Integration Reference Sheet

## 1️⃣ STANDARDIZED DATA KEYS (What FCM sends to your app)

```dart
const String type = 'type';              // e.g., "like_update"
const String screen = 'screen';          // e.g., "song_detail"
const String entityId = 'entity_id';     // e.g., "song_uuid_12345"
const String notificationId = 'notification_id'; // For analytics
const String title = 'title';            // Optional override
const String body = 'body';              // Optional override
const String imageUrl = 'image_url';     // Optional thumbnail
```

## 2️⃣ TYPE → SCREEN MAPPING

| Type | Screen | Entity | Example |
|------|--------|--------|---------|
| `like_update` | `song_detail` | `song_id` | Navigate to song |
| `comment_update` | `comments` | `song_id` | Navigate to comments |
| `live_battle` | `live_battle_detail` | `battle_id` | Join live battle |
| `follow_notification` | `profile` | `follower_id` | View profile |
| `collaboration_invite` | `collaboration` | `collab_id` | View collaboration |
| `new_song` | `home` | — | Refresh home feed |
| `new_video` | `home` | — | Refresh home feed |
| `coin_reward` | `home` | — | Show reward dialog |
| `system_announcement` | `home` | — | Show dialog |

## 3️⃣ API ENDPOINT: `/api/push/register`

**When:** Call after `FCMService.initialize()`

**Method:** `POST`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer {firebase_id_token}
```

**Request Body:**
```json
{
  "token": "e1k2K3N...LxA:APA...",
  "platform": "ios" | "android" | "web",
  "device_id": "optional-device-uuid",
  "country_code": "ng",
  "topics": ["consumers", "marketing", "trending"],
  "app_version": "1.2.3",
  "device_model": "iPhone 14 Pro",
  "locale": "en-NG"
}
```

**Response (200):**
```json
{
  "ok": true,
  "message": "Token registered",
  "user_uid": "firebase-uid-extracted-server-side"
}
```

**Authentication:**
- Firebase ID token in `Authorization: Bearer` header
- `user_uid` is derived server-side from token, NOT sent in body
- likes/comments are direct notifications (not topics)
- On 401: Refresh token and retry

**Verify token storage (Supabase SQL):**
```sql
select token, user_uid, topics, country_code
from notification_device_tokens
order by last_seen_at desc
limit 20;
```

## 4️⃣ EXAMPLE FCM PAYLOAD (What your backend sends)

```json
{
  "notification": {
    "title": "New Like!",
    "body": "John liked your song"
  },
  "data": {
    "type": "like_update",
    "screen": "song_detail",
    "entity_id": "song_abc123",
    "notification_id": "notif_xyz789",
    "image_url": "https://cdn.weafrica.com/song.jpg"
  }
}
```

## 5️⃣ MESSAGE HANDLERS IN YOUR APP

```dart
// Foreground (app open)
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  final data = message.data;
  final type = data['type'];
  final screen = data['screen'];
  final entityId = data['entity_id'];
  // → Show custom notification UI
});

// User taps notification
FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
  final data = message.data;
  final screen = data['screen'];
  final entityId = data['entity_id'];
  // → Navigate to screen with entityId as parameter
});
```

## 6️⃣ ROUTING LOGIC

```dart
switch (screen) {
  case 'song_detail':
    navigateTo('song_detail', id: entityId);
    break;
  case 'comments':
    navigateTo('comments', songId: entityId);
    break;
  case 'live_battle_detail':
    navigateTo('live_battle', id: entityId);
    break;
  case 'profile':
    navigateTo('profile', userId: entityId);
    break;
  case 'home':
  default:
    navigateTo('home');
}
```

## 7️⃣ BACKEND: What to Send (Node.js Example)

```javascript
// Send notification via FCM
await admin.messaging().sendEachForMulticast({
  notification: {
    title: "New Like!",
    body: "John liked your song"
  },
  data: {
    type: "like_update",
    screen: "song_detail",
    entity_id: songId,
    notification_id: notificationId,
    image_url: songImageUrl
  },
  tokens: fcmTokensArray // from database
});

// Also save to database for analytics
await db.collection('notifications').insert({
  id: notificationId,
  type: "like_update",
  to_users: userIdsArray,
  status: "sent",
  created_at: new Date(),
  sent_at: new Date()
});
```

## 8️⃣ TOKEN REGISTRATION FLOW

```
App Opens
    ↓
User Logs In
    ↓
FCMService.initialize(userId)
    ├─ Request permissions
    ├─ Get FCM token from Firebase
    └─ Save to Supabase
    ↓
Call POST /api/push/register
    ├─ Send token to your backend
    └─ Backend upserts in DB
    ↓
Listen to token refresh
    └─ Re-register if token changes
```

## 9️⃣ SETUP CODE (Copy-Paste Ready)

```dart
Future<void> setupPushNotifications() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // 1. Initialize FCM
  final analyticsService = NotificationAnalyticsService(
    Supabase.instance.client,
  );
  await FCMService.initialize(analyticsService, userId: user.uid);

  // 2. Get token
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken == null) return;

  // 3. Register with backend
  await _registerTokenWithBackend(fcmToken);

  // 4. Listen to token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    _registerTokenWithBackend(newToken);
  });
}

Future<void> _registerTokenWithBackend(String fcmToken) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final idToken = await user.getIdToken(true);

  final response = await http.post(
    Uri.parse('https://your-api.com/api/push/register'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    },
    body: jsonEncode({
      'token': fcmToken,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'device_id': await _getDeviceId(),
      'topics': await _getUserTopics(),
      'app_version': '1.0.0',
      'device_model': 'iPhone',
      'country_code': 'ng',
      'locale': Platform.localeName.replaceAll('_', '-'),
    }),
  );

  if (response.statusCode == 200) {
    print('✅ Token registered');
  }
}
```

## 10️⃣ SMOKE TEST (Admin Dashboard)

1. Admin → Notifications → Push
2. Delivery = Device tokens
3. Topic = marketing (or system)
4. Optional: set Country
5. Send now
6. Verify device receives and routes by `data.type`, `data.screen`, `data.entity_id`
  (you will always receive `notification_id`)

## 11️⃣ INTERNAL AUTOMATION (Backend/Cloud Function)

Use `POST /api/push/send` with:

```
Authorization: Bearer <PUSH_INTERNAL_SECRET>
```

Examples:
- Likes/comments (direct): `audience: { type: 'user_uid', uid: '...' }`
- Trending (broadcast): `token_topic: 'trending'` + `max_per_user_per_day: 2`

## 🔟 KEY POINTS

✅ Always use standardized data keys (type, screen, entity_id)
✅ Type + EntityId determine routing destination
✅ Register token immediately after login
✅ Re-register when token refreshes
✅ Log engagement (delivered, opened, clicked)
✅ Handle both foreground and background messages
✅ Validate data before routing (prevent crashes)
✅ Store notification_id for analytics tracking

---

**File Location:** `lib/features/notifications/FCM_API_REFERENCE.dart`

This is your complete integration spec! Use this to:
- Build your backend API
- Validate FCM payloads
- Test in Postman
- Onboard team members
