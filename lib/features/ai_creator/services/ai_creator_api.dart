import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/config/api_env.dart';
import '../../../app/config/app_env.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../../auth/user_role.dart';
import '../models/ai_creator_models.dart';

class AiCreatorApi {
  const AiCreatorApi();

  Uri _uri(String path) {
    final base = Uri.tryParse(ApiEnv.baseUrl);
    final qp = <String, String>{};

    final bypass = AppEnv.vercelProtectionBypassToken.trim();
    final isVercel = base != null && base.host.endsWith('vercel.app');
    if (isVercel && bypass.isNotEmpty) {
      qp['x-vercel-set-bypass-cookie'] = 'true';
      qp['x-vercel-protection-bypass'] = bypass;
    }

    final u = Uri.parse('${ApiEnv.baseUrl}$path');
    return qp.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...qp});
  }

  String _generatePathFor(UserRole role) {
    return switch (role) {
      UserRole.dj => '/api/consumer/dj/ai/generate',
      UserRole.artist => '/api/consumer/artist/ai/generate',
      _ => throw StateError('AI Creator is only available for DJ/Artist roles.'),
    };
  }

  String _generationsPathFor(UserRole role) {
    return switch (role) {
      UserRole.dj => '/api/consumer/dj/ai/generations',
      UserRole.artist => '/api/consumer/artist/ai/generations',
      _ => throw StateError('AI Creator is only available for DJ/Artist roles.'),
    };
  }

  Future<void> startGeneration({
    required UserRole role,
    required AiCreatorStartRequest request,
  }) async {
    final uri = _uri(_generatePathFor(role));

    http.Response res;
    try {
      res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        },
        body: jsonEncode(request.toJson()),
        timeout: const Duration(seconds: 30),
        requireAuth: true,
      );
    } on TimeoutException {
      throw Exception('Generation request timed out');
    } on SocketException catch (e) {
      throw Exception('Network error starting generation: ${e.message}');
    }

    Map<String, dynamic> decoded = const {};
    try {
      final j = jsonDecode(res.body);
      if (j is Map<String, dynamic>) decoded = j;
      if (j is Map) decoded = j.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();
      throw Exception('AI generation failed (HTTP ${res.statusCode}): $msg');
    }
  }

  Future<List<AiCreatorGeneration>> listGenerations({
    required UserRole role,
  }) async {
    final uri = _uri(_generationsPathFor(role));

    http.Response res;
    try {
      res = await FirebaseAuthedHttp.get(
        uri,
        headers: const {
          HttpHeaders.acceptHeader: 'application/json',
        },
        timeout: const Duration(seconds: 5),
        requireAuth: true,
      );
    } on TimeoutException {
      throw Exception('Generations request timed out');
    } on SocketException catch (e) {
      throw Exception('Network error loading generations: ${e.message}');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }

    if (res.statusCode != 200) {
      final msg = (decoded is Map ? (decoded['message'] ?? decoded['error']) : null) ?? res.body;
      throw Exception('Failed to load generations (HTTP ${res.statusCode}): $msg');
    }

    final List items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['generations'] is List) {
      items = decoded['generations'] as List;
    } else if (decoded is Map && decoded['items'] is List) {
      items = decoded['items'] as List;
    } else {
      items = const [];
    }

    return items
        .whereType<Object?>()
        .map(
          (it) => it is Map<String, dynamic>
              ? AiCreatorGeneration.fromJson(it)
              : it is Map
                  ? AiCreatorGeneration.fromJson(it.map((k, v) => MapEntry(k.toString(), v)))
                  : null,
        )
        .whereType<AiCreatorGeneration>()
        .toList();
  }
}
