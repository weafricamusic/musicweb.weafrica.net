import 'package:supabase_flutter/supabase_flutter.dart';

class BattleRepository {
  BattleRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> getActiveBattles(
    String artistId, {
    String? firebaseUid,
    int limit = 20,
  }) async {
    final id = artistId.trim();
    final uid = (firebaseUid ?? '').trim();
    if (id.isEmpty && uid.isEmpty) return const <Map<String, dynamic>>[];

    final rows = await _queryByCompetitorColumns(
      artistId: id,
      firebaseUid: uid,
      limit: limit,
    );
    return _filterActive(rows);
  }

  List<Map<String, dynamic>> _filterActive(List<Map<String, dynamic>> list) {
    return list.where((b) {
      final status = (b['status'] ?? '').toString().toLowerCase();
      if (status.isEmpty) return true;
      return status != 'completed' && status != 'ended' && status != 'finished';
    }).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _queryByCompetitorColumns({
    required String artistId,
    required String firebaseUid,
    required int limit,
  }) async {
    final parts = <String>[];
    if (artistId.isNotEmpty) {
      parts.addAll([
        'competitor1_id.eq.$artistId',
        'competitor2_id.eq.$artistId',
        'artist1_id.eq.$artistId',
        'artist2_id.eq.$artistId',
      ]);
    }
    if (firebaseUid.isNotEmpty) {
      parts.addAll([
        'competitor1_id.eq.$firebaseUid',
        'competitor2_id.eq.$firebaseUid',
        'artist1_id.eq.$firebaseUid',
        'artist2_id.eq.$firebaseUid',
      ]);
    }
    return _queryWithOr(parts, limit: limit);
  }

  Future<List<Map<String, dynamic>>> _queryWithOr(List<String> parts, {required int limit}) async {
    if (parts.isEmpty) return const <Map<String, dynamic>>[];

    final rows = await _client
        .from('battles')
        .select('*')
        .or(parts.join(','))
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  String _pgArrayValue(String value) {
    return value.replaceAll('"', '\\"');
  }

  Future<bool> acceptBattle(String battleId, String trackId) async {
    final id = battleId.trim();
    if (id.isEmpty) return false;

    await _client.from('battles').update({
      'status': 'accepted',
      'accepted_track_id': trackId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
    return true;
  }

  Future<bool> declineBattle(String battleId) async {
    final id = battleId.trim();
    if (id.isEmpty) return false;

    await _client.from('battles').update({
      'status': 'declined',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
    return true;
  }
}
