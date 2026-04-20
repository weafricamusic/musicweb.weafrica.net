import 'download_stats_model.dart';

Future<DownloadStats> getDownloadStatsImpl() async {
  // Web (and other non-io platforms): downloads folder is not accessible.
  return const DownloadStats(fileCount: 0, totalBytes: 0);
}
