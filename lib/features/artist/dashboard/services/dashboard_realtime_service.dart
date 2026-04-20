import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal realtime trigger service.
///
/// It does not try to be clever with per-field deltas; it simply emit a
/// debounced "something changed" signal so the UI/services can refresh.
class DashboardRealtimeService {
  DashboardRealtimeService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  RealtimeChannel? _channel;
  Timer? _debounce;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  void subscribe({required String artistId}) {
    unsubscribe();

    // Note: Table list is intentionally conservative to avoid missing data.
    // Add/remove tables as the backend schema evolves.
    _channel = _client.channel('public:artist_dashboard:$artistId');

    void ping() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        if (_changes.isClosed) return;
        _changes.add(null);
      });
    }

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'songs',
          callback: (_) => ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'videos',
          callback: (_) => ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => ping(),
        )
        .subscribe();
  }

  void unsubscribe() {
    _debounce?.cancel();
    _debounce = null;
    _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> dispose() async {
    unsubscribe();
    await _changes.close();
  }
}
