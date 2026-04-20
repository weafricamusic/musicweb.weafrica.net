import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';

class AnnouncementsRepository {
  AnnouncementsRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Announcement>> listActive({int limit = 10}) async {
    try {
      final rows = await _client
          .from('announcements')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
      return list.map(Announcement.fromSupabase).toList(growable: false);
    } catch (e) {
      developer.log('AnnouncementsRepository.listActive failed', error: e);
      return const <Announcement>[];
    }
  }
}
