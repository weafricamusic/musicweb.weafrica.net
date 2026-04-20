import 'library_download_service_stub.dart'
    if (dart.library.io) 'library_download_service_io.dart';

abstract class LibraryDownloadService {
  factory LibraryDownloadService() = LibraryDownloadServiceImpl;

  Future<Map<String, String>> listDownloadedTrackPaths();

  Future<String?> getLocalPathForTrackId(String trackId);

  Future<String> downloadTrack({
    required String trackId,
    required Uri remoteUri,
    String? suggestedFileName,
  });

  Future<bool> removeDownload(String trackId);

  Future<int> clearDownloads();
}
