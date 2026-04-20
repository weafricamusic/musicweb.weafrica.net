import 'dart:developer' as developer;

import '../../../app/services/connectivity_service.dart';
import '../../../app/utils/result.dart';
import '../models/album.dart';
import '../repositories/albums_repository.dart';

class AlbumService {
  AlbumService({
    AlbumsRepository? repository,
    ConnectivityService? connectivity,
  })  : _repository = repository ?? AlbumsRepository(),
        _connectivity = connectivity ?? ConnectivityService.instance;

  final AlbumsRepository _repository;
  final ConnectivityService _connectivity;

  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  static const Duration _cacheDuration = Duration(minutes: 5);

  Future<Result<List<Album>>> getLatestAlbums({
    int limit = 80,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'latest_$limit';

    final cached = _cache[cacheKey];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      developer.log('Using cached albums', name: 'WEAFRICA.Albums');
      return Result.success(cached.data as List<Album>);
    }

    final hasConnection = await _connectivity.hasConnection;
    if (!hasConnection) {
      return Result.failure(Exception('No internet connection.'));
    }

    final res = await _repository.getLatestPublished(limit: limit);
    if (res.isSuccess && res.data != null) {
      _cache[cacheKey] = _CacheEntry(data: res.data!, timestamp: DateTime.now());
    }

    return res;
  }

  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.data,
    required this.timestamp,
  });

  final Object data;
  final DateTime timestamp;

  bool get isExpired => DateTime.now().difference(timestamp) > AlbumService._cacheDuration;
}
