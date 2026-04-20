import 'beat_download_service_stub.dart'
    if (dart.library.io) 'beat_download_service_io.dart';

abstract class BeatDownloadService {
  factory BeatDownloadService() = BeatDownloadServiceImpl;

  /// Downloads the remote MP3 and returns the local file path.
  Future<String> downloadMp3({
    required String url,
    required String fileNameStem,
  });
}
