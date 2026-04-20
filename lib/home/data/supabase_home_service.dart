import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/media/artwork_resolver.dart';
import '../models/song_model.dart';

class SupabaseHomeService {
  SupabaseHomeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Song>> fetchContinueListening({int limit = 10}) async {
    // Prefer your `songs` table; fall back to the app's `tracks` table.
    try {
      final rows = await _songsBaseQuery()
          .order('created_at', ascending: false)
          .limit(limit);
      return _mapSongsFromSongsTable(rows, isTrending: false);
    } catch (e) {
      if (e is PostgrestException) {
        final msg = e.message.toLowerCase();
        final details = (e.details ?? '').toString();
        if (msg.contains('does not exist') || details.contains('42P01')) {
          // Fall back.
        } else {
          // If your schema doesn't have some filters/columns, retry without them.
          try {
            final rows = await _client
                .from('songs')
                .select('id,title,thumbnail_url,thumbnail,image_url,artwork_url,audio_url,duration,duration_seconds,artist_id,artists(name),created_at')
                .order('created_at', ascending: false)
                .limit(limit);
            return _mapSongsFromSongsTable(rows, isTrending: false);
          } catch (_) {
            rethrow;
          }
        }
      }
    }

    final rows = await _client
        .from('tracks')
        .select(
          'id,title,artist,audio_url,duration_ms,artwork_url,thumbnail_url,thumbnail,image_url,created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    return _mapSongsFromTracksTable(rows, isTrending: false);
  }

  Future<List<Song>> fetchTrendingSongs({int limit = 10}) async {
    debugPrint('📊 fetchTrendingSongs called with limit: $limit');
    
    Future<List<Map<String, dynamic>>> runQuery({
      required bool includeIsPublic,
      required bool includeApproved,
      required bool includePlaysCount,
    }) async {
      // FIXED: Added artwork_url to select statements
      final select = includePlaysCount
          ? 'id,title,thumbnail_url,thumbnail,image_url,artwork_url,audio_url,duration,duration_seconds,artist_id,artists(name),plays_count,created_at'
          : 'id,title,thumbnail_url,thumbnail,image_url,artwork_url,audio_url,duration,duration_seconds,artist_id,artists(name),created_at';

      debugPrint('   Query select: $select');
      
      dynamic q = _client.from('songs').select(select).eq('is_active', true);
      if (includeApproved) q = q.eq('approved', true);
      if (includeIsPublic) q = q.eq('is_public', true);

      q = includePlaysCount
          ? q.order('plays_count', ascending: false)
          : q.order('created_at', ascending: false);

      final rowsRaw = await q.limit(limit);
      final rows = (rowsRaw as List).whereType<Map<String, dynamic>>().toList();
      debugPrint('   Got ${rows.length} rows');
      if (rows.isNotEmpty) {
        debugPrint('   First row artwork_url: ${rows.first['artwork_url']}');
      }

      return rows;
    }

    // Try the strictest query first; progressively relax if columns are missing.
    try {
      final rows = await runQuery(includeIsPublic: true, includeApproved: true, includePlaysCount: true);
      return _mapSongsFromSongsTable(rows, isTrending: true);
    } on PostgrestException catch (e) {
      debugPrint('⚠️ First query failed: ${e.message}');
      final msg = e.message.toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();

      // Missing plays_count: use latest ordering.
      final missingPlaysCount = (msg.contains('column') || msg.contains('could not find')) && (msg.contains('plays_count') || details.contains('plays_count'));
      if (missingPlaysCount) {
        debugPrint('   Missing plays_count, retrying without it');
        try {
          final rows = await runQuery(includeIsPublic: true, includeApproved: true, includePlaysCount: false);
          return _mapSongsFromSongsTable(rows, isTrending: true);
        } on PostgrestException catch (_) {
          // Continue to broader fallbacks below.
        }
      }

      // Missing is_public column: retry without it.
      final missingIsPublic = (msg.contains('column') || msg.contains('could not find')) && (msg.contains('is_public') || details.contains('is_public'));
      if (missingIsPublic) {
        debugPrint('   Missing is_public, retrying without it');
        try {
          final rows = await runQuery(includeIsPublic: false, includeApproved: true, includePlaysCount: !missingPlaysCount);
          return _mapSongsFromSongsTable(rows, isTrending: true);
        } on PostgrestException catch (_) {
          // Continue to broader fallbacks below.
        }
      }

      // Missing approved column (or other drift): retry with just is_active.
      debugPrint('   Trying final fallback query');
      try {
        final rows = await runQuery(includeIsPublic: false, includeApproved: false, includePlaysCount: false);
        return _mapSongsFromSongsTable(rows, isTrending: true);
      } catch (_) {
        rethrow;
      }
    }
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _songsBaseQuery() {
    // FIXED: Added artwork_url to base query
    return _client
        .from('songs')
        .select(
          'id,title,thumbnail_url,thumbnail,image_url,artwork_url,audio_url,duration,duration_seconds,artist_id,artists(name),plays_count,created_at',
        )
        .eq('is_active', true)
        .eq('approved', true);
  }

  List<Song> _mapSongsFromSongsTable(Object rows, {required bool isTrending}) {
    final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    if (kDebugMode) {
      debugPrint('🎵 _mapSongsFromSongsTable mapping ${list.length} rows (isTrending: $isTrending)');
      if (list.isNotEmpty) {
        debugPrint('   Sample row keys: ${list.first.keys}');
        debugPrint('   Sample row artwork_url: ${list.first['artwork_url']}');
      }
    }

    return list.map((item) {
      final id = item['id']?.toString() ?? '';
      final title = (item['title'] ?? 'Unknown Title').toString();

      // Artist from joined table.
      String artistName = 'Unknown Artist';
      final artists = item['artists'];
      if (artists is Map) {
        artistName = (artists['name'] ?? artistName).toString();
      } else if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map) {
          artistName = (first['name'] ?? artistName).toString();
        }
      }

      final durationRaw = item['duration'] ?? item['duration_seconds'];
      final seconds = durationRaw is num
          ? durationRaw.toInt()
          : int.tryParse(durationRaw?.toString() ?? '');

      // FIXED: Added artwork_url to the list of keys
      String? pickThumbnail() {
        final value = pickArtworkValue(
          item,
          keys: const [
            'artwork_url',  // Now first priority
            'artworkUrl',
            'thumbnail_url',
            'thumbnailUrl',
            'thumbnail',
            'image_url',
            'imageUrl',
          ],
        );
        if (kDebugMode && value != null) {
          debugPrint('   ✅ Picked thumbnail: $value');
        }
        return value;
      }

      final song = Song(
        id: id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : id,
        title: title,
        artist: artistName,
        thumbnail: pickThumbnail(),
        audioUrl: (item['audio_url'] ?? item['audioUrl'] ?? item['url'])?.toString(),
        duration: Duration(seconds: seconds ?? 180),
        isTrending: isTrending,
      );
      
      if (kDebugMode && song.thumbnail == null) {
        debugPrint('   ⚠️ Song "${song.title}" has no thumbnail');
      }
      
      return song;
    }).toList(growable: false);
  }

  List<Song> _mapSongsFromTracksTable(Object rows, {required bool isTrending}) {
    final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    if (kDebugMode) {
      debugPrint('🎵 _mapSongsFromTracksTable mapping ${list.length} rows');
      if (list.isNotEmpty) debugPrint('   Sample row: ${list.first}');
    }

    return list.map((item) {
      final id = item['id']?.toString() ?? '';
      final title = (item['title'] ?? 'Unknown Title').toString();
      final artist = (item['artist'] ?? 'Unknown Artist').toString();

      String? pickThumbnail() {
        return pickArtworkValue(
          item,
          keys: const [
            'artwork_url',
            'artworkUrl',
            'thumbnail_url',
            'thumbnailUrl',
            'thumbnail',
            'image_url',
            'imageUrl',
          ],
        );
      }

      final audioUrl = (item['audio_url'] ?? item['audioUrl'] ?? item['url'])?.toString();

      final durationRaw = item['duration_ms'];
      final ms = durationRaw is num
          ? durationRaw.toInt()
          : int.tryParse(durationRaw?.toString() ?? '');

      return Song(
        id: id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : id,
        title: title,
        artist: artist,
        thumbnail: pickThumbnail(),
        audioUrl: audioUrl,
        duration: Duration(milliseconds: ms ?? 180000),
        isTrending: isTrending,
      );
    }).toList(growable: false);
  }
}