import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/utils/result.dart';
import '../data/albums_query_adapter.dart';
import '../models/album.dart';

class AlbumsRepository {
  AlbumsRepository({
    SupabaseClient? client,
    AlbumsQueryAdapter? queryAdapter,
  })  : _client = client ?? Supabase.instance.client,
        _queryAdapter = queryAdapter ?? const AlbumsQueryAdapter();

  final SupabaseClient _client;
  final AlbumsQueryAdapter _queryAdapter;

  /// Backwards-compatible API: returns albums or throws.
  Future<List<Album>> latestPublished({int limit = 80}) async {
    final res = await getLatestPublished(limit: limit);
    return res.fold(
      onSuccess: (albums) => albums,
      onFailure: (error) => throw error,
    );
  }

  Future<Result<List<Album>>> getLatestPublished({
    int limit = 80,
  }) async {
    try {
      developer.log('Fetching latest published albums (limit=$limit)', name: 'WEAFRICA.Albums');

      final rows = await _queryAdapter.latestPublishedRows(_client, limit: limit);

      final albums = <Album>[];
      final parseErrors = <Object>[];

      for (final row in rows) {
        try {
          final album = Album.fromSupabase(row);
          if (album.isPublished) albums.add(album);
        } catch (e, st) {
          parseErrors.add(e);
          developer.log(
            'Failed to parse album row',
            name: 'WEAFRICA.Albums',
            error: e,
            stackTrace: st,
          );
        }
      }

      if (albums.isEmpty && parseErrors.isNotEmpty) {
        return Result.failure(Exception('Failed to load albums'));
      }

      return Result.success(albums);
    } on PostgrestException catch (e, st) {
      developer.log('Supabase error loading albums', name: 'WEAFRICA.Albums', error: e, stackTrace: st);
      return Result.failure(_friendlyPostgrestError(e));
    } catch (e, st) {
      developer.log('Unexpected error loading albums', name: 'WEAFRICA.Albums', error: e, stackTrace: st);
      return Result.failure(Exception('Failed to load albums'));
    }
  }

  Exception _friendlyPostgrestError(PostgrestException error) {
    final message = error.message.toLowerCase();
    final details = (error.details ?? '').toString();

    if (message.contains('does not exist') || details.contains('42P01')) {
      return Exception('Albums are not available right now.');
    }

    if (message.contains('permission denied') || message.contains('row level security')) {
      return Exception('Unable to access albums.');
    }

    if (message.contains('jwt') || message.contains('invalid api key')) {
      return Exception('Authentication failed. Please sign in again.');
    }

    return Exception('Database error loading albums.');
  }
}
