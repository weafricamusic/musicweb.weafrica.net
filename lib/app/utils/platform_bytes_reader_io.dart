import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List> readPlatformFileBytesImpl(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes != null) return bytes;

  final path = file.path;
  if (path == null || path.trim().isEmpty) {
    throw StateError('No file path available to read bytes.');
  }

  return File(path).readAsBytes();
}
