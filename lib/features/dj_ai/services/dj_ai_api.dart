import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/config/api_env.dart';
import '../../../app/config/app_env.dart';
import '../../../app/network/firebase_authed_http.dart';
import '../models/dj_models.dart';

class DjAiApi {
  const DjAiApi();

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

  Future<DjNextResponse> next(DjNextRequest data) async {
    final uri = _uri('/api/dj/next');

    http.Response res;
    try {
      res = await FirebaseAuthedHttp.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(data.toJson()),
        timeout: const Duration(seconds: 5),
        includeAuthIfAvailable: true,
      );
    } on TimeoutException {
      throw Exception('DJ AI request timed out');
    } on SocketException catch (e) {
      throw Exception('Network error calling DJ AI: ${e.message}');
    }

    Map<String, dynamic> decoded = const {};
    try {
      final j = jsonDecode(res.body);
      if (j is Map<String, dynamic>) decoded = j;
      if (j is Map) decoded = j.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}

    if (res.statusCode != 200) {
      final msg = (decoded['message'] ?? decoded['error'] ?? res.body).toString();
      throw Exception('DJ AI failed (HTTP ${res.statusCode}): $msg');
    }

    return DjNextResponse.fromJson(decoded);
  }
}
