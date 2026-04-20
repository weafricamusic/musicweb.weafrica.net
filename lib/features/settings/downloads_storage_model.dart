class DownloadedFile {
  const DownloadedFile({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modified,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime modified;

  String get prettySize {
    final b = bytes;
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}
