# 🔔 PUSH NOTIFICATION SMOKE TEST - COMPLETE INDEX

## 📌 Start Here

**Welcome!** This directory contains everything you need to test and validate your push notification system end-to-end.

### 🎯 What's This For?

The smoke test validates that your WEAFRICA MUSIC push notification system works correctly:
- ✅ Device tokens register properly
- ✅ Backend stores tokens correctly
- ✅ Notifications deliver to devices
- ✅ Rate-limiting prevents spam
- ✅ Everything works before production

---

## 📚 Documentation Files

### 1. **[PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md](PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md)** ⭐ START HERE
   - Overview of all created files
   - Quick start (5 minutes)
   - Integration instructions
   - Next steps checklist
   
   **Best for:** Getting the big picture

### 2. **[PUSH_SMOKE_TEST_QUICK_REFERENCE.html](PUSH_SMOKE_TEST_QUICK_REFERENCE.html)** 📄 PRINT THIS
   - Visual step-by-step cards
   - Success criteria checklist
   - Architecture timeline
   - Print-friendly design
   
   **Best for:** Team reference or printing

### 3. **[PUSH_SMOKE_TEST_GUIDE.md](PUSH_SMOKE_TEST_GUIDE.md)** 📖 DETAILED GUIDE
   - Complete architecture flow diagram
   - All 6 steps explained in detail
   - Code examples for each step
   - Expected outputs and responses
   - Troubleshooting guide
   
   **Best for:** Understanding how everything works

### 4. **[PUSH_SMOKE_TEST_IMPLEMENTATION.md](PUSH_SMOKE_TEST_IMPLEMENTATION.md)** ✅ IMPLEMENTATION
   - Pre-test requirements checklist
   - Supabase table schema (SQL)
   - Step-by-step execution guide
   - Test results template
   - Common issues and solutions
   
   **Best for:** Actually running the test

### 5. **[PUSH_SMOKE_TEST_QUERIES.sql](PUSH_SMOKE_TEST_QUERIES.sql)** 🔍 VERIFICATION
   - 10 ready-to-use SQL queries
   - Analytics queries
   - Maintenance queries
   - Copy-paste into Supabase SQL Editor
   
   **Best for:** Verifying token registration in database

---

## 💻 Code Files

### Dart Services

#### **`lib/features/notifications/services/push_smoke_test_helper.dart`**
- Collects Firebase & FCM tokens
- Registers token with backend
- Verifies in Supabase
- Auto-runs Steps 1-3

```dart
final helper = PushSmokeTestHelper();
await helper.runFullTest();
```

#### **`lib/features/notifications/services/push_rate_limit_test.dart`**
- Tests rate-limiting (Step 6)
- Tests burst protection
- Tests quota reset
- Checks rate-limit status

```dart
final test = PushRateLimitTest();
await test.runRateLimitTest();
```

#### **`lib/features/notifications/screens/push_smoke_test_screen.dart`**
- Beautiful Flutter UI test runner
- Real-time log viewer
- Test status dashboard
- Add to debug menu

### Backend Code

#### **`functions/src/deviceTokens.ts`**
- HTTP endpoints for token registration
- Backend verification
- FCM topic subscription
- Deploy to Firebase Functions

```bash
firebase deploy --only functions:registerDeviceToken
```

---

## 🚀 Quick Start

### 1. Update Configuration
```dart
// In push_smoke_test_helper.dart
static const String _backendBaseUrl = 'https://YOUR_BACKEND_DOMAIN';
```

### 2. Create Database Table
Copy SQL from [PUSH_SMOKE_TEST_IMPLEMENTATION.md](PUSH_SMOKE_TEST_IMPLEMENTATION.md) and run in Supabase SQL Editor.

### 3. Deploy Cloud Functions
```bash
cd functions
npm install
firebase deploy --only functions
```

### 4. Run Smoke Test
```dart
// In your app
final helper = PushSmokeTestHelper();
await helper.runFullTest();
```

### 5. Verify Results
```sql
-- In Supabase SQL Editor
SELECT * FROM notification_device_tokens
WHERE user_id = 'YOUR_FIREBASE_UID'
ORDER BY last_updated DESC LIMIT 1;
```

---

## 📊 The 6 Steps

| Step | What | Expected | File |
|------|------|----------|------|
| 1 | Collect tokens from device | Firebase ID Token + FCM Token | `push_smoke_test_helper.dart` |
| 2 | Register with backend | 200 OK response | `deviceTokens.ts` |
| 3 | Verify in Supabase | Token found in database | `push_smoke_test_helper.dart` |
| 4 | Admin sends notification | Sent to 1 device | Admin Dashboard |
| 5 | Device receives notification | Native alert + app opens | Device |
| 6 | Test rate-limiting | 429 on second attempt | `push_rate_limit_test.dart` |

---

## ✅ Success Checklist

After running the smoke test:

- [ ] Step 1: Tokens collected ✅
- [ ] Step 2: Token registered ✅
- [ ] Step 3: Token found in Supabase ✅
- [ ] Step 4: Notification sent from admin ✅
- [ ] Step 5: Device receives notification ✅
- [ ] Step 6: Rate-limiting works ✅
- [ ] No console errors ✅
- [ ] All response times < 5 seconds ✅

---

## 🔗 File Structure

```
docs/
├── PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md      (Overview)
├── PUSH_SMOKE_TEST_QUICK_REFERENCE.html         (Printable)
├── PUSH_SMOKE_TEST_GUIDE.md                     (Detailed)
├── PUSH_SMOKE_TEST_IMPLEMENTATION.md            (Checklist)
├── PUSH_SMOKE_TEST_QUERIES.sql                  (SQL)
└── PUSH_SMOKE_TEST_INDEX.md                     (This file)

lib/features/notifications/services/
├── push_smoke_test_helper.dart                  (Steps 1-3)
└── push_rate_limit_test.dart                    (Step 6)

lib/features/notifications/screens/
└── push_smoke_test_screen.dart                  (UI Runner)

functions/src/
└── deviceTokens.ts                              (Backend)

root/
└── run_smoke_test.sh                            (Bash script)
```

---

## 📖 Reading Guide

### If you have 5 minutes:
→ Read [PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md](PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md)

### If you have 15 minutes:
→ Read [PUSH_SMOKE_TEST_GUIDE.md](PUSH_SMOKE_TEST_GUIDE.md)

### If you're implementing:
→ Follow [PUSH_SMOKE_TEST_IMPLEMENTATION.md](PUSH_SMOKE_TEST_IMPLEMENTATION.md)

### If you're debugging:
→ Check [PUSH_SMOKE_TEST_GUIDE.md](PUSH_SMOKE_TEST_GUIDE.md) Troubleshooting section

### If you need to verify:
→ Use queries from [PUSH_SMOKE_TEST_QUERIES.sql](PUSH_SMOKE_TEST_QUERIES.sql)

### If you need a reference:
→ Print [PUSH_SMOKE_TEST_QUICK_REFERENCE.html](PUSH_SMOKE_TEST_QUICK_REFERENCE.html)

---

## 🎯 Common Tasks

### Run the smoke test
```dart
import 'package:weafrica_music/features/notifications/services/push_smoke_test_helper.dart';

final helper = PushSmokeTestHelper();
await helper.runFullTest();
```

### Test rate-limiting
```dart
import 'package:weafrica_music/features/notifications/services/push_rate_limit_test.dart';

final test = PushRateLimitTest();
await test.runRateLimitTest();
```

### Verify token in database
```sql
SELECT * FROM notification_device_tokens
WHERE user_id = 'YOUR_FIREBASE_UID'
LIMIT 1;
```

### Deploy cloud functions
```bash
firebase deploy --only functions:registerDeviceToken
```

### View cloud function logs
```bash
firebase functions:log
```

---

## 💡 Key Concepts

### Firebase ID Token
- Proves user is authenticated
- Sent in Authorization header
- Expires in 1 hour, auto-refreshes
- Required for all API calls

### FCM Device Token
- Unique to this device/app combination
- Provided by Firebase Messaging
- Stored in Supabase database
- Used by FCM to deliver notifications

### Device Registration
- Associates FCM token with user
- Stores platform (iOS/Android)
- Includes metadata (country, app version)
- Enables selective notification targeting

### Rate-Limiting
- Prevents notification spam
- Typical limit: 5 per user per day
- Returns 429 when limit exceeded
- User limit resets at midnight

---

## 🛠️ Troubleshooting

**Problem: "Failed to register device token"**
- Check backend URL is correct
- Verify Cloud Functions deployed
- Check Firebase auth token is valid

**Problem: "Token not found in Supabase"**
- Registration returned 200 OK but token not saved
- Check Supabase table exists
- Verify user_id matches Firebase UID

**Problem: "Notification not received"**
- Check device notifications enabled
- Verify token is_active = true
- Check FCM service status

**Problem: "Rate-limiting not working"**
- Check backend rate-limiting logic
- Verify max_per_user_per_day value
- Check rate-limiting database/cache

See [PUSH_SMOKE_TEST_IMPLEMENTATION.md](PUSH_SMOKE_TEST_IMPLEMENTATION.md) for detailed solutions.

---

## 📞 Next Steps

1. ✅ Review [PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md](PUSH_NOTIFICATION_SMOKE_TEST_SUMMARY.md)
2. ✅ Follow [PUSH_SMOKE_TEST_IMPLEMENTATION.md](PUSH_SMOKE_TEST_IMPLEMENTATION.md)
3. ✅ Run the smoke test
4. ✅ Verify results in Supabase
5. ✅ Document results
6. ✅ Deploy to production

---

## 📋 Document Stats

| File | Lines | Purpose |
|------|-------|---------|
| Summary | 200+ | Overview & quick start |
| Guide | 400+ | Detailed walkthrough |
| Implementation | 300+ | Checklist & execution |
| Quick Reference | 400+ | HTML printable card |
| SQL Queries | 150+ | Verification queries |
| This Index | 250+ | Navigation & reference |

**Total:** 1700+ lines of documentation + code

---

## 🎉 You're All Set!

Everything you need is in this package:

✅ Code files (Dart + TypeScript)  
✅ Complete documentation  
✅ SQL verification queries  
✅ HTML reference card  
✅ Implementation checklists  
✅ Troubleshooting guides  

**Next:** Pick a document above and get started! 🚀

---

**Version:** 1.0  
**Created:** January 28, 2025  
**Status:** Production Ready  
**Last Updated:** January 28, 2025
