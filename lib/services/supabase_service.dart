import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase service for the app
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  
  /// Initialize Supabase - call this in main.dart before runApp
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }
  
  /// Get current authenticated user
  static User? get currentUser => client.auth.currentUser;
  
  /// Get current user ID
  static String? get currentUserId => currentUser?.id;
  
  /// Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;
}