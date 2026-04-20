import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/content_access_policy.dart';
import '../subscriptions/subscriptions_controller.dart';
import 'track.dart';

class TracksRepository {
  TracksRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const Duration _cacheMaxAge = Duration(hours: 12);
  static const int _maxPlayablePrefetch = 240;

  String _cacheKeyTrending(String countryCode) => 'tracks.cache.trending.${countryCode.trim().toUpperCase()}.v1';
  String _cacheKeyNew(String countryCode) => 'tracks.cache.new.${countryCode.trim().toUpperCase()}.v1';

  int _prefetchLimit(int limit) {
    if (limit <= 0) return 0;
    final expanded = limit <= 40 ? limit * 3 : limit * 2;
    return expanded > _maxPlayablePrefetch ? _maxPlayablePrefetch : expanded;
  }

  List<Map<String, dynamic>> _mapsFromRows(Object rows) {
    return (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList(growable: false);
  }

  num _readNum(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final raw = row[key];
      if (raw is num) return raw;
      final parsed = num.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  double _recencyScore(Map<String, dynamic> row) {
    final raw = row['created_at'] ?? row['createdAt'];
    final createdAt = raw == null ? null : DateTime.tryParse(raw.toString());
    if (createdAt == null) return 0;

    final age = DateTime.now().difference(createdAt);
    if (age.isNegative) return 30;
    if (age.inDays >= 30) return 0;
    return (30 - age.inDays).toDouble();
  }

  double _feedScore(Map<String, dynamic> row) {
    final likes = _readNum(row, const ['likes_count', 'likes']).toDouble();
    final plays = _readNum(row, const ['plays_count', 'plays', 'streams']).toDouble();
    final promoBonus = _readNum(row, const ['promotion_bonus']).toDouble();
    return likes + (plays * 0.5) + _recencyScore(row) + promoBonus;
  }

  void _sortRowsForFeed(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final scoreDiff = _feedScore(b).compareTo(_feedScore(a));
      if (scoreDiff != 0) return scoreDiff;

      final aCreated = DateTime.tryParse((a['created_at'] ?? '').toString());
      final bCreated = DateTime.tryParse((b['created_at'] ?? '').toString());
      if (aCreated != null && bCreated != null) {
        return bCreated.compareTo(aCreated);
      }
      return 0;
    });
  }

  Future<List<Map<String, dynamic>>> _attachActivePromotions(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    final ids = rows
        .map((row) => (row['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return rows;

    final promotionsByContent = <String, Map<String, dynamic>>{};

    void mergePromotionRows(List<dynamic> rawRows) {
      for (final item in rawRows.whereType<Map>()) {
        final row = item.cast<String, dynamic>();
        final contentId = (row['content_id'] ?? row['target_id'] ?? '').toString().trim();
        if (contentId.isEmpty) continue;

        final contentType = (row['content_type'] ?? 'song').toString().trim().toLowerCase();
        if (contentType.isNotEmpty && contentType != 'song' && contentType != 'track') {
          continue;
        }

        final current = promotionsByContent[contentId];
        final nextBonus = _readNum(row, const ['promotion_bonus', 'promotion_score_bonus']).toDouble();
        final currentBonus = current == null
            ? double.negativeInfinity
            : _readNum(current, const ['promotion_bonus', 'promotion_score_bonus']).toDouble();
        if (current == null || nextBonus >= currentBonus) {
          promotionsByContent[contentId] = row;
        }
      }
    }

    final viewRows = await _client
        .from('active_content_promotions')
        .select('content_id,content_type,plan,end_date,featured_badge,promotion_bonus')
        .inFilter('content_id', ids);
    mergePromotionRows(viewRows as List<dynamic>);

    if (promotionsByContent.isEmpty) return rows;

    return rows.map((row) {
      final contentId = (row['id'] ?? '').toString().trim();
      final promotion = promotionsByContent[contentId];
      if (promotion == null) return row;

      final merged = Map<String, dynamic>.from(row);
      final plan = (promotion['plan'] ?? '').toString().trim().toLowerCase();
      final bonus = _readNum(promotion, const ['promotion_bonus', 'promotion_score_bonus']).toDouble();
      merged['is_promoted'] = true;
      merged['promotion_plan'] = plan.isEmpty ? 'basic' : plan;
      merged['promotion_end_date'] = promotion['end_date'] ?? promotion['ends_at'];
      merged['promotion_badge'] = promotion['featured_badge'];
      merged['promotion_bonus'] = bonus;
      return merged;
    }).toList(growable: false);
  }

  List<Track> _playableTracksFromMaps(
    Iterable<Map<String, dynamic>> rows, {
    required int limit,
  }) {
    if (limit <= 0) return const <Track>[];

    final entitlements = SubscriptionsController.instance.entitlements;
    final userKey = FirebaseAuth.instance.currentUser?.uid;

    final out = <Track>[];
    final seen = <String>{};
    for (final row in rows) {
      final track = Track.fromSupabase(row);
      final uri = track.audioUri;
      if (uri == null) continue;

      final key = track.id ?? uri.toString();
      if (!seen.add(key)) continue;

      final access = ContentAccessPolicy.decide(
        entitlements: entitlements,
        contentId: key,
        isExclusive: track.isExclusive,
        userKey: userKey,
      );
      if (!access.allowed) continue;

      out.add(track);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<Track> _playableTracksFromRows(Object rows, {required int limit}) {
    return _playableTracksFromMaps(
      _mapsFromRows(rows),
      limit: limit,
    );
  }

  Future<List<Track>> getCachedTrendingByCountry(String countryCode, {int limit = 40}) {
    return _readCachedList(_cacheKeyTrending(countryCode), limit: limit);
  }

  Future<List<Track>> getCachedNewReleasesByCountry(String countryCode, {int limit = 40}) {
    return _readCachedList(_cacheKeyNew(countryCode), limit: limit);
  }

  Future<void> _writeCachedList(String key, List<Track> tracks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'savedAt': DateTime.now().toIso8601String(),
        'items': tracks.take(60).map((t) => t.toCacheMap()).toList(growable: false),
      };
      await prefs.setString(key, jsonEncode(payload));
    } catch (_) {
      // ignore cache failures
    }
  }

  Future<List<Track>> _readCachedList(String key, {int limit = 40}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return const <Track>[];

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <Track>[];

      final savedAtRaw = decoded['savedAt']?.toString();
      final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
      if (savedAt == null) return const <Track>[];
      if (DateTime.now().difference(savedAt) > _cacheMaxAge) return const <Track>[];

      final items = decoded['items'];
      if (items is! List) return const <Track>[];

      return _playableTracksFromMaps(
        items.whereType<Map>().map((item) => item.cast<String, dynamic>()),
        limit: limit,
      );
    } catch (_) {
      return const <Track>[];
    }
  }

  Never _rethrowFriendly(Object error) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      final details = (error.details ?? '').toString();
      final hint = (error.hint ?? '').toString();

      if (message.contains('does not exist') || details.contains('42P01')) {
        throw StateError(
          'Supabase table "songs" not found. Ensure your database has a public.songs table (or update the app to target your media table) and apply the latest schema SQL/migrations.',
        );
      }

      if (message.contains('permission denied') ||
          message.contains('row level security')) {
        throw StateError(
          'Supabase blocked the query (RLS/policy). Add a SELECT policy for anon on table "songs" (or your media table) and try again.',
        );
      }

      if (message.contains('jwt') || message.contains('invalid api key')) {
        throw StateError(
          'Supabase auth failed. Double-check SUPABASE_URL and SUPABASE_ANON_KEY passed via --dart-define-from-file.',
        );
      }

      final extra = [details, hint].where((s) => s.trim().isNotEmpty).join('\n');
      throw StateError(
        'Supabase error loading tracks: ${error.message}${extra.isEmpty ? '' : "\n$extra"}',
      );
    }

    throw error;
  }

  Future<List<Track>> latest({int limit = 40}) async {
    final fetchLimit = _prefetchLimit(limit);
    late final Object rows;
    try {
      rows = await _client
          .from('songs')
          .select('*')
          .order('created_at', ascending: false)
          .limit(fetchLimit);
    } catch (e) {
      _rethrowFriendly(e);
    }

    final preparedRows = await _attachActivePromotions(_mapsFromRows(rows));
    _sortRowsForFeed(preparedRows);
    return _playableTracksFromMaps(preparedRows, limit: limit);
  }

  Future<List<Track>> search(String query, {int limit = 40}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return latest(limit: limit);

    final fetchLimit = _prefetchLimit(limit);

    final q = trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_');

    late final Object rows;
    try {
      rows = await _client
          .from('songs')
          .select('*,artists(name,stage_name,artist_name)')
          .or('title.ilike.%$q%,artists.name.ilike.%$q%,artists.stage_name.ilike.%$q%')
          .order('created_at', ascending: false)
          .limit(fetchLimit);
    } catch (e) {
      _rethrowFriendly(e);
    }

    final preparedRows = await _attachActivePromotions(_mapsFromRows(rows));
    return _playableTracksFromMaps(preparedRows, limit: limit);
  }

  Future<Track?> getById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    late final Object rows;
    try {
      rows = await _client
          .from('songs')
          .select('*')
          .eq('id', trimmed)
          .limit(1);
    } catch (e) {
      _rethrowFriendly(e);
    }

    final list = await _attachActivePromotions(_mapsFromRows(rows));
    if (list.isEmpty) return null;
    return Track.fromSupabase(list.first);
  }

  Future<List<Track>> byCountry(
    String countryCode, {
    int limit = 40,
  }) async {
    final cc = countryCode.trim().toUpperCase();
    if (cc.isEmpty) return const <Track>[];
    final fetchLimit = _prefetchLimit(limit);

    late final Object rows;
    try {
      rows = await _client
          .from('songs')
          .select('*')
          .eq('country_code', cc)
          .order('created_at', ascending: false)
          .limit(fetchLimit);
    } catch (e) {
      _rethrowFriendly(e);
    }

    final preparedRows = await _attachActivePromotions(_mapsFromRows(rows));
    return _playableTracksFromMaps(preparedRows, limit: limit);
  }

  Future<List<Track>> byGenre(
    String genre, {
    int limit = 40,
  }) async {
    final g = genre.trim();
    if (g.isEmpty) return const <Track>[];

    final fetchLimit = _prefetchLimit(limit);

    final q = g.replaceAll('%', r'\%').replaceAll('_', r'\_');

    late final Object rows;
    try {
      rows = await _client
          .from('songs')
          .select('*')
          .ilike('genre', '%$q%')
          .order('created_at', ascending: false)
          .limit(fetchLimit);
    } catch (e) {
      _rethrowFriendly(e);
    }

    return _playableTracksFromRows(rows, limit: limit);
  }

  Future<List<Track>> trendingByCountry(
    String countryCode, {
    int limit = 40,
  }) async {
    final cc = countryCode.trim().toUpperCase();
    if (cc.isEmpty) return const <Track>[];
    final fetchLimit = _prefetchLimit(limit);

    late final Object rows;
    try {
      rows = await _client
          .from('songs')
          .select('*')
          .eq('country_code', cc)
          .order('plays_count', ascending: false)
          .limit(fetchLimit);
    } catch (e) {
      _rethrowFriendly(e);
    }

    final preparedRows = await _attachActivePromotions(_mapsFromRows(rows));
    _sortRowsForFeed(preparedRows);
    final list = _playableTracksFromMaps(preparedRows, limit: limit);

    unawaited(_writeCachedList(_cacheKeyTrending(cc), list));
    return list;
  }

  Future<List<Track>> newReleasesByCountry(
    String countryCode, {
    int limit = 40,
  }) async {
    // "New" is modeled as recent releases. We keep this tolerant and simply
    // order by created_at.
    final list = await byCountry(countryCode, limit: limit);
    unawaited(_writeCachedList(_cacheKeyNew(countryCode), list));
    return list;
  }
}
