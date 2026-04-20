import '../../../../app/services/connectivity_service.dart';
import '../../../../app/utils/result.dart';
import '../models/dashboard_notification.dart';
import '../repositories/artist_notification_repository.dart';

class DashboardNotificationService {
  DashboardNotificationService({ArtistNotificationRepository? repository})
      : _repository = repository ?? ArtistNotificationRepository();

  final ArtistNotificationRepository _repository;

  Future<Result<int>> count() async {
    final connected = await ConnectivityService.instance.hasConnection;
    if (!connected) return Result.failure(Exception('WEAFRICA: No internet connection'));
    return _repository.countNotifications();
  }

  Future<Result<List<DashboardNotification>>> listRecent({
    int limit = 5,
    int offset = 0,
  }) async {
    final connected = await ConnectivityService.instance.hasConnection;
    if (!connected) return Result.failure(Exception('WEAFRICA: No internet connection'));
    return _repository.listRecent(limit: limit, offset: offset);
  }
}
