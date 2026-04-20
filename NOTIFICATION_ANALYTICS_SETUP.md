"""
NOTIFICATION ANALYTICS IMPLEMENTATION GUIDE
============================================

This document guides you through setting up the notification analytics layer
for WeAfrica Music.

---

## ✅ STEP 1: Database Setup

Run this SQL in your Supabase SQL Editor:

```sql
-- Copy entire contents from: tool/notification_analytics_schema.sql
-- This creates:
-- - notification_logs table
-- - Analytics views (delivery_stats, stats_by_type, stats_by_country, etc.)
-- - RLS policies for admin access
```

File: `tool/notification_analytics_schema.sql`

---

## ✅ STEP 2: Add Models (Already Created)

File: `lib/features/notifications/models/notification_log.dart`

Classes:
- `NotificationLog` - Single log entry
- `NotificationAnalyticsSummary` - Aggregated stats
- `NotificationHourlyTrend` - Time-based trends
- `TokenHealthDiagnostic` - Token validity status
- Enums: `NotificationStatus`, `NotificationType`, `UserRoleAnalytics`

---

## ✅ STEP 3: Create Analytics Service (Already Created)

File: `lib/features/notifications/services/notification_analytics_service.dart`

Methods:
- `logNotificationSent()` - Log when push is sent
- `logNotificationDelivered()` - Log delivery confirmation
- `logNotificationFailed()` - Log failed delivery
- `logNotificationOpened()` - Log when user taps (CTR)
- `logNotificationClicked()` - Log action completion
- `getOverallStats()` - Overall metrics
- `getStatsByType()` - Metrics by notification type
- `getStatsByCountry()` - Geographic performance
- `getStatsByRole()` - User role performance
- `getHourlyTrends()` - Time-based trends
- `getTokenHealth()` - Device token diagnostics

---

## ✅ STEP 4: Update FCM Service (Already Created)

File: `lib/features/notifications/services/fcm_service.dart`

Key methods:
- `FCMService.initialize()` - Set up FCM with analytics
- `firebaseMessagingBackgroundHandler()` - Background message handler
- `_handleForegroundMessage()` - Log delivered + open listener
- `_handleMessageOpenedApp()` - Log when user taps
- `logDelivery()` - Log after sending

---

## ✅ STEP 5: Create Admin Dashboard (Already Created)

File: `lib/features/notifications/admin/notification_analytics_dashboard.dart`

Tabs:
- **Overall** - Total stats, delivery rate, open rate
- **By Type** - Performance of each notification type
- **By Country** - Geographic breakdown
- **By Role** - Consumer vs Artist vs DJ
- **Hourly Trends** - Time-based patterns
- **Token Health** - Invalid token diagnostics

---

## ✅ STEP 6: Create Analytics Repository (Already Created)

File: `lib/features/notifications/repositories/notification_analytics_repository.dart`

Features:
- Query aggregated statistics
- Get optimal send times
- Generate recommendations
- Calculate engagement metrics

---

## 🔧 STEP 7: Integration with Your App

### 7.1 Initialize FCM in main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );
  
  final analyticsService = NotificationAnalyticsService(
    Supabase.instance.client,
  );
  
  await FCMService.initialize(analyticsService);
  
  runApp(const MyApp());
}
```

### 7.2 Log Notifications When Sending

When you send a push via FCM from your backend:

```dart
// After successfully sending via FCM
final token = await FCMService.getDeviceToken();
final country = await FCMService.getCurrentUserCountry();

await FCMService.logDelivery(
  userId: currentUser.uid,
  token: token!,
  type: NotificationType.likeUpdate,
  payload: fcmPayload,
  countryCode: country,
  role: UserRoleAnalytics.consumer,
);
```

### 7.3 Include Notification ID in Payload

When sending FCM from backend, include:

```json
{
  "to": "<FCM_TOKEN>",
  "data": {
    "notif_id": "<UNIQUE_NOTIFICATION_LOG_ID>",
    "type": "like_update",
    "entity_id": "song_123",
    "silent": false
  }
}
```

### 7.4 Add Admin Dashboard to Navigation

```dart
// In your admin panel
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const NotificationAnalyticsDashboard(),
  ),
);
```

---

## 📊 Key Metrics Explained

| Metric | Definition | Target |
|--------|-----------|--------|
| **Delivery Rate** | (Delivered / Sent) × 100 | > 95% |
| **Open Rate / CTR** | (Opened / Delivered) × 100 | > 15% |
| **Failure Rate** | (Failed / Sent) × 100 | < 5% |
| **Avg Time to Open** | Average seconds from sent to first open | < 2 min |

---

## 🎯 Best Practices

### 1. **Batch Operations**
- Don't log every single event in real-time
- Collect and batch every 5-10 minutes

### 2. **Segment by Time**
- Send notifications at optimal hours (based on trends)
- Avoid peak work hours (9-5) for casual content

### 3. **Monitor Token Health**
- Run token cleanup weekly
- Remove tokens with >50% failure rate

### 4. **A/B Test Copy**
- Test different notification text
- Compare open rates
- Use best performing copies

### 5. **Avoid Fatigue**
- Limit to 1-2 notifications per day per user
- Track "mute" signals (repeated ignores)
- Increase interval if user stops opening

### 6. **Personalize by Role**
- Artists care about engagement metrics
- DJs care about live events
- Consumers care about new music

---

## 🚀 Advanced Queries (Optional)

### Get user who opened most notifications

```sql
select user_id, count(*) as opens
from notification_logs
where status = 'opened'
group by user_id
order by opens desc
limit 10;
```

### Best performing notification type by country

```sql
select type, country_code, 
  round(100.0 * count(*) filter (where status = 'opened') / count(*), 2) as open_rate
from notification_logs
where created_at >= now() - interval '30 days'
group by type, country_code
order by open_rate desc;
```

### Predict optimal send time

```sql
select 
  extract(hour from created_at) as hour,
  round(100.0 * count(*) filter (where status = 'opened') / 
    nullif(count(*), 0), 2) as open_rate
from notification_logs
where created_at >= now() - interval '7 days'
group by hour
order by open_rate desc;
```

---

## 🆘 Troubleshooting

**Q: Token health shows >50% failures**
- Check if tokens are from app reinstalls
- Verify token format is valid
- Check FCM project credentials

**Q: Delivery rate < 85%**
- Verify Firebase project is configured correctly
- Check user notification permissions in device settings
- Review FCM topic subscriptions

**Q: Open rate is 0%**
- Ensure `notification_log_id` is included in payload
- Check `onMessageOpenedApp` listener is registered
- Verify analytics service is initialized

---

## ✨ Next Steps

1. Run `tool/notification_analytics_schema.sql` in Supabase
2. Initialize FCM in `main.dart`
3. Start logging notifications from your backend
4. Monitor dashboard for trends
5. Optimize send times based on data
6. A/B test notification copy
7. Track engagement by user role and country
"""
