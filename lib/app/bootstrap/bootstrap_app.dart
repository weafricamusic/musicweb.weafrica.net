import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/settings/settings_controller.dart';
import '../../features/subscriptions/subscriptions_controller.dart';
import '../../features/auth/web_auth_session.dart';
import '../../services/device_capability_service.dart';
import '../../services/journey_service.dart';
import '../../services/liked_tracks_store.dart';
import '../../services/notification_service.dart';
import '../../services/playback_interstitial_ads.dart';
import '../../services/user_service.dart';
import '../config/api_env.dart';
import '../config/app_env.dart';
import '../config/firebase_web_env.dart';
import '../config/supabase_env.dart';
import 'app_bootstrap_result.dart';
import 'bootstrap_connectivity.dart';
import 'bootstrap_error_handling.dart';
import 'bootstrap_progress.dart';
import 'bootstrap_retry.dart';

/// Bootstrap the WEAFRICA Music application.
///
/// Returns [AppBootstrapResult] containing initialization errors (if any) plus
/// useful status signals for the UI.
Future<AppBootstrapResult> bootstrapApp({
  ValueChanged<String>? onProgress,
  bool deferNonCritical = false,
}) async {
  final stopwatch = Stopwatch()..start();

  onProgress?.call(BootstrapProgress.stage1);
  WidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // Phase 1: Load environment configuration
  // ============================================================
  await ApiEnv.load();
  await AppEnv.load();
  await FirebaseWebEnv.load();

  if (kDebugMode) {
    final defined = ApiEnv.definedBaseUrl;
    final isSet = defined.isNotEmpty;
    developer.log(
      'ApiEnv.baseUrl=${ApiEnv.baseUrl} (WEAFRICA_API_BASE_URL=${isSet ? defined : '(not set)'})',
      name: 'WEAFRICA.Bootstrap',
    );
    if (!isSet) {
      developer.log(
        'Tip: run with --dart-define-from-file=tool/supabase.env.json (see .vscode/launch.json). '
        'This app now prefers hosted Supabase Edge Functions by default. '
        'Only override WEAFRICA_API_BASE_URL if you intentionally need a different hosted API origin.',
        name: 'WEAFRICA.Bootstrap',
      );
    }
  }

  configureBootstrapErrorHandling();

  // ============================================================
  // Phase 3: Light UI/perf tweaks
  // ============================================================
  onProgress?.call(BootstrapProgress.stage2);

  // Better UX for image-heavy feeds.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 100;

  // ============================================================
  // Phase 4: Initialize Mobile Ads (best-effort)
  // ============================================================
  unawaited(PlaybackInterstitialAds.instance.initialize());

  // ============================================================
  // Phase 5: Initialize Supabase (primary)
  // ============================================================
  onProgress?.call(BootstrapProgress.stage4);

  Object? supabaseInitError;
  final supabaseInitialized = await initializeWithRetry(
    operation: 'Supabase',
    retryCount: 3,
    action: () async {
      await SupabaseEnv.load();
      SupabaseEnv.validate();

      // Helpful when debugging “Bucket not found” with multiple Supabase environments.
      ApiEnv.debugWarnIfProjectMismatch();

      await Supabase.initialize(
        url: SupabaseEnv.supabaseUrl,
        anonKey: SupabaseEnv.supabaseAnonKey,
        debug: kDebugMode,
      );
    },
    onAttemptFailure: (error, stackTrace) {
      supabaseInitError = error;
    },
    onAttemptSuccess: () {
      supabaseInitError = null;
    },
  );

  // ============================================================
  // Phase 6: Initialize Firebase (secondary; notifications)
  // ============================================================
  Object? firebaseInitError;
  final firebaseInitialized = await initializeWithRetry(
    operation: 'Firebase',
    retryCount: 2,
    action: () async {
      if (kIsWeb) {
        final options = FirebaseWebEnv.tryOptions();
        if (options == null) {
          throw StateError(
            'Missing Firebase Web config. Add FIREBASE_WEB_API_KEY, FIREBASE_WEB_PROJECT_ID, '
            'FIREBASE_WEB_MESSAGING_SENDER_ID, and FIREBASE_WEB_APP_ID to '
            'tool/supabase.env.json (or pass as --dart-define).',
          );
        }
        await Firebase.initializeApp(options: options);
        await WebAuthSession.initialize();
      } else {
        await Firebase.initializeApp();
      }
    },
    onAttemptFailure: (error, stackTrace) {
      firebaseInitError = error;
    },
    onAttemptSuccess: () {
      firebaseInitError = null;
    },
  );

  // ============================================================
  // Phase 7+: Defer non-critical work (keep first screen fast)
  // ============================================================
  if (deferNonCritical) {
    onProgress?.call(BootstrapProgress.stage6);
    unawaited(
      _runDeferredBootstrapTasks(firebaseInitialized: firebaseInitialized).catchError((e, st) {
        developer.log(
          'Deferred bootstrap tasks failed (non-critical)',
          name: 'WEAFRICA.Bootstrap',
          error: e,
          stackTrace: st,
        );
      }),
    );
  } else {
    // Legacy behavior: do everything before returning.
    onProgress?.call(BootstrapProgress.stage3);
    final bool isOffline = await checkIsOffline();
    if (isOffline) {
      developer.log('Device appears offline; continuing in limited mode.', name: 'WEAFRICA.Bootstrap');
    }

    await SettingsController.instance.load();
    await UserService.instance.load();
    await LikedTracksStore.instance.load();

    if (firebaseInitialized) {
      try {
        await NotificationService.instance.initialize();
        await SubscriptionsController.instance.initialize();
        unawaited(JourneyService.instance.logEvent(eventType: 'app_open'));
      } catch (e, st) {
        developer.log(
          'Notification initialization failed (non-critical)',
          name: 'WEAFRICA.Bootstrap',
          error: e,
          stackTrace: st,
        );
      }
    }

    onProgress?.call(BootstrapProgress.stage5);
    await DeviceCapabilityService.instance.checkCapabilities();
  }

  stopwatch.stop();
  developer.log(
    'Bootstrap completed in ${stopwatch.elapsedMilliseconds}ms '
    '(supabase=${supabaseInitialized ? 'ok' : 'fail'}, firebase=${firebaseInitialized ? 'ok' : 'fail'})',
    name: 'WEAFRICA.Bootstrap',
  );

  return AppBootstrapResult(
    firebaseInitError: firebaseInitError,
    supabaseInitError: supabaseInitialized ? null : (supabaseInitError ?? Exception('Supabase initialization failed')),
    deviceReady: true,
    initializationTimeMs: stopwatch.elapsedMilliseconds,
    offlineMode: false,
  );
}

Future<void> _runDeferredBootstrapTasks({
  required bool firebaseInitialized,
}) async {
  // Keep everything best-effort and non-blocking for first paint.
  try {
    await SettingsController.instance.load();
  } catch (_) {
    // ignore
  }

  try {
    await UserService.instance.load();
  } catch (_) {
    // ignore
  }

  try {
    await LikedTracksStore.instance.load();
  } catch (_) {
    // ignore
  }

  if (firebaseInitialized) {
    try {
      await NotificationService.instance.initialize();
      await SubscriptionsController.instance.initialize();
      unawaited(JourneyService.instance.logEvent(eventType: 'app_open'));
    } catch (_) {
      // ignore
    }
  }

  // Live/stream readiness should not block opening the app.
  try {
    await DeviceCapabilityService.instance.checkCapabilities();
  } catch (_) {
    // ignore
  }
}
