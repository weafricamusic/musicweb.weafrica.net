import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/creator_finance_api.dart';

class EarningsRepository {
  EarningsRepository({SupabaseClient? client});

  /// Returns an earnings summary from the canonical wallet backend.
  Future<Map<String, dynamic>> getEarningsSummary(
    String artistId, {
    String? firebaseUid,
  }) async {
    final uid = (firebaseUid ?? '').trim();
    if (uid.isEmpty) {
      throw StateError('Firebase UID is required to load earnings summary');
    }

    final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
    if (summary.userId.trim().isNotEmpty && summary.userId.trim() != uid) {
      throw StateError('Wallet summary user mismatch');
    }

    return <String, dynamic>{
      'available': summary.coinBalance + summary.cashBalances.values.fold<double>(0, (p, v) => p + v),
      'pending': 0,
      'total': summary.totalEarned,
      'by_source': <String, num>{'wallet': summary.totalEarned},
    };
  }
}
