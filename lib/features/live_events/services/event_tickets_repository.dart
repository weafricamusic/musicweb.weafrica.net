import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event_ticket_type.dart';

class EventTicketsRepository {
  EventTicketsRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<EventTicketType>> listByEventId({
    required String eventId,
    int limit = 20,
  }) async {
    final eid = eventId.trim();
    if (eid.isEmpty) return const <EventTicketType>[];

    try {
      final rows = await _client
          .from('event_tickets')
          .select('*')
          .eq('event_id', eid)
          .order('created_at', ascending: true)
          .limit(limit);

      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
      return list.map(EventTicketType.fromSupabase).toList(growable: false);
    } catch (e) {
      developer.log('EventTicketsRepository.listByEventId failed', error: e);
      return const <EventTicketType>[];
    }
  }
}
