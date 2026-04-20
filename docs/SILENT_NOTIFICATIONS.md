# Silent Notifications & Badge Sync - Implementation Guide

## ✅ What's Implemented

### 1. Core Services

- **NotificationService** ([lib/services/notification_service.dart](lib/services/notification_service.dart))
  - FCM token management
  - Background & foreground message handling
  - Silent push notification processing
  - Badge counter updates
  - Navigation from notifications

- **UserService** ([lib/services/user_service.dart](lib/services/user_service.dart))
  - Coin balance management
  - Daily bonus tracking
  - Sync with Supabase

### 2. Dependencies Added

```yaml
firebase_messaging: ^15.1.5
flutter_app_badger: ^1.5.0
```

### 3. Platform Configuration

**iOS** ([ios/Runner/Info.plist](ios/Runner/Info.plist)):
- Background modes: audio, fetch, remote-notification
- Firebase App Delegate disabled (manual handling)

**Android** ([android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)):
- POST_NOTIFICATIONS permission
- RECEIVE_BOOT_COMPLETED permission

### 4. Database Schema

**New table**: `notifications` (see [tool/notifications_schema.sql](tool/notifications_schema.sql))
- Stores notification history
- RLS policies for security
- Unread count tracking

**Updated**: `users` table
- `fcm_token` - FCM device token
- `coins` - User coin balance
- `last_bonus_date` - Daily bonus tracking

---

## 🚀 How to Use

### Step 1: Install Dependencies

```bash
flutter pub get
cd ios && pod install && cd ..
```

### Step 2: Run Database Migration

1. Open Supabase Dashboard → SQL Editor
2. Run [tool/notifications_schema.sql](tool/notifications_schema.sql)

### Step 3: Build & Run

```bash
flutter run
```

On first launch:
- User will be prompted for notification permission (iOS)
- FCM token will be saved to Supabase
- Badge support will be initialized

---

## 📱 Silent Notification Types

### 1. Coin Update
```json
{
  "to": "<FCM_TOKEN>",
  "content_available": true,
  "priority": "high",
  "data": {
    "type": "coin_update",
    "amount": "50",
    "reason": "daily_bonus",
    "silent": "true"
  }
}
```

### 2. Like Update
```json
{
  "data": {
    "type": "like_update",
    "entity_id": "track_123",
    "count": "42",
    "silent": "true"
  }
}
```

### 3. Content Refresh
```json
{
  "data": {
    "type": "content_refresh",
    "section": "home",
    "silent": "true"
  }
}
```

### 4. Daily Bonus
```json
{
  "data": {
    "type": "daily_bonus",
    "amount": "50",
    "silent": "true"
  }
}
```

---

## 🔔 Regular Notifications

For notifications that SHOW a banner:

```json
{
  "to": "<FCM_TOKEN>",
  "notification": {
    "title": "New Like",
    "body": "Someone liked your track!"
  },
  "data": {
    "type": "new_like",
    "entity_id": "track_123"
  }
}
```

---

## 🎯 Navigation from Notifications

When user taps a notification, `NotificationService._handleNotificationTap()` routes based on `type`:

- `new_like`, `new_comment` → Track detail screen
- `daily_bonus` → Rewards screen
- `live_battle` → Live battle room
- Default → Notifications screen

Update the navigation helpers in [lib/services/notification_service.dart](lib/services/notification_service.dart#L257) to match your routing.

---

## 🔢 Badge Management

### Clear Badge
```dart
await NotificationService.instance.clearBadge();
```

### Get Unread Count
```dart
int count = NotificationService.instance.unreadCount;
```

Badge auto-updates on every silent push.

---

## 🧪 Testing

### Test FCM Token Retrieval
1. Run app
2. Check logs for: `📱 FCM Token: ...`
3. Verify token saved in Supabase `users.fcm_token`

### Test Silent Push
Use Firebase Console or curl:

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "FCM_TOKEN_HERE",
    "content_available": true,
    "priority": "high",
    "data": {
      "type": "coin_update",
      "amount": "100",
      "silent": "true"
    }
  }'
```

Check logs for: `🔕 Silent push: coin_update`

### Test Badge
```dart
await NotificationService.instance.handleSilentPush({
  'type': 'badge_update',
  'count': '5',
});
```

App icon should show badge with "5".

---

## 🏗️ Next Steps

### Option A: Notification Analytics
- Track delivery rate
- Track open rate
- Track click-through rate
- Dashboard with charts

### Option B: Admin Dashboard UX
- Send notification templates
- Schedule notifications
- Filter by country/role
- Preview before sending

Which would you like to implement next?

---

## 📖 Code Reference

### Initialize FCM
[lib/main.dart](lib/main.dart#L64) - Called on app startup

### Handle Silent Push
[lib/services/notification_service.dart](lib/services/notification_service.dart#L130)

### Claim Daily Bonus
```dart
final amount = await UserService.instance.claimDailyBonus();
print('Claimed $amount coins');
```

### Check if Bonus Available
```dart
if (UserService.instance.isDailyBonusAvailable) {
  // Show "Claim" button
}
```

---

## 🔥 Key Features

✅ Silent background updates  
✅ Badge sync  
✅ Foreground + background + terminated handling  
✅ FCM token refresh on rotation  
✅ Daily bonus system  
✅ Coin balance sync  
✅ Navigation from notifications  
✅ iOS & Android support  
✅ Supabase integration  

Ready for production! 🚀
