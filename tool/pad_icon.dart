import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final inPath = _argValue(args, '--in') ?? 'assets/images/launcher_icon.png';
  final outPath = _argValue(args, '--out') ??
      'assets/images/launcher_icon_foreground.png';
  final scale = double.tryParse(_argValue(args, '--scale') ?? '0.72') ?? 0.72;

  if (scale <= 0 || scale > 1) {
    stderr.writeln('Invalid --scale. Use a value in (0, 1].');
    exitCode = 2;
    return;
  }

  final inFile = File(inPath);
  if (!inFile.existsSync()) {
    stderr.writeln('Input not found: $inPath');
    exitCode = 2;
    return;
  }

  final bytes = inFile.readAsBytesSync();
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    stderr.writeln('Failed to decode PNG: $inPath');
    exitCode = 2;
    return;
  }

  // Ensure square canvas based on the largest dimension.
  final size = decoded.width > decoded.height ? decoded.width : decoded.height;

  // Resize the source to fit within the padded area.
  final targetSize = (size * scale).round();
  final resized = img.copyResize(
    decoded,
    width: targetSize,
    height: targetSize,
    interpolation: img.Interpolation.cubic,
  );

  // Transparent square canvas.
  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final dx = ((size - resized.width) / 2).round();
  final dy = ((size - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(canvas));

  stdout.writeln('Wrote padded foreground: $outPath');
}

String? _argValue(List<String> args, String name) {
  final idx = args.indexOf(name);
  if (idx == -1) return null;
  if (idx + 1 >= args.length) return null;
  return args[idx + 1];
}
