import 'dart:typed_data';

import 'upload_media_compressor_stub.dart'
    if (dart.library.html) 'upload_media_compressor_web.dart'
    if (dart.library.io) 'upload_media_compressor_io.dart';

class CompressedUpload {
  const CompressedUpload({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

enum UploadCompressionPreset {
  high,
  balanced,
  dataSaver;

  String get label {
    switch (this) {
      case UploadCompressionPreset.high:
        return 'High quality';
      case UploadCompressionPreset.balanced:
        return 'Balanced';
      case UploadCompressionPreset.dataSaver:
        return 'Data saver';
    }
  }
}

Future<CompressedUpload> compressAudioForUpload({
  required Uint8List inputBytes,
  required String originalName,
  UploadCompressionPreset preset = UploadCompressionPreset.balanced,
}) {
  return compressAudioForUploadImpl(
    inputBytes: inputBytes,
    originalName: originalName,
    preset: preset,
  );
}

Future<CompressedUpload> compressVideoForUpload({
  required Uint8List inputBytes,
  required String originalName,
  UploadCompressionPreset preset = UploadCompressionPreset.balanced,
}) {
  return compressVideoForUploadImpl(
    inputBytes: inputBytes,
    originalName: originalName,
    preset: preset,
  );
}

Future<CompressedUpload> compressImageForUpload({
  required Uint8List inputBytes,
  required String originalName,
  int maxDimension = 800,
  int jpegQuality = 80,
}) {
  return compressImageForUploadImpl(
    inputBytes: inputBytes,
    originalName: originalName,
    maxDimension: maxDimension,
    jpegQuality: jpegQuality,
  );
}
