import 'package:flutter/material.dart';

/// v1.2.2 completion animation: instead of the row popping off
/// instantly, a strike line draws across the title while the row fades
/// slightly, then the toggle lands and the row moves to Completed today.
const completeAnimationDuration = Duration(milliseconds: 800);

/// Strike/completed grey that reads on both brightnesses: classic grey
/// on light surfaces, a step lighter on dark ones. Shared by the
/// animated strike line and the static completed-row style so the
/// animation lands seamlessly into the same color.
Color completeStrikeColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade400
        : Colors.grey.shade500;

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
