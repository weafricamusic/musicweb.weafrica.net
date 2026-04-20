import 'package:supabase_flutter/supabase_flutter.dart';

import 'live_event.dart';

class LiveEventsRepository {
  LiveEventsRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<LiveEvent>> list({
    required String kind,
    required int limit,
    required String countryCode,
  }) async {
    final k = kind.trim().toLowerCase();
    final cc = countryCode.trim().toUpperCase();

    var q = _client.from('events').select('*');
    if (cc.isNotEmpty) {
      q = q.eq('country_code', cc);
    }
    if (k.isNotEmpty) {
      q = q.eq('kind', k);
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
    final mapped = list.map(LiveEvent.fromSupabase).toList(growable: false);
    if (k.isEmpty) {
      return mapped.where((e) => e.kind.trim().toLowerCase() != 'live').toList(growable: false);
    }
    return mapped.where((e) => e.kind.trim().toLowerCase() == k).toList(growable: false);
  }

  Future<LiveEvent?> getById(String eventId) async {
    final id = eventId.trim();
    if (id.isEmpty) return null;

    final row = await _client
        .from('events')
        .select('*')
        .eq('id', id)
        .maybeSingle();

    if (row is Map<String, dynamic>) {
      return LiveEvent.fromSupabase(row);
    }
    return null;
  }
}
