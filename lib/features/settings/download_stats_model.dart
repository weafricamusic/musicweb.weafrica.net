class DownloadStats {
  const DownloadStats({required this.fileCount, required this.totalBytes});

  final int fileCount;
  final int totalBytes;

  String get prettySize {
    final b = totalBytes;
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}
