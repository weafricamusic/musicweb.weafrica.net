import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/upload_status.dart';

/// Persists upload progress so app restarts don't lose state.
///
/// Note: This stores lightweight status only (not file bytes).
class UploadPersistence {
  UploadPersistence._();
  static final instance = UploadPersistence._();

  static const String _key = 'weafrica.uploads.v1';

  Future<List<UploadStatus>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final out = <UploadStatus>[];
      for (final item in decoded) {
        if (item is Map) {
          final s = UploadStatus.tryFromJson(Map<String, dynamic>.from(item));
          if (s != null) out.add(s);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(UploadStatus status) async {
    final existing = await loadAll();
    final list = existing.where((e) => e.uploadId != status.uploadId).toList(growable: true);
    list.add(status);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<void> remove(String uploadId) async {
    final existing = await loadAll();
    final list = existing.where((e) => e.uploadId != uploadId).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
