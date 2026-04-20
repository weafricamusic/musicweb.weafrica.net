import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef SupabaseRowCallback = void Function(Map<String, dynamic> row);

/// Thin convenience wrapper around [Supabase.instance.client].
///
/// Note: This app uses Firebase Auth for sign-in. Supabase Auth may be unset.
class SupabaseService {
  SupabaseService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  final List<RealtimeChannel> _channels = <RealtimeChannel>[];

  SupabaseClient get client => _client;

  User? get currentUser => _client.auth.currentUser;

  /// Subscribes to Postgres changes on a given table and invokes [onRow] with the
  /// best-effort record payload.
  ///
  /// Returns the created [RealtimeChannel] so callers can manage lifecycle.
  RealtimeChannel subscribeToTable(
    String table,
    SupabaseRowCallback onRow, {
    String schema = 'public',
    PostgresChangeEvent event = PostgresChangeEvent.all,
  }) {
    final channel = _client.channel('$schema:$table:${DateTime.now().millisecondsSinceEpoch}');

    channel.onPostgresChanges(
      event: event,
      schema: schema,
      table: table,
      callback: (payload) {
        final row = payload.newRecord.isNotEmpty
            ? payload.newRecord
            : (payload.oldRecord.isNotEmpty ? payload.oldRecord : const <String, dynamic>{});
        if (row.isEmpty) return;
        onRow(row);
      },
    );

    channel.subscribe();
    _channels.add(channel);
    return channel;
  }

  Future<void> unsubscribeAll() async {
    for (final c in _channels) {
      await c.unsubscribe();
    }
    _channels.clear();
  }
}
