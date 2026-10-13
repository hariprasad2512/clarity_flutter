import 'package:flutter/material.dart';

/// v1.2.2 completion animation: instead of the row popping off
/// instantly, a strike line draws across the title while the row fades
/// slightly, then the toggle lands and the row moves to Completed today.
const completeAnimationDuration = Duration(milliseconds: 800);

/// Draws a horizontal strike line across [progress] (0→1) of the width,
/// vertically centered — the animated counterpart of
/// `TextDecoration.lineThrough` used for already-completed rows.
class StrikePainter extends CustomPainter {
  const StrikePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * progress.clamp(0.0, 1.0), y),
      paint,
    );
  }

  @override
  bool shouldRepaint(StrikePainter old) =>
      old.progress != progress || old.color != color;
}
