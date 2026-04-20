import 'beat_download_service.dart';

class BeatDownloadServiceImpl implements BeatDownloadService {
  @override
  Future<String> downloadMp3({
    required String url,
    required String fileNameStem,
  }) {
    throw UnsupportedError('Download is not supported on this platform yet.');
  }
}
