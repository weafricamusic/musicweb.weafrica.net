import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing user profile data and rewards.
class UserService {
  UserService._();
  static final instance = UserService._();

  static const _keyCoins = 'user_coins';

  int _coins = 0;

  /// Load user data from local storage.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _coins = prefs.getInt(_keyCoins) ?? 0;

    debugPrint('💰 User loaded: $_coins coins');
  }

  /// Add coins to user balance.
  Future<void> addCoins(int amount) async {
    _coins += amount;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCoins, _coins);

    // Sync to Supabase
    await _syncCoinsToServer();

    debugPrint('💰 Coins added: +$amount (total: $_coins)');
  }

  /// Replace the locally cached balance with a backend-confirmed value.
  Future<void> setCoins(int amount) async {
    _coins = amount.clamp(0, 999999999);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCoins, _coins);

    debugPrint('💰 Coins set from backend: $_coins');
  }

  /// Remove coins from user balance.
  Future<void> removeCoins(int amount) async {
    _coins = (_coins - amount).clamp(0, 999999999);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCoins, _coins);

    await _syncCoinsToServer();

    debugPrint('💰 Coins removed: -$amount (total: $_coins)');
  }

  /// Sync coins to Supabase user profile.
  Future<void> _syncCoinsToServer() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('users').upsert({
        'id': userId,
        'coins': _coins,
      });

      debugPrint('✅ Coins synced to server: $_coins');
    } catch (e) {
      debugPrint('⚠️ Failed to sync coins: $e');
    }
  }

  /// Get current coin balance.
  int get coins => _coins;
}
