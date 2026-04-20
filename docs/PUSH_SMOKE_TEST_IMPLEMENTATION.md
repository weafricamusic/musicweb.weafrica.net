
# 🔔 PUSH NOTIFICATION SMOKE TEST - IMPLEMENTATION CHECKLIST

## 📋 Pre-Test Checklist

Before running the smoke test, verify these are in place:

### Backend Setup
- [ ] Firebase Cloud Functions deployed
- [ ] Cloud Function logs accessible
- [ ] Supabase `notification_device_tokens` table exists
- [ ] Environment variables set:
  - [ ] `SUPABASE_URL`
  - [ ] `SUPABASE_SERVICE_ROLE`
  - [ ] `FIREBASE_PROJECT_ID`
- [ ] CORS configured if needed
- [ ] Rate-limiting database/cache set up (Redis or Supabase)

### Flutter App Setup
- [ ] Firebase initialized in `main.dart`
- [ ] Firebase Messaging initialized
- [ ] FCM permissions requested (iOS)
- [ ] Push notification service running
- [ ] Test account created and logged in

### Supabase Setup
- [ ] Table `notification_device_tokens` exists with columns:
  - [ ] `id` (UUID, primary key)
  - [ ] `user_id` (TEXT, foreign key to auth.users)
  - [ ] `fcm_token` (TEXT, unique)
  - [ ] `platform` (TEXT: 'ios' or 'android')
  - [ ] `device_model` (TEXT, nullable)
  - [ ] `country_code` (TEXT, nullable)
  - [ ] `is_active` (BOOLEAN, default true)
  - [ ] `topics` (JSONB array, default ['all'])
  - [ ] `created_at` (TIMESTAMP, default now())
  - [ ] `last_updated` (TIMESTAMP, default now())
  - [ ] `app_version` (TEXT, nullable)
  - [ ] `locale` (TEXT, nullable)

```sql
CREATE TABLE notification_device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES auth.users(id),
  fcm_token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL,
  device_model TEXT,
  country_code TEXT,
  is_active BOOLEAN DEFAULT true,
  topics JSONB DEFAULT '["all"]'::jsonb,
  created_at TIMESTAMP DEFAULT now(),
  last_updated TIMESTAMP DEFAULT now(),
  app_version TEXT,
  locale TEXT
);

CREATE INDEX idx_user_tokens ON notification_device_tokens(user_id);
CREATE INDEX idx_active_tokens ON notification_device_tokens(is_active);
```

---

## 🚀 STEP-BY-STEP TEST EXECUTION

### ✅ STEP 1: Run Full Smoke Test (Steps 1-3)

**Location:** Debug screen or Test Runner UI

**Code:**
```dart
import 'package:weafrica_music/features/notifications/services/push_smoke_test_helper.dart';

final helper = PushSmokeTestHelper();
final success = await helper.runFullTest(countryCode: 'gh');

if (success) {
  print('✅ Smoke test passed!');
} else {
  print('❌ Smoke test failed - check logs');
}
```

**Expected Output:**
```
============================================================
🔔 PUSH NOTIFICATION SMOKE TEST - STARTING
============================================================

📱 STEP 1: Collecting tokens...
✅ User: user@gmail.com
✅ Firebase ID Token: eyJhbGci...
✅ FCM Token: d-7v-EYAAe...
✅ iOS Device: iPhone 15 (17.3)

📱 STEP 2: Registering device token with backend...
📤 Sending request to: https://YOUR_BACKEND_DOMAIN/api/push/register
✅ Device token registered successfully!

🔍 STEP 3: Verifying token in Supabase...
✅ Token found in Supabase!
   User ID: firebase-uid-12345
   Platform: ios
   Country: gh
   Topics: ["all", "consumers"]

============================================================
✅ SMOKE TEST PASSED - All systems operational!
============================================================
```

**Troubleshooting:**
- If Step 2 fails: Check backend URL and Firebase auth
- If Step 3 fails: Verify Supabase table exists and is accessible
- Check Cloud Function logs for any errors

---

### ✅ STEP 2: Manually Verify in Supabase

**Location:** Supabase Dashboard → SQL Editor

**Query:**
```sql
SELECT 
    id, user_id, fcm_token, platform, country_code, 
    is_active, topics, last_updated
FROM notification_device_tokens
WHERE user_id = 'YOUR_FIREBASE_UID'
ORDER BY last_updated DESC
LIMIT 1;
```

**Expected Result:**
| Column | Value |
|--------|-------|
| user_id | `firebase-uid-12345` |
| platform | `ios` or `android` |
| is_active | `true` |
| topics | `["all", "consumers"]` |
| country_code | `gh` |
| last_updated | Recent timestamp |

---

### ✅ STEP 3: Manual Admin Dashboard Test

**Location:** Admin Console → Notifications → Push

**Configuration:**
```
Delivery Type: Device tokens
Topic: system
Country: gh
Title: "Test Notification"
Body: "This is a smoke test"
```

**Click:** "Send Now"

**Expected:**
- Status shows: "Sent to 1 device"
- Response time: < 5 seconds

---

### ✅ STEP 4: Verify Device Reception

**Device Requirements:**
- App is running (or backgrounded)
- Notifications enabled in OS settings
- FCM initialized

**Foreground (App Open):**
```
Console Output:
🔔 Foreground message: msg-12345
📢 Show banner: Test Notification
```

**Background (App Closed):**
```
Native notification appears:
┌──────────────────────┐
│ Test Notification    │
│ This is a smoke test  │
└──────────────────────┘
```

**Tap Notification:**
- App opens
- Navigates to correct screen based on data

---

### ✅ STEP 5: Run Rate-Limiting Test

**Location:** Debug screen or Test Runner UI

**Code:**
```dart
import 'package:weafrica_music/features/notifications/services/push_rate_limit_test.dart';

final test = PushRateLimitTest();
final success = await test.runRateLimitTest(
  tokenTopic: 'trending',
  maxPerUserPerDay: 1,
);
```

**Expected Output:**
```
============================================================
🧪 RATE-LIMITING TEST - STARTING
============================================================

📤 ATTEMPT 1: Send notification
✅ ATTEMPT 1: Success - 200 OK

📤 ATTEMPT 2: Send same notification again
✅ ATTEMPT 2: Correctly rate-limited - 429

============================================================
✅ RATE-LIMITING TEST PASSED!
============================================================
```

---

### ✅ STEP 6: Run Burst Protection Test (Optional)

**Code:**
```dart
final test = PushRateLimitTest();
await test.testBurstProtection();
```

**Expected:**
- Some requests succeed (200)
- Some requests rate-limited (429)
- System prevents notification spam

---

## 📊 Test Results Template

Save this after each successful test run:

```
# PUSH NOTIFICATION SMOKE TEST RESULTS

**Date:** 2025-01-28
**Tester:** [Your Name]
**Device:** iPhone 15 / Pixel 8
**App Version:** 1.0.0
**Backend URL:** https://backend.example.com

## Test Execution

### Step 1: Token Collection
- [ ] Firebase Auth: Logged in
- [ ] Firebase ID Token: ✅ Collected
- [ ] FCM Token: ✅ Collected
- [ ] Device Info: ✅ Collected
- **Result:** ✅ PASS

### Step 2: Backend Registration
- [ ] HTTP Status: 200 OK
- [ ] Response Time: ___ ms
- [ ] Error Response: None
- **Result:** ✅ PASS

### Step 3: Supabase Verification
- [ ] Token Found: Yes
- [ ] is_active: true
- [ ] Topics: ["all", "consumers"]
- [ ] Country: gh
- **Result:** ✅ PASS

### Step 4: Admin Notification Send
- [ ] Status: Sent
- [ ] Recipients: 1
- [ ] Response Time: ___ ms
- **Result:** ✅ PASS

### Step 5: Device Reception
- [ ] Notification Received: Yes
- [ ] onMessage Fired: Yes
- [ ] Tapped Opens App: Yes
- [ ] Correct Screen: Yes
- **Result:** ✅ PASS

### Step 6: Rate-Limiting
- [ ] First Attempt: 200 OK
- [ ] Second Attempt: 429 Limited
- [ ] Burst Protection: Works
- **Result:** ✅ PASS

## Overall Result: ✅ ALL TESTS PASSED

System is **production-ready** for push notifications!

**Notes:**
- 
- 
- 

**Next Steps:**
- Deploy to production
- Monitor for errors
- Set up alerts
```

---

## 🚨 Common Issues & Fixes

### "No user logged in"
```
Fix: Ensure user is authenticated before running tests
- Login with email/password or Google
- Check FirebaseAuth.instance.currentUser is not null
```

### "Failed to register device token" (Backend Error)
```
Fix: Check backend logs and configuration
1. Verify Cloud Function is deployed: firebase deploy --only functions
2. Check logs: firebase functions:log
3. Verify environment variables in Cloud Function settings
4. Test endpoint manually: curl -X POST https://YOUR_DOMAIN/api/push/register ...
```

### "Token not found in Supabase"
```
Fix: 
1. Verify registration request returned 200 OK
2. Check Supabase table exists: 
   SELECT * FROM notification_device_tokens LIMIT 1;
3. Check user_id matches Firebase UID:
   SELECT * FROM auth.users WHERE email = 'your@email.com';
4. Verify RLS policies don't block access
```

### "Notification not received"
```
Fix:
1. Check device notifications are enabled (OS settings)
2. Verify token is_active = true in database
3. Check Firebase Console FCM status
4. Test with a new device/account
5. Check FCM Service Health: https://status.firebase.google.com/
```

### "429 Rate Limit - but should be 200"
```
Fix:
1. Check max_per_user_per_day is > 1
2. Try with a different user account
3. Wait 24 hours and try again
4. Check rate-limiting logic in backend
```

---

## 📚 Created Files

| File | Purpose | Location |
|------|---------|----------|
| `push_smoke_test_helper.dart` | Steps 1-3 automation | `lib/features/notifications/services/` |
| `push_rate_limit_test.dart` | Step 6 rate-limiting tests | `lib/features/notifications/services/` |
| `push_smoke_test_screen.dart` | UI test runner | `lib/features/notifications/screens/` |
| `deviceTokens.ts` | Backend registration endpoint | `functions/src/` |
| `PUSH_SMOKE_TEST_QUERIES.sql` | Supabase verification queries | `docs/` |
| `PUSH_SMOKE_TEST_GUIDE.md` | Detailed guide | `docs/` |
| `PUSH_SMOKE_TEST_QUICK_REFERENCE.html` | Printable cheat sheet | `docs/` |
| `PUSH_SMOKE_TEST_IMPLEMENTATION.md` | This file | `docs/` |

---

## 🎯 Success Criteria

Your push notification system is **production-ready** when:

✅ All 6 steps complete without errors
✅ Token appears in Supabase database  
✅ Device receives notifications in foreground
✅ Device receives notifications in background
✅ Tapping notification opens correct screen
✅ Rate-limiting prevents duplicate notifications
✅ No console errors or warnings
✅ Response times are < 5 seconds
✅ Rate-limiting works as configured

---

## 📞 Support & Next Steps

1. **Run the full smoke test** using `PushSmokeTestHelper`
2. **Monitor logs** in Firebase Console
3. **Document results** using the template above
4. **Deploy to production** after all tests pass
5. **Set up monitoring** for notification delivery and errors

## Configuration Constants

Update these in the Dart helper files:

```dart
// push_smoke_test_helper.dart
static const String _backendBaseUrl = 'https://YOUR_BACKEND_DOMAIN';

// Firebase Project ID
static const String firebaseProjectId = 'your-firebase-project';

// Test country code
static const String testCountryCode = 'gh';

// Test topics
static const List<String> testTopics = ['all', 'consumers'];
```

---

**Last Updated:** January 28, 2025  
**Version:** 1.0  
**Status:** Ready for testing
