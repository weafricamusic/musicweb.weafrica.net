import 'dart:convert';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

class LiveCategoriesApi {
  const LiveCategoriesApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Map<String, dynamic>? _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Fetches the list of live setup categories.
  ///
  /// Backend response shape:
  /// - { ok: true, categories: [{ id, label }, ...] }
  Future<List<String>> fetchCategories() async {
    final uri = _uriBuilder.build('/api/live/categories');

    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
      timeout: const Duration(seconds: 8),
      includeAuthIfAvailable: true,
      requireAuth: false,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Failed to fetch live categories (${res.statusCode})');
    }

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null || decoded['ok'] != true) {
      throw StateError('Invalid live categories response shape');
    }

    final raw = decoded['categories'];
    if (raw is! List) {
      throw StateError('Categories payload missing list');
    }

    final labels = <String>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final label = (map['label'] ?? '').toString().trim();
      if (label.isNotEmpty) labels.add(label);
    }
    return labels;
  }
}
