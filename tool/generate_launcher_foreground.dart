import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args[0] : 'assets/images/launcher_icon.png';
  final outputPath = args.length > 1
      ? args[1]
      : 'assets/images/launcher_foreground.png';

  // Android adaptive icon safe zone is roughly 66% of the full canvas.
  // We keep the canvas size the same as the source image (usually square),
  // then scale the artwork down to ~66% and center it.
  const safeZoneFraction = 0.66;

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input file not found: $inputPath');
    exitCode = 2;
    return;
  }

  final bytes = inputFile.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Failed to decode image: $inputPath');
    exitCode = 3;
    return;
  }

  final canvasSize = decoded.width < decoded.height ? decoded.width : decoded.height;
  if (canvasSize <= 0) {
    stderr.writeln('Invalid image dimensions: ${decoded.width}x${decoded.height}');
    exitCode = 4;
    return;
  }

  final targetMaxSide = (canvasSize * safeZoneFraction).round().clamp(1, canvasSize);
  final scale = targetMaxSide / (decoded.width > decoded.height ? decoded.width : decoded.height);
  final resizedWidth = (decoded.width * scale).round().clamp(1, canvasSize);
  final resizedHeight = (decoded.height * scale).round().clamp(1, canvasSize);

  final resized = img.copyResize(
    decoded,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: img.Interpolation.average,
  );

  final canvas = img.Image(width: canvasSize, height: canvasSize);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final dstX = ((canvasSize - resized.width) / 2).round();
  final dstY = ((canvasSize - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dstX, dstY: dstY);

  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(canvas));

  stdout.writeln('Wrote: $outputPath (${canvas.width}x${canvas.height})');
}
