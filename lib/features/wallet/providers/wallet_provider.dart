import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/coin_transaction.dart';
import '../models/creator_earnings.dart';
import '../services/coin_service.dart';
import '../services/gift_service.dart';
import '../services/withdrawal_service.dart';
import '../../auth/user_role.dart';

/// WeAfrica Music Wallet Provider
/// 
/// Central state management for coins, gifts, and earnings
/// Supports BOTH Artists AND DJs as creators
class WalletProvider extends ChangeNotifier {
  WalletProvider._();
  static final WalletProvider instance = WalletProvider._();

  String? _userId;
  UserRole? _userRole;
  int _balance = 0;
  bool _isLoading = false;
  List<CoinTransaction> _recentTransactions = [];
  CreatorEarnings? _creatorEarnings;

  // Getters
  int get balance => _balance;
  bool get isLoading => _isLoading;
  List<CoinTransaction> get recentTransactions => _recentTransactions;
  bool get isInitialized => _userId != null;
  CreatorEarnings? get creatorEarnings => _creatorEarnings;
  bool get isCreator => _userRole == UserRole.artist || _userRole == UserRole.dj;
  String get creatorTypeLabel {
    if (_userRole == UserRole.dj) return 'DJ';
    if (_userRole == UserRole.artist) return 'Artist';
    return 'User';
  }

  StreamSubscription<int>? _balanceSubscription;

  /// Initialize for user (with role)
  Future<void> initialize(String userId, {UserRole? role}) async {
    _userId = userId;
    _userRole = role;
    
    // Listen to balance updates
    _balanceSubscription = CoinService.instance.balanceStream.listen((newBalance) {
      _balance = newBalance;
      notifyListeners();
    });

    await refreshBalance();
    
    // If creator, also load earnings
    if (isCreator) {
      await refreshCreatorEarnings();
    }
  }

  /// Refresh balance from server
  Future<void> refreshBalance() async {
    if (_userId == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      _balance = await CoinService.instance.getBalance(_userId!);
      _recentTransactions = await CoinService.instance.getTransactionHistory(
        _userId!,
        limit: 10,
      );
    } catch (e) {
      debugPrint('⚠️ Error refreshing balance: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh creator earnings (Artist or DJ)
  Future<void> refreshCreatorEarnings() async {
    if (_userId == null || !isCreator) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      _creatorEarnings = await WithdrawalService.instance.getEarningsByRole(
        _userId!,
        _userRole!,
      );
    } catch (e) {
      debugPrint('⚠️ Error refreshing earnings: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Add coins (from ads)
  Future<bool> addCoinsFromAd(int amount) async {
    if (_userId == null) return false;

    final success = await CoinService.instance.addCoins(
      userId: _userId!,
      amount: amount,
      type: TransactionType.earn,
      description: 'Earned from watching ad',
    );

    if (success) {
      await refreshBalance();
    }

    return success;
  }

  /// Send gift to creator (Artist or DJ)
  Future<bool> sendGift({
    required String creatorId,
    required String giftId,
    String? battleId,
  }) async {
    if (_userId == null) return false;

    _isLoading = true;
    notifyListeners();

    final success = await GiftService.instance.sendGift(
      fromUserId: _userId!,
      toArtistId: creatorId,
      giftId: giftId,
      battleId: battleId,
    );

    if (success) {
      await refreshBalance();
    } else {
      _isLoading = false;
      notifyListeners();
    }

    return success;
  }

  /// Join battle (spend coins)
  Future<bool> joinBattle(String battleId, int entryFee) async {
    if (_userId == null) return false;

    _isLoading = true;
    notifyListeners();

    final success = await CoinService.instance.deductCoins(
      userId: _userId!,
      amount: entryFee,
      type: TransactionType.battleEntry,
      description: 'Battle entry fee',
      relatedEntityId: battleId,
    );

    if (success) {
      await refreshBalance();
    } else {
      _isLoading = false;
      notifyListeners();
    }

    return success;
  }

  /// Get creator earnings (Artist or DJ)
  Future<CreatorEarnings?> getCreatorEarnings() async {
    if (_userId == null || !isCreator) return null;
    return await WithdrawalService.instance.getEarningsByRole(
      _userId!,
      _userRole!,
    );
  }

  /// Alias for backward compatibility
  Future<CreatorEarnings?> getArtistEarnings() => getCreatorEarnings();

  /// Request withdrawal (for Artists AND DJs)
  Future<({bool success, String message, String? requestId})> requestWithdrawal({
    required double amount,
    required String method,
    required Map<String, dynamic> accountDetails,
  }) async {
    if (_userId == null) {
      return (success: false, message: 'Not initialized', requestId: null);
    }

    if (!isCreator) {
      return (success: false, message: 'Only Artists and DJs can withdraw', requestId: null);
    }

    _isLoading = true;
    notifyListeners();

    final result = await WithdrawalService.instance.requestWithdrawal(
      creatorId: _userId!,
      amount: amount,
      method: method,
      accountDetails: accountDetails,
      creatorRole: _userRole,
    );

    if (result.success) {
      await refreshCreatorEarnings();
    } else {
      _isLoading = false;
      notifyListeners();
    }

    return result;
  }

  /// Check if user can afford amount
  bool canAfford(int amount) => _balance >= amount;

  /// Set user role (for when role changes or is discovered later)
  void setUserRole(UserRole role) {
    if (_userRole != role) {
      _userRole = role;
      notifyListeners();
      
      if (isCreator) {
        refreshCreatorEarnings();
      }
    }
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    super.dispose();
  }
}
