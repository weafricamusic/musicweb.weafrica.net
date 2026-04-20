import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

class FirebaseWebEnv {
  static const String _apiKeyDefined =
      String.fromEnvironment('FIREBASE_WEB_API_KEY', defaultValue: '');
  static const String _authDomainDefined =
      String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN', defaultValue: '');
  static const String _projectIdDefined =
      String.fromEnvironment('FIREBASE_WEB_PROJECT_ID', defaultValue: '');
  static const String _storageBucketDefined =
      String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET', defaultValue: '');
  static const String _messagingSenderIdDefined =
      String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID', defaultValue: '');
  static const String _appIdDefined =
      String.fromEnvironment('FIREBASE_WEB_APP_ID', defaultValue: '');
  static const String _measurementIdDefined =
      String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID', defaultValue: '');

  static Map<String, dynamic>? _decoded;

  static Future<void> load({String assetPath = 'assets/config/supabase.env.json'}) async {
    if (_decoded != null) return;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        _decoded = parsed.map((k, v) => MapEntry(k.toString(), v));
      } else {
        _decoded = <String, dynamic>{};
      }
    } catch (_) {
      _decoded = <String, dynamic>{};
    }
  }

  static String _get(String key, String defined) {
    if (defined.trim().isNotEmpty) return defined.trim();
    final v = _decoded?[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return '';
  }

  static FirebaseOptions? tryOptions() {
    final apiKey = _get('FIREBASE_WEB_API_KEY', _apiKeyDefined);
    final authDomain = _get('FIREBASE_WEB_AUTH_DOMAIN', _authDomainDefined);
    final projectId = _get('FIREBASE_WEB_PROJECT_ID', _projectIdDefined);
    final storageBucket = _get('FIREBASE_WEB_STORAGE_BUCKET', _storageBucketDefined);
    final messagingSenderId =
        _get('FIREBASE_WEB_MESSAGING_SENDER_ID', _messagingSenderIdDefined);
    final appId = _get('FIREBASE_WEB_APP_ID', _appIdDefined);
    final measurementId = _get('FIREBASE_WEB_MEASUREMENT_ID', _measurementIdDefined);

    final hasRequired = apiKey.isNotEmpty &&
        projectId.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        appId.isNotEmpty;

    if (!hasRequired) return null;

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain,
      storageBucket: storageBucket,
      measurementId: measurementId,
    );
  }
}
