import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'downloads_storage_model.dart';

Future<Directory> _downloadsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  return Directory('${dir.path}/pulse_downloads');
}

Future<List<DownloadedFile>> listDownloadedFilesImpl() async {
  try {
    final downloadsDir = await _downloadsDir();
    if (!await downloadsDir.exists()) return const <DownloadedFile>[];

    final out = <DownloadedFile>[];
    await for (final ent in downloadsDir.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;

      final stat = await ent.stat();
      final name = ent.uri.pathSegments.isEmpty ? ent.path.split(Platform.pathSeparator).last : ent.uri.pathSegments.last;
      out.add(
        DownloadedFile(
          path: ent.path,
          name: name,
          bytes: stat.size,
          modified: stat.modified,
        ),
      );
    }

    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  } catch (_) {
    return const <DownloadedFile>[];
  }
}

Future<bool> deleteDownloadedFileImpl(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  } catch (_) {
    return false;
  }
}

Future<int> clearDownloadedFilesImpl() async {
  try {
    final downloadsDir = await _downloadsDir();
    if (!await downloadsDir.exists()) return 0;

    int count = 0;
    await for (final ent in downloadsDir.list(recursive: true, followLinks: false)) {
      if (ent is File) count += 1;
    }

    await downloadsDir.delete(recursive: true);
    return count;
  } catch (_) {
    return 0;
  }
}
