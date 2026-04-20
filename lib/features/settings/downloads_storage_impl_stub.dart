import 'downloads_storage_model.dart';

Future<List<DownloadedFile>> listDownloadedFilesImpl() async {
  // Web (and other non-io platforms): app documents directory is not accessible.
  return const <DownloadedFile>[];
}

Future<bool> deleteDownloadedFileImpl(String path) async {
  return false;
}

Future<int> clearDownloadedFilesImpl() async {
  return 0;
}
