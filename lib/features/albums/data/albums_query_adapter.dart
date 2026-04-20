import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles small schema drift between environments.
///
/// Keep all column fallbacks here (not in the repository/model).
class AlbumsQueryAdapter {
  const AlbumsQueryAdapter();

  Future<List<Map<String, dynamic>>> latestPublishedRows(
    SupabaseClient client, {
    required int limit,
  }) async {
    Object rows;

    try {
      rows = await client
          .from('albums')
          .select('*')
          .or('status.eq.published,is_published.eq.true,published_at.not.is.null')
          .order('published_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();

      final statusMissing = _mentionsColumnMissing(msg, details, 'status');
      final isPublishedMissing = _mentionsColumnMissing(msg, details, 'is_published');
      final publishedAtMissing = _mentionsColumnMissing(msg, details, 'published_at');

      developer.log(
        'AlbumsQueryAdapter primary query failed; applying fallback',
        name: 'WEAFRICA.Albums',
        error: e,
      );

      // Fallback 1: no status
      if (statusMissing && !isPublishedMissing && !publishedAtMissing) {
        rows = await client
            .from('albums')
            .select('*')
            .or('is_published.eq.true,published_at.not.is.null')
            .order('published_at', ascending: false)
            .order('created_at', ascending: false)
            .limit(limit);
      }
      // Fallback 2: no is_published
      else if (isPublishedMissing && !publishedAtMissing) {
        rows = await client
            .from('albums')
            .select('*')
            .not('published_at', 'is', null)
            .order('published_at', ascending: false)
            .order('created_at', ascending: false)
            .limit(limit);
      }
      // Fallback 3: no published_at
      else if (publishedAtMissing && !isPublishedMissing) {
        rows = await client
            .from('albums')
            .select('*')
            .or('status.eq.published,is_published.eq.true')
            .order('created_at', ascending: false)
            .limit(limit);
      }
      // Fallback 4: minimal
      else {
        rows = await client.from('albums').select('*').order('created_at', ascending: false).limit(limit);
      }
    }

    return (rows as List)
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }

  bool _mentionsColumnMissing(String msg, String details, String column) {
    return (msg.contains('could not find') || msg.contains('column') || msg.contains('schema cache') || msg.contains('does not exist')) &&
        (msg.contains(column) || details.contains(column));
  }
}
