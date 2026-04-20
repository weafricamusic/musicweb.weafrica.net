import 'package:flutter/material.dart';

class BeatWaveform extends StatelessWidget {
  const BeatWaveform({
    super.key,
    required this.data,
    required this.isPlaying,
    required this.color,
    this.playheadT,
  });

  final List<double> data;
  final bool isPlaying;
  final Color color;

  /// 0..1 playhead position.
  final double? playheadT;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        data: data,
        isPlaying: isPlaying,
        color: color,
        playheadT: playheadT,
      ),
      size: const Size(double.infinity, 100),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.data,
    required this.isPlaying,
    required this.color,
    required this.playheadT,
  });

  final List<double> data;
  final bool isPlaying;
  final Color color;
  final double? playheadT;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final barWidth = size.width / data.length;
    final centerY = size.height / 2;

    final paint = Paint()
      ..color = color.withValues(alpha: isPlaying ? 1.0 : 0.55)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final barHeight = (data[i]).clamp(0.0, 1.0) * size.height * 0.85;
      final x = i * barWidth + 2;
      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        (barWidth - 4).clamp(0.0, double.infinity),
        barHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }

    final t = playheadT;
    if (isPlaying && t != null) {
      final playheadPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final x = (size.width * t).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.isPlaying != isPlaying ||
        oldDelegate.data != data ||
        oldDelegate.playheadT != playheadT ||
        oldDelegate.color != color;
  }
}
