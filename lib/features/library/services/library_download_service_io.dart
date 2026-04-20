import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_download_service.dart';

class LibraryDownloadServiceImpl implements LibraryDownloadService {
  static const _prefsKey = 'library_track_downloads_v1';

  Future<Directory> _downloadsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/track_downloads');
  }

  Future<Map<String, String>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim();
        if (key.isEmpty || value == null || value.isEmpty) continue;
        out[key] = value;
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeIndex(Map<String, String> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(index));
  }

  @override
  Future<Map<String, String>> listDownloadedTrackPaths() async {
    final index = await _readIndex();
    final out = <String, String>{};

    for (final entry in index.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        out[entry.key] = entry.value;
      }
    }

    if (out.length != index.length) {
      await _writeIndex(out);
    }

    return out;
  }

  @override
  Future<String?> getLocalPathForTrackId(String trackId) async {
    final id = trackId.trim();
    if (id.isEmpty) return null;

    final index = await _readIndex();
    final path = index[id];
    if (path == null || path.trim().isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) {
      index.remove(id);
      await _writeIndex(index);
      return null;
    }

    return path;
  }

  @override
  Future<String> downloadTrack({
    required String trackId,
    required Uri remoteUri,
    String? suggestedFileName,
  }) async {
    final id = trackId.trim();
    if (id.isEmpty) throw StateError('Missing trackId');

    final res = await http.get(remoteUri).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Download failed (${res.statusCode})');
    }

    final dir = await _downloadsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final safeName = (suggestedFileName ?? 'track_$id.mp3').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filename = safeName.isEmpty ? 'track_$id.mp3' : safeName;
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(res.bodyBytes, flush: true);

    final index = await _readIndex();
    index[id] = file.path;
    await _writeIndex(index);

    return file.path;
  }

  @override
  Future<bool> removeDownload(String trackId) async {
    final id = trackId.trim();
    if (id.isEmpty) return false;

    final index = await _readIndex();
    final path = index.remove(id);
    await _writeIndex(index);

    if (path == null || path.trim().isEmpty) return true;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort
    }

    return true;
  }

  @override
  Future<int> clearDownloads() async {
    final index = await _readIndex();
    int removed = 0;

    for (final path in index.values) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          removed += 1;
        }
      } catch (_) {
        // ignore
      }
    }

    await _writeIndex(<String, String>{});

    try {
      final dir = await _downloadsDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // ignore
    }

    return removed;
  }
}
