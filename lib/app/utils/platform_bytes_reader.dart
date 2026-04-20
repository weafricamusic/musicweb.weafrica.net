import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'platform_bytes_reader_stub.dart'
    if (dart.library.html) 'platform_bytes_reader_web.dart'
    if (dart.library.io) 'platform_bytes_reader_io.dart';

Future<Uint8List> readPlatformFileBytes(PlatformFile file) {
  return readPlatformFileBytesImpl(file);
}
