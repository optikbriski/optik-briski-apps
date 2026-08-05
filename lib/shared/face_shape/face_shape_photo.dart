import '../theme.dart';
import 'package:flutter/material.dart';

import 'face_shape_type.dart';

/// Foto model referensi per bentuk wajah (+ overlay frame rekomendasi).
class FaceShapePhoto extends StatelessWidget {
  const FaceShapePhoto({
    super.key,
    required this.shape,
    this.size = 200,
    this.showFrame = false,
    this.frameVariant = 0,
  });

  final FaceShapeType shape;
  final double size;
  final bool showFrame;
  final int frameVariant;

  static String assetFor(FaceShapeType shape) {
    switch (shape) {
      case FaceShapeType.oval:
        return 'assets/images/face_shapes/face_oval.png';
      case FaceShapeType.round:
        return 'assets/images/face_shapes/face_round.png';
      case FaceShapeType.square:
        return 'assets/images/face_shapes/face_square.png';
      case FaceShapeType.heart:
        return 'assets/images/face_shapes/face_heart.png';
      case FaceShapeType.diamond:
        return 'assets/images/face_shapes/face_diamond.png';
      case FaceShapeType.oblong:
        return 'assets/images/face_shapes/face_oblong.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              assetFor(shape),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: OptikAdminTokens.lineStrong,
                child: Center(
                  child: Text(
                    shape.labelId,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            if (showFrame)
              CustomPaint(
                painter: FaceFrameOverlayPainter(
                  shape: shape,
                  frameVariant: frameVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Overlay kacamata di atas foto (posisi mata ~45% tinggi portrait).
class FaceFrameOverlayPainter extends CustomPainter {
  FaceFrameOverlayPainter({
    required this.shape,
    required this.frameVariant,
  });

  final FaceShapeType shape;
  final int frameVariant;

  @override
  void paint(Canvas canvas, Size size) {
    // Reuse style helpers from visual via temporary FaceShapeVisual painter logic.
    final style = _style(shape, frameVariant);
    final eyeY = size.height * 0.455;
    final halfGap = size.width * 0.028;
    final lensW = size.width * style.lensW;
    final lensH = size.height * style.lensH;
    final leftCx = size.width / 2 - halfGap - lensW / 2;
    final rightCx = size.width / 2 + halfGap + lensW / 2;

    final stroke = Paint()
      ..color = OptikAdminTokens.navy.withOpacity(0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.bold ? 3.6 : 2.6
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = OptikAdminTokens.navy.withOpacity(0.16)
      ..style = PaintingStyle.fill;

    Path lens(double cx) {
      final rect = Rect.fromCenter(
        center: Offset(cx, eyeY),
        width: lensW,
        height: lensH,
      );
      switch (style.kind) {
        case _K.round:
          return Path()..addOval(rect);
        case _K.rect:
          return Path()
            ..addRRect(RRect.fromRectAndRadius(
              rect,
              Radius.circular(style.corner),
            ));
        case _K.catEye:
          final p = Path();
          p.moveTo(rect.left, rect.center.dy);
          p.quadraticBezierTo(
              rect.left, rect.top, rect.center.dx - 2, rect.top + 2);
          p.quadraticBezierTo(
              rect.right - 4, rect.top - 6, rect.right + 3, rect.top + 8);
          p.quadraticBezierTo(
              rect.right, rect.bottom, rect.center.dx, rect.bottom);
          p.quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.center.dy);
          p.close();
          return p;
        case _K.aviator:
          final p = Path();
          p.moveTo(rect.left, rect.top + lensH * 0.22);
          p.lineTo(rect.right, rect.top + lensH * 0.15);
          p.quadraticBezierTo(
              rect.right + 2, rect.bottom, rect.center.dx, rect.bottom);
          p.quadraticBezierTo(
              rect.left - 2, rect.bottom, rect.left, rect.top + lensH * 0.22);
          p.close();
          return p;
      }
    }

    final left = lens(leftCx);
    final right = lens(rightCx);
    canvas.drawPath(left, fill);
    canvas.drawPath(right, fill);
    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);

    canvas.drawLine(
      Offset(leftCx + lensW / 2, eyeY),
      Offset(rightCx - lensW / 2, eyeY),
      stroke,
    );

    final templeY = eyeY - lensH * 0.08;
    canvas.drawLine(
      Offset(leftCx - lensW / 2, templeY),
      Offset(leftCx - lensW / 2 - size.width * 0.1, templeY - 3),
      stroke,
    );
    canvas.drawLine(
      Offset(rightCx + lensW / 2, templeY),
      Offset(rightCx + lensW / 2 + size.width * 0.1, templeY - 3),
      stroke,
    );

    if (style.browline) {
      final brow = Paint()
        ..color = OptikAdminTokens.navy.withOpacity(0.88)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(leftCx - lensW / 2, eyeY - lensH / 2),
        Offset(leftCx + lensW / 2, eyeY - lensH / 2),
        brow,
      );
      canvas.drawLine(
        Offset(rightCx - lensW / 2, eyeY - lensH / 2),
        Offset(rightCx + lensW / 2, eyeY - lensH / 2),
        brow,
      );
    }
  }

  _S _style(FaceShapeType shape, int variant) {
    switch (shape) {
      case FaceShapeType.oval:
        return variant == 0
            ? const _S(kind: _K.rect, lensW: 0.26, lensH: 0.11, corner: 7, bold: true)
            : const _S(kind: _K.round, lensW: 0.24, lensH: 0.13, corner: 99);
      case FaceShapeType.round:
        return variant == 0
            ? const _S(kind: _K.rect, lensW: 0.27, lensH: 0.10, corner: 5, bold: true)
            : const _S(
                kind: _K.rect,
                lensW: 0.26,
                lensH: 0.11,
                corner: 4,
                bold: true,
                browline: true,
              );
      case FaceShapeType.square:
        return variant == 0
            ? const _S(kind: _K.round, lensW: 0.25, lensH: 0.14, corner: 99)
            : const _S(kind: _K.catEye, lensW: 0.27, lensH: 0.11, corner: 10);
      case FaceShapeType.heart:
        return variant == 0
            ? const _S(kind: _K.aviator, lensW: 0.28, lensH: 0.13, corner: 8)
            : const _S(kind: _K.round, lensW: 0.24, lensH: 0.13, corner: 99);
      case FaceShapeType.diamond:
        return variant == 0
            ? const _S(kind: _K.catEye, lensW: 0.27, lensH: 0.11, corner: 10)
            : const _S(kind: _K.round, lensW: 0.25, lensH: 0.12, corner: 99);
      case FaceShapeType.oblong:
        return variant == 0
            ? const _S(kind: _K.rect, lensW: 0.32, lensH: 0.10, corner: 7, bold: true)
            : const _S(kind: _K.rect, lensW: 0.30, lensH: 0.11, corner: 5, bold: true);
    }
  }

  @override
  bool shouldRepaint(covariant FaceFrameOverlayPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.frameVariant != frameVariant;
}

enum _K { round, rect, catEye, aviator }

class _S {
  const _S({
    required this.kind,
    required this.lensW,
    required this.lensH,
    required this.corner,
    this.bold = false,
    this.browline = false,
  });

  final _K kind;
  final double lensW;
  final double lensH;
  final double corner;
  final bool bold;
  final bool browline;
}
