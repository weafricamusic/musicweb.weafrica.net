import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/utils/result.dart';
import '../../albums/models/album.dart';
import '../../albums/repositories/albums_repository.dart';
import '../../playlists/playlists_repository.dart';
import '../../subscriptions/subscriptions_controller.dart';
import '../../tracks/track.dart';
import '../../tracks/tracks_repository.dart';
import '../models/library_album.dart';
import '../models/library_playlist.dart';
import '../models/library_track.dart';
import 'library_download_service.dart';
import 'library_recent_service.dart';

class LibraryService {
  LibraryService({
    SupabaseClient? supabase,
    TracksRepository? tracksRepository,
    AlbumsRepository? albumsRepository,
    PlaylistsRepository? playlistsRepository,
    LibraryDownloadService? downloads,
    LibraryRecentService? recents,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _tracks = tracksRepository ?? TracksRepository(),
        _albums = albumsRepository ?? AlbumsRepository(),
        _playlists = playlistsRepository ?? PlaylistsRepository(),
        _downloads = downloads ?? LibraryDownloadService(),
        _recents = recents ?? LibraryRecentService();

  final SupabaseClient _supabase;
  final TracksRepository _tracks;
  final AlbumsRepository _albums;
  final PlaylistsRepository _playlists;
  final LibraryDownloadService _downloads;
  final LibraryRecentService _recents;

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  static const _likedTracksPrefsKey = 'liked_tracks';

  Future<Result<List<LibraryTrack>>> getLikedTracks({int limit = 50}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList(_likedTracksPrefsKey) ?? const <String>[];

      final ids = <String>[];
      for (final k in keys) {
        final trimmed = k.trim();
        if (!trimmed.startsWith('id:')) continue;
        final id = trimmed.substring(3).trim();
        if (id.isEmpty) continue;
        ids.add(id);
      }

      if (ids.isEmpty) return Result.success(const <LibraryTrack>[]);

      final unique = <String>[];
      final seen = <String>{};
      for (final id in ids) {
        if (seen.add(id)) unique.add(id);
        if (unique.length >= limit) break;
      }

      final downloadedIndex = await _downloads.listDownloadedTrackPaths();

      final resolved = await Future.wait(unique.map(_tracks.getById));
      final out = <LibraryTrack>[];
      for (final t in resolved) {
        if (t == null) continue;
        final id = t.id;
        final local = (id == null) ? null : downloadedIndex[id];
        out.add(
          LibraryTrack(
            track: t,
            downloaded: local != null,
            localFilePath: local,
          ),
        );
      }

      developer.log('Loaded liked tracks: ${out.length}', name: 'WEAFRICA.Library');
      return Result.success(out);
    } catch (e, st) {
      developer.log('Failed to load liked tracks', name: 'WEAFRICA.Library', error: e, stackTrace: st);
      return Result.failure(Exception('Failed to load liked tracks: $e'));
    }
  }

  Future<Result<List<LibraryTrack>>> getDownloadedTracks({int limit = 50}) async {
    try {
      final downloadedIndex = await _downloads.listDownloadedTrackPaths();
      final ids = downloadedIndex.keys.take(limit).toList(growable: false);
      if (ids.isEmpty) return Result.success(const <LibraryTrack>[]);

      final resolved = await Future.wait(ids.map(_tracks.getById));
      final out = <LibraryTrack>[];
      for (final t in resolved) {
        if (t == null) continue;
        final id = t.id;
        final local = id == null ? null : downloadedIndex[id];
        out.add(LibraryTrack(track: t, downloaded: local != null, localFilePath: local));
      }
      return Result.success(out);
    } catch (e) {
      return Result.failure(Exception('Failed to load downloads: $e'));
    }
  }

  Future<Result<List<LibraryTrack>>> getRecentlyPlayed({int limit = 20}) async {
    final res = await _recents.getRecentlyPlayed(limit: limit);
    if (!res.isSuccess) return res;

    try {
      final downloadedIndex = await _downloads.listDownloadedTrackPaths();
      final out = <LibraryTrack>[];
      for (final item in res.data ?? const <LibraryTrack>[]) {
        final id = item.track.id;
        final local = id == null ? null : downloadedIndex[id];
        out.add(
          LibraryTrack(
            track: item.track,
            downloaded: local != null,
            localFilePath: local,
            lastPlayedAt: item.lastPlayedAt,
          ),
        );
      }
      return Result.success(out);
    } catch (_) {
      return res;
    }
  }

  Future<Result<List<LibraryAlbum>>> getSavedAlbums({int limit = 50, int offset = 0}) async {
    final userId = _userId;
    if (userId == null || userId.trim().isEmpty) {
      return Result.failure(Exception('Sign in is required to load saved albums.'));
    }

    try {
      final response = await _supabase
          .from('saved_albums')
          .select('albums!inner(*)')
          .eq('user_id', userId)
          .order('saved_at', ascending: false)
          .range(offset, offset + limit - 1);

      final list = (response as List<dynamic>).whereType<Map<String, dynamic>>();
      final albums = list
          .map((row) => row['albums'])
          .whereType<Map<String, dynamic>>()
          .map((row) => Album.fromSupabase(row))
          .map((a) => LibraryAlbum(album: a))
          .toList(growable: false);
      return Result.success(albums);
    } catch (e) {
      developer.log('saved_albums query failed', name: 'WEAFRICA.Library', error: e);
      return Result.failure(Exception('Failed to load saved albums: $e'));
    }
  }

  Future<Result<List<LibraryPlaylist>>> getPlaylists() async {
    try {
      final list = await _playlists.fetchMyPlaylists();
      return Result.success(list.map((p) => LibraryPlaylist(playlist: p)).toList(growable: false));
    } catch (e) {
      return Result.failure(Exception('Failed to load playlists: $e'));
    }
  }

  Future<Result<LibraryPlaylist>> createPlaylist(String title) async {
    final name = title.trim();
    if (name.isEmpty) return Result.failure(Exception('Playlist name is required'));
    if (!SubscriptionsController.instance.canCreatePlaylists) {
      return Result.failure(Exception('Playlist creation requires an active subscription.'));
    }

    try {
      final created = await _playlists.createPlaylist(name: name);
      return Result.success(LibraryPlaylist(playlist: created));
    } catch (e) {
      return Result.failure(Exception('Failed to create playlist: $e'));
    }
  }

  Future<Result<String>> downloadTrack(Track track) async {
    if (!SubscriptionsController.instance.canDownloadOffline) {
      return Result.failure(Exception('Offline downloads require an active subscription.'));
    }

    final id = track.id?.trim();
    final uri = track.audioUri;

    if (id == null || id.isEmpty) {
      return Result.failure(Exception('This track cannot be downloaded yet.'));
    }

    if (uri == null) {
      return Result.failure(Exception('This track has no audio URL.'));
    }

    try {
      final filename = 'weafrica_$id${DateTime.now().millisecondsSinceEpoch}.mp3';
      final path = await _downloads.downloadTrack(trackId: id, remoteUri: uri, suggestedFileName: filename);
      return Result.success(path);
    } catch (e) {
      return Result.failure(Exception('Download failed: $e'));
    }
  }

  Future<Result<bool>> removeDownloadedTrack(String trackId) async {
    try {
      final ok = await _downloads.removeDownload(trackId);
      return Result.success(ok);
    } catch (e) {
      return Result.failure(Exception('Failed to remove download: $e'));
    }
  }

  // Utility for debugging / future: export library snapshot.
  Future<String> exportDebugSnapshot() async {
    final liked = await getLikedTracks(limit: 50);
    final playlists = await getPlaylists();
    final map = <String, dynamic>{
      'liked_tracks': (liked.data ?? const <LibraryTrack>[]).map((t) => t.trackId).toList(),
      'playlists': (playlists.data ?? const <LibraryPlaylist>[]).map((p) => p.id).toList(),
    };
    return jsonEncode(map);
  }
}
