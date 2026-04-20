import 'dart:convert';

import '../../../app/network/api_uri_builder.dart';
import '../../../app/network/firebase_authed_http.dart';

class ArtistDashboardSettings {
  const ArtistDashboardSettings({
    required this.notificationsEnabled,
    required this.emailAlerts,
    required this.dataSharingEnabled,
  });

  final bool notificationsEnabled;
  final bool emailAlerts;
  final bool dataSharingEnabled;

  static const defaults = ArtistDashboardSettings(
    notificationsEnabled: true,
    emailAlerts: true,
    dataSharingEnabled: false,
  );

  ArtistDashboardSettings copyWith({
    bool? notificationsEnabled,
    bool? emailAlerts,
    bool? dataSharingEnabled,
  }) {
    return ArtistDashboardSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      emailAlerts: emailAlerts ?? this.emailAlerts,
      dataSharingEnabled: dataSharingEnabled ?? this.dataSharingEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'notifications_enabled': notificationsEnabled,
        'email_alerts': emailAlerts,
        'data_sharing': dataSharingEnabled,
      };

  static ArtistDashboardSettings fromJson(Map<String, dynamic> json) {
    bool readBool(String key, bool fallback) {
      final v = json[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
      return fallback;
    }

    return ArtistDashboardSettings(
      notificationsEnabled: readBool('notifications_enabled', defaults.notificationsEnabled),
      emailAlerts: readBool('email_alerts', defaults.emailAlerts),
      dataSharingEnabled: readBool('data_sharing', defaults.dataSharingEnabled),
    );
  }
}

class ArtistDashboardSettingsService {
  const ArtistDashboardSettingsService({ApiUriBuilder? uriBuilder}) : _uriBuilder = uriBuilder ?? const ApiUriBuilder();

  final ApiUriBuilder _uriBuilder;

  Future<ArtistDashboardSettings> load() async {
    final uri = _uriBuilder.build('/api/profile/settings');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 10),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return ArtistDashboardSettings.defaults;
    }

    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final raw = decoded['settings'];
        if (raw is Map) {
          return ArtistDashboardSettings.fromJson(Map<String, dynamic>.from(raw));
        }
      }
    } catch (_) {
      // ignore
    }

    return ArtistDashboardSettings.defaults;
  }

  Future<ArtistDashboardSettings> update(ArtistDashboardSettings settings) async {
    final uri = _uriBuilder.build('/api/profile/settings');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'settings': settings.toJson()}),
      timeout: const Duration(seconds: 12),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Failed to save settings (${res.statusCode}).');
    }

    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final raw = decoded['settings'];
        if (raw is Map) {
          return ArtistDashboardSettings.fromJson(Map<String, dynamic>.from(raw));
        }
      }
    } catch (_) {
      // ignore
    }

    return settings;
  }

  Future<Map<String, dynamic>> exportData() async {
    final uri = _uriBuilder.build('/api/profile/export');
    final res = await FirebaseAuthedHttp.get(
      uri,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 15),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Export failed (${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return <String, dynamic>{};
  }

  Future<void> deleteAccount() async {
    final uri = _uriBuilder.build('/api/profile/delete');
    final res = await FirebaseAuthedHttp.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'confirm': true}),
      timeout: const Duration(seconds: 15),
      requireAuth: true,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Delete failed (${res.statusCode}).');
    }
  }
}
