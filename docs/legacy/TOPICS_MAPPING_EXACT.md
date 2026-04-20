# 📋 TOPICS MAPPING: Exact Logic for Your App

## Overview

The `topics` array sent to `/api/push/register` determines which notifications your backend sends to each device. Topics are built from two sources:

1. **Role-Based Topics** - Automatically included based on user role
2. **Opt-In Topics** - Only included if user enabled them in settings

---

## Role-Based Topics (Automatic)

### Consumer Role
```dart
topics: ['consumers']
```
- Receives role-scoped broadcasts intended for consumers
- Likes/comments are direct notifications (not topics)

### Artist Role
```dart
topics: ['artists']
```
- Receives role-scoped broadcasts intended for artists
- Likes/comments are direct notifications (not topics)

### DJ Role
```dart
topics: ['djs']
```
- Receives role-scoped broadcasts intended for DJs
- Likes/comments are direct notifications (not topics)

### Admin Role
```dart
topics: ['admins']
```
- Receives admin-scoped broadcasts for monitoring and support

---

## Opt-In Topics (User Preference)

These are **only added** if `SharedPreferences` has `opt_in_{feature} = true`:

### Marketing Topics
```dart
if (prefs.getBool('opt_in_marketing') ?? false) {
  topics.add('marketing');
}
```
- Promotional campaigns
- New feature announcements
- Platform updates

### Trending Topics
```dart
if (prefs.getBool('opt_in_trending') ?? false) {
  topics.add('trending');
}
```
- Trending music alerts
- Popular content recommendations
- Viral moments

### System Topics
```dart
if (prefs.getBool('opt_in_system') ?? true) {
  topics.add('system');
}
```
- Platform maintenance announcements
- Critical system updates
- Default: `true` (enabled by default)

### Collaboration Topics
```dart
if (prefs.getBool('opt_in_collaborations') ?? false) {
  topics.add('collaborations');
}
```
- Collaboration invitations
- Project notifications
- Team requests

---

## Examples: Real-World Topic Arrays

### Consumer in Nigeria who wants marketing:
```json
{
  "topics": ["consumers", "marketing"]
}
```

### Artist in Ghana who opted into trending:
```json
{
  "topics": ["artists", "live_battles", "trending"]
}
```

### DJ in Kenya with all opt-ins:
```json
{
  "topics": ["djs", "live_battles", "trending", "marketing", "system", "collaborations"]
}
```

### Admin monitoring all activity:
```json
{
  "topics": ["admins", "system", "marketing"]
}
```

---

## How Backend Uses Topics

When you send a notification from the admin dashboard:

```sql
-- Find all users matching targeting criteria
SELECT DISTINCT token
FROM notification_device_tokens
WHERE 
  country_code = 'ng'  -- Target Nigeria
  AND topics @> '["marketing"]'::jsonb  -- Has "marketing" topic
  AND is_active = true
ORDER BY last_updated DESC;
```

Or in Node.js with Firebase Realtime Database:

```javascript
const usersRef = admin.database().ref('users');
usersRef.once('value', (snap) => {
  const matchingTokens = [];
  
  snap.forEach((userSnap) => {
    userSnap.child('devices').forEach((deviceSnap) => {
      const device = deviceSnap.val();
      
      // Check if device matches targeting criteria
      if (targetCountries?.includes(device.country_code)) {
        if (targetTopics?.some(t => device.topics?.includes(t))) {
          matchingTokens.push(device.token);
        }
      }
    });
  });
  
  // Send to all matching tokens
  admin.messaging().sendEachForMulticast({
    notification: { title, body },
    data: { type, screen, entity_id },
    tokens: matchingTokens
  });
});
```

---

## SharedPreferences Keys

Store these in your settings/profile management:

```dart
// User role (set at signup/profile completion)
await prefs.setString('user_role', 'consumer'); // or 'artist', 'dj', 'admin'

// User country (set at signup/profile completion)
await prefs.setString('user_country', 'ng'); // Always lowercase

// Notification opt-ins (set in settings screen)
await prefs.setBool('opt_in_marketing', false);
await prefs.setBool('opt_in_trending', false);
await prefs.setBool('opt_in_system', true); // Default: enabled
await prefs.setBool('opt_in_collaborations', false);
```

---

## What to Show in Settings Screen

Add a "Notifications" section in your settings:

```
⚙️ Notification Settings

Role: Artist (read-only)
Country: Nigeria (read-only)

📬 Opt-In Notifications:
  ☐ Marketing & Promotions
  ☐ Trending Music Alerts
  ☑ System Announcements (always on)
  ☐ Collaboration Invitations

💾 Last registered: 2026-01-28 14:32:15
🔄 Re-register device
```

When user changes opt-in settings, immediately call:
```dart
await registerDeviceToken(); // Re-registers with new topics
```

---

## Integration Checklist

- [ ] User role stored in SharedPreferences at signup
- [ ] User country stored in SharedPreferences at signup
- [ ] Opt-in preferences stored in SharedPreferences
- [ ] Settings screen allows users to toggle opt-ins
- [ ] `registerDeviceToken()` called after login
- [ ] `setupTokenRefreshListener()` called in main app
- [ ] Topics are re-registered whenever opt-in preferences change
- [ ] Backend `/api/push/register` stores topics array in database
- [ ] Backend filtering uses topics when sending notifications

---

## Testing: Verify Topics Are Sent Correctly

```bash
# 1. Get Firebase ID token (from browser DevTools after login)
TOKEN="your_firebase_id_token_here"

# 2. Register with specific topics
curl -X POST https://your-backend.com/api/push/register \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "token": "test-fcm-token-123",
    "platform": "ios",
    "country_code": "ng",
    "topics": ["consumers", "marketing"],
    "app_version": "1.2.3",
    "device_model": "iPhone 14",
    "locale": "en-NG"
  }'

# 3. Verify in database
SELECT user_uid, topics, country_code FROM notification_device_tokens 
WHERE token = 'test-fcm-token-123';

# Should see: topics=['consumers', 'marketing']
```

