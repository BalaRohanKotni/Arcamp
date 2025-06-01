// ignore_for_file: avoid_print
import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final Color accentColor;
  final bool isDragging;

  WaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.accentColor,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final Paint activePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final Paint inactivePaint = Paint()
      ..color = accentColor.withAlpha(77)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final double barWidth = size.width / waveformData.length;
    final double centerY = size.height / 2;
    final double progressX = progress * size.width;

    for (int i = 0; i < waveformData.length; i++) {
      final double x = i * barWidth + barWidth / 2;
      final double barHeight = waveformData[i] * size.height * 0.8;
      final double startY = centerY - barHeight / 2;
      final double endY = centerY + barHeight / 2;

      final Paint paint = x <= progressX ? activePaint : inactivePaint;

      canvas.drawLine(Offset(x, startY), Offset(x, endY), paint);
    }

    // Draw progress indicator (thumb)
    if (isDragging || progress > 0) {
      final Paint thumbPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(progressX, centerY), 6.0, thumbPaint);

      // Draw outer ring for better visibility
      final Paint ringPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(Offset(progressX, centerY), 6.0, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
