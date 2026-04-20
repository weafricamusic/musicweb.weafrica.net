import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'beat_download_service.dart';

class BeatDownloadServiceImpl implements BeatDownloadService {
  @override
  Future<String> downloadMp3({
    required String url,
    required String fileNameStem,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/weafrica_beats');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final safeStem = fileNameStem
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]+'), '')
        .trim()
        .replaceAll(' ', '_');

    String extension = 'mp3';
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      final dot = last.lastIndexOf('.');
      if (dot != -1 && dot < last.length - 1) {
        final ext = last.substring(dot + 1).toLowerCase();
        if (ext.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
          extension = ext;
        }
      }
    } catch (_) {
      // Best-effort extension parsing.
    }

    final file = File('${folder.path}/${safeStem.isEmpty ? 'beat' : safeStem}.$extension');

    if (await file.exists()) {
      final len = await file.length();
      if (len > 0) return file.path;
    }

    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Download failed (HTTP ${res.statusCode})');
    }

    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file.path;
  }
}
