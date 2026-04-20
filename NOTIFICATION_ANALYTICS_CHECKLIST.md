# ✅ NOTIFICATION ANALYTICS — IMPLEMENTATION CHECKLIST

---

## 📋 PHASE 1: SETUP (Database + Models)

- [ ] **1.1** Run `tool/notification_analytics_schema.sql` in Supabase SQL Editor
  - Creates `notification_logs` table
  - Creates 7 analytics views
  - Sets up RLS policies
  
- [ ] **1.2** Verify tables exist in Supabase
  ```sql
  SELECT * FROM information_schema.tables 
  WHERE table_name = 'notification_logs';
  ```

- [ ] **1.3** Review models in `lib/features/notifications/models/notification_log.dart`
  - `NotificationLog`
  - `NotificationAnalyticsSummary`
  - `NotificationHourlyTrend`
  - `TokenHealthDiagnostic`
  - Enums: `NotificationStatus`, `NotificationType`, `UserRoleAnalytics`

---

## 🔧 PHASE 2: SERVICES (Core Logic)

- [ ] **2.1** Review `NotificationAnalyticsService` in `lib/features/notifications/services/notification_analytics_service.dart`
  - Logging methods (sent, delivered, failed, opened, clicked)
  - Query methods (stats, trends, health)

- [ ] **2.2** Review `FCMService` in `lib/features/notifications/services/fcm_service.dart`
  - Background handler
  - Foreground message handler
  - Message opened handler
  - Token management

- [ ] **2.3** Update `pubspec.yaml` (verify dependencies)
  ```yaml
  dependencies:
    firebase_messaging: ^14.6.0  # or latest
    supabase_flutter: ^1.0.0
    firebase_core: ^2.24.0
  ```

- [ ] **2.4** Run `flutter pub get`

---

## 📊 PHASE 3: UI (Dashboard + Admin)

- [ ] **3.1** Review Dashboard in `lib/features/notifications/admin/notification_analytics_dashboard.dart`
  - Overall stats tab
  - By type tab
  - By country tab
  - By role tab
  - Hourly trends tab
  - Token health tab

- [ ] **3.2** Review Repository in `lib/features/notifications/repositories/notification_analytics_repository.dart`
  - Query methods
  - Recommendations engine
  - Engagement metrics

- [ ] **3.3** Verify all UI builds without errors
  ```bash
  flutter analyze lib/features/notifications/
  ```

---

## 🚀 PHASE 4: INTEGRATION

### Step 4.1: Initialize FCM in main.dart

- [ ] Update `lib/main.dart`:
  ```dart
  import 'package:firebase_core/firebase_core.dart';
  import 'firebase_options.dart';
  import 'lib/features/notifications/services/notification_analytics_service.dart';
  import 'lib/features/notifications/services/fcm_service.dart';

  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    final analyticsService = NotificationAnalyticsService(
      Supabase.instance.client,
    );
    
    await FCMService.initialize(analyticsService);
    
    runApp(const MyApp());
  }
  ```

- [ ] Test that app starts without errors
  ```bash
  flutter run
  ```

### Step 4.2: Add Dashboard Route

- [ ] Add route to admin panel / settings:
  ```dart
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const NotificationAnalyticsDashboard(),
    ),
  );
  ```

- [ ] Test dashboard loads and shows tabs

### Step 4.3: Log Notifications from Backend

- [ ] When sending notification from backend (FCM), call:
  ```dart
  await FCMService.logDelivery(
    userId: user.uid,
    token: deviceToken,
    type: NotificationType.likeUpdate,
    payload: fcmPayload,
    countryCode: userCountry,
    role: UserRoleAnalytics.consumer,
  );
  ```

- [ ] Include `notif_id` in FCM payload:
  ```json
  {
    "data": {
      "notif_id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "like_update",
      "silent": false
    }
  }
  ```

### Step 4.4: Handle Message Opens

- [ ] Verify `FirebaseMessaging.onMessageOpenedApp` listener in `FCMService`
- [ ] Test tapping notification updates `opened_at` in database
  ```sql
  SELECT opened_at FROM notification_logs 
  WHERE status = 'opened' 
  ORDER BY opened_at DESC LIMIT 5;
  ```

---

## 🧪 PHASE 5: TESTING

- [ ] **5.1** Send test notification manually
  ```bash
  # Via Firebase Console → Cloud Messaging
  # Or use firebase_admin SDK
  ```

- [ ] **5.2** Check notification was logged
  ```sql
  SELECT * FROM notification_logs 
  ORDER BY created_at DESC LIMIT 1;
  ```

- [ ] **5.3** Open notification on device
  ```sql
  SELECT status, opened_at FROM notification_logs 
  WHERE status = 'opened' 
  ORDER BY opened_at DESC LIMIT 1;
  ```

- [ ] **5.4** View analytics dashboard
  - Overall tab should show metrics
  - By Type tab should show entries
  - Tokens tab should show device tokens

- [ ] **5.5** Test token cleanup
  ```dart
  final repo = NotificationAnalyticsRepository(...);
  await repo.cleanupInvalidTokens();
  ```

- [ ] **5.6** Test recommendations
  ```dart
  final recs = await repo.getRecommendations();
  print(recs);
  ```

---

## 📈 PHASE 6: OPTIMIZATION

- [ ] **6.1** Get optimal send times
  ```dart
  final times = await repo.getOptimalSendTimes();
  // Schedule notifications for best hours
  ```

- [ ] **6.2** A/B test notifications
  - Send variant A to 50% of users
  - Send variant B to 50% of users
  - Compare open rates in dashboard

- [ ] **6.3** Segment by geography
  - Review country metrics
  - Optimize timing by timezone
  - Adjust copy per region

- [ ] **6.4** Segment by role
  - Compare Consumer vs Artist vs DJ
  - Send role-specific content
  - Measure engagement lift

---

## 🎯 PHASE 7: MONITORING (Ongoing)

- [ ] **7.1** Set up weekly health checks
  ```dart
  Timer.periodic(Duration(days: 7), (_) {
    NotificationAnalyticsRepository.cleanupInvalidTokens();
  });
  ```

- [ ] **7.2** Monitor key metrics daily
  - [ ] Delivery rate > 95%?
  - [ ] Open rate > 15%?
  - [ ] Token failure rate < 5%?

- [ ] **7.3** Review dashboard weekly
  - [ ] Check for anomalies
  - [ ] Review recommendations
  - [ ] Adjust send times if needed

- [ ] **7.4** Archive old data monthly
  ```sql
  -- Archive logs older than 90 days (optional)
  -- CREATE TABLE notification_logs_archive AS
  -- SELECT * FROM notification_logs
  -- WHERE created_at < now() - interval '90 days';
  ```

---

## 🚨 PHASE 8: TROUBLESHOOTING

### Issue: Dashboard shows no data

- [ ] Check database table has rows
  ```sql
  SELECT COUNT(*) FROM notification_logs;
  ```
- [ ] Check RLS policies allow select
  ```sql
  SELECT * FROM pg_policies 
  WHERE tablename = 'notification_logs';
  ```
- [ ] Check auth user is admin
  ```sql
  SELECT auth.jwt() ->> 'role';
  ```

### Issue: Delivery rate < 85%

- [ ] Check Firebase project credentials
- [ ] Verify app has notification permissions
- [ ] Check device token format
- [ ] Review failure reasons in token_health view

### Issue: Open rate is 0%

- [ ] Ensure `notif_id` in FCM payload
- [ ] Check `onMessageOpenedApp` listener is active
- [ ] Verify analytics service initialized
- [ ] Check database for `opened_at` values

### Issue: App crashes on startup

- [ ] Check Firebase initialization
- [ ] Verify Supabase client initialized
- [ ] Check `google-services.json` (Android)
- [ ] Check `GoogleService-Info.plist` (iOS)

---

## 📚 REFERENCE DOCS

- [ ] Read `NOTIFICATION_ANALYTICS_SETUP.md` — Installation guide
- [ ] Read `NOTIFICATION_ANALYTICS_SUMMARY.md` — Feature overview
- [ ] Read `NOTIFICATION_ANALYTICS_EXAMPLES.md` — Code examples
- [ ] Review SQL schema: `tool/notification_analytics_schema.sql`

---

## ✨ SUCCESS CRITERIA

You'll know implementation is complete when:

✅ Dashboard shows real metrics  
✅ Sending test notifications logs to database  
✅ Tapping notifications updates `opened_at`  
✅ All 6 dashboard tabs load without errors  
✅ Delivery rate > 95%  
✅ Open rate > 15%  
✅ Token cleanup removes invalid tokens  
✅ Recommendations engine suggests optimizations  

---

## 🎬 NEXT STEPS

Once analytics is working:

1. **A/B Test Notifications** — Test different copy/timing
2. **Schedule Smartly** — Use optimal send times
3. **Segment Users** — Target by country/role/behavior
4. **Measure Lifetime Value** — Track long-term retention impact
5. **Scale Globally** — Replicate success across regions

---

**You now have premium-grade notification analytics!**  
Compare with: Mixpanel, Amplitude, Braze 🚀
