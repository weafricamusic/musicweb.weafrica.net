import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'audio/audio.dart';
import 'app/app_root.dart';
import 'app/config/app_env.dart';
import 'features/creator_dashboard/providers/creator_dashboard_provider.dart';
import 'home/providers/audio_provider.dart';
import 'services/notification_service.dart';

Future<void> main() async {
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
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioProvider()..init()),
        ChangeNotifierProvider(create: (_) => CreatorDashboardProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

