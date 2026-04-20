import 'dart:convert';
import 'dart:developer' as developer;

import '../app/network/api_uri_builder.dart';
import '../app/network/firebase_authed_http.dart';

class CreatorWalletSummary {
  const CreatorWalletSummary({
    required this.userId,
    required this.coinBalance,
    required this.totalEarned,
    required this.cashBalances,
    required this.updatedAt,
  });

  final String userId;
  final double coinBalance;
  final double totalEarned;
  final Map<String, double> cashBalances;
  final String updatedAt;

  double cashBalanceFor(String currency) {
    final c = currency.trim().toUpperCase();
    return cashBalances[c] ?? 0;
  }
}

class CreatorFinanceApi {
  const CreatorFinanceApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  static Map<String, dynamic>? _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static double _readDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _normalizeRows(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }

  Future<CreatorWalletSummary> fetchMyWalletSummary() async {
    final uri = _uriBuilder.build('/api/wallet/summary/me');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 10),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString();
      throw Exception('Wallet summary failed (HTTP ${res.statusCode}): $msg');
    }

    final userId = (decoded?['user_id'] ?? decoded?['userId'] ?? '').toString().trim();
    final coin = _readDouble(decoded?['coin_balance'] ?? decoded?['coinBalance']);
    final earned = _readDouble(decoded?['total_earned'] ?? decoded?['totalEarned']);

    final balances = <String, double>{'MWK': 0, 'USD': 0, 'ZAR': 0};
    final raw = decoded?['cash_balances'] ?? decoded?['cashBalances'];
    if (raw is Map) {
      final m = raw.map((k, v) => MapEntry(k.toString().trim().toUpperCase(), v));
      for (final c in balances.keys) {
        balances[c] = _readDouble(m[c]);
      }
    }

    final updatedAt = (decoded?['updated_at'] ?? decoded?['updatedAt'] ?? '').toString().trim();

    return CreatorWalletSummary(
      userId: userId,
      coinBalance: coin,
      totalEarned: earned,
      cashBalances: balances,
      updatedAt: updatedAt,
    );
  }

  Future<List<Map<String, dynamic>>> fetchMyWalletTransactions({int limit = 50}) async {
    final capped = limit.clamp(1, 200);
    final uri = _uriBuilder.build(
      '/api/wallet/transactions/me',
      queryParameters: {'limit': '$capped'},
    );
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString();
      throw Exception('Wallet transactions failed (HTTP ${res.statusCode}): $msg');
    }

    return _normalizeRows(decoded?['transactions']);
  }

  Future<List<Map<String, dynamic>>> fetchMyWithdrawals({int limit = 50}) async {
    final capped = limit.clamp(1, 200);
    final uri = _uriBuilder.build(
      '/api/withdrawals/me',
      queryParameters: {'limit': '$capped'},
    );
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded?['ok'] != true) {
      final msg = (decoded?['message'] ?? decoded?['error'] ?? res.body).toString();
      throw Exception('Withdrawals failed (HTTP ${res.statusCode}): $msg');
    }

    return _normalizeRows(decoded?['withdrawals']);
  }

  Future<Map<String, dynamic>> requestWithdrawal({
    required double amount,
    required String currency,
    required String paymentMethod,
    Map<String, dynamic>? accountDetails,
  }) async {
    final uri = _uriBuilder.build('/api/withdrawals/request');
    final payload = <String, Object?>{
      'amount': amount,
      'currency': currency.trim().toUpperCase(),
      'payment_method': paymentMethod.trim(),
      // ignore: use_null_aware_elements
      if (accountDetails != null) 'account_details': accountDetails,
    };

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 15),
      requireAuth: true,
    );

    final decoded = _decodeJsonMap(res.body) ?? const <String, dynamic>{};
    final ok = decoded['ok'] == true;
    if (res.statusCode < 200 || res.statusCode >= 300 || !ok) {
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString().trim();
      throw Exception('Withdrawal request failed (HTTP ${res.statusCode}): $msg');
    }

    developer.log('Withdrawal requested', name: 'WEAFRICA.Finance');
    return decoded;
  }
}
