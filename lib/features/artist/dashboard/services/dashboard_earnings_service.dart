import 'dart:developer' as developer;

import '../../../../app/services/connectivity_service.dart';
import '../../../../app/utils/result.dart';
import '../../../../services/creator_finance_api.dart';
import '../../../artist_dashboard/services/artist_identity_service.dart';
import '../models/dashboard_earnings.dart';

class DashboardEarningsService {
  DashboardEarningsService({
    ArtistIdentityService? identity,
    CreatorFinanceApi? finance,
  })  : _identity = identity ?? ArtistIdentityService(),
        _finance = finance ?? const CreatorFinanceApi();

  final ArtistIdentityService _identity;
  final CreatorFinanceApi _finance;

  Future<Result<DashboardEarningsSummary>> getSummary() async {
    final connected = await ConnectivityService.instance.hasConnection;
    if (!connected) return Result.failure(Exception('WEAFRICA: No internet connection'));

    final uid = _identity.currentFirebaseUid();
    final u = (uid ?? '').trim();
    if (u.isEmpty) return Result.failure(Exception('WEAFRICA: Please sign in'));

    try {
      final summary = await _finance.fetchMyWalletSummary();
      final total = summary.totalEarned;
      final available = summary.cashBalances.values.fold<double>(0, (p, v) => p + v);
      return Result.success(DashboardEarningsSummary(totalEarnings: total, availableBalance: available));
    } catch (e, st) {
      developer.log('Unexpected error loading earnings summary', name: 'WEAFRICA.Dashboard', error: e, stackTrace: st);
      return Result.failure(Exception('WEAFRICA: Failed to load earnings'));
    }
  }
}
