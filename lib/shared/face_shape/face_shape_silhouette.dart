import '../theme.dart';
import 'package:flutter/material.dart';

import 'face_shape_type.dart';

/// Siluet bentuk wajah (CustomPaint) untuk referensi visual.
class FaceShapeSilhouette extends StatelessWidget {
  const FaceShapeSilhouette({
    super.key,
    required this.shape,
    this.size = 88,
    this.color = OptikAdminTokens.navy,
    this.fillOpacity = 0.12,
  });

  final FaceShapeType shape;
  final double size;
  final Color color;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(
        painter: _FaceSilhouettePainter(
          shape: shape,
          color: color,
          fillOpacity: fillOpacity,
        ),
      ),
    );
  }
}

class _FaceSilhouettePainter extends CustomPainter {
  _FaceSilhouettePainter({
    required this.shape,
    required this.color,
    required this.fillOpacity,
  });

  final FaceShapeType shape;
  final Color color;
  final double fillOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _pathFor(shape, size);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(fillOpacity)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Mata + hidung tip sederhana biar kebaca “wajah”.
    final eyeY = size.height * 0.42;
    final eyeR = size.width * 0.035;
    final eyePaint = Paint()..color = color.withOpacity(0.55);
    canvas.drawCircle(Offset(size.width * 0.35, eyeY), eyeR, eyePaint);
    canvas.drawCircle(Offset(size.width * 0.65, eyeY), eyeR, eyePaint);
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.46),
      Offset(size.width * 0.5, size.height * 0.58),
      Paint()
        ..color = color.withOpacity(0.4)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.68),
        width: size.width * 0.22,
        height: size.height * 0.08,
      ),
      0.15,
      2.84,
      false,
      Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  Path _pathFor(FaceShapeType shape, Size size) {
    final w = size.width;
    final h = size.height;
    switch (shape) {
      case FaceShapeType.oval:
        return Path()
          ..addOval(Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.52),
            width: w * 0.72,
            height: h * 0.92,
          ));
      case FaceShapeType.round:
        return Path()
          ..addOval(Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.52),
            width: w * 0.86,
            height: h * 0.86,
          ));
      case FaceShapeType.square:
        return _roundPoly(size, const [
          Offset(0.22, 0.12),
          Offset(0.78, 0.12),
          Offset(0.82, 0.38),
          Offset(0.80, 0.72),
          Offset(0.72, 0.92),
          Offset(0.28, 0.92),
          Offset(0.20, 0.72),
          Offset(0.18, 0.38),
        ], corner: 0.06);
      case FaceShapeType.heart:
        return _smoothClosed(size, const [
          Offset(0.18, 0.22),
          Offset(0.28, 0.10),
          Offset(0.50, 0.14),
          Offset(0.72, 0.10),
          Offset(0.82, 0.22),
          Offset(0.78, 0.42),
          Offset(0.68, 0.62),
          Offset(0.56, 0.82),
          Offset(0.50, 0.92),
          Offset(0.44, 0.82),
          Offset(0.32, 0.62),
          Offset(0.22, 0.42),
        ]);
      case FaceShapeType.diamond:
        return _smoothClosed(size, const [
          Offset(0.50, 0.08),
          Offset(0.68, 0.28),
          Offset(0.86, 0.48),
          Offset(0.68, 0.72),
          Offset(0.50, 0.94),
          Offset(0.32, 0.72),
          Offset(0.14, 0.48),
          Offset(0.32, 0.28),
        ]);
      case FaceShapeType.oblong:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(w * 0.5, h * 0.52),
              width: w * 0.62,
              height: h * 0.96,
            ),
            Radius.circular(w * 0.28),
          ));
    }
  }

  Path _smoothClosed(Size size, List<Offset> norms) {
    final pts = [
      for (final n in norms) Offset(n.dx * size.width, n.dy * size.height),
    ];
    final path = Path();
    if (pts.length < 3) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length; i++) {
      final p0 = pts[i];
      final p1 = pts[(i + 1) % pts.length];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      if (i == 0) {
        path.lineTo(mid.dx, mid.dy);
      } else {
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
    }
    path.close();
    return path;
  }

  Path _roundPoly(Size size, List<Offset> norms, {required double corner}) {
    // Approksimasi sudut lembut via smooth closed.
    return _smoothClosed(size, norms);
  }

  @override
  bool shouldRepaint(covariant _FaceSilhouettePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.fillOpacity != fillOpacity;
}
