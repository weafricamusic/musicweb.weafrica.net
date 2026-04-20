🔔 WEAFRICA MUSIC - COMPLETE ADMIN NOTIFICATION FLOW
Production-Accurate Documentation

═══════════════════════════════════════════════════════════════════════════

📋 ADMIN DASHBOARD → FCM FLOW

When admin clicks "Send Now" in the notification UI:

┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 1: Admin UI Action                                                │
├─────────────────────────────────────────────────────────────────────────┤
│ Admin configures:                                                       │
│   • Title: "New track released"                                        │
│   • Body: "Check out the latest from Artist X"                         │
│   • Topic: "all" or "consumers"                                        │
│   • Country: "mw" (or "all")                                           │
│   • Screen: "track_detail"                                             │
│   • Entity ID: "track-123"                                             │
│                                                                          │
│ Admin clicks: "Send Now"                                               │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 2: API Call                                                       │
├─────────────────────────────────────────────────────────────────────────┤
│ POST /api/admin/notifications/push                                     │
│ Headers: Authorization: Bearer <admin_token>                           │
│                                                                          │
│ Body:                                                                   │
│ {                                                                       │
│   "title": "New track released",                                       │
│   "body": "Check out the latest from Artist X",                        │
│   "topic": "all",                                                       │
│   "country": "mw",                                                      │
│   "data": {                                                            │
│     "screen": "track_detail",                                          │
│     "entity_id": "track-123"                                           │
│   },                                                                   │
│   "send_now": true                                                     │
│ }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 3: Backend Processing                                             │
├─────────────────────────────────────────────────────────────────────────┤
│ Next.js API route does:                                                │
│                                                                          │
│ 1. Verify admin authentication                                         │
│                                                                          │
│ 2. Create row in notifications table:                                  │
│    INSERT INTO notifications (                                         │
│      title, body, topic, country, data, status                         │
│    ) VALUES (                                                           │
│      'New track released',                                             │
│      'Check out...',                                                   │
│      'all',                                                             │
│      'mw',                                                              │
│      '{"screen": "track_detail", "entity_id": "track-123"}',           │
│      'pending'                                                          │
│    ) RETURNING id                                                       │
│                                                                          │
│ 3. Auto-inject notification_id into data:                              │
│    data.notification_id = <row.id>                                     │
│                                                                          │
│ 4. Query matching device tokens:                                       │
│    SELECT token FROM notification_device_tokens                        │
│    WHERE country_code = 'mw'                                           │
│    AND topics @> '["all"]'::jsonb                                      │
│                                                                          │
│ 5. For each token:                                                     │
│    - Check rate limit (has user been notified today?)                  │
│    - Build FCM payload                                                 │
│    - Send to Firebase Cloud Messaging                                  │
│    - Log result                                                        │
│                                                                          │
│ 6. Update notification status:                                         │
│    UPDATE notifications                                                │
│    SET status = 'sent', sent_count = X                                 │
│    WHERE id = <row.id>                                                 │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 4: FCM Delivery                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│ FCM Payload:                                                           │
│ {                                                                       │
│   "notification": {                                                    │
│     "title": "New track released",                                     │
│     "body": "Check out the latest from Artist X"                       │
│   },                                                                   │
│   "data": {                                                            │
│     "screen": "track_detail",                                          │
│     "entity_id": "track-123",                                          │
│     "notification_id": "abc123-def456",  ← AUTO-INJECTED              │
│     "type": "admin_push"                                               │
│   },                                                                   │
│   "token": "device_fcm_token_here"                                     │
│ }                                                                       │
│                                                                          │
│ FCM sends to device via APNs (iOS) or GCM (Android)                    │
└─────────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 5: Device Reception                                               │
├─────────────────────────────────────────────────────────────────────────┤
│ Foreground (App Open):                                                 │
│   → FirebaseMessaging.onMessage fires                                  │
│   → message.data contains:                                             │
│      {                                                                  │
│        "screen": "track_detail",                                       │
│        "entity_id": "track-123",                                       │
│        "notification_id": "abc123-def456"                              │
│      }                                                                  │
│   → App can show custom in-app notification UI                         │
│                                                                          │
│ Background/Terminated:                                                  │
│   → OS shows native notification                                       │
│   → User taps notification                                             │
│   → App opens                                                           │
│   → FirebaseMessaging.onMessageOpenedApp fires                         │
│   → App extracts data.screen and data.entity_id                        │
│   → App navigates to TrackDetailScreen(trackId: "track-123")           │
└─────────────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════════

📊 DATA FLOW EXAMPLE

Admin Input:
  Title: "New battle starting!"
  Body: "Join the rap battle now"
  Topic: "battles"
  Country: "gh"
  Screen: "live_battle"
  Entity ID: "battle-789"

Row Created in notifications table:
  id: "notif-abc-123"
  title: "New battle starting!"
  body: "Join the rap battle now"
  topic: "battles"
  country: "gh"
  data: {
    "screen": "live_battle",
    "entity_id": "battle-789"
  }
  status: "pending"

Auto-injected before sending:
  data: {
    "screen": "live_battle",
    "entity_id": "battle-789",
    "notification_id": "notif-abc-123"  ← ADDED
  }

FCM receives:
  {
    "notification": { "title": "...", "body": "..." },
    "data": {
      "screen": "live_battle",
      "entity_id": "battle-789",
      "notification_id": "notif-abc-123"
    }
  }

Device routing logic:
  switch (data['screen']) {
    case 'live_battle':
      Navigator.push(
        LiveBattleScreen(battleId: data['entity_id'])
      );
      break;
  }

═══════════════════════════════════════════════════════════════════════════

🔍 KEY POINTS

1. data.notification_id is ALWAYS present
   • Admin pushes: Auto-injected from row.id
   • System pushes: Generated at send time
   • Used for: Analytics, read receipts, deduplication

2. send_now: true means immediate send
   • Creates row + sends in one operation
   • Alternative: send_now: false schedules for later

3. Rate-limiting happens per user per topic
   • Checked before each send
   • Prevents spam to same user
   • Default: max_per_user_per_day

4. Routing is data-driven
   • data.screen determines destination
   • data.entity_id provides context
   • App handles navigation logic

═══════════════════════════════════════════════════════════════════════════

🧪 TESTING THE FLOW

Test 1: Admin Send → Device Receive
```dart
// On device, listen for notifications
FirebaseMessaging.onMessage.listen((message) {
  print('Received: ${message.data}');
  assert(message.data['notification_id'] != null); // Should always be present
  assert(message.data['screen'] != null);
});
```

Test 2: Verify notification_id matches database
```sql
-- In Supabase
SELECT id, title, status 
FROM notifications 
WHERE id = '<notification_id_from_device>';
-- Should return the row created by admin
```

Test 3: Test routing
```dart
// When notification tapped
FirebaseMessaging.onMessageOpenedApp.listen((message) {
  final screen = message.data['screen'];
  final entityId = message.data['entity_id'];
  
  // Navigate based on screen
  if (screen == 'track_detail') {
    Navigator.push(TrackDetailScreen(trackId: entityId));
  }
});
```

═══════════════════════════════════════════════════════════════════════════

Version: 1.0
Date: January 28, 2026
System: Next.js + Supabase + FCM
Status: ✅ Production-Accurate
