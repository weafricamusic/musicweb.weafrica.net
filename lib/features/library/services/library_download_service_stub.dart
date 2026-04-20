import 'library_download_service.dart';

class LibraryDownloadServiceImpl implements LibraryDownloadService {
  @override
  Future<int> clearDownloads() async {
    throw UnsupportedError('Downloads are not supported on this platform.');
  }

  @override
  Future<String> downloadTrack({
    required String trackId,
    required Uri remoteUri,
    String? suggestedFileName,
  }) async {
    throw UnsupportedError('Downloads are not supported on this platform.');
  }

  @override
  Future<String?> getLocalPathForTrackId(String trackId) async {
    return null;
  }

  @override
  Future<Map<String, String>> listDownloadedTrackPaths() async {
    return const <String, String>{};
  }

  @override
  Future<bool> removeDownload(String trackId) async {
    return false;
  }
}
