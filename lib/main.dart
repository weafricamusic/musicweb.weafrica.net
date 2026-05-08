import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/auth_gate.dart';
import 'audio/audio.dart';

void main() async {
  // Track repeated overflow errors to avoid spamming the console.
  final _seenOverflows = <String, int>{};
  const _maxOverflowPrints = 3;

  // Override error handling to catch and display errors
  FlutterError.onError = (FlutterErrorDetails details) {
    final desc = details.toString();
    final isOverflow = desc.contains('overflow') ||
        desc.contains('RenderFlex') ||
        desc.contains('debug_overflow_indicator');

    if (isOverflow) {
      final key = details.exception?.toString() ?? desc;
      final count = (_seenOverflows[key] ?? 0) + 1;
      _seenOverflows[key] = count;
      if (count > _maxOverflowPrints) return; // Suppress after N occurrences
      print('⚠️ FLUTTER OVERFLOW (#$count): $key');
      if (count == 1) {
        // Print stack only once per unique overflow
        debugPrintStack();
      }
      return;
    }

    print('❌ FLUTTER ERROR: ${details.exception}');
    print('❌ Stack trace: ${details.stack}');
    debugPrintStack();
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    print('❌ PLATFORM ERROR: $error');
    print('❌ Stack: $stack');
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();

  print("🚀 APP STARTING - main() called");

  try {
    // Initialize Supabase first
    print("📡 Initializing Supabase...");
    await Supabase.initialize(
      url: 'https://nxkutpjdoidfwpkjbwcm.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54a3V0cGpkb2lkZndwa2pid2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxMDA2NjEsImV4cCI6MjA4MjY3NjY2MX0.eQ5Z5lyYEXxepG-XzdSmPOqb6zCxI-qEnXLmXtl6K4U',
    );
    print("✅ Supabase initialized successfully");

    try {
        print("🔥 Initializing Firebase...");
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print("✅ Firebase initialized successfully");
      } on FirebaseException catch (e) {
        if (e.code == 'duplicate-app') {
          print("ℹ️ Firebase already initialized, continuing...");
        } else {
          rethrow;
        }
      }

    print("🎵 Initializing Audio...");
    await initWeAfricaAudio();
    print("✅ Audio initialized successfully");

    print("🏠 Running MyApp...");
    runApp(const ProviderScope(child: MyApp()));
  } catch (e, stackTrace) {
    print("❌ FATAL ERROR during initialization: $e");
    print("❌ Stack trace: $stackTrace");
    
    // Show error UI instead of blank screen
    runApp(ErrorApp(error: e, stackTrace: stackTrace));
  }
}

// Error display widget
class ErrorApp extends StatelessWidget {
  final dynamic error;
  final StackTrace stackTrace;

  const ErrorApp({super.key, required this.error, required this.stackTrace});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeAfrica Error',
      home: Scaffold(
        backgroundColor: Colors.red[900],
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 80),
                const SizedBox(height: 24),
                Text(
                  'App Failed to Start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Error: ${error.toString()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Check the console for more details',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    // Attempt to restart
                    SystemNavigator.pop();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red[900],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print("🏠 MyApp.build - building AppShell");
    return MaterialApp(
      title: 'WeAfrica Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}
