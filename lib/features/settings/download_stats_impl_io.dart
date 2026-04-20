import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'download_stats_model.dart';

Future<DownloadStats> getDownloadStatsImpl() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${dir.path}/pulse_downloads');
    if (!await downloadsDir.exists()) {
      return const DownloadStats(fileCount: 0, totalBytes: 0);
    }

    int files = 0;
    int bytes = 0;
    await for (final ent in downloadsDir.list(recursive: true, followLinks: false)) {
      if (ent is File) {
        files += 1;
        try {
          bytes += await ent.length();
        } catch (_) {}
      }
    }
    return DownloadStats(fileCount: files, totalBytes: bytes);
  } catch (_) {
    return const DownloadStats(fileCount: 0, totalBytes: 0);
  }
}
