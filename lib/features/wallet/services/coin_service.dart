import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coin_transaction.dart';
import '../../ads/services/analytics_ad_service.dart';

/// WeAfrica Music Coin Service
/// 
/// Central service for all coin operations
/// - Earn coins (ads, rewards)
/// - Spend coins (battles, gifts)
/// - Transfer coins (gifts to artists)
class CoinService {
  CoinService._();
  static final CoinService instance = CoinService._();

  final _supabase = Supabase.instance.client;
  final _streamController = StreamController<int>.broadcast();

  /// Stream of coin balance updates
  Stream<int> get balanceStream => _streamController.stream;

  /// Get current user's coin balance
  Future<int> getBalance(String userId) async {
    try {
      final response = await _supabase
          .from('user_coins')
          .select('balance')
          .eq('user_id', userId)
          .single();

      return response['balance'] ?? 0;
    } catch (e) {
      debugPrint('⚠️ Error getting balance: $e');
      return 0;
    }
  }

  /// Add coins (from ads, purchases, rewards)
  Future<bool> addCoins({
    required String userId,
    required int amount,
    required TransactionType type,
    String? description,
    String? relatedUserId,
    String? relatedEntityId,
    Map<String, dynamic>? metadata,
  }) async {
    if (amount <= 0) return false;

    try {
      // Start transaction
      await _supabase.rpc('add_coins', params: {
        'p_user_id': userId,
        'p_amount': amount,
      });

      // Record transaction
      await _recordTransaction(CoinTransaction(
        id: _generateId(),
        userId: userId,
        type: type,
        amount: amount,
        description: description,
        relatedUserId: relatedUserId,
        relatedEntityId: relatedEntityId,
        metadata: metadata,
        createdAt: DateTime.now(),
      ));

      // Update stream
      final newBalance = await getBalance(userId);
      _streamController.add(newBalance);

      // Track analytics
      await AnalyticsAdService.instance.logCoinsEarned(
        amount: amount,
        source: type.name,
      );

      debugPrint('✅ Added $amount coins to $userId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Error adding coins: $e');
      return false;
    }
  }

  /// Deduct coins (for battles, gifts)
  Future<bool> deductCoins({
    required String userId,
    required int amount,
    required TransactionType type,
    String? description,
    String? relatedUserId,
    String? relatedEntityId,
    Map<String, dynamic>? metadata,
  }) async {
    if (amount <= 0) return false;

    try {
      // Check balance first
      final currentBalance = await getBalance(userId);
      if (currentBalance < amount) {
        debugPrint('⚠️ Insufficient balance');
        return false;
      }

      // Deduct coins
      await _supabase.rpc('deduct_coins', params: {
        'p_user_id': userId,
        'p_amount': amount,
      });

      // Record transaction
      await _recordTransaction(CoinTransaction(
        id: _generateId(),
        userId: userId,
        type: type,
        amount: -amount,
        description: description,
        relatedUserId: relatedUserId,
        relatedEntityId: relatedEntityId,
        metadata: metadata,
        createdAt: DateTime.now(),
      ));

      // Update stream
      final newBalance = await getBalance(userId);
      _streamController.add(newBalance);

      debugPrint('✅ Deducted $amount coins from $userId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Error deducting coins: $e');
      return false;
    }
  }

  /// Transfer coins (gift to artist)
  Future<bool> transferCoins({
    required String fromUserId,
    required String toUserId,
    required int amount,
    String? description,
    String? relatedEntityId,
  }) async {
    if (amount <= 0) return false;
    if (fromUserId == toUserId) return false;

    try {
      // Deduct from sender
      final deducted = await deductCoins(
        userId: fromUserId,
        amount: amount,
        type: TransactionType.giftSent,
        description: description ?? 'Gift to artist',
        relatedUserId: toUserId,
        relatedEntityId: relatedEntityId,
      );

      if (!deducted) return false;

      // Add to receiver
      final added = await addCoins(
        userId: toUserId,
        amount: amount,
        type: TransactionType.giftReceived,
        description: description ?? 'Gift from fan',
        relatedUserId: fromUserId,
        relatedEntityId: relatedEntityId,
      );

      if (!added) {
        // Refund sender if failed
        await addCoins(
          userId: fromUserId,
          amount: amount,
          type: TransactionType.refund,
          description: 'Refund - transfer failed',
        );
        return false;
      }

      debugPrint('✅ Transferred $amount coins: $fromUserId → $toUserId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Error transferring coins: $e');
      return false;
    }
  }

  /// Get transaction history
  Future<List<CoinTransaction>> getTransactionHistory(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('coin_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => CoinTransaction.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Error getting transactions: $e');
      return [];
    }
  }

  /// Record transaction in database
  Future<void> _recordTransaction(CoinTransaction transaction) async {
    try {
      await _supabase.from('coin_transactions').insert(transaction.toJson());
    } catch (e) {
      debugPrint('⚠️ Error recording transaction: $e');
    }
  }

  /// Generate unique ID
  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_randomString(6)}';
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rand.nextInt(chars.length)),
      ),
    );
  }

  void dispose() {
    _streamController.close();
  }
}