import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'upload_media_compressor.dart';

String _baseName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'file';
  final dot = n.lastIndexOf('.');
  if (dot <= 0) return n;
  return n.substring(0, dot);
}

String _safeExt(String name) {
  final n = name.trim();
  final dot = n.lastIndexOf('.');
  if (dot < 0 || dot >= n.length - 1) return 'bin';
  final ext = n.substring(dot + 1).toLowerCase();
  // Keep it conservative: only allow short alnum extensions.
  final safe = ext.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (safe.isEmpty || safe.length > 8) return 'bin';
  return safe;
}

Future<Uint8List?> _tryTranscode({
  required Uint8List inputBytes,
  required String inputExt,
  required String outExt,
  required List<String> ffmpegArgs,
}) async {
  // FFmpegKit is not supported on all desktop targets; be safe.
  if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    return null;
  }

  final tmp = await getTemporaryDirectory();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final inputPath = '${tmp.path}/weafrica_upload_in_$stamp.$inputExt';
  final outPath = '${tmp.path}/weafrica_upload_out_$stamp.$outExt';

  final inFile = File(inputPath);
  final outFile = File(outPath);

  try {
    await inFile.writeAsBytes(inputBytes, flush: true);

    final args = <String>['-y', '-i', inputPath, ...ffmpegArgs, outPath];
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      return null;
    }

    if (!await outFile.exists()) {
      return null;
    }

    final outBytes = await outFile.readAsBytes();
    if (outBytes.isEmpty) return null;

    // Avoid “compression” that grows the file.
    if (outBytes.lengthInBytes >= inputBytes.lengthInBytes) {
      return null;
    }

    return Uint8List.fromList(outBytes);
  } catch (_) {
    return null;
  } finally {
    try {
      if (await inFile.exists()) await inFile.delete();
    } catch (_) {}
    try {
      if (await outFile.exists()) await outFile.delete();
    } catch (_) {}
  }
}

Future<CompressedUpload> compressAudioForUploadImpl({
  required Uint8List inputBytes,
  required String originalName,
  UploadCompressionPreset preset = UploadCompressionPreset.balanced,
}) async {
  final base = _baseName(originalName);
  final inputExt = _safeExt(originalName);

  final bitrate = switch (preset) {
    UploadCompressionPreset.high => '192k',
    UploadCompressionPreset.balanced => '128k',
    UploadCompressionPreset.dataSaver => '96k',
  };

  final channels = preset == UploadCompressionPreset.dataSaver ? '1' : '2';

  // Try: AAC in M4A using the selected preset.
  final outBytes = await _tryTranscode(
    inputBytes: inputBytes,
    inputExt: inputExt,
    outExt: 'm4a',
    ffmpegArgs: <String>[
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      bitrate,
      '-ar',
      '44100',
      '-ac',
      channels,
      '-movflags',
      '+faststart',
    ],
  );

  if (outBytes == null) {
    return CompressedUpload(bytes: inputBytes, fileName: originalName);
  }
  return CompressedUpload(bytes: outBytes, fileName: '$base.m4a');
}

Future<CompressedUpload> compressVideoForUploadImpl({
  required Uint8List inputBytes,
  required String originalName,
  UploadCompressionPreset preset = UploadCompressionPreset.balanced,
}) async {
  final base = _baseName(originalName);
  final inputExt = _safeExt(originalName);

  final maxWidth = switch (preset) {
    UploadCompressionPreset.high => 1920,
    UploadCompressionPreset.balanced => 1280,
    UploadCompressionPreset.dataSaver => 854,
  };

  final crf = switch (preset) {
    UploadCompressionPreset.high => '23',
    UploadCompressionPreset.balanced => '28',
    UploadCompressionPreset.dataSaver => '32',
  };

  final speed = switch (preset) {
    UploadCompressionPreset.high => 'fast',
    UploadCompressionPreset.balanced => 'veryfast',
    UploadCompressionPreset.dataSaver => 'ultrafast',
  };

  // Try: H.264 + AAC in MP4, capped to 720p/1280w and reasonable CRF.
  // If this fails (codec unavailable), we fall back to original bytes.
  final outBytes = await _tryTranscode(
    inputBytes: inputBytes,
    inputExt: inputExt,
    outExt: 'mp4',
    ffmpegArgs: <String>[
      '-vf',
      "scale='min($maxWidth,iw)':-2",
      '-r',
      '30',
      '-c:v',
      'libx264',
      '-preset',
      speed,
      '-crf',
      crf,
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
    ],
  );

  if (outBytes == null) {
    return CompressedUpload(bytes: inputBytes, fileName: originalName);
  }
  return CompressedUpload(bytes: outBytes, fileName: '$base.mp4');
}

Future<CompressedUpload> compressImageForUploadImpl({
  required Uint8List inputBytes,
  required String originalName,
  int maxDimension = 800,
  int jpegQuality = 80,
}) async {
  final decoded = img.decodeImage(inputBytes);
  if (decoded == null) {
    return CompressedUpload(bytes: inputBytes, fileName: originalName);
  }

  final w = decoded.width;
  final h = decoded.height;
  final maxSide = w > h ? w : h;

  img.Image out = decoded;
  if (maxDimension > 0 && maxSide > maxDimension) {
    final scale = maxDimension / maxSide;
    final newW = (w * scale).round().clamp(1, maxDimension);
    final newH = (h * scale).round().clamp(1, maxDimension);
    out = img.copyResize(decoded, width: newW, height: newH, interpolation: img.Interpolation.average);
  }

  final q = jpegQuality.clamp(40, 95);
  final encoded = img.encodeJpg(out, quality: q);
  final outBytes = Uint8List.fromList(encoded);

  if (outBytes.isEmpty || outBytes.lengthInBytes >= inputBytes.lengthInBytes) {
    return CompressedUpload(bytes: inputBytes, fileName: originalName);
  }

  final base = _baseName(originalName);
  return CompressedUpload(bytes: outBytes, fileName: '$base.jpg');
}
