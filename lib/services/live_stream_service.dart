import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveStreamService {
  final SupabaseClient supabase;

  LiveStreamService({SupabaseClient? client}) : supabase = client ?? Supabase.instance.client;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isValidUuid(String value) => _uuidRegex.hasMatch(value.trim());

  static const String _logTag = 'LIVE_DEBUG';

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('$_logTag $message');
  }

  /// Debug helper: prints whether the given Firebase UID can be resolved
  /// to an `artists` or `djs` UUID in Supabase.
  Future<void> debugCheckFirebaseUser(String firebaseUid) async {
    final uid = firebaseUid.trim();
    if (uid.isEmpty) {
      _log('debugCheckFirebaseUser: empty firebaseUid');
      return;
    }

    _log('debugCheckFirebaseUser: firebaseUid=$uid');

    Future<void> checkTable(String table) async {
      try {
        final row = await supabase
            .from(table)
            .select('id,name,firebase_uid,user_id')
            .or('firebase_uid.eq.$uid,user_id.eq.$uid')
            .limit(1)
            .maybeSingle();

        if (row == null) {
          _log('debugCheckFirebaseUser: not found in $table');
          return;
        }

        final id = row['id']?.toString();
        final name = row['name']?.toString();
        final firebase = row['firebase_uid']?.toString();
        final userId = row['user_id']?.toString();
        _log('debugCheckFirebaseUser: found in $table id=$id name=$name firebase_uid=$firebase user_id=$userId');
      } catch (e) {
        _log('debugCheckFirebaseUser: $table query failed: $e');
      }
    }

    await checkTable('artists');
    await checkTable('djs');
    await checkTable('users');
  }

  /// Debug helper: confirms Supabase connectivity for this app session.
  Future<void> debugPingSupabase() async {
    try {
      await supabase.from('live_streams').select('id').limit(1);
      _log('debugPingSupabase: live_streams select OK');
    } catch (e) {
      _log('debugPingSupabase: live_streams select FAILED: $e');
    }
  }

  /// Best-effort resolver for deployments that use Firebase Auth but store
  /// creator identities in Supabase tables (e.g. `artists` / `djs`).
  ///
  /// Returns a UUID string suitable for `live_streams.host_id`.
  Future<String?> resolveHostUuidFromFirebaseUid(
    String firebaseUid, {
    String? preferredTable,
  }) async {
    final uid = firebaseUid.trim();
    if (uid.isEmpty) return null;
    if (isValidUuid(uid)) return uid;

    _log('resolveHostUuidFromFirebaseUid: uid=$uid preferredTable=${preferredTable ?? ""}');

    Future<String?> lookup(String table) async {
      try {
        _log('resolveHostUuidFromFirebaseUid: lookup $table for uid=$uid');
        final row = await supabase
            .from(table)
            .select('id,firebase_uid,user_id')
            .or('firebase_uid.eq.$uid,user_id.eq.$uid')
            .limit(1)
            .maybeSingle();

        final id = row?['id']?.toString().trim();
        if (id != null && id.isNotEmpty && isValidUuid(id)) {
          _log('resolveHostUuidFromFirebaseUid: found uuid=$id in $table');
          return id;
        }
        _log('resolveHostUuidFromFirebaseUid: no uuid in $table (row=${row == null ? "null" : "present"})');
      } catch (_) {
        // Best-effort.
        _log('resolveHostUuidFromFirebaseUid: lookup failed for $table');
      }
      return null;
    }

    final order = <String>[];
    void addOnce(String? table) {
      final t = (table ?? '').trim();
      if (t.isEmpty) return;
      if (order.contains(t)) return;
      order.add(t);
    }

    addOnce(preferredTable);
    addOnce('artists');
    addOnce('djs');
    addOnce('users');

    for (final table in order) {
      final id = await lookup(table);
      if (id != null) return id;
    }

    _log('resolveHostUuidFromFirebaseUid: could not resolve uuid for uid=$uid');
    return null;
  }

  /// Convenience wrapper: accepts Firebase UID (or a UUID) and ensures
  /// `live_streams.host_id` is written as a UUID.
  Future<Map<String, dynamic>> createLiveStreamForFirebaseHost({
    required String firebaseUid,
    required String hostName,
    required String channelName,
    required String title,
    String? thumbnailUrl,
    String? preferredTable,
  }) async {
    final hostUuid = await resolveHostUuidFromFirebaseUid(
      firebaseUid,
      preferredTable: preferredTable,
    );

    if (hostUuid == null) {
      throw StateError('Could not resolve a UUID host_id for this user');
    }

    _log('createLiveStreamForFirebaseHost: resolved hostUuid=$hostUuid for firebaseUid=${firebaseUid.trim()}');

    return createLiveStream(
      hostId: hostUuid,
      hostName: hostName,
      channelName: channelName,
      title: title,
      thumbnailUrl: thumbnailUrl,
    );
  }

  // Create a live stream when host goes live
  Future<Map<String, dynamic>> createLiveStream({
    required String hostId,
    required String hostName,
    required String channelName,
    required String title,
    String? thumbnailUrl,
  }) async {
    final host = hostId.trim();
    if (!isValidUuid(host)) {
      throw FormatException('host_id must be a UUID string', hostId);
    }

    _log('createLiveStream: host_id=$host channel=$channelName title=${title.trim()}');

    final streamData = {
      'host_id': host,
      'host_name': hostName,
      'channel_name': channelName,
      'title': title,
      'thumbnail_url': (thumbnailUrl ?? '').trim(),
      'status': 'live',
      'viewers': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await supabase.from('live_streams').insert(streamData).select().single();
    final mapped = (response as Map).map((k, v) => MapEntry(k.toString(), v));
    _log('createLiveStream: inserted id=${mapped['id'] ?? ''} status=${mapped['status'] ?? ''}');
    return mapped;
  }

  // Get all active live streams
  Future<List<Map<String, dynamic>>> getActiveLiveStreams() async {
    final response = await supabase
        .from('live_streams')
        .select()
        .eq('status', 'live')
        .order('created_at', ascending: false);

    return (response as List)
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }

  // Update viewer count
  Future<void> updateViewerCount(String streamId, int count) async {
    _log('updateViewerCount: streamId=$streamId count=$count');
    await supabase.from('live_streams').update({'viewers': count}).eq('id', streamId);
  }

  // End live stream
  Future<void> endLiveStream(String streamId) async {
    _log('endLiveStream: streamId=$streamId');
    await supabase
        .from('live_streams')
        .update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', streamId);
  }

  // Get stream by channel name
  Future<Map<String, dynamic>?> getStreamByChannel(String channelName) async {
    final response = await supabase
        .from('live_streams')
        .select()
        .eq('channel_name', channelName)
        .eq('status', 'live')
        .maybeSingle();

    if (response == null) return null;
    return (response as Map).map((k, v) => MapEntry(k.toString(), v));
  }

  // Check if user is already live
  Future<bool> isUserLive(String hostId) async {
    final host = hostId.trim();
    final uuid = isValidUuid(host) ? host : await resolveHostUuidFromFirebaseUid(host);
    if (uuid == null || uuid.isEmpty) return false;

    final response = await supabase
        .from('live_streams')
        .select('id')
        .eq('host_id', uuid)
        .eq('status', 'live')
        .maybeSingle();

    return response != null;
  }
}
