import 'package:supabase_flutter/supabase_flutter.dart';

import 'creator_profile.dart';

class FriendlyException implements Exception {
  const FriendlyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CreatorsRepository {
  CreatorsRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Never _rethrowFriendly(Object error, {required CreatorRole role}) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      final details = (error.details ?? '').toString();

      bool containsAny(String haystack, List<String> needles) {
        for (final n in needles) {
          if (haystack.contains(n)) return true;
        }
        return false;
      }

      final isMissingTable =
          message.contains('does not exist') ||
          details.contains('42P01') ||
          message.contains('schema cache') ||
          message.contains('could not find the table');
      if (isMissingTable) {
        throw const FriendlyException(
          'Supabase table "creator_profiles" not found. Apply the CREATOR PROFILES section in tool/supabase_schema.sql.',
        );
      }

      final isMissingColumn =
          containsAny(message, ['column', 'field']) && containsAny(message, ['does not exist', 'not found']);
      if (isMissingColumn) {
        throw const FriendlyException(
          'Supabase schema mismatch for "creator_profiles". Re-apply the CREATOR PROFILES section in tool/supabase_schema.sql (or update the app query/columns to match your table).',
        );
      }

      if (message.contains('permission denied') || message.contains('row level security')) {
        throw const FriendlyException(
          'Supabase blocked the query (RLS/policy). Add a SELECT policy/grant for anon/authenticated on "creator_profiles".',
        );
      }

      if (containsAny(message, ['jwt', 'invalid api key', 'apikey', 'anon key', 'unauthorized', 'forbidden'])) {
        throw const FriendlyException(
          'Supabase auth failed. Double-check SUPABASE_URL and SUPABASE_ANON_KEY passed via --dart-define-from-file.',
        );
      }

      throw FriendlyException('Supabase error loading ${role.id} profiles: ${error.message}');
    }

    throw error;
  }

  Future<List<CreatorProfile>> list({
    required CreatorRole role,
    int limit = 60,
    String query = '',
    String? countryCode,
  }) async {
    final q = query.trim();
    final qLower = q.toLowerCase();
    final cc = (countryCode ?? '').trim().toUpperCase();

    try {
      final requestLimit = q.isNotEmpty
          ? ((limit * 4) > 240 ? 240 : (limit * 4))
          : limit;

      var builder = _client
          .from('creator_profiles')
          // Use '*' to be tolerant of schema variations (missing/extra columns).
          .select('*')
          .eq('role', role.id);

      if (cc.isNotEmpty) {
        builder = builder.eq('country_code', cc);
      }

      final rows = await builder.order('created_at', ascending: false).limit(requestLimit);

      final List<dynamic> rowList = switch (rows) {
        final List<dynamic> l => l,
        final Map<String, dynamic> m => <dynamic>[m],
        _ => const <dynamic>[],
      };

      final items = rowList
          .whereType<Map<String, dynamic>>()
          .map(CreatorProfile.fromSupabase)
          .where((p) {
            final name = p.displayName.trim();
            return name.isNotEmpty && !_looksLikeUuid(name);
          });

      final filtered = q.isEmpty
          ? items
          : items.where(
              (p) => p.displayName.toLowerCase().contains(qLower),
            );

      return filtered.take(limit).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e, role: role);
    }
  }

  Future<List<CreatorProfile>> listFeaturedArtists({
    int limit = 18,
    String query = '',
    String? countryCode,
  }) async {
    final q = query.trim();
    final qLower = q.toLowerCase();
    final cc = (countryCode ?? '').trim().toUpperCase();

    try {
      final requestLimit = (limit * 6) > 200 ? 200 : (limit * 6);

      final rows = await _client
          .from('featured_artists')
          .select('artist_id,country_code,priority,created_at')
          .order('priority', ascending: false)
          .order('created_at', ascending: false)
          .limit(requestLimit);

      final featured = <Map<String, dynamic>>[];
      for (final item in rows) {
        featured.add(item.cast<String, dynamic>());
      }

      if (featured.isEmpty) return const <CreatorProfile>[];

      final scored = <({String id, bool matchesCountry})>[];
      for (final f in featured) {
        final artistId = (f['artist_id'] ?? '').toString().trim();
        if (artistId.isEmpty) continue;

        final rawCc = (f['country_code'] ?? '').toString().trim().toUpperCase();
        final matchesCountry = cc.isEmpty ? true : (rawCc.isEmpty || rawCc == cc);
        if (!matchesCountry) continue;

        scored.add((id: artistId, matchesCountry: rawCc == cc));
      }

      if (scored.isEmpty) return const <CreatorProfile>[];

      // Prefer exact country matches first, then global (NULL country_code).
      final ids = <String>[];
      final seen = <String>{};
      for (final item in scored.where((e) => e.matchesCountry)) {
        if (seen.add(item.id)) ids.add(item.id);
        if (ids.length >= limit) break;
      }
      if (ids.length < limit) {
        for (final item in scored.where((e) => !e.matchesCountry)) {
          if (seen.add(item.id)) ids.add(item.id);
          if (ids.length >= limit) break;
        }
      }

      if (ids.isEmpty) return const <CreatorProfile>[];

      final artists = await _client.from('artists').select('*').inFilter('id', ids);

      final byId = <String, Map<String, dynamic>>{};
      for (final item in artists) {
        final map = item.cast<String, dynamic>();
        final id = (map['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        byId[id] = map;
      }

      final out = <CreatorProfile>[];
      for (final id in ids) {
        final row = byId[id];
        if (row == null) continue;

        final display = _pickArtistDisplayName(row);
        if (display.isEmpty || _looksLikeUuid(display)) continue;
        if (q.isNotEmpty && !display.toLowerCase().contains(qLower)) continue;

        out.add(
          CreatorProfile(
            id: id,
            userId: _asNullableText(row['firebase_uid']) ?? _asNullableText(row['user_id']),
            role: CreatorRole.artist,
            displayName: display,
            avatarUrl: _asNullableText(row['profile_image']) ?? _asNullableText(row['avatar_url']),
            bio: _asNullableText(row['bio']),
          ),
        );
      }

      return out.take(limit).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e, role: CreatorRole.artist);
    }
  }

  static String _pickArtistDisplayName(Map<String, dynamic> row) {
    const keys = <String>[
      'display_name',
      'stage_name',
      'artist_name',
      'name',
      'full_name',
      'username',
      'title',
      'artist',
      'stage',
      'email',
    ];
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String? _asNullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static bool _looksLikeUuid(String value) => _uuidPattern.hasMatch(value.trim());
}
