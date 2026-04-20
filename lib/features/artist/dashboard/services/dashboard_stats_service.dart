import 'dart:async';
import 'dart:developer' as developer;

import '../../../../app/services/connectivity_service.dart';
import '../../../../app/utils/result.dart';
import '../models/dashboard_stats.dart';
import '../repositories/artist_stats_repository.dart';

class DashboardStatsService {
  DashboardStatsService({ArtistStatsRepository? repository}) : _repository = repository ?? ArtistStatsRepository();

  final ArtistStatsRepository _repository;

  DashboardStats? _cached;
  DateTime? _lastFetch;
  static const Duration cacheTtl = Duration(minutes: 2);

  final StreamController<DashboardStats> _controller = StreamController<DashboardStats>.broadcast();
  Stream<DashboardStats> get stream => _controller.stream;

  Future<Result<DashboardStats>> get({bool forceRefresh = false}) async {
    final cached = _cached;
    final last = _lastFetch;
    if (!forceRefresh && cached != null && last != null) {
      final age = DateTime.now().difference(last);
      if (age < cacheTtl) {
        developer.log('Using cached dashboard stats', name: 'WEAFRICA.Dashboard');
        return Result.success(cached);
      }
    }

    final connected = await ConnectivityService.instance.hasConnection;
    if (!connected) {
      if (cached != null) return Result.success(cached);
      return Result.failure(Exception('WEAFRICA: No internet connection'));
    }

    final result = await _repository.getDashboardStats();
    if (result.isSuccess && result.data != null) {
      _cached = result.data;
      _lastFetch = DateTime.now();
      _controller.add(result.data!);
    }

    return result;
  }

  Future<Result<DashboardStats>> refresh() => get(forceRefresh: true);

  void clearCache() {
    _cached = null;
    _lastFetch = null;
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
