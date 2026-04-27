part of 'home_screen.dart';

// ── Home Clock Painter (large circle with optional charging arc) ────────────────

class _HomeClockPainter extends CustomPainter {
  final double animValue;
  final bool isCharging;
  const _HomeClockPainter({required this.animValue, required this.isCharging});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Always draw faint background circle
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, bgPaint);

    // Charging arc (sweeps half revolution in 30s)
    if (isCharging) {
      final arcPaint = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      final sweep = pi * animValue; // 0 → π (half revolution)
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        sweep,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HomeClockPainter old) =>
      old.animValue != animValue || old.isCharging != isCharging;
}
