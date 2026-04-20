import 'dart:typed_data';

import 'upload_media_compressor.dart';

Future<CompressedUpload> compressAudioForUploadImpl({
  required Uint8List inputBytes,
  required String originalName,
  UploadCompressionPreset preset = UploadCompressionPreset.balanced,
}) async {
  return CompressedUpload(bytes: inputBytes, fileName: originalName);
}

Future<CompressedUpload> compressVideoForUploadImpl({
  required Uint8List inputBytes,
  required String originalName,
  UploadCompressionPreset preset = UploadCompressionPreset.balanced,
}) async {
  return CompressedUpload(bytes: inputBytes, fileName: originalName);
}

Future<CompressedUpload> compressImageForUploadImpl({
  required Uint8List inputBytes,
  required String originalName,
  int maxDimension = 800,
  int jpegQuality = 80,
}) async {
  return CompressedUpload(bytes: inputBytes, fileName: originalName);
}
