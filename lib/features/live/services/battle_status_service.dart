import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../app/network/api_uri_builder.dart';
import '../../../app/utils/app_result.dart';
import '../models/battle_status.dart';

class BattleStatusService {
  static final BattleStatusService _instance = BattleStatusService._internal();
  factory BattleStatusService() => _instance;
  BattleStatusService._internal();

  final ApiUriBuilder _uriBuilder = const ApiUriBuilder();

  Future<AppResult<BattleStatus>> fetchStatus({required String battleId}) async {
    final bid = battleId.trim();
    if (bid.isEmpty) return const AppFailure(userMessage: 'Battle ID is required.');

    try {
      final uri = _uriBuilder.build(
        '/api/battle/status',
        queryParameters: <String, String>{'battle_id': bid},
      );

      final res = await http
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        developer.log(
          'fetch battle status failed',
          name: 'WEAFRICA.Live',
          error: 'HTTP ${res.statusCode} ${res.body}',
        );
        return const AppFailure(userMessage: 'Could not load battle status.');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return const AppFailure(userMessage: 'Invalid battle status response.');
      final ok = decoded['ok'] == true;
      if (!ok) return const AppFailure(userMessage: 'Could not load battle status.');

      final battle = decoded['battle'];
      if (battle is! Map) return const AppFailure(userMessage: 'Invalid battle status response.');

      final battleMap = battle.map((k, v) => MapEntry(k.toString(), v));
      return AppSuccess(BattleStatus.fromMap(Map<String, dynamic>.from(battleMap)));
    } catch (e, st) {
      developer.log('fetch battle status failed', name: 'WEAFRICA.Live', error: e, stackTrace: st);
      return const AppFailure(userMessage: 'Could not load battle status.');
    }
  }
}
