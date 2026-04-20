import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List> readPlatformFileBytesImpl(PlatformFile file) {
  throw UnsupportedError('Reading file bytes is not supported on this platform.');
}
