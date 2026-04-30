import 'dart:convert';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

class LiveSetupPrivacyOption {
  const LiveSetupPrivacyOption({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}

class LiveSetupMonetizationOption {
  const LiveSetupMonetizationOption({
    required this.id,
    required this.label,
    required this.enabled,
  });

  final String id;
  final String label;
  final bool enabled;
}

class LiveSetupOptions {
  const LiveSetupOptions({
    required this.privacy,
    required this.monetization,
  });

  final List<LiveSetupPrivacyOption> privacy;
  final List<LiveSetupMonetizationOption> monetization;
}

class LiveSetupOptionsApi {
  const LiveSetupOptionsApi({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Map<String, dynamic>? _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<LiveSetupOptions?> fetchOptions() async {
    final uri = _uriBuilder.build('/api/live/setup/options');

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
      throw StateError('Failed to fetch live setup options (${res.statusCode})');
    }

    final decoded = _decodeJsonMap(res.body);
    if (decoded == null || decoded['ok'] != true) {
      throw StateError('Invalid live setup options response shape');
    }

    final privacyRaw = decoded['privacy'];
    final monetizationRaw = decoded['monetization'];

    final privacy = <LiveSetupPrivacyOption>[];
    if (privacyRaw is List) {
      for (final item in privacyRaw) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final id = (map['id'] ?? '').toString().trim();
          final label = (map['label'] ?? '').toString().trim();
          final desc = (map['description'] ?? '').toString().trim();
          if (id.isEmpty || label.isEmpty) continue;
          privacy.add(LiveSetupPrivacyOption(id: id, label: label, description: desc.isEmpty ? null : desc));
        }
      }
    }

    final monetization = <LiveSetupMonetizationOption>[];
    if (monetizationRaw is List) {
      for (final item in monetizationRaw) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final id = (map['id'] ?? '').toString().trim();
          final label = (map['label'] ?? '').toString().trim();
          final enabled = map['enabled'] == true;
          if (id.isEmpty || label.isEmpty) continue;
          monetization.add(LiveSetupMonetizationOption(id: id, label: label, enabled: enabled));
        }
      }
    }

    if (privacy.isEmpty && monetization.isEmpty) {
      throw StateError('Live setup options payload is empty');
    }

    return LiveSetupOptions(privacy: privacy, monetization: monetization);
  }
}
