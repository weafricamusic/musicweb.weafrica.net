import 'downloads_storage_impl_stub.dart'
    if (dart.library.io) 'downloads_storage_impl_io.dart';

import 'downloads_storage_model.dart';

export 'downloads_storage_model.dart';

Future<List<DownloadedFile>> listDownloadedFiles() => listDownloadedFilesImpl();

Future<bool> deleteDownloadedFile(String path) => deleteDownloadedFileImpl(path);

Future<int> clearDownloadedFiles() => clearDownloadedFilesImpl();
