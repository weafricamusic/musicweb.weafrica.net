import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../app/network/api_uri_builder.dart';

class LiveEconomyApi {
  LiveEconomyApi({FirebaseAuth? auth, ApiUriBuilder? uriBuilder})
      : _auth = auth ?? FirebaseAuth.instance,
        _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final FirebaseAuth _auth;
  final ApiUriBuilder _uriBuilder;

  static Map<String, dynamic>? _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<int?> fetchMyCoinBalance() async {
    final bearer = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (bearer.isEmpty) {
      throw StateError('Not signed in');
    }

    final uri = _uriBuilder.build('/api/wallet/me');
    final res = await http
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $bearer',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      developer.log(
        'fetchMyCoinBalance failed',
        name: 'WEAFRICA.Economy',
        error: 'HTTP ${res.statusCode} ${res.body}',
      );
      throw StateError('Failed to fetch coin balance (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['ok'] != true) {
      throw StateError('Invalid wallet response shape');
    }

    final balRaw = decoded['coin_balance'] ?? decoded['coinBalance'];
    final bal = (balRaw is num) ? balRaw.toInt() : int.tryParse('$balRaw');
    if (bal == null) {
      throw StateError('Coin balance missing in response');
    }
    return bal;
  }

  Future<SongRequestApiResult> requestSong({
    required String liveId,
    required String channelId,
    required String song,
    required int coinCost,
    required String userName,
  }) async {
    final bearer = (await _auth.currentUser?.getIdToken())?.trim() ?? '';
    if (bearer.isEmpty) {
      throw StateError('Not signed in');
    }

      final uri = _uriBuilder.build('/api/live/song_request');
      final payload = <String, Object?>{
        'live_id': liveId.trim(),
        'channel_id': channelId.trim(),
        'song': song.trim(),
        'coin_cost': coinCost,
        'user_name': userName.trim(),
      };

    final res = await http
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
            'Authorization': 'Bearer $bearer',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null) {
      throw StateError('Invalid song request response shape');
    }
    final ok = decoded['ok'] == true;
    if (res.statusCode < 200 || res.statusCode >= 300 || !ok) {
      final message = (decoded['message'] ?? decoded['error_description'] ?? '').toString().trim();
      throw StateError(
        'Song request failed (HTTP ${res.statusCode}).'
        '${message.isNotEmpty ? ' $message' : ''}',
      );
    }

      final newBalanceRaw = decoded['new_balance'] ?? decoded['newBalance'];
      final messageId = (decoded['message_id'] ?? decoded['messageId'] ?? '').toString().trim();
      final newBalance = (newBalanceRaw is num) ? newBalanceRaw.toInt() : int.tryParse('$newBalanceRaw');

    if (newBalance == null || newBalance < 0 || messageId.isEmpty) {
      throw StateError('Invalid song request response payload');
    }

    return SongRequestApiResult(
      ok: true,
      newBalance: newBalance,
      messageId: messageId,
    );
  }
}

class SongRequestApiResult {
  const SongRequestApiResult({
    required this.ok,
    this.newBalance,
    this.messageId,
    this.errorCode,
    this.errorMessage,
  });

  final bool ok;
  final int? newBalance;
  final String? messageId;
  final String? errorCode;
  final String? errorMessage;
}
