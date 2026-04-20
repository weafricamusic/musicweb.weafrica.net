# WEAFRICA MUSIC - Firebase FCM Implementation Checklist

**Date:** January 28, 2026  
**Status:** Ready for Production  
**Authentication:** Firebase ID Token  
**Database:** Firebase Realtime Database or Firestore (backend choice)

---

## ✅ Flutter Client (Consumer App)

### 1. Dependencies
- [x] `firebase_messaging: ^14.6.0`
- [x] `firebase_auth: ^4.0.0` (already in use)
- [x] `device_info_plus: ^10.1.0`
- [x] `package_info_plus: ^5.0.0`
- [x] `http: ^1.1.0`
- [x] `intl: ^0.18.0` (for locale)
- [x] `shared_preferences: ^2.0.0` (for UserRoleStore)

### 2. File Structure
- [x] `lib/features/notifications/FCM_API_REFERENCE.dart` - Complete reference with all functions
- [x] `lib/features/notifications/services/fcm_service.dart` - Main FCM service
- [x] `lib/features/auth/user_role.dart` - User role enum (consumer, artist, dj)
- [x] `lib/features/auth/user_role_store.dart` - Role persistence

### 3. Token Registration Flow

**When:** On successful Firebase login

```dart
// In your login screen / auth service after FirebaseAuth.signInWithEmail()

final user = FirebaseAuth.instance.currentUser;
if (user != null) {
  // Get FCM token
  final fcmToken = await FirebaseMessaging.instance.getToken();
  
  // Register with backend
  await registerTokenWithBackend(fcmToken);
  
  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    registerTokenWithBackend(newToken);
  });
}
```

### 4. Exact Request Format

**Method:** `POST`  
**Endpoint:** `https://your-backend.com/api/push/register`  
**Headers:**
```
Content-Type: application/json
Authorization: Bearer {firebase_id_token}
```

**Body:**
```json
{
  "fcm_token": "e1k2K3N...LxA:APA91bGkL...",
  "platform": "ios",
  "device_id": "device-uuid-optional",
  "country_code": "ng",
  "topics": [
    "consumers",
    "likes",
    "comments",
    "trending",
    "recommendations"
  ],
  "app_version": "1.2.3",
  "device_model": "iPhone 14 Pro",
  "locale": "en-NG"
}
```

### 5. Topics by User Role

| Role | Topics |
|------|--------|
| **Consumer** | `consumers`, `likes`, `comments`, `trending`, `recommendations` |
| **Artist** | `artist`, `likes`, `comments`, `collaborations` |
| **DJ** | `dj`, `live_battles`, `followers` |

**Implementation:** In `_getUserTopics()` → reads from `UserRoleStore.getRole()`

### 6. Message Handlers

```dart
// Foreground (app open)
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  final type = message.data['type'];
  final screen = message.data['screen'];
  final entityId = message.data['entity_id'];
  
  // Show custom notification UI or update state
  showCustomNotification(message);
});

// Background/Foreground (user tapped notification)
FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
  final screen = message.data['screen'];
  final entityId = message.data['entity_id'];
  
  // Navigate to screen with entity
  navigateToScreen(screen, entityId);
});
```

### 7. Navigation Mapping

| Type | Screen | Navigation |
|------|--------|------------|
| `like_update` | `song_detail` | GoRouter.of(context).push('/song/$entityId') |
| `comment_update` | `comments` | GoRouter.of(context).push('/song/$entityId/comments') |
| `live_battle` | `live_battle_detail` | GoRouter.of(context).push('/battle/$entityId') |
| `collaboration_invite` | `collaboration` | GoRouter.of(context).push('/collaboration/$entityId') |
| `follow_notification` | `profile` | GoRouter.of(context).push('/profile/$entityId') |
| `new_song`, `new_video` | `home` | GoRouter.of(context).push('/home') |
| `coin_reward` | `home` | Show reward dialog + refresh balance |

---

## ✅ Backend API (Node.js/Express)

### 1. POST /api/push/register

**Authentication:** Firebase ID token verification

```javascript
const admin = require('firebase-admin');
const express = require('express');
const app = express();

app.post('/api/push/register', async (req, res) => {
  try {
    // Extract and verify Firebase ID token
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing authorization header' });
    }
    
    const idToken = authHeader.substring(7);
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    const userId = decodedToken.uid;
    
    // Extract request data
    const {
      fcm_token,
      platform,
      device_id,
      country_code,
      topics,
      app_version,
      device_model,
      locale
    } = req.body;
    
    // Store or update device token
    await admin.database().ref(`users/${userId}/devices/${device_id || fcm_token}`).set({
      fcm_token,
      platform,
      device_id: device_id || null,
      country_code: country_code?.toLowerCase() || 'unknown',
      topics: topics || [],
      app_version,
      device_model,
      locale,
      is_active: true,
      last_updated: admin.database.ServerValue.TIMESTAMP,
      created_at: admin.database.ServerValue.TIMESTAMP,
    });
    
    res.status(200).json({
      success: true,
      message: 'Token registered',
      user_id: userId
    });
    
  } catch (error) {
    console.error('Error registering token:', error);
    res.status(401).json({ error: 'Unauthorized' });
  }
});
```

### 2. POST /api/notifications/send (Admin Dashboard)

```javascript
app.post('/api/notifications/send', verifyAdminToken, async (req, res) => {
  try {
    const {
      title,
      body,
      type,           // 'like_update', 'comment_update', etc
      screen,
      entity_id,
      image_url,
      target_topics,  // Array: ['consumers', 'likes']
      target_countries,  // Optional: ['ng', 'gh', 'ke']
      scheduled_at,
      notification_id
    } = req.body;
    
    // Find all devices matching topic criteria
    const usersSnapshot = await admin.database().ref('users').get();
    const matchingTokens = [];
    
    usersSnapshot.forEach(userSnap => {
      userSnap.child('devices').forEach(deviceSnap => {
        const device = deviceSnap.val();
        
        // Check topic match (device must have at least one target topic)
        if (target_topics && !target_topics.some(t => device.topics?.includes(t))) {
          return;
        }
        
        // Check country match
        if (target_countries && !target_countries.includes(device.country_code)) {
          return;
        }
        
        if (device.fcm_token && device.is_active) {
          matchingTokens.push(device.fcm_token);
        }
      });
    });
    
    // Build FCM message
    const message = {
      notification: {
        title,
        body,
        imageUrl: image_url
      },
      data: {
        type,
        screen,
        entity_id: entity_id?.toString() || '',
        notification_id: notification_id?.toString() || '',
        image_url: image_url || ''
      },
      webpush: {
        notification: {
          title,
          body,
          icon: image_url
        }
      }
    };
    
    // Send via FCM (batch every 500 tokens)
    let successCount = 0;
    let failureCount = 0;
    
    for (let i = 0; i < matchingTokens.length; i += 500) {
      const batch = matchingTokens.slice(i, i + 500);
      const response = await admin.messaging().sendEachForMulticast({
        ...message,
        tokens: batch
      });
      
      successCount += response.successCount;
      failureCount += response.failureCount;
      
      // Log failures
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          console.log(`Failed to send to ${batch[idx]}: ${resp.error.code}`);
        }
      });
    }
    
    // Log notification in database
    const notifData = {
      title,
      body,
      type,
      target_topics,
      target_countries,
      recipients_sent: successCount,
      recipients_failed: failureCount,
      created_by: req.user.uid,
      created_at: admin.database.ServerValue.TIMESTAMP,
      scheduled_at: scheduled_at || null,
      status: 'sent'
    };
    
    const notifRef = await admin.database().ref('notifications').push(notifData);
    
    res.status(200).json({
      success: true,
      notification_id: notifRef.key,
      sent: successCount,
      failed: failureCount,
      message: `Notification sent to ${successCount} users`
    });
    
  } catch (error) {
    console.error('Error sending notification:', error);
    res.status(500).json({ error: 'Failed to send notification' });
  }
});
```

### 3. Handle Token Refresh

```javascript
app.post('/api/push/token-refresh', async (req, res) => {
  try {
    const { old_token, new_token, user_id } = req.body;
    
    // Remove old token
    await admin.database().ref(`users/${user_id}/devices/${old_token}`).remove();
    
    // New token will be registered via normal /api/push/register endpoint
    
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to refresh token' });
  }
});
```

---

## ✅ Admin Dashboard

### Location
`lib/features/notifications/admin/notification_admin_dashboard.dart`

### Features
- [x] Create notification form (title, body, type, screen, entity_id, image_url)
- [x] Target selection (topics checkboxes, countries multiselect)
- [x] Schedule option (date + time picker)
- [x] Preview notification
- [x] Send button
- [x] Analytics tab (delivery rate, open rate, engagement)
- [x] Health tab (token status, delivery errors)

### Topics Multiselect
```
☐ consumers
☐ likes
☐ comments
☐ trending
☐ recommendations
☐ artist
☐ collaborations
☐ dj
☐ live_battles
☐ followers
```

---

## ✅ Database Schema

### Firebase Realtime Database Structure

```
firebase_project/
  users/
    {user_id}/
      devices/
        {device_id or fcm_token}/
          fcm_token: "e1k2..."
          platform: "ios"
          device_id: "uuid-..."
          country_code: "ng"
          topics: ["consumers", "likes", "comments"]
          app_version: "1.2.3"
          device_model: "iPhone 14"
          locale: "en-NG"
          is_active: true
          last_updated: 1706464800000
          created_at: 1706464200000
      
  notifications/
    {notification_id}/
      title: "New Like!"
      body: "Someone liked your song"
      type: "like_update"
      screen: "song_detail"
      entity_id: "song_abc123"
      target_topics: ["likes"]
      target_countries: ["ng", "gh"]
      recipients_sent: 1250
      recipients_failed: 5
      created_by: "admin_uid"
      created_at: 1706464800000
      scheduled_at: null
      status: "sent"
```

---

## 🔄 Implementation Order

### Week 1: Backend Setup
1. [ ] Initialize Firebase Admin SDK
2. [ ] Build `/api/push/register` endpoint
3. [ ] Build `/api/notifications/send` endpoint
4. [ ] Test with Postman using real Firebase ID tokens
5. [ ] Deploy to production

### Week 2: Flutter Integration
1. [ ] Update login flow to call `registerTokenWithBackend()` after auth
2. [ ] Set up message handlers (foreground/background)
3. [ ] Implement navigation router for all notification types
4. [ ] Test with real Firebase tokens and test notifications
5. [ ] Deploy to TestFlight/Internal Testing

### Week 3: Admin Dashboard
1. [ ] Deploy admin dashboard (or use existing)
2. [ ] Train admin team on topic targeting
3. [ ] Create test campaigns
4. [ ] Monitor analytics and delivery rates
5. [ ] Production launch

### Week 4: Monitoring
1. [ ] Set up alerts for failed deliveries
2. [ ] Monitor token refresh rates
3. [ ] Track user engagement by notification type
4. [ ] Optimize send times and targeting

---

## 📊 Success Metrics

- **Token Registration Rate:** > 95% of users within 24 hours of install
- **Delivery Rate:** > 98% (measured in FCM)
- **Open Rate (Goal):** > 30% depending on notification type
- **Re-engagement:** Users who receive notifications have 2x+ higher retention

---

## 🚨 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Firebase token expired | Refresh token with `getIdToken(true)` |
| Tokens not registered | Not calling registerTokenWithBackend() | Add to login flow immediately |
| Users not receiving | Topics don't match | Check `_getUserTopics()` logic and admin targeting |
| High unregistration | Invalid tokens | Implement token refresh handler |
| App crashes on notification | Missing data keys | Validate all data keys match schema |

---

## 📝 Notes

- **Firebase Console:** All device tokens stored in Realtime Database at `users/{user_id}/devices/`
- **Topics are case-sensitive:** Use lowercase only
- **Country codes:** Use lowercase ISO 3166-1 alpha-2 (ng, gh, ke, etc)
- **Batching:** Send notifications in batches of 500 for performance
- **Token Refresh:** Re-register whenever FCM token changes (listen to `onTokenRefresh`)
- **Opt-Out:** Users can uninstall app or disable notifications in system settings

---

**Last Updated:** January 28, 2026  
**Status:** ✅ Ready for Production  
**Next:** Deploy backend API
