import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/media/artwork_resolver.dart';
import 'live_discovery_service.dart';

class LiveFeedDiscoverService {
  LiveFeedDiscoverService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        _discovery = LiveDiscoveryService(client: client ?? Supabase.instance.client);

  final SupabaseClient _client;
  final LiveDiscoveryService _discovery;

  Future<List<Map<String, dynamic>>> fetchLiveNow({int limit = 20}) async {
    final budget = limit <= 2 ? limit : (limit / 2).ceil();
    final battleLimit = budget;
    final soloLimit = limit - battleLimit;

    final battles = await _discovery.listLiveNowBattles(limit: battleLimit);
    final solos = await _discovery.listLiveNowSolo(limit: soloLimit <= 0 ? battleLimit : soloLimit);

    final combined = <Map<String, dynamic>>[
      ...battles,
      ...solos,
    ];

    int readInt(Map<String, dynamic> row, String key) {
      final v = row[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '').toString()) ?? 0;
    }

    DateTime? readTime(Map<String, dynamic> row, String key) {
      final raw = (row[key] ?? '').toString().trim();
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    combined.sort((a, b) {
      final scoreA = readInt(a, 'trending_score');
      final scoreB = readInt(b, 'trending_score');
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);

      final viewersA = readInt(a, 'viewer_count');
      final viewersB = readInt(b, 'viewer_count');
      if (viewersA != viewersB) return viewersB.compareTo(viewersA);

      final timeA = readTime(a, 'started_at') ?? readTime(a, 'created_at');
      final timeB = readTime(b, 'started_at') ?? readTime(b, 'created_at');
      if (timeA == null && timeB == null) return 0;
      if (timeA == null) return 1;
      if (timeB == null) return -1;
      return timeB.compareTo(timeA);
    });

    if (combined.length <= limit) return combined;
    return combined.take(limit).toList(growable: false);
  }

  /// Fetches active battles for the battles tab
  Future<List<Map<String, dynamic>>> fetchActiveBattles({int limit = 10}) async {
    try {
      final rowsRaw = await _client
          .from('live_battles')
          .select('''
            id,
            channel_id,
            competitor1_id,
            competitor2_id,
            competitor1_name,
            competitor2_name,
            competitor1_type,
            competitor2_type,
            competitor1_score,
            competitor2_score,
            viewer_count,
            status,
            duration_seconds,
            created_at,
            competitor1_image:profiles!competitor1_id(avatar_url),
            competitor2_image:profiles!competitor2_id(avatar_url)
          ''')
          .eq('status', 'active')
          .order('viewer_count', ascending: false)
          .limit(limit);
      
      final rows = (rowsRaw as List).whereType<Map<String, dynamic>>().toList();
      
      return rows.map((row) {
        final competitor1Image = row['competitor1_image'] is Map 
            ? row['competitor1_image']['avatar_url'] 
            : null;
        final competitor2Image = row['competitor2_image'] is Map 
            ? row['competitor2_image']['avatar_url'] 
            : null;
            
        return {
          'id': row['id'],
          'channel_id': row['channel_id'],
          'competitor1_id': row['competitor1_id'],
          'competitor2_id': row['competitor2_id'],
          'competitor1_name': row['competitor1_name'],
          'competitor2_name': row['competitor2_name'],
          'competitor1_type': row['competitor1_type'],
          'competitor2_type': row['competitor2_type'],
          'competitor1_score': row['competitor1_score'] ?? 0,
          'competitor2_score': row['competitor2_score'] ?? 0,
          'competitor1_image': competitor1Image,
          'competitor2_image': competitor2Image,
          'viewer_count': row['viewer_count'] ?? 0,
          'status': row['status'],
          'duration_seconds': row['duration_seconds'],
          'created_at': row['created_at'],
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetches upcoming battles scheduled for later
  Future<List<Map<String, dynamic>>> fetchUpcomingBattles({int limit = 10}) async {
    try {
      final rowsRaw = await _client
          .from('live_battles')
          .select('''
            id,
            title,
            competitor1_id,
            competitor2_id,
            competitor1_name,
            competitor2_name,
            scheduled_at,
            prize,
            status
          ''')
          .eq('status', 'scheduled')
          .gt('scheduled_at', DateTime.now().toIso8601String())
          .order('scheduled_at', ascending: true)
          .limit(limit);
      
      final rows = (rowsRaw as List).whereType<Map<String, dynamic>>().toList();
      return rows.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Fetches top creators who are currently live or recently active
  Future<List<Map<String, dynamic>>> fetchTopCreators({int limit = 10}) async {
    try {
      // First get currently live creators
      final liveRowsRaw = await _client
          .from('live_sessions')
          .select('''
            host_id,
            host_name,
            host_type,
            viewer_count,
            category,
            is_live,
            host_profile:profiles!host_id(avatar_url, genre)
          ''')
          .eq('is_live', true)
          .order('viewer_count', ascending: false)
          .limit(limit);
      
      final liveRows = (liveRowsRaw as List).whereType<Map<String, dynamic>>().toList();
      
      return liveRows.map((row) {
        final profile = row['host_profile'] is Map ? row['host_profile'] : {};
        return {
          'id': row['host_id'],
          'name': row['host_name'],
          'type': row['host_type'],
          'genre': profile['genre'] ?? row['category'] ?? 'Artist',
          'avatar_url': profile['avatar_url'],
          'is_live': true,
          'viewer_count': row['viewer_count'] ?? 0,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetches lightweight "discover" content items for the vertical feed.
  ///
  /// Returned rows are normalized for UI consumption:
  /// - title, artist, thumbnail, plays, likes
  Future<List<Map<String, dynamic>>> fetchContent({int limit = 30}) async {
    const select =
        'id,title,artist,artists(name),thumbnail_url,thumbnail,image_url,artwork_url,plays_count,likes,likes_count,created_at';

    final rowsRaw = await _client
        .from('songs')
        .select(select)
        .eq('is_active', true)
        .eq('approved', true)
        .eq('is_public', true)
        .order('plays_count', ascending: false)
        .limit(limit);
    final rows = (rowsRaw as List).whereType<Map<String, dynamic>>().toList();

    String pickArtist(Map<String, dynamic> row) {
      final direct = (row['artist'] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;

      final artists = row['artists'];
      if (artists is Map) {
        final name = (artists['name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
      if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map) {
          final name = (first['name'] ?? '').toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
      return 'Unknown Artist';
    }

    int readInt(Map<String, dynamic> row, List<String> keys) {
      for (final key in keys) {
        final v = row[key];
        if (v == null) continue;
        if (v is int) return v;
        if (v is num) return v.toInt();
        final parsed = int.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
      return 0;
    }

    String? pickThumb(Map<String, dynamic> row) {
      return pickArtworkValue(
        row,
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

    return rows.map((row) {
      final id = (row['id'] ?? '').toString().trim();
      final title = (row['title'] ?? '').toString().trim();

      return <String, dynamic>{
        'id': id,
        'title': title.isNotEmpty ? title : 'Untitled',
        'artist': pickArtist(row),
        'thumbnail': pickThumb(row),
        'plays': readInt(row, const ['plays_count', 'plays']),
        'likes': readInt(row, const ['likes_count', 'likes']),
      };
    }).toList(growable: false);
  }
}