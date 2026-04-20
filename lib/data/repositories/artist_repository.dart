import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Data access for the `artists` table.
class ArtistRepository {
  ArtistRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> getArtistByUserId(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return null;

    try {
      final rows = await _client
          .from('artists')
          .select('*')
          .or('user_id.eq.$uid,firebase_uid.eq.$uid')
          .limit(1);
      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      return list.isEmpty ? null : list.first;
    } catch (e) {
      debugPrint('❌ ArtistRepository.getArtistByUserId failed: $e');
      return null;
    }
  }

  /// Best-effort stats for the creator dashboard.
  ///
  /// The schema for streams/plays varies by deployment; we read a few common
  /// columns and fall back to 0.
  Future<Map<String, dynamic>> getArtistStats(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return const <String, dynamic>{};

    int totalStreams = 0;
    int totalBattles = 0;

    try {
      final rows = await _client.from('artists').select('*').eq('id', id).limit(1);
      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      final row = list.isEmpty ? null : list.first;

      int readInt(String key) {
        final v = row?[key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }

      totalStreams = readInt('total_streams');
      if (totalStreams == 0) totalStreams = readInt('streams');
      if (totalStreams == 0) totalStreams = readInt('total_plays');
      if (totalStreams == 0) totalStreams = readInt('plays_count');
    } catch (e) {
      debugPrint('⚠️ ArtistRepository.getArtistStats artist row read failed: $e');
    }

    try {
      // Best-effort battle count; column names vary.
      // Prefer competitor1_id/competitor2_id; fall back to artist1_id/artist2_id.
      final rows = await _client
          .from('battles')
          .select('id,competitor1_id,competitor2_id,artist1_id,artist2_id')
          .or('competitor1_id.eq.$id,competitor2_id.eq.$id,artist1_id.eq.$id,artist2_id.eq.$id')
          .order('created_at', ascending: false)
          .limit(500);
      totalBattles = (rows as List<dynamic>).length;
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e)) {
        try {
          final rows = await _client
              .from('battles')
              .select('id,dj_id,participant_ids')
              .or('dj_id.eq.$id,participant_ids.cs.{${_pgArrayValue(id)}}')
              .order('created_at', ascending: false)
              .limit(500);
          totalBattles = (rows as List<dynamic>).length;
        } catch (e2) {
          debugPrint('⚠️ ArtistRepository.getArtistStats battle count fallback failed: $e2');
          totalBattles = 0;
        }
      } else {
        debugPrint('⚠️ ArtistRepository.getArtistStats battle count failed: $e');
        totalBattles = 0;
      }
    } catch (e) {
      debugPrint('⚠️ ArtistRepository.getArtistStats battle count failed: $e');
      totalBattles = 0;
    }

    return <String, dynamic>{
      'total_streams': totalStreams,
      'total_battles': totalBattles,
    };
  }

  bool _isMissingColumnError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('column') && msg.contains('does not exist');
  }

  String _pgArrayValue(String value) {
    return value.replaceAll('"', '\\"');
  }
}
