import 'dart:convert';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

class BattleReplayApi {
  const BattleReplayApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Map<String, dynamic>? _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<bool> startReplay({required String battleId}) async {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      throw ArgumentError('battleId is required');
    }

    final uri = _uriBuilder.build('/api/battle/replay/start');

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'battle_id': bid,
      }),
      timeout: const Duration(seconds: 8),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('startReplay failed (${res.statusCode})');
    }

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null) return true;
    return decoded['ok'] == true;
  }

  Future<bool> stopReplay({required String battleId}) async {
    final bid = battleId.trim();
    if (bid.isEmpty) {
      throw ArgumentError('battleId is required');
    }

    final uri = _uriBuilder.build('/api/battle/replay/stop');

    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'battle_id': bid,
      }),
      timeout: const Duration(seconds: 8),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('stopReplay failed (${res.statusCode})');
    }

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null) return true;
    return decoded['ok'] == true;
  }
}
