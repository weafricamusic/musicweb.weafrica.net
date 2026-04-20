# 🔔 Push Notification Smoke Test - Complete Guide

## 📋 Quick Reference

### Architecture Flow
```
┌─────────────────┐
│  Consumer App   │ (Flutter)
│ - Firebase Auth │
│ - FCM Messaging │
└────────┬────────┘
         │ STEP 1: Collect tokens
         │ - Firebase ID Token
         │ - FCM Device Token
         │ - Device Info
         │
         ▼
┌──────────────────────┐
│  Backend API         │ (Firebase Functions)
│ POST /api/push/      │
│      register        │
└──────────┬───────────┘
           │ STEP 2: Register token
           │ Save to Supabase
           │
           ▼
┌──────────────────────┐
│   Supabase DB        │ (PostgreSQL)
│ notification_device_ │
│     tokens table     │
└──────────┬───────────┘
           │ STEP 3: Verify
           │ Query the database
           │
           ▼
    ✅ Token Stored


    🔄 Later: Admin sends notification
    
┌─────────────────┐
│  Admin Panel    │
│ - Select topic  │
│ - Select target │
│ - Send to FCM   │
└────────┬────────┘
         │
         ▼
┌──────────────────────┐
│   Firebase Cloud     │
│   Messaging (FCM)    │
│ - Route to devices   │
│ - Handle retries     │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Consumer App        │
│ - Receive in-app     │
│ - Show notification  │
│ - Handle tap routing │
└──────────────────────┘
    ✅ Notification Delivered
```

---

## 🚀 STEP 1: Consumer App - Login & Get Tokens

### What happens:
1. User logs in with Firebase
2. App collects:
   - Firebase ID Token (for auth)
   - FCM Device Token (unique to this device)
   - Device Info (model, OS, country)

### Code (Flutter):
```dart
import 'package:weafrica_music/features/notifications/services/push_smoke_test_helper.dart';

// In your debug screen or settings:
final helper = PushSmokeTestHelper();
final tokens = await helper.collectTokens();

// Output:
// ✅ User: user@example.com
// ✅ Firebase ID Token: eyJhbGciOiJSUzI1NiIs...
// ✅ FCM Token: d-7v-EYAAe0:APA91bHK3j_Ux...
// ✅ iOS Device: iPhone 15 (17.3)
```

### Expected Output:
```
✅ User: your-email@gmail.com
✅ Firebase ID Token: eyJhbGciOiJSUzI1NiIs...
✅ FCM Token: d-7v-EYAAe0:APA91bHK3j_Ux...
✅ iOS Device: iPhone 15 (17.3)
```

---

## 📱 STEP 2: Register Device Token with Backend

### What happens:
1. App sends FCM token to backend
2. Backend verifies Firebase auth
3. Backend saves token to Supabase
4. Backend returns confirmation

### Request:
```
POST https://YOUR_BACKEND_DOMAIN/api/push/register

Headers:
  Authorization: Bearer <Firebase ID Token>
  Content-Type: application/json

Body:
{
  "token": "d-7v-EYAAe0:APA91bHK3j_Ux...",
  "platform": "ios",
  "device_model": "iPhone 15",
  "country_code": "gh",
  "topics": ["all", "consumers"]
}
```

### Code (Flutter):
```dart
final helper = PushSmokeTestHelper();
final tokens = await helper.collectTokens();

final result = await helper.registerDeviceToken(
  idToken: tokens['id_token'],
  fcmToken: tokens['fcm_token'],
  platform: tokens['platform'],
  deviceModel: tokens['device_model'],
  countryCode: 'gh',
);

print(result); // { "success": true, "data": {...} }
```

### Expected Response (200 OK):
```json
{
  "success": true,
  "message": "Device token registered",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "user_id": "firebase-uid-12345",
    "fcm_token": "d-7v-EYAAe0:APA91bHK3j_Ux...",
    "platform": "ios",
    "country_code": "gh",
    "is_active": true,
    "topics": ["all", "consumers"],
    "created_at": "2025-01-28T10:30:00Z",
    "last_updated": "2025-01-28T10:30:00Z"
  }
}
```

---

## 🔍 STEP 3: Verify Token in Supabase

### What happens:
1. Open Supabase SQL Editor
2. Run verification query
3. Confirm token appears in database

### Query:
```sql
SELECT 
    id,
    user_id,
    fcm_token,
    platform,
    country_code,
    is_active,
    topics,
    last_updated
FROM notification_device_tokens
WHERE user_id = 'YOUR_FIREBASE_UID'
ORDER BY last_updated DESC
LIMIT 5;
```

### Expected Result:
| id | user_id | fcm_token | platform | country_code | is_active | topics | last_updated |
|----|---------|-----------|----------|--------------|-----------|--------|--------------|
| 550e8400... | firebase-uid-12345 | d-7v-EYAAe0:APA91... | ios | gh | true | `["all", "consumers"]` | 2025-01-28 10:30:00 |

### Verification Checklist:
- ✅ One row returned with your FCM token
- ✅ `is_active` = true
- ✅ `country_code` = gh (or your test country)
- ✅ `topics` includes "all" and "consumers"
- ✅ `last_updated` is recent (within last few minutes)

---

## 📤 STEP 4: Admin Dashboard - Send Test Push

### What happens:
1. Admin (or you) logs into Admin Dashboard
2. Navigate to Notifications > Push
3. Configure the notification:
   - **Delivery:** Device tokens
   - **Topic:** system (or consumers)
   - **Country:** gh (match your device)
   - **Title:** "Test Notification"
   - **Body:** "This is a smoke test"
4. Click "Send Now"

### Admin Dashboard UI (example):
```
┌─────────────────────────────────────┐
│ Notifications > Push                 │
├─────────────────────────────────────┤
│ Delivery: [Device tokens ▼]          │
│ Topic:    [system ▼]                 │
│ Country:  [gh ▼]                     │
│                                     │
│ Title:    [Test Notification       ] │
│ Body:     [This is a smoke test    ] │
│                                     │
│           [SEND NOW] [SCHEDULE]     │
├─────────────────────────────────────┤
│ Status: ⏳ Sending...               │
│ Sent: 1/1 devices                   │
│ Last updated: 2 seconds ago          │
└─────────────────────────────────────┘
```

---

## 📲 STEP 5: Confirm Push on Device

### Foreground (App is Open)
```
Console Output:
🔔 Foreground message: msg-12345
📢 Show banner: Test Notification
This is a smoke test
```

### Background (App is Closed)
```
iOS Notification Center:
┌──────────────────────────┐
│ Test Notification        │
│ This is a smoke test      │
└──────────────────────────┘
```

### Tap Notification
```
Expected: App opens to the appropriate screen
based on the notification data.type
```

### Check Payload (Console):
```
Data received:
  type: test
  entity_id: test-entity-001
  notification_id: test-1234567890
  timestamp: 2025-01-28T10:35:00Z
```

---

## 🧪 STEP 6: Test Rate-Limiting

### Code (Flutter):
```dart
import 'package:weafrica_music/features/notifications/services/push_rate_limit_test.dart';

final rateLimitTest = PushRateLimitTest();
await rateLimitTest.runRateLimitTest(
  tokenTopic: 'trending',
  maxPerUserPerDay: 1,
);
```

### What it does:
1. **Attempt 1:** Send notification → Expected: ✅ 200 OK
2. **Attempt 2:** Send same notification → Expected: ⏱️ 429 Too Many Requests

### Console Output:
```
============================================================
🧪 RATE-LIMITING TEST - STARTING
============================================================

📤 ATTEMPT 1: Send notification to topic: trending
   Expected: 200 OK (notification sent)
✅ ATTEMPT 1: Success - 200 OK
   Response: {"success": true, "message": "Notification sent"}

📤 ATTEMPT 2: Send same notification again
   Expected: 429 Too Many Requests (rate limit exceeded)
✅ ATTEMPT 2: Correctly rate-limited - 429
   Response: {"error": "Rate limit exceeded for user today"}

============================================================
✅ RATE-LIMITING TEST PASSED!
============================================================
System correctly prevents duplicate notifications
within max_per_user_per_day limit.
```

---

## 📊 Complete Test Summary Template

```markdown
# PUSH NOTIFICATION SMOKE TEST RESULTS

Date: 2025-01-28
Tester: [Your Name]
Device: [iPhone 15 / Pixel 8 Pro]
Platform: [iOS / Android]
Country: gh

## STEP 1: Token Collection ✅
- Firebase Auth: Logged in as user@gmail.com
- Firebase ID Token: Collected ✅
- FCM Token: d-7v-EYAAe0:APA91bHK3j_Ux... ✅
- Device Info: iPhone 15 (iOS 17.3) ✅

## STEP 2: Backend Registration ✅
- HTTP Status: 200 OK ✅
- Token Saved: Yes ✅
- Response Time: 245ms ✅

## STEP 3: Supabase Verification ✅
- Token Found: Yes ✅
- is_active: true ✅
- Topics: ["all", "consumers"] ✅
- Country: gh ✅

## STEP 4: Admin Notification Send ✅
- Sent via: Admin Dashboard ✅
- Topic: system ✅
- Recipients: 1 ✅

## STEP 5: Device Reception ✅
- Foreground: Notification received ✅
- onMessage fired: Yes ✅
- onMessageOpenedApp: Works ✅
- Routing: Correct screen opened ✅

## STEP 6: Rate-Limiting ✅
- First attempt: 200 OK ✅
- Second attempt: 429 Rate Limited ✅
- Burst protection: Works ✅

## Overall Status: ✅ PASSED
System is fully functional and production-ready!
```

---

## 🛠️ Troubleshooting

### Problem: "No user logged in"
**Solution:** Make sure you're logged in with Firebase Auth before running tests.

### Problem: "Failed to register device token"
**Solution:** 
1. Check Firebase ID Token is valid
2. Verify backend URL is correct
3. Check Firebase Auth rules allow the endpoint

### Problem: "Token not found in Supabase"
**Solution:**
1. Verify registration request returned 200 OK
2. Check Supabase table exists
3. Check user_id matches Firebase UID

### Problem: "Notification not received"
**Solution:**
1. Verify token is active in Supabase
2. Check device has notifications enabled
3. Verify FCM token in database matches device

### Problem: "Rate-limiting not working"
**Solution:**
1. Check backend rate-limiting logic
2. Verify max_per_user_per_day is < 2
3. Try with a new user account

---

## 📚 Files Created for This Test

| File | Purpose |
|------|---------|
| `lib/features/notifications/services/push_smoke_test_helper.dart` | STEP 1-3 automation |
| `lib/features/notifications/services/push_rate_limit_test.dart` | STEP 6 rate-limiting test |
| `functions/src/deviceTokens.ts` | STEP 2 backend endpoint |
| `docs/PUSH_SMOKE_TEST_QUERIES.sql` | STEP 3 verification queries |
| `docs/PUSH_SMOKE_TEST_GUIDE.md` | This guide |

---

## 🎯 Next Steps

1. **Update Backend URL:** Change `YOUR_BACKEND_DOMAIN` in the Dart files
2. **Deploy Cloud Functions:** `firebase deploy --only functions`
3. **Run Tests:** Use `PushSmokeTestHelper().runFullTest()`
4. **Document Results:** Fill out the test summary template
5. **Go Live:** After all tests pass, your push notification system is ready!

---

## 📞 Support

If tests fail, check:
1. Backend logs for registration errors
2. Supabase database for token records
3. Firebase Console for authentication issues
4. FCM diagnostics for delivery problems
