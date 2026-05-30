import 'dart:math' as math;

import 'package:flutter/material.dart';

class ProjectLogo extends StatelessWidget {
  const ProjectLogo({
    super.key,
    this.size = 64,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ProjectLogoPainter(
          shadowColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withValues(alpha: 0.5)
              : const Color(0x330F172A),
        ),
      ),
    );
  }
}

class _ProjectLogoPainter extends CustomPainter {
  const _ProjectLogoPainter({required this.shadowColor});

  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4);
    canvas.scale(scale);

    final pill = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-45, -18, 90, 36),
      const Radius.circular(18),
    );

    final shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawRRect(pill.shift(const Offset(5, 7)), shadowPaint);

    final clipPath = Path()..addRRect(pill);
    canvas.save();
    canvas.clipPath(clipPath);

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF0254D6),
          Color(0xFF168AF4),
          Color(0xFF65D8F5),
        ],
      ).createShader(pill.outerRect);
    canvas.drawRRect(pill, bodyPaint);

    const leftHalf = Rect.fromLTWH(-45, -18, 45, 36);
    final leftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF0153C8),
          Color(0xFF0575EA),
          Color(0xFF249BFF),
        ],
      ).createShader(leftHalf);
    canvas.drawRect(leftHalf, leftPaint);

    const rightHalf = Rect.fromLTWH(0, -18, 45, 36);
    final rightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF0474DC),
          Color(0xFF40BDF2),
          Color(0xFF7EE6FA),
        ],
      ).createShader(rightHalf);
    canvas.drawRect(rightHalf, rightPaint);

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = Colors.white.withValues(alpha: 0.32);
    final highlight = Path()
      ..moveTo(-30, -10)
      ..quadraticBezierTo(-8, -18, 15, -12)
      ..quadraticBezierTo(25, -10, 34, -11);
    canvas.drawPath(highlight, highlightPaint);

    final lowerGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: 0.1);
    final lowerGlow = Path()
      ..moveTo(-35, 11)
      ..quadraticBezierTo(-12, 19, 17, 8);
    canvas.drawPath(lowerGlow, lowerGlowPaint);

    final seamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFF0A5ECF).withValues(alpha: 0.9);
    canvas.drawLine(const Offset(0, -18), const Offset(0, 18), seamPaint);

    final seamGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawLine(const Offset(-2.5, -18), const Offset(-2.5, 18), seamGlow);

    canvas.restore();

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawRRect(pill.deflate(1), rimPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProjectLogoPainter oldDelegate) {
    return oldDelegate.shadowColor != shadowColor;
  }
}
