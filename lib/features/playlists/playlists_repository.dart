import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/models/song_model.dart';
import '../tracks/track.dart';
import 'playlist.dart';

@immutable
class PlaylistSongRow {
  const PlaylistSongRow({
    required this.playlistId,
    required this.songId,
    required this.position,
    required this.song,
  });

  final String playlistId;
  final String songId;
  final int position;
  final Song song;
}

@immutable
class PlaylistTrackRow {
  const PlaylistTrackRow({
    required this.playlistId,
    required this.trackId,
    required this.position,
    required this.track,
  });

  final String playlistId;
  final String trackId;
  final int position;
  final Track track;
}

class PlaylistsRepository {
  PlaylistsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _deviceUserIdKey = 'playlists_device_user_idv1';

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  // Stable namespace UUID for deriving UUIDv5 values from arbitrary strings.
  // (Randomly generated once for this app; do not change or users will lose access
  // to previously created playlists when the DB expects UUID user_id.)
  static const String _userNamespaceUuid = 'c7b3b92f-2f0b-4d86-8b32-3a8f2d9c1e21';

  Future<String> _getOrCreateUserId() async {
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    if (firebaseUid != null && firebaseUid.trim().isNotEmpty) return firebaseUid;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUserIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final created = _uuidV4();
    await prefs.setString(_deviceUserIdKey, created);
    return created;
  }

  bool _looksLikeUuid(String value) => _uuidRegex.hasMatch(value.trim());

  List<int> _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '').toLowerCase();
    if (hex.length != 32) {
      throw ArgumentError.value(uuid, 'uuid', 'Invalid UUID format');
    }
    final out = <int>[];
    for (var i = 0; i < 32; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  String _bytesToUuid(List<int> bytes) {
    String b(int v) => v.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(b).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  /// Derive a UUIDv5 from an arbitrary string.
  ///
  /// Useful if the Supabase column `playlists.user_id` is UUID in some
  /// environments but the app identity is a Firebase UID (non-UUID).
  String _uuidV5(String name, {required String namespaceUuid}) {
    final namespaceBytes = _uuidToBytes(namespaceUuid);
    final nameBytes = utf8.encode(name);
    final hash = sha1.convert([...namespaceBytes, ...nameBytes]).bytes;
    final bytes = hash.sublist(0, 16);

    // Set version to 5.
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    // Set variant to RFC 4122.
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return _bytesToUuid(bytes);
  }

  String _formatPostgrestError(PostgrestException e) {
    final message = e.message.trim();
    final lower = message.toLowerCase();

    if (lower.contains('relation') && lower.contains('playlists') && lower.contains('does not exist')) {
      return 'Playlists table is missing in Supabase. Apply the SQL in tool/supabase_schema.sql (PLAYLISTS section) and try again.';
    }

    if (lower.contains('row-level security') || lower.contains('rls') || lower.contains('permission denied')) {
      return 'Playlists are blocked by Supabase security (RLS/privileges). Apply grants/policies in tool/supabase_schema.sql and try again.';
    }

    if (lower.contains('invalid input syntax') && lower.contains('type uuid')) {
      return 'This Supabase database expects a UUID user id, but the app is sending a Firebase/device id string. Update the DB schema (set playlists.user_id to TEXT as in tool/supabase_schema.sql) or keep using UUID user ids.';
    }

    // Default: keep it concise but useful.
    final details = (e.details ?? '').toString().trim();
    final hint = (e.hint ?? '').toString().trim();
    final parts = <String>[message];
    if (details.isNotEmpty) parts.add(details);
    if (hint.isNotEmpty) parts.add(hint);
    return parts.join('\n');
  }

  bool _isUuidTypeMismatch(Object e) {
    if (e is! PostgrestException) return false;
    final lower = e.message.toLowerCase();
    return lower.contains('invalid input syntax') && lower.contains('type uuid');
  }

  Future<List<Playlist>> fetchMyPlaylists() async {
    final rawUserId = await _getOrCreateUserId();

    Future<List<Playlist>> run(String userId) async {
      final rows = await _client
          .from('playlists')
          .select('id,user_id,name,cover_url,created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
      return list.map(Playlist.fromSupabase).toList(growable: false);
    }

    try {
      return await run(rawUserId);
    } on PostgrestException catch (e) {
      // If the DB column is UUID but we sent a Firebase UID (non-UUID), retry
      // with a stable derived UUID so the app remains usable.
      if (_isUuidTypeMismatch(e) && !_looksLikeUuid(rawUserId)) {
        try {
          final derived = _uuidV5(rawUserId, namespaceUuid: _userNamespaceUuid);
          return await run(derived);
        } on PostgrestException catch (e2) {
          throw Exception(_formatPostgrestError(e2));
        }
      }
      throw Exception(_formatPostgrestError(e));
    }
  }

  Future<Playlist> createPlaylist({required String name, String? coverUrl}) async {
    final rawUserId = await _getOrCreateUserId();

    Future<Playlist> run(String userId) async {
      final rows = await _client
          .from('playlists')
          .insert({
            'user_id': userId,
            'name': name,
            'cover_url': coverUrl,
          })
          .select('id,user_id,name,cover_url,created_at')
          .limit(1);

      final row = (rows as List).cast<Map<String, dynamic>>().first;
      return Playlist.fromSupabase(row);
    }

    try {
      return await run(rawUserId);
    } on PostgrestException catch (e) {
      if (_isUuidTypeMismatch(e) && !_looksLikeUuid(rawUserId)) {
        try {
          final derived = _uuidV5(rawUserId, namespaceUuid: _userNamespaceUuid);
          return await run(derived);
        } on PostgrestException catch (e2) {
          throw Exception(_formatPostgrestError(e2));
        }
      }
      throw Exception(_formatPostgrestError(e));
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _client.from('playlists').delete().eq('id', playlistId);
  }

  Future<List<PlaylistSongRow>> fetchPlaylistSongs(String playlistId) async {
    final rows = await _client
        .from('playlist_songs')
        .select(
          'playlist_id,song_id,position,songs(id,title,thumbnail_url,thumbnail,image_url,audio_url,duration,duration_seconds,artists(name))',
        )
        .eq('playlist_id', playlistId)
        .order('position', ascending: true)
        .order('created_at', ascending: true);

    final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();

    return list.map((row) {
      final songMap = row['songs'];
      if (songMap is! Map<String, dynamic>) {
        throw StateError('playlist_songs row missing embedded songs data');
      }

      return PlaylistSongRow(
        playlistId: row['playlist_id']?.toString() ?? playlistId,
        songId: row['song_id']?.toString() ?? '',
        position: (row['position'] is num)
            ? (row['position'] as num).toInt()
            : int.tryParse(row['position']?.toString() ?? '') ?? 0,
        song: Song.fromJson(songMap),
      );
    }).toList(growable: false);
  }

  Future<List<PlaylistTrackRow>> fetchPlaylistTracks(String playlistId) async {
    final rows = await _client
        .from('playlist_tracks')
        .select(
          'playlist_id,track_id,position,tracks(id,title,artist,audio_url,artwork_url,country,genre,duration_ms,created_at)',
        )
        .eq('playlist_id', playlistId)
        .order('position', ascending: true)
        .order('created_at', ascending: true);

    final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();

    return list.map((row) {
      final trackMap = row['tracks'];
      if (trackMap is! Map<String, dynamic>) {
        throw StateError('playlist_tracks row missing embedded tracks data');
      }

      return PlaylistTrackRow(
        playlistId: row['playlist_id']?.toString() ?? playlistId,
        trackId: row['track_id']?.toString() ?? '',
        position: (row['position'] is num)
            ? (row['position'] as num).toInt()
            : int.tryParse(row['position']?.toString() ?? '') ?? 0,
        track: Track.fromSupabase(trackMap),
      );
    }).toList(growable: false);
  }

  Future<void> addSongToPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final last = (await _client
        .from('playlist_songs')
        .select('position')
        .eq('playlist_id', playlistId)
        .order('position', ascending: false)
        .limit(1)) as List<dynamic>;

    int nextPos = 0;
    if (last.isNotEmpty) {
      final row = last.first;
      if (row is Map<String, dynamic>) {
        final pos = row['position'];
        nextPos = (pos is num) ? pos.toInt() + 1 : (int.tryParse('$pos') ?? -1) + 1;
        if (nextPos < 0) nextPos = 0;
      }
    }

    await _client.from('playlist_songs').insert({
      'playlist_id': playlistId,
      'song_id': songId,
      'position': nextPos,
    });
  }

  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final last = (await _client
        .from('playlist_tracks')
        .select('position')
        .eq('playlist_id', playlistId)
        .order('position', ascending: false)
        .limit(1)) as List<dynamic>;

    int nextPos = 0;
    if (last.isNotEmpty) {
      final row = last.first;
      if (row is Map<String, dynamic>) {
        final pos = row['position'];
        nextPos = (pos is num) ? pos.toInt() + 1 : (int.tryParse('$pos') ?? -1) + 1;
        if (nextPos < 0) nextPos = 0;
      }
    }

    await _client.from('playlist_tracks').insert({
      'playlist_id': playlistId,
      'track_id': trackId,
      'position': nextPos,
    });
  }

  Future<void> removeSongFromPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    await _client
        .from('playlist_songs')
        .delete()
        .eq('playlist_id', playlistId)
        .eq('song_id', songId);
  }

  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    await _client
        .from('playlist_tracks')
        .delete()
        .eq('playlist_id', playlistId)
        .eq('track_id', trackId);
  }

  Future<void> reorderPlaylistTracks({
    required String playlistId,
    required List<String> orderedTrackIds,
  }) async {
    // Persist Spotify-style manual ordering.
    // Uses the unique constraint (playlist_id, track_id) to upsert positions.
    final updates = <Map<String, dynamic>>[];
    for (var i = 0; i < orderedTrackIds.length; i++) {
      updates.add({
        'playlist_id': playlistId,
        'track_id': orderedTrackIds[i],
        'position': i,
      });
    }

    if (updates.isEmpty) return;

    await _client
        .from('playlist_tracks')
        .upsert(updates, onConflict: 'playlist_id,track_id');
  }

  Future<List<Song>> fetchSongPickerChoices({int limit = 60}) async {
    final rows = await _client
        .from('songs')
        .select(
          'id,title,thumbnail_url,thumbnail,image_url,audio_url,duration,duration_seconds,artists(name),created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
    return list.map(Song.fromJson).toList(growable: false);
  }

  Future<List<Track>> fetchTrackPickerChoices({int limit = 80}) async {
    final rows = await _client
        .from('songs')
        .select('id,title,artist,audio_url,artwork_url,country,genre,duration_ms,created_at')
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Track.fromSupabase)
        .toList(growable: false);
  }

  String _uuidV4() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String b(int v) => v.toRadixString(16).padLeft(2, '0');

    final s = bytes.map(b).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  @override
  String toString() => jsonEncode({'repo': 'PlaylistsRepository'});
}
