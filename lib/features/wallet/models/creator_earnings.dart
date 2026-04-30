import '../../auth/user_role.dart';

/// Creator Earnings Model
/// 
/// Tracks earnings for both Artists AND DJs
/// from gifts, battles, streams
class CreatorEarnings {
  const CreatorEarnings({
    required this.creatorId,
    required this.creatorRole, // artist or dj
    required this.totalEarnings,
    required this.availableForWithdrawal,
    required this.pendingEarnings,
    required this.totalWithdrawn,
    this.platformFeePercent = 30, // WeAfrica takes 30%
    this.totalGiftsReceived = 0,
    this.totalBattleWinnings = 0,
    this.totalStreamEarnings = 0,
  });

  final String creatorId;
  final UserRole creatorRole;
  final double totalEarnings;
  final double availableForWithdrawal;
  final double pendingEarnings;
  final double totalWithdrawn;
  final int platformFeePercent;
  
  // Breakdown by source
  final double totalGiftsReceived;
  final double totalBattleWinnings;
  final double totalStreamEarnings;

  /// Calculate net earnings (after platform fee)
  double get netEarnings => totalEarnings * (100 - platformFeePercent) / 100;

  /// Get platform fee amount
  double get platformFee => totalEarnings * platformFeePercent / 100;
  
  /// Display name based on role
  String get creatorTypeLabel => creatorRole == UserRole.dj ? 'DJ' : 'Artist';

  factory CreatorEarnings.fromJson(Map<String, dynamic> json) {
    return CreatorEarnings(
      creatorId: json['creator_id']?.toString() ?? json['artist_id']?.toString() ?? '',
      creatorRole: UserRole.values.firstWhere(
        (e) => e.name == (json['creator_role'] ?? json['role'] ?? 'artist'),
        orElse: () => UserRole.artist,
      ),
      totalEarnings: (json['total_earnings'] ?? 0).toDouble(),
      availableForWithdrawal: (json['available_for_withdrawal'] ?? 0).toDouble(),
      pendingEarnings: (json['pending_earnings'] ?? 0).toDouble(),
      totalWithdrawn: (json['total_withdrawn'] ?? 0).toDouble(),
      platformFeePercent: json['platform_fee_percent'] ?? 30,
      totalGiftsReceived: (json['total_gifts_received'] ?? 0).toDouble(),
      totalBattleWinnings: (json['total_battle_winnings'] ?? 0).toDouble(),
      totalStreamEarnings: (json['total_stream_earnings'] ?? 0).toDouble(),
    );
  }
}

// Keep ArtistEarnings as alias for backward compatibility
typedef ArtistEarnings = CreatorEarnings;

/// Withdrawal Request Model
class WithdrawalRequest {
  const WithdrawalRequest({
    required this.id,
    required this.artistId,
    required this.amount,
    required this.status,
    required this.method,
    this.accountDetails,
    required this.requestedAt,
    this.processedAt,
  });

  final String id;
  final String artistId;
  final double amount;
  final WithdrawalStatus status;
  final String method; // 'mobile_money', 'bank', 'paypal'
  final Map<String, dynamic>? accountDetails;
  final DateTime requestedAt;
  final DateTime? processedAt;

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: json['id']?.toString() ?? '',
      artistId: json['artist_id']?.toString() ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      status: WithdrawalStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => WithdrawalStatus.pending,
      ),
      method: json['method']?.toString() ?? 'mobile_money',
      accountDetails: json['account_details'] as Map<String, dynamic>?,
      requestedAt: DateTime.tryParse(json['requested_at']?.toString() ?? '') ?? DateTime.now(),
      processedAt: json['processed_at'] != null
          ? DateTime.tryParse(json['processed_at'].toString())
          : null,
    );
  }
}

enum WithdrawalStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
}