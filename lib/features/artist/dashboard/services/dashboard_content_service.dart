import 'dart:developer' as developer;

import '../../../../app/services/connectivity_service.dart';
import '../../../../app/utils/result.dart';
import '../../../tracks/track.dart';
import '../models/dashboard_content.dart';
import '../repositories/artist_content_repository.dart';

class DashboardContentService {
  DashboardContentService({ArtistContentRepository? repository}) : _repository = repository ?? ArtistContentRepository();

  final ArtistContentRepository _repository;

  List<Track>? _cachedSongsFirstPage;
  List<DashboardVideoItem>? _cachedVideosFirstPage;

  Future<Result<List<Track>>> getRecentSongs({
    int limit = 10,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && offset == 0 && _cachedSongsFirstPage != null) {
      return Result.success(_cachedSongsFirstPage!);
    }

    final connected = await ConnectivityService.instance.hasConnection;
    if (!connected) {
      return Result.failure(Exception('WEAFRICA: No internet connection'));
    }

    final result = await _repository.listRecentSongs(limit: limit, offset: offset);
    if (result.isSuccess && offset == 0) {
      _cachedSongsFirstPage = result.data;
      developer.log('Cached recent songs (page 1)', name: 'WEAFRICA.Dashboard');
    }
    return result;
  }

  Future<Result<List<DashboardVideoItem>>> getRecentVideos({
    int limit = 10,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && offset == 0 && _cachedVideosFirstPage != null) {
      return Result.success(_cachedVideosFirstPage!);
    }

    final connected = await ConnectivityService.instance.hasConnection;
    if (!connected) {
      return Result.failure(Exception('WEAFRICA: No internet connection'));
    }

    final result = await _repository.listRecentVideos(limit: limit, offset: offset);
    if (result.isSuccess && offset == 0) {
      _cachedVideosFirstPage = result.data;
      developer.log('Cached recent videos (page 1)', name: 'WEAFRICA.Dashboard');
    }
    return result;
  }

  void clearCache() {
    _cachedSongsFirstPage = null;
    _cachedVideosFirstPage = null;
  }
}
