import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fan messaging repository.
///
/// Newer deployments use `messages`. Some older docs/screens mention
/// `fan_messages`. We try both (best-effort) to keep the app resilient.
class FanRepository {
  FanRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> getMessages(
    String artistId, {
    String? firebaseUid,
    int limit = 50,
  }) async {
    final id = artistId.trim();
    final uid = (firebaseUid ?? '').trim();

    try {
      dynamic q = _client.from('messages').select('*');
      if (id.isNotEmpty) q = q.eq('artist_id', id);
      if (id.isEmpty && uid.isNotEmpty) q = q.eq('artist_uid', uid);
      final rows = await q.order('created_at', ascending: false).limit(limit);
      return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (e) {
      // Fallback to `fan_messages` schema from older builds.
      try {
        dynamic q = _client.from('fan_messages').select('*');
        if (id.isNotEmpty) q = q.eq('artist_id', id);
        if (id.isEmpty && uid.isNotEmpty) q = q.eq('artist_uid', uid);
        final rows = await q.order('created_at', ascending: false).limit(limit);
        return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false);
      } catch (e2) {
        debugPrint('❌ FanRepository.getMessages failed: $e / $e2');
        return const <Map<String, dynamic>>[];
      }
    }
  }

  Future<int> getUnreadCount(
    String artistId, {
    String? firebaseUid,
  }) async {
    final id = artistId.trim();
    final uid = (firebaseUid ?? '').trim();

    try {
      dynamic q = _client.from('messages').select('id');
      q = q.eq('read', false);
      if (id.isNotEmpty) q = q.eq('artist_id', id);
      if (id.isEmpty && uid.isNotEmpty) q = q.eq('artist_uid', uid);
      final rows = await q.limit(500);
      return (rows as List<dynamic>).length;
    } catch (e) {
      try {
        dynamic q = _client.from('fan_messages').select('id');
        q = q.eq('is_read', false);
        if (id.isNotEmpty) q = q.eq('artist_id', id);
        if (id.isEmpty && uid.isNotEmpty) q = q.eq('artist_uid', uid);
        final rows = await q.limit(500);
        return (rows as List<dynamic>).length;
      } catch (e2) {
        debugPrint('❌ FanRepository.getUnreadCount failed: $e / $e2');
        return 0;
      }
    }
  }

  Future<bool> markAsRead(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return false;

    try {
      await _client.from('messages').update({'is_read': true, 'read': true}).eq('id', id);
      return true;
    } catch (e) {
      try {
        await _client.from('fan_messages').update({'is_read': true}).eq('id', id);
        return true;
      } catch (e2) {
        debugPrint('❌ FanRepository.markAsRead failed: $e / $e2');
        return false;
      }
    }
  }

  Future<bool> sendReply(String messageId, String reply) async {
    final id = messageId.trim();
    if (id.isEmpty) return false;

    try {
      await _client.from('messages').update({'reply': reply}).eq('id', id);
      return true;
    } catch (e) {
      try {
        await _client.from('fan_messages').update({'reply': reply}).eq('id', id);
        return true;
      } catch (e2) {
        debugPrint('❌ FanRepository.sendReply failed: $e / $e2');
        return false;
      }
    }
  }
}
