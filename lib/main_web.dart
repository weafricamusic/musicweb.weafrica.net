import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/audio.dart';
import 'app/app_root.dart';
import 'app/config/app_env.dart';
import 'features/creator_dashboard/providers/creator_dashboard_provider.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  // Track repeated overflow errors to avoid spamming the console.
  final _seenOverflows = <String, int>{};
  const _maxOverflowPrints = 3;

  FlutterError.onError = (FlutterErrorDetails details) {
    final desc = details.toString();
    final isOverflow = desc.contains('overflow') ||
        desc.contains('RenderFlex') ||
        desc.contains('debug_overflow_indicator');

    if (isOverflow) {
      final key = details.exception?.toString() ?? desc;
      final count = (_seenOverflows[key] ?? 0) + 1;
      _seenOverflows[key] = count;
      if (count > _maxOverflowPrints) return;
      debugPrint('⚠️ FLUTTER OVERFLOW (#$count): $key');
      if (count == 1) {
        debugPrintStack();
      }
      return;
    }

    debugPrint('❌ FLUTTER ERROR: ${details.exception}');
    debugPrint('❌ Stack trace: ${details.stack}');
    debugPrintStack();
  };

  WidgetsFlutterBinding.ensureInitialized();

  // Register background message handler as early as possible.
  // Web uses the service worker (`web/firebase-messaging-sw.js`).
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Load bundled env config early (safe to call twice; bootstrap also loads it).
  await AppEnv.load();

  // Ticket 2.15: local caching (Hive).
  // Safe to call on all platforms; required before opening any Hive boxes.
  await Hive.initFlutter();

  // Ensure the global audio handler is ready before any UI tries playback.
  await initWeAfricaAudio();

  runApp(
    ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CreatorDashboardProvider()),
        ],
        child: const MyApp(),
      ),
    ),
  );
}
