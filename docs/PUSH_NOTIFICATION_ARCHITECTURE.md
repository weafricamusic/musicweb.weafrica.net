# 🔔 Push Notification System - Architecture & Flow

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PUSH NOTIFICATION SYSTEM                         │
└─────────────────────────────────────────────────────────────────────────┘

                        ┌──────────────────┐
                        │  CONSUMER DEVICE │
                        │  (iOS/Android)   │
                        └────────┬─────────┘
                                 │
                    Step 1: Collect Tokens
                    • Firebase ID Token
                    • FCM Device Token
                    • Device Info
                                 │
                                 ▼
                        ┌──────────────────┐
                        │   FIREBASE AUTH  │
                        │   & MESSAGING    │
                        └────────┬─────────┘
                                 │
                    Verify Auth Token
                    Get FCM Device Token
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  YOUR BACKEND SERVER    │
                    │  (Firebase Functions)   │
                    │                         │
                    │ POST /api/push/register │
                    └────────┬────────────────┘
                             │
        Step 2: Register Token with Backend
        • Receive Firebase ID Token
        • Receive FCM Device Token
        • Verify user authentication
        • Validate token
                             │
                             ▼
                    ┌─────────────────────┐
                    │  SUPABASE DATABASE  │
                    │  (PostgreSQL)       │
                    │                     │
                    │ notification_device│
                    │ _tokens table       │
                    └────────┬────────────┘
                             │
        Step 3: Store Token in Database
        • Save user_id
        • Save fcm_token
        • Save platform (iOS/Android)
        • Save country_code
        • Save topics
        • Save timestamps
                             │
                             ▼
                    ┌─────────────────────┐
                    │  VERIFY IN DB       │
                    │  SELECT * WHERE ... │
                    │  ✅ Token Found    │
                    └─────────────────────┘

        Later: Send Notification
                    │
                    ▼
        ┌──────────────────────┐
        │  ADMIN DASHBOARD     │
        │ or Backend Trigger   │
        └──────────┬───────────┘
                   │
        Step 4: Query Matching Devices
        • Match by country
        • Match by topic
        • Match by user role
                   │
                   ▼
        ┌──────────────────────────────┐
        │  Get All Matching FCM Tokens │
        │  FROM notification_device_   │
        │      tokens                  │
        └──────────┬───────────────────┘
                   │
        Step 5: Send via Firebase Cloud Messaging (FCM)
        • Build notification payload
        • Send to each device token
        • Handle retries
        • Log delivery status
                   │
                   ▼
        ┌──────────────────────────────┐
        │  FIREBASE CLOUD MESSAGING    │
        │  (FCM Service)               │
        └──────────┬───────────────────┘
                   │
        Route to Device
        • Check device is active
        • Retry if failed
        • Store delivery status
                   │
                   ▼
        ┌──────────────────────────────┐
        │  CONSUMER DEVICE             │
        │  Receives Notification       │
        │                              │
        │  • Foreground: onMessage     │
        │  • Background: Native Alert  │
        │  • Tap: onMessageOpenedApp   │
        └──────────────────────────────┘
```

---

## Step-by-Step Flow Diagram

```
STEP 1: TOKEN COLLECTION
─────────────────────────

[App Startup]
      │
      ├─► FirebaseAuth.instance.currentUser ──► [Firebase UID]
      │
      ├─► FirebaseMessaging.instance.getToken() ──► [FCM Token]
      │
      ├─► DeviceInfoPlugin().deviceInfo ──► [Device Model, OS]
      │
      └─► user.getIdToken() ──► [ID Token for Auth Header]

All tokens collected ──► STEP 2


STEP 2: DEVICE REGISTRATION
───────────────────────────

[Ready to Register]
      │
      ├─► Build Request Body:
      │   {
      │     "token": "fcm-token",
      │     "platform": "ios|android",
      │     "device_model": "iPhone 15",
      │     "country_code": "gh",
      │     "topics": ["all", "consumers"]
      │   }
      │
      ├─► Add Auth Header:
      │   Authorization: Bearer <ID Token>
      │
      └─► POST to backend
          /api/push/register
          
          Backend processes request:
          1. Verify ID Token ──► Extract user_id
          2. Validate input ──► Check token, platform
          3. Upsert to DB ──► Save/update token
          4. Subscribe to topics ──► FCM topic subscription
          5. Return 200 OK
                │
                └─► STEP 3


STEP 3: VERIFICATION IN SUPABASE
────────────────────────────────

[Verify Registration]
      │
      └─► Query Database:
          SELECT * FROM notification_device_tokens
          WHERE user_id = 'firebase-uid'
          AND is_active = true
          
          Check:
          ✅ user_id matches
          ✅ fcm_token saved
          ✅ platform correct
          ✅ is_active = true
          ✅ country_code set
          ✅ topics list populated
          ✅ last_updated is recent
          
          All checks pass ──► SMOKE TEST PASSED ✅


STEP 4: ADMIN SENDS NOTIFICATION
────────────────────────────────

[Admin Dashboard]
      │
      ├─► Select Target:
      │   • Topic: "system" | "marketing" | "consumers"
      │   • Country: "gh" | "all"
      │   • User Role: "all" | "premium" | etc
      │
      ├─► Configure Message:
      │   • Title: "Test Notification"
      │   • Body: "This is a test"
      │   • Data: {type: "test", entity_id: "123"}
      │
      ├─► Click "Send Now"
      │
      └─► Backend Query:
          SELECT * FROM notification_device_tokens
          WHERE country_code = 'gh'
          AND is_active = true
          AND topics @> ARRAY['system']
          
          Found 1 token ──► STEP 5


STEP 5: DEVICE RECEIVES NOTIFICATION
────────────────────────────────────

[Device Behavior]

Foreground (App Open):
  │
  ├─► FirebaseMessaging.onMessage listener
  │   └─► _handleForegroundMessage(RemoteMessage)
  │       ├─► Show in-app banner
  │       ├─► Update UI
  │       └─► Log in console

Background (App Closed):
  │
  ├─► OS handles notification
  │   └─► Native notification alert
  │       ├─► Show title + body
  │       ├─► Play sound
  │       └─► Badge count

User Taps Notification:
  │
  ├─► FirebaseMessaging.onMessageOpenedApp listener
  │   └─► _handleNotificationTap(RemoteMessage)
  │       ├─► Extract notification type
  │       ├─► Route to correct screen
  │       └─► Pass data payload


STEP 6: RATE-LIMITING TEST
──────────────────────────

[Test Rate-Limiting]

Attempt 1:
  POST /api/push/send
  {
    "token_topic": "trending",
    "max_per_user_per_day": 1
  }
  
  Backend:
  1. Check if user already notified today
  2. Not notified ──► ALLOW
  3. Send notification ──► 200 OK ✅
  4. Record in rate_limits table
  
Attempt 2 (Same User, Same Topic):
  POST /api/push/send (same payload)
  
  Backend:
  1. Check if user already notified today
  2. Already notified ──► DENY
  3. Return 429 Too Many Requests ──► RATE-LIMITED ✅
  4. No notification sent

Rate-limiting works ✅
```

---

## Database Schema

```
notification_device_tokens
┌──────────────────────────────────────────────────────────────┐
│ id               UUID (PK)                                   │
│ user_id          TEXT (FK to auth.users.id)  [Indexed]       │
│ fcm_token        TEXT (Unique)                [Indexed]       │
│ platform         TEXT ('ios' | 'android')                    │
│ device_model     TEXT (e.g., "iPhone 15")                   │
│ country_code     TEXT (e.g., "gh")                          │
│ is_active        BOOLEAN (default: true)     [Indexed]       │
│ topics           JSONB (default: ["all"])                   │
│ app_version      TEXT (e.g., "1.0.0")                       │
│ locale           TEXT (e.g., "en_US")                       │
│ created_at       TIMESTAMP (default: now())                 │
│ last_updated     TIMESTAMP (default: now())  [Indexed]       │
└──────────────────────────────────────────────────────────────┘

Typical Row:
┌──────────────────────────────────────────────────────────────┐
│ id: 550e8400-e29b-41d4-a716-446655440000                   │
│ user_id: firebase-uid-12345                                │
│ fcm_token: d-7v-EYAAe0:APA91bHK3j_Ux...                    │
│ platform: ios                                              │
│ device_model: iPhone 15                                    │
│ country_code: gh                                           │
│ is_active: true                                            │
│ topics: ["all", "consumers"]                               │
│ app_version: 1.0.0                                         │
│ locale: en_US                                              │
│ created_at: 2025-01-28 10:30:00+00                         │
│ last_updated: 2025-01-28 10:30:00+00                       │
└──────────────────────────────────────────────────────────────┘
```

---

## API Endpoints

```
┌────────────────────────────────────────────────────────────┐
│ ENDPOINT 1: Register Device Token                          │
├────────────────────────────────────────────────────────────┤
│ POST /api/push/register                                    │
│ Auth: Bearer <Firebase ID Token>                           │
│                                                             │
│ Request Body:                                              │
│ {                                                          │
│   "token": "fcm-device-token",                            │
│   "platform": "ios",                                       │
│   "device_model": "iPhone 15",                            │
│   "country_code": "gh",                                    │
│   "topics": ["all", "consumers"]                          │
│ }                                                          │
│                                                             │
│ Response (200 OK):                                         │
│ {                                                          │
│   "success": true,                                         │
│   "message": "Device token registered",                    │
│   "data": { ... token record ... }                        │
│ }                                                          │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ ENDPOINT 2: Verify Token                                   │
├────────────────────────────────────────────────────────────┤
│ GET /api/push/verify/:fcmToken                            │
│ Auth: Optional (public endpoint)                           │
│                                                             │
│ Response (200 OK):                                         │
│ {                                                          │
│   "success": true,                                         │
│   "data": { ... token record ... }                        │
│ }                                                          │
│                                                             │
│ Response (404 Not Found):                                  │
│ {                                                          │
│   "error": "Token not found"                              │
│ }                                                          │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ ENDPOINT 3: Deregister Token                               │
├────────────────────────────────────────────────────────────┤
│ POST /api/push/deregister                                  │
│ Auth: Bearer <Firebase ID Token>                           │
│                                                             │
│ Request Body:                                              │
│ {                                                          │
│   "token": "fcm-device-token"                             │
│ }                                                          │
│                                                             │
│ Response (200 OK):                                         │
│ {                                                          │
│   "success": true,                                         │
│   "message": "Device token deregistered"                   │
│ }                                                          │
└────────────────────────────────────────────────────────────┘
```

---

## Notification Payload Structure

```
FCM Message Format:
┌──────────────────────────────────────────────────────┐
│ {                                                    │
│   "notification": {                                 │
│     "title": "Test Notification",                  │
│     "body": "This is a test message"               │
│   },                                                │
│   "data": {                                         │
│     "type": "test",                                │
│     "entity_id": "track-123",                      │
│     "notification_id": "notif-456",                │
│     "timestamp": "2025-01-28T10:30:00Z"            │
│   }                                                 │
│ }                                                    │
└──────────────────────────────────────────────────────┘

Data Field Keys (Used for routing):
  type:              "test" | "like" | "comment" | "bonus" | etc
  entity_id:         Track/Post ID (for navigation)
  notification_id:   Unique notification ID
  screen:            Target screen to open
  action:            Action to perform
  timestamp:         When notification was sent
```

---

## Rate-Limiting Logic

```
Rate-Limiting Decision Tree:

User sends notification request
│
├─► Extract user_id from auth token
│
├─► Query rate_limits table:
│   SELECT sent_count, last_sent_at
│   FROM notification_rate_limits
│   WHERE user_id = ? AND topic = ?
│
├─► Check if reset needed:
│   if (last_sent_at < TODAY at 00:00)
│   then: reset sent_count = 0
│
├─► Check quota:
│   if (sent_count >= max_per_user_per_day)
│   then: REJECT (return 429)
│   else: ALLOW
│
├─► If ALLOW:
│   ├─► Send notification
│   ├─► Increment sent_count
│   ├─► Update last_sent_at = NOW()
│   └─► Return 200 OK
│
└─► If REJECT:
    └─► Return 429 Too Many Requests
        (No notification sent)

Example:
User A, Topic "trending", max_per_user_per_day = 1

Request 1:
  sent_count = 0 (or reset)
  0 < 1 ──► ALLOW ✅
  sent_count = 1
  Return 200 OK

Request 2 (same day):
  sent_count = 1
  1 >= 1 ──► REJECT ❌
  Return 429
  No notification sent

Next Day:
  Quota resets
  sent_count = 0
  0 < 1 ──► ALLOW ✅
```

---

## Error Handling Flow

```
Error Scenario                  Action
────────────────────────────────────────────────────
No user logged in          → Show login screen
Firebase auth failed       → Request new ID token
Invalid FCM token          → Request new token from FCM
Token not found in DB      → Re-register token
Registration failed        → Retry with exponential backoff
Network error              → Queue and retry later
Rate limit exceeded        → Show user message
Device not reachable       → Mark inactive in DB
Old token on new device    → Register as new token
Duplicate token            → Update existing record
Invalid country code       → Use 'unknown' default
```

---

## Success Criteria

```
✅ SMOKE TEST PASSES WHEN:

Step 1: Token Collection
  ✅ Firebase ID Token obtained
  ✅ FCM Device Token obtained
  ✅ Device info collected

Step 2: Backend Registration
  ✅ HTTP 200 OK response
  ✅ Response includes token ID
  ✅ No validation errors

Step 3: Database Verification
  ✅ Token appears in Supabase
  ✅ is_active = true
  ✅ user_id matches
  ✅ All fields populated

Step 4: Admin Notification
  ✅ Status shows "Sent"
  ✅ Recipient count = 1
  ✅ No errors logged

Step 5: Device Reception
  ✅ Notification appears
  ✅ onMessage fires (foreground)
  ✅ Native alert shows (background)
  ✅ Tapping opens app

Step 6: Rate-Limiting
  ✅ First request: 200 OK
  ✅ Second request: 429 Limited
  ✅ System prevents spam

Overall:
  ✅ No console errors
  ✅ All response times < 5 seconds
  ✅ Database queries execute quickly
  ✅ System handles edge cases
```

---

**Diagrams Created:** 7  
**Total Lines:** 600+  
**Version:** 1.0  
**Status:** Ready for Production
