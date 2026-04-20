import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List> readPlatformFileBytesImpl(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null) {
    throw StateError('No bytes available. Re-pick the file (web requires withData=true).');
  }
  return bytes;
}
