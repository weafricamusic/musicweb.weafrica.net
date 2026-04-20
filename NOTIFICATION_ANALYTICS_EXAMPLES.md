"""
NOTIFICATION ANALYTICS — CODE EXAMPLES
=======================================

Common patterns and use cases for the notification analytics system.
"""

# ============================================================================
# EXAMPLE 1: Initialize Analytics in main.dart
# ============================================================================

"""
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'lib/features/notifications/services/notification_analytics_service.dart';
import 'lib/features/notifications/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Supabase
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  // Initialize notification analytics
  final analyticsService = NotificationAnalyticsService(
    Supabase.instance.client,
  );

  // Initialize FCM with analytics
  await FCMService.initialize(analyticsService);

  runApp(const MyApp());
}
"""

# ============================================================================
# EXAMPLE 2: Send Notification From Backend + Log Analytics
# ============================================================================

"""
Future<void> sendLikeNotification({
  required String userId,
  required String senderName,
  required String songTitle,
}) async {
  final user = await Supabase.instance.client
      .from('profiles')
      .select('fcm_token, country_code, role')
      .eq('id', userId)
      .single();

  final fcmToken = user['fcm_token'];
  final countryCode = user['country_code'];
  final role = user['role'];

  // Generate unique notification ID
  final notificationId = const Uuid().v4();

  // Prepare FCM payload
  final payload = {
    'to': fcmToken,
    'notification': {
      'title': '❤️ New Like!',
      'body': '$senderName liked "$songTitle"',
      'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
    },
    'data': {
      'notif_id': notificationId,
      'type': 'like_update',
      'entity_id': songId,
      'sender_id': senderName,
      'silent': 'false',
    },
  };

  try {
    // Send via FCM Cloud Function
    final response = await http.post(
      Uri.parse('YOUR_FCM_ENDPOINT'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      // Log to analytics
      final analyticsService = NotificationAnalyticsService(
        Supabase.instance.client,
      );

      await analyticsService.logNotificationSent(
        userId: userId,
        token: fcmToken,
        type: NotificationType.likeUpdate,
        payload: payload['data'],
        countryCode: countryCode,
        role: UserRoleAnalytics.fromString(role),
      );

      print('✅ Notification sent & logged');
    } else {
      print('❌ FCM send failed: ${response.body}');
    }
  } catch (e) {
    print('❌ Error sending notification: $e');
  }
}
"""

# ============================================================================
# EXAMPLE 3: View Analytics Dashboard in Admin Panel
# ============================================================================

"""
class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛠️ Admin Panel'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('📊 Notification Analytics'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationAnalyticsDashboard(),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('📤 Send Notification'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SendNotificationScreen(),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('🧹 Cleanup Invalid Tokens'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => _performTokenCleanup(context),
          ),
        ],
      ),
    );
  }

  Future<void> _performTokenCleanup(BuildContext context) async {
    final repo = NotificationAnalyticsRepository(
      NotificationAnalyticsService(Supabase.instance.client),
    );

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('🧹 Cleaning up invalid tokens...')),
    );

    await repo.cleanupInvalidTokens();

    scaffoldMessenger.removeCurrentSnackBar();
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('✅ Cleanup complete')),
    );
  }
}
"""

# ============================================================================
# EXAMPLE 4: Get Engagement Metrics for a Notification Type
# ============================================================================

"""
Future<void> analyzeNotificationPerformance() async {
  final repo = NotificationAnalyticsRepository(
    NotificationAnalyticsService(Supabase.instance.client),
  );

  // Get metrics for 'like' notifications
  final metrics = await repo.getEngagementMetrics(
    NotificationType.likeUpdate,
  );

  print('''
  📊 LIKE NOTIFICATION METRICS
  ════════════════════════════════
  Type: ${metrics.type.value}
  Total Sent: ${metrics.totalSent}
  Total Opened: ${metrics.totalOpened}
  Open Rate: ${metrics.formattedOpenRate}
  Avg Time to Open: ${metrics.formattedAvgTime}
  Best Country: ${metrics.bestPerformingCountry ?? 'N/A'}
  Best Role: ${metrics.bestPerformingRole ?? 'N/A'}
  ''');
}
"""

# ============================================================================
# EXAMPLE 5: A/B Testing Notifications
# ============================================================================

"""
class NotificationABTestScreen extends StatefulWidget {
  const NotificationABTestScreen({super.key});

  @override
  State<NotificationABTestScreen> createState() =>
      _NotificationABTestScreenState();
}

class _NotificationABTestScreenState extends State<NotificationABTestScreen> {
  late NotificationAnalyticsRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = NotificationAnalyticsRepository(
      NotificationAnalyticsService(Supabase.instance.client),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('A/B Test Notifications')),
      body: FutureBuilder(
        future: Future.wait([
          _repo.getEngagementMetrics(NotificationType.likeUpdate),
          _repo.getEngagementMetrics(NotificationType.commentUpdate),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final [likesMetrics, commentsMetrics] = snapshot.data as List;

          final likeWins = likesMetrics.openRate > commentsMetrics.openRate;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _ComparisonCard(
                  title: 'Likes Notifications',
                  metrics: likesMetrics,
                  winner: likeWins,
                ),
                const SizedBox(height: 16),
                _ComparisonCard(
                  title: 'Comments Notifications',
                  metrics: commentsMetrics,
                  winner: !likeWins,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Winner: ${likeWins ? "Likes" : "Comments"}'
                          ' (${(likeWins ? likesMetrics.openRate : commentsMetrics.openRate).toStringAsFixed(2)}%)',
                        ),
                      ),
                    );
                  },
                  child: const Text('View Winner'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final String title;
  final NotificationEngagementMetrics metrics;
  final bool winner;

  const _ComparisonCard({
    required this.title,
    required this.metrics,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: winner ? Colors.green.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (winner)
                  const Chip(
                    label: Text('WINNER'),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Sent'),
                    Text(
                      metrics.totalSent.toString(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Opened'),
                    Text(
                      metrics.totalOpened.toString(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Open Rate'),
                    Text(
                      metrics.formattedOpenRate,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
"""

# ============================================================================
# EXAMPLE 6: Smart Recommendations Widget
# ============================================================================

"""
class NotificationRecommendationsWidget extends StatefulWidget {
  const NotificationRecommendationsWidget({super.key});

  @override
  State<NotificationRecommendationsWidget> createState() =>
      _NotificationRecommendationsWidgetState();
}

class _NotificationRecommendationsWidgetState
    extends State<NotificationRecommendationsWidget> {
  late NotificationAnalyticsRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = NotificationAnalyticsRepository(
      NotificationAnalyticsService(Supabase.instance.client),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NotificationRecommendation>>(
      future: _repo.getRecommendations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final recommendations = snapshot.data ?? [];

        if (recommendations.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade50,
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  'All systems optimal! No recommendations.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          itemCount: recommendations.length,
          itemBuilder: (context, index) {
            final rec = recommendations[index];
            return Card(
              color: rec.priority == Priority.high
                  ? Colors.red.shade50
                  : rec.priority == Priority.medium
                      ? Colors.yellow.shade50
                      : Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          rec.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Chip(
                          label: Text(rec.priorityLabel),
                          backgroundColor: rec.priorityColor,
                          labelStyle:
                              const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rec.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        // Handle action
                      },
                      child: Text(rec.action),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
"""

# ============================================================================
# EXAMPLE 7: Schedule Notifications at Optimal Time
# ============================================================================

"""
Future<void> scheduleOptimalNotification({
  required String userId,
  required String title,
  required String body,
}) async {
  final repo = NotificationAnalyticsRepository(
    NotificationAnalyticsService(Supabase.instance.client),
  );

  // Get optimal send times
  final optimalTimes = await repo.getOptimalSendTimes();

  if (optimalTimes.isEmpty) {
    print('⚠️ Not enough data to determine optimal time yet');
    return;
  }

  // Find best hour
  final bestHour = optimalTimes.entries
      .reduce((a, b) => a.value > b.value ? a : b)
      .key;

  print('🎯 Optimal send time: $bestHour:00 UTC');

  // Schedule notification for that hour
  // Using a scheduling library like workmanager
  // scheduleNotification(userId, bestHour);
}
"""

# ============================================================================
# EXAMPLE 8: Monitor Token Health Periodically
# ============================================================================

"""
class TokenHealthMonitor {
  static Future<void> checkTokenHealth() async {
    final repo = NotificationAnalyticsRepository(
      NotificationAnalyticsService(Supabase.instance.client),
    );

    final invalidCount = await repo.getInvalidTokenCount();

    if (invalidCount > 0) {
      print('⚠️ Found $invalidCount invalid tokens');
      print('🧹 Running cleanup...');
      await repo.cleanupInvalidTokens();
      print('✅ Cleanup complete');
    } else {
      print('✅ All tokens are healthy');
    }
  }

  // Run this once per day
  static void scheduleDaily() {
    Timer.periodic(const Duration(days: 1), (_) {
      checkTokenHealth();
    });
  }
}
"""

# ============================================================================
# EXAMPLE 9: Custom Analytics Query
# ============================================================================

"""
Future<void> getCountrySpecificMetrics(String countryCode) async {
  final supabase = Supabase.instance.client;

  final results = await supabase
      .from('notification_logs')
      .select()
      .eq('country_code', countryCode)
      .gte('created_at', DateTime.now().subtract(Duration(days: 30)).toIso8601String());

  final opened = results.where((r) => r['status'] == 'opened').length;
  final failed = results.where((r) => r['status'] == 'failed').length;
  final total = results.length;

  final openRate = total > 0 ? (opened / total * 100).toStringAsFixed(2) : '0';
  final failureRate = total > 0 ? (failed / total * 100).toStringAsFixed(2) : '0';

  print('''
  📍 METRICS FOR $countryCode (Last 30 Days)
  ═════════════════════════════════════════
  Total Sent: $total
  Opened: $opened
  Failed: $failed
  Open Rate: $openRate%
  Failure Rate: $failureRate%
  ''');
}
"""

# ============================================================================
# END OF EXAMPLES
# ============================================================================
"""
