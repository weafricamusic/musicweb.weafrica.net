import 'dart:typed_data';

import '../models/media_type.dart';
import '../../../app/media/upload_media_compressor.dart';

class CompressedFile {
  const CompressedFile({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class UploadCompressor {
  const UploadCompressor();

  Future<CompressedFile> compressPrimary({
    required MediaType type,
    required Uint8List bytes,
    required String originalName,
    UploadCompressionPreset preset = UploadCompressionPreset.balanced,
  }) async {
    final compressed = type == MediaType.song
        ? await compressAudioForUpload(inputBytes: bytes, originalName: originalName, preset: preset)
        : await compressVideoForUpload(inputBytes: bytes, originalName: originalName, preset: preset);
    return CompressedFile(bytes: compressed.bytes, fileName: compressed.fileName);
  }

  Future<CompressedFile> compressImage({
    required Uint8List bytes,
    required String originalName,
    int maxDimension = 800,
    int jpegQuality = 80,
  }) async {
    final compressed = await compressImageForUpload(
      inputBytes: bytes,
      originalName: originalName,
      maxDimension: maxDimension,
      jpegQuality: jpegQuality,
    );
    return CompressedFile(bytes: compressed.bytes, fileName: compressed.fileName);
  }
}
