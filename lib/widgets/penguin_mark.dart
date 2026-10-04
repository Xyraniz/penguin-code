import 'package:flutter/material.dart';

import '../app_theme.dart';

class PenguinMark extends StatelessWidget {
  const PenguinMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.iceStrong,
        shape: BoxShape.circle,
      ),
      child: const CustomPaint(painter: _PenguinPainter()),
    );
  }
}

class _PenguinPainter extends CustomPainter {
  const _PenguinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40;
    canvas.save();
    canvas.scale(scale, scale);

    final outline = Paint()..color = const Color(0xFF334B5D);
    final belly = Paint()..color = const Color(0xFFF8FCFF);
    final eye = Paint()..color = const Color(0xFF19364B);
    final beak = Paint()..color = const Color(0xFFF2C66D);
    final flipper = Paint()..color = const Color(0xFF728B9B);

    canvas.drawOval(const Rect.fromLTWH(8, 4, 24, 33), outline);
    canvas.drawOval(const Rect.fromLTWH(12, 17, 16, 18), belly);
    canvas.drawOval(const Rect.fromLTWH(8, 19, 6, 14), flipper);
    canvas.drawOval(const Rect.fromLTWH(26, 19, 6, 14), flipper);
    canvas.drawCircle(const Offset(15, 14), 1.5, eye);
    canvas.drawCircle(const Offset(25, 14), 1.5, eye);
    canvas.drawPath(
      Path()
        ..moveTo(18, 16)
        ..lineTo(22, 16)
        ..lineTo(20, 18)
        ..close(),
      beak,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PenguinPainter oldDelegate) => false;
}
