# Firebase FCM Topics Mapping for WEAFRICA MUSIC

## Topic-Based Segmentation Strategy

This document defines how WEAFRICA MUSIC uses FCM topics to segment push notifications to the right users based on their role, preferences, and engagement.

---

## 1. Core Topics (By User Role)

### Consumer
Topics: `consumers`, `likes`, `comments`, `trending`, `recommendations`

**What they receive:**
- ✅ New likes on their songs (`likes`)
- ✅ New comments on their songs (`comments`)
- ✅ Trending songs & charts (`trending`)
- ✅ Personalized recommendations (`recommendations`)
- ✅ System announcements (`consumers`)

### Artist
Topics: `artist`, `likes`, `comments`, `collaborations`

**What they receive:**
- ✅ All consumer topics (since artists can also be consumers)
- ✅ Collaboration invites (`collaborations`)
- ✅ Artist-specific metrics (`artist`)
- ✅ Engagement on their work (`likes`, `comments`)

### DJ
Topics: `dj`, `live_battles`, `followers`

**What they receive:**
- ✅ Live battle invitations (`live_battles`)
- ✅ Follower milestones (`followers`)
- ✅ DJ-exclusive events (`dj`)
- ✅ System announcements

---

## 2. Flutter Implementation

### In `lib/features/notifications/FCM_API_REFERENCE.dart`

```dart
Future<List<String>> _getUserTopics() async {
  final topics = <String>[];
  final userRole = await UserRoleStore.getRole();
  
  // All users get consumer base
  topics.add('consumers');
  
  // Add role-specific topics
  switch (userRole) {
    case UserRole.artist:
      topics.addAll(['artist', 'likes', 'comments', 'collaborations']);
      break;
    case UserRole.dj:
      topics.addAll(['dj', 'live_battles', 'followers']);
      break;
    case UserRole.consumer:
      topics.addAll(['likes', 'comments', 'trending', 'recommendations']);
      break;
  }
  
  return topics;
}
```

### Called During Token Registration

```dart
final idToken = await user.getIdToken(true);
final fcmToken = await FirebaseMessaging.instance.getToken();

await http.post(
  Uri.parse('https://YOUR_ADMIN_DOMAIN.com/api/push/register'),
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $idToken',
  },
  body: jsonEncode({
    'fcm_token': fcmToken,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'country_code': 'ng',
    'topics': await _getUserTopics(),  // ← Sent here
    'app_version': '1.2.3',
    'device_model': 'iPhone 14',
    'locale': 'en-NG',
  }),
);
```

---

## 3. Backend Topic Storage (Node.js Example)

When the Flutter app sends the topics array, the backend stores them:

```javascript
// POST /api/push/register

app.post('/api/push/register', async (req, res) => {
  const decodedToken = await admin.auth().verifyIdToken(req.headers.authorization.split('Bearer ')[1]);
  const userId = decodedToken.uid;
  
  const { fcm_token, platform, topics, country_code, device_model } = req.body;
  
  // Store device token WITH its topics
  await admin.database().ref(`users/${userId}/devices/${fcm_token}`).set({
    fcm_token,
    platform,
    topics,  // ← Array like ['consumers', 'likes', 'comments']
    country_code,
    device_model,
    is_active: true,
    last_updated: new Date().toISOString(),
  });
  
  res.json({ success: true, user_id: userId });
});
```

---

## 4. Admin Dashboard: Targeting by Topics

When an admin creates a notification in the dashboard, they specify which topics to send to:

```typescript
// POST /api/notifications/send

app.post('/api/notifications/send', async (req, res) => {
  const { 
    title, 
    body, 
    notification_type, 
    target_topics,  // ← e.g., ['likes', 'comments']
    scheduled_at 
  } = req.body;
  
  // Find all devices that have AT LEAST ONE of the target topics
  const usersSnapshot = await admin.database().ref('users').get();
  const matchingTokens = [];
  
  usersSnapshot.forEach(userSnap => {
    userSnap.child('devices').forEach(deviceSnap => {
      const device = deviceSnap.val();
      
      // Check if device's topics overlap with target_topics
      const hasMatchingTopic = device.topics?.some(t => target_topics.includes(t));
      
      if (hasMatchingTopic) {
        matchingTokens.push(device.fcm_token);
      }
    });
  });
  
  // Send FCM notification to all matching tokens
  const response = await admin.messaging().sendEachForMulticast({
    notification: { title, body },
    data: {
      type: notification_type,
      screen: target_screen,
      entity_id: entity_id,
    },
    tokens: matchingTokens,
  });
  
  console.log(`Sent to ${response.successCount} users`);
  res.json({ success: true, sent: response.successCount });
});
```

---

## 5. Admin Dashboard UI Flow

1. **Admin logs in** → Firebase Admin Auth
2. **Admin clicks "Create Notification"**
3. **Admin fills form:**
   - Title: "New Song Release"
   - Body: "Check out our latest track"
   - Type: `new_song`
   - **Target Topics:** `["consumers", "trending"]` ← Multi-select
   - Country: (optional)
   - Schedule: (optional)
4. **Admin clicks "Send"**
5. **Backend:**
   - Finds all users with `topics` array containing `consumers` OR `trending`
   - Sends FCM message to those tokens
   - Logs in `notifications` table with `target_topics: ["consumers", "trending"]`

---

## 6. Example Notifications by Topics

| Notification | Target Topics | Reaches |
|--------------|---------------|---------|
| "New comment on your song" | `['comments']` | Consumers, Artists, DJs who subscribe to comments |
| "You got a like!" | `['likes']` | Consumers, Artists |
| "Collaboration request" | `['collaborations']` | Artists only |
| "Live battle starts" | `['live_battles']` | DJs only |
| "Trending now" | `['trending']` | Consumers only |
| "New recommendation" | `['recommendations']` | Consumers only |
| "Follower milestone" | `['followers']` | DJs only |
| "System announcement" | `['consumers']` | Everyone |

---

## 7. Topic Change / Re-registration

If a user **changes their role** (e.g., upgrades to artist):

1. Update `UserRoleStore.setRole(UserRole.artist)`
2. Call `registerTokenWithBackend(fcmToken)` again
3. New topics array is sent: `['consumers', 'artist', 'likes', 'comments', 'collaborations']`
4. Backend updates stored topics for that device
5. User now receives artist-specific notifications

---

## 8. Opt-In Topics (Marketing)

For optional notifications (marketing, newsletters), add preference-based topics:

```dart
Future<List<String>> _getUserTopics() async {
  final topics = <String>[];
  final userRole = await UserRoleStore.getRole();
  
  // ... role-specific logic ...
  
  // Add opt-in topics if user enabled them
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('opt_in_marketing') ?? false) {
    topics.add('marketing');
  }
  if (prefs.getBool('opt_in_newsletter') ?? false) {
    topics.add('newsletter');
  }
  
  return topics;
}
```

Then in settings/preferences UI, toggling these saves to SharedPreferences and triggers re-registration.

---

## Summary

✅ **Flutter sends topics based on user role**
✅ **Backend stores topics with device token**
✅ **Admin sends to specific topics, not individual users**
✅ **Scalable: Add new topics without app updates**
✅ **Flexible: Users can opt-in/opt-out of optional topics**

**Total topics: 9** → `consumers`, `artist`, `likes`, `comments`, `collaborations`, `dj`, `live_battles`, `followers`, `trending`, `recommendations` (+ optional: `marketing`, `newsletter`)
