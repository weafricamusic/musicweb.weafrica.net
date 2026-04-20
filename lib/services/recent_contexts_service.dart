import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/tracks/track.dart';
import '../home/models/song_model.dart';

@immutable
class RecentContext {
  const RecentContext({
    required this.id,
    required this.userId,
    required this.contextType,
    required this.contextId,
    required this.title,
    required this.source,
    required this.lastPlayedAt,
    this.imageUrl,
  });

  final String id;
  final String userId;
  final String contextType;
  final String contextId;
  final String title;
  final String source;
  final DateTime lastPlayedAt;
  final String? imageUrl;

  Uri? get imageUri => imageUrl == null ? null : Uri.tryParse(imageUrl!);

  static RecentContext fromSupabase(Map<String, dynamic> row) {
    return RecentContext(
      id: row['id']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      contextType: row['context_type']?.toString() ?? '',
      contextId: row['context_id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      imageUrl: row['image_url']?.toString(),
      source: row['source']?.toString() ?? 'music',
      lastPlayedAt: DateTime.tryParse(row['last_played_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class RecentContextsService {
  RecentContextsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static final RecentContextsService instance = RecentContextsService();

  final SupabaseClient _client;

  static const String _deviceUserIdKey = 'recent_contexts_device_user_idv1';
  static const String _malawiLovePlaysKeyPrefix = 'recent_contexts_malawi_love_plays_v1:';

  Future<String> _getOrCreateUserId() async {
    final authId = _client.auth.currentUser?.id;
    if (authId != null && authId.trim().isNotEmpty) return authId;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUserIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final created = _uuidV4();
    await prefs.setString(_deviceUserIdKey, created);
    return created;
  }

  Future<void> upsertContext({
    required String contextType,
    required String contextId,
    required String title,
    Uri? imageUri,
    String source = 'music',
    DateTime? lastPlayedAt,
  }) async {
    final userId = await _getOrCreateUserId();

    final payload = <String, dynamic>{
      'user_id': userId,
      'context_type': contextType,
      'context_id': contextId,
      'title': title,
      'image_url': imageUri?.toString(),
      'source': source,
      'last_played_at': (lastPlayedAt ?? DateTime.now()).toIso8601String(),
    };

    try {
      await _client.from('recent_contexts').upsert(
            payload,
            onConflict: 'user_id,context_id',
          );
      if (kDebugMode) {
        debugPrint('✅ recent_contexts upsert ok: $contextType/$contextId (user=$userId)');
      }
    } on PostgrestException catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ recent_contexts upsert failed: ${e.message}');
        debugPrint('   details: ${e.details}');
        debugPrint('   hint: ${e.hint}');
        debugPrint('   payload: $payload');
        debugPrintStack(stackTrace: st, maxFrames: 50);
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ recent_contexts upsert failed: $e');
        debugPrint('   payload: $payload');
        debugPrintStack(stackTrace: st, maxFrames: 50);
      }
      rethrow;
    }
  }

  Future<List<RecentContext>> fetchQuickAccess({
    String source = 'music',
    int limit = 8,
  }) async {
    final userId = await _getOrCreateUserId();

    final rows = await _client
        .from('recent_contexts')
        .select('id,user_id,context_type,context_id,title,image_url,source,last_played_at')
        .eq('user_id', userId)
        .eq('source', source)
        .order('last_played_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(RecentContext.fromSupabase)
        .where((c) => c.title.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> recordTrackPlay(Track track) async {
    final id = track.id?.trim();
    if (id == null || id.isEmpty) return;

    await upsertContext(
      contextType: 'track',
      contextId: id,
      title: track.title,
      imageUri: track.artworkUri,
      source: 'music',
    );

    unawaited(
      _recordPlayEventBestEffort(
        contentType: 'track',
        contentId: id,
      ).catchError((e, st) {
        if (kDebugMode) {
          if (e is PostgrestException && e.code == 'PGRST205') {
            // play_events table not installed in this environment; ignore.
            return;
          }
          debugPrint('play_events recordTrackPlay failed: $e');
          debugPrintStack(stackTrace: st, maxFrames: 30);
        }
      }),
    );

    await _maybeTriggerMalawiLove(track);
  }

  Future<void> recordSongPlay(Song song) async {
    final id = song.id.trim();
    if (id.isEmpty) return;

    final imageUri = song.imageUrl == null ? null : Uri.tryParse(song.imageUrl!);

    await upsertContext(
      contextType: 'song',
      contextId: id,
      title: song.title,
      imageUri: imageUri,
      source: 'music',
    );

    unawaited(
      _recordPlayEventBestEffort(
        contentType: 'song',
        contentId: id,
      ).catchError((e, st) {
        if (kDebugMode) {
          if (e is PostgrestException && e.code == 'PGRST205') {
            // play_events table not installed in this environment; ignore.
            return;
          }
          debugPrint('play_events recordSongPlay failed: $e');
          debugPrintStack(stackTrace: st, maxFrames: 30);
        }
      }),
    );

    await _maybeTriggerMalawiLoveFromSongsTable(songId: id, fallbackImageUri: imageUri);
  }

  Future<void> _recordPlayEventBestEffort({
    required String contentType,
    required String contentId,
  }) async {
    final userId = await _getOrCreateUserId();

    String? artistId;
    try {
      // songs is public-readable for active content (per migrations).
      final rows = await _client
          .from('songs')
          .select('artist_id')
          .eq('id', contentId)
          .limit(1);
      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
      if (list.isNotEmpty) {
        final raw = list.first['artist_id'];
        final s = raw?.toString().trim();
        if (s != null && s.isNotEmpty) artistId = s;
      }
    } catch (_) {
      // ignore
    }

    final payload = <String, dynamic>{
      'content_type': contentType,
      'content_id': contentId,
      'user_id': userId,
      ...?(artistId == null ? null : {'artist_id': artistId}),
    };

    try {
      await _client.from('play_events').insert(payload);
      return;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.message.toLowerCase().contains("could not find the table 'public.play_events'")) {
        // play_events table is optional in some deployments; treat as a no-op.
        return;
      }
      // Compatibility fallback: older play_events schema without artist_id.
      final msg = (e.message).toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();
      final missingArtistCol = (msg.contains('artist_id') || details.contains('artist_id')) &&
          (msg.contains('could not find') || msg.contains('column') || msg.contains('schema cache') || details.contains('schema cache'));
      if (!missingArtistCol) rethrow;
    }

    try {
      await _client.from('play_events').insert({
        'content_type': contentType,
        'content_id': contentId,
        'user_id': userId,
      });
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.message.toLowerCase().contains("could not find the table 'public.play_events'")) {
        // play_events table is optional in some deployments; treat as a no-op.
        return;
      }
      rethrow;
    }
  }

  Future<void> _maybeTriggerMalawiLoveFromSongsTable({
    required String songId,
    Uri? fallbackImageUri,
  }) async {
    try {
      final rows = await _client
          .from('songs')
          .select('id,country,genre')
          .eq('id', songId)
          .limit(1);

      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      if (list.isEmpty) return;
      final row = list.first;

      final country = row['country']?.toString().trim();
      final genre = row['genre']?.toString().trim();
      if (country == null || genre == null) return;

      final isMalawi = country.toLowerCase() == 'malawi';
      final isLove = genre.toLowerCase() == 'love';
      if (!isMalawi || !isLove) return;

      // Reuse the same counter logic as Track-based trigger.
      final prefs = await SharedPreferences.getInstance();
      final userId = await _getOrCreateUserId();
      final key = '$_malawiLovePlaysKeyPrefix$userId';

      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(hours: 24));

      final raw = prefs.getString(key);
      final parsed = <DateTime>[];
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              final dt = DateTime.tryParse(item?.toString() ?? '');
              if (dt != null && dt.isAfter(cutoff)) {
                parsed.add(dt);
              }
            }
          }
        } catch (_) {
          // Ignore corrupted payload.
        }
      }

      parsed.add(now);
      await prefs.setString(
        key,
        jsonEncode(parsed.map((d) => d.toIso8601String()).toList(growable: false)),
      );

      if (parsed.length < 3) return;

      await upsertContext(
        contextType: 'smart_playlist',
        contextId: 'malawi_love_auto',
        title: 'Malawi Love Songs',
        imageUri: fallbackImageUri,
        source: 'music',
      );
    } catch (_) {
      // songs table/columns may not exist in some environments; ignore.
    }
  }

  Future<void> _maybeTriggerMalawiLove(Track track) async {
    final country = track.country?.trim();
    final genre = track.genre?.trim();
    if (country == null || genre == null) return;

    final isMalawi = country.toLowerCase() == 'malawi';
    final isLove = genre.toLowerCase() == 'love';
    if (!isMalawi || !isLove) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = await _getOrCreateUserId();
    final key = '$_malawiLovePlaysKeyPrefix$userId';

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));

    final raw = prefs.getString(key);
    final parsed = <DateTime>[];

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final dt = DateTime.tryParse(item?.toString() ?? '');
            if (dt != null && dt.isAfter(cutoff)) {
              parsed.add(dt);
            }
          }
        }
      } catch (_) {
        // Ignore corrupted payload.
      }
    }

    parsed.add(now);

    await prefs.setString(
      key,
      jsonEncode(parsed.map((d) => d.toIso8601String()).toList(growable: false)),
    );

    if (parsed.length < 3) return;

    await upsertContext(
      contextType: 'smart_playlist',
      contextId: 'malawi_love_auto',
      title: 'Malawi Love Songs',
      imageUri: track.artworkUri,
      source: 'music',
    );
  }

  static String _uuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));

    // Version 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Variant 10xxxxxx
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
