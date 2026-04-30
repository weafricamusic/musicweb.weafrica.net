import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/creator_earnings.dart';
import '../../auth/user_role.dart';

/// WeAfrica Music Withdrawal Service
/// 
/// Handles withdrawals for BOTH Artists AND DJs
/// Platform commission: 30% (WeAfrica keeps 30%, creator gets 70%)
class WithdrawalService {
  WithdrawalService._();
  static final WithdrawalService instance = WithdrawalService._();

  final _supabase = Supabase.instance.client;
  static const double _minWithdrawal = 10.0; // Minimum $10
  static const int _platformFeePercent = 30;

  /// Get creator earnings summary (Artist or DJ)
  Future<CreatorEarnings?> getEarnings(String creatorId) async {
    try {
      final response = await _supabase
          .from('creator_earnings') // Unified table for both
          .select()
          .eq('creator_id', creatorId)
          .single();

      return CreatorEarnings.fromJson(response);
    } catch (e) {
      // Fallback to old artist_earnings table for backward compatibility
      try {
        final response = await _supabase
            .from('artist_earnings')
            .select()
            .eq('artist_id', creatorId)
            .single();
        
        return CreatorEarnings.fromJson(response);
      } catch (_) {
        debugPrint('⚠️ Error getting earnings: $e');
        return null;
      }
    }
  }

  /// Get earnings with specific role
  Future<CreatorEarnings?> getEarningsByRole(
    String creatorId,
    UserRole role,
  ) async {
    final earnings = await getEarnings(creatorId);
    if (earnings != null) return earnings;
    
    // If no record exists, return empty earnings for the role
    return CreatorEarnings(
      creatorId: creatorId,
      creatorRole: role,
      totalEarnings: 0,
      availableForWithdrawal: 0,
      pendingEarnings: 0,
      totalWithdrawn: 0,
    );
  }

  /// Request withdrawal (works for both Artists and DJs)
  Future<({bool success, String message, String? requestId})> requestWithdrawal({
    required String creatorId,
    required double amount,
    required String method,
    required Map<String, dynamic> accountDetails,
    UserRole? creatorRole,
  }) async {
    // Validate minimum
    if (amount < _minWithdrawal) {
      return (
        success: false,
        message: 'Minimum withdrawal is \$$_minWithdrawal',
        requestId: null,
      );
    }

    try {
      // Check available balance
      final earnings = await getEarnings(creatorId);
      if (earnings == null) {
        return (
          success: false,
          message: 'Could not load earnings',
          requestId: null,
        );
      }

      if (earnings.availableForWithdrawal < amount) {
        return (
          success: false,
          message: 'Insufficient balance. Available: \$${earnings.availableForWithdrawal}',
          requestId: null,
        );
      }

      // Create withdrawal request
      final requestId = await _supabase.rpc('create_withdrawal_request', params: {
        'p_creator_id': creatorId,
        'p_creator_role': creatorRole?.name ?? earnings.creatorRole.name,
        'p_amount': amount,
        'p_method': method,
        'p_account_details': accountDetails,
      });

      debugPrint('✅ Withdrawal requested for ${creatorRole?.name ?? "creator"}: $requestId');

      return (
        success: true,
        message: 'Withdrawal request submitted for review',
        requestId: requestId?.toString(),
      );
    } catch (e) {
      debugPrint('⚠️ Error requesting withdrawal: $e');
      return (
        success: false,
        message: 'Failed to submit request. Please try again.',
        requestId: null,
      );
    }
  }

  /// Get withdrawal history
  Future<List<WithdrawalRequest>> getWithdrawalHistory(
    String creatorId, {
    int limit = 20,
  }) async {
    try {
      final response = await _supabase
          .from('withdrawal_requests')
          .select()
          .eq('creator_id', creatorId)
          .order('requested_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => WithdrawalRequest.fromJson(json))
          .toList();
    } catch (e) {
      // Fallback to old column name
      try {
        final response = await _supabase
            .from('withdrawal_requests')
            .select()
            .eq('artist_id', creatorId)
            .order('requested_at', ascending: false)
            .limit(limit);

        return (response as List)
            .map((json) => WithdrawalRequest.fromJson(json))
            .toList();
      } catch (_) {
        debugPrint('⚠️ Error getting withdrawal history: $e');
        return [];
      }
    }
  }

  /// Calculate platform fee
  double calculatePlatformFee(double amount) {
    return amount * _platformFeePercent / 100;
  }

  /// Calculate artist net amount
  double calculateNetAmount(double amount) {
    return amount * (100 - _platformFeePercent) / 100;
  }

  /// Get minimum withdrawal
  double get minWithdrawal => _minWithdrawal;

  /// Get platform fee percentage
  int get platformFeePercent => _platformFeePercent;

  /// Convert coins to USD (example rate: 100 coins = $1)
  double coinsToUsd(int coins) {
    return coins / 100;
  }

  /// Convert USD to coins
  int usdToCoins(double usd) {
    return (usd * 100).round();
  }
}