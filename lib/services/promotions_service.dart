import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app/config/api_env.dart';

class PromotionsService {
  static Future<List<Map<String, dynamic>>> fetchPromotions({String? planId}) async {
    final base = ApiEnv.baseUrl;
    final uri = Uri.parse('$base/api/subscriptions/promotions').replace(
      queryParameters: planId == null ? null : <String, String>{'plan_id': planId},
    );

    if (kDebugMode) {
      final defined = ApiEnv.definedBaseUrl;
      debugPrint(
        '🌐 Promotions fetch: $uri (WEAFRICA_API_BASE_URL=${defined.isEmpty ? '(not set)' : defined})',
      );
    }

    http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
    } on TimeoutException catch (e) {
      final base = ApiEnv.baseUrl;
      final hint = base.contains('.functions.supabase.co') || base.contains('.supabase.co')
          ? ' (Hint: confirm WEAFRICA_API_BASE_URL points at your hosted Supabase Functions origin for this project.)'
          : '';
      throw Exception('Timeout fetching promotions from $uri (${e.duration}).$hint');
    } on SocketException catch (e) {
      throw Exception('Network error fetching promotions from $uri: ${e.message}');
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw Exception(
          'Promotions endpoint not found (HTTP 404): $uri\n'
          'Most likely WEAFRICA_API_BASE_URL is pointing at the wrong server.\n'
          'If you are using the Supabase Edge Function in supabase/functions/api, set:\n'
          '  WEAFRICA_API_BASE_URL=https://<project-ref>.functions.supabase.co',
        );
      }
      throw Exception(
        'Failed to load promotions (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid promotions response shape (expected JSON object).');
    }

    final promotions = decoded['promotions'];
    if (promotions is! List) return const <Map<String, dynamic>>[];

    return promotions
        .whereType<Map>()
        .map((p) => p.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }
}
