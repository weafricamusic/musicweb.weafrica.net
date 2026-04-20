import 'package:flutter/foundation.dart';

@immutable
class DashboardEarningsSummary {
  const DashboardEarningsSummary({
    required this.totalEarnings,
    required this.availableBalance,
  });

  final double totalEarnings;
  final double availableBalance;
}

@immutable
class EarningsDataPoint {
  const EarningsDataPoint({required this.timestamp, required this.amount});

  final DateTime timestamp;
  final double amount;
}

@immutable
class EarningsHistory {
  const EarningsHistory({required this.items});
  final List<EarningsDataPoint> items;
}
