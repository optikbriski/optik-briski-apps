import 'package:flutter/material.dart';

import 'face_shape_type.dart';
import '../theme.dart';

/// Siluet bentuk wajah + contoh frame rekomendasi (ilustrasi).
class FaceShapeVisual extends StatelessWidget {
  const FaceShapeVisual({
    super.key,
    required this.shape,
    this.size = 148,
    this.showFrame = true,
    this.frameVariant = 0,
  });

  final FaceShapeType shape;
  final double size;

  /// Tampilkan kacamata rekomendasi di atas wajah.
  final bool showFrame;

  /// 0 = rekomendasi utama, 1 = alternatif (jika ada).
  final int frameVariant;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(
        painter: _FaceShapePainter(
          shape: shape,
          showFrame: showFrame,
          frameVariant: frameVariant,
        ),
      ),
    );
  }
}

class _FaceShapePainter extends CustomPainter {
  _FaceShapePainter({
    required this.shape,
    required this.showFrame,
    required this.frameVariant,
  });

  final FaceShapeType shape;
  final bool showFrame;
  final int frameVariant;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.48;
    final facePath = _facePath(Offset(cx, cy), size);

    // Soft fill
    canvas.drawPath(
      facePath,
      Paint()
        ..color = OptikAdminTokens.ice
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      facePath,
      Paint()
        ..color = OptikAdminTokens.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Simple facial guides (eyes / nose hint) — bukan foto orang.
    _drawGuides(canvas, Offset(cx, cy), size);

    if (showFrame) {
      _drawFrame(canvas, Offset(cx, cy), size);
    }
  }

  Path _facePath(Offset c, Size size) {
    final w = size.width;
    final h = size.height;
    switch (shape) {
      case FaceShapeType.oval:
        return Path()
          ..addOval(Rect.fromCenter(
            center: c,
            width: w * 0.62,
            height: h * 0.78,
          ));
      case FaceShapeType.round:
        return Path()
          ..addOval(Rect.fromCenter(
            center: c,
            width: w * 0.70,
            height: h * 0.70,
          ));
      case FaceShapeType.square:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: c,
            width: w * 0.66,
            height: h * 0.72,
          ),
          const Radius.circular(18),
        );
        return Path()..addRRect(r);
      case FaceShapeType.heart:
        return _heartLike(c, w * 0.36, h * 0.40);
      case FaceShapeType.diamond:
        return _diamond(c, w * 0.34, h * 0.40);
      case FaceShapeType.oblong:
        return Path()
          ..addOval(Rect.fromCenter(
            center: c,
            width: w * 0.52,
            height: h * 0.86,
          ));
    }
  }

  Path _heartLike(Offset c, double rx, double ry) {
    // Dahi lebar → dagu meruncing.
    final p = Path();
    p.moveTo(c.dx, c.dy - ry);
    p.cubicTo(
      c.dx + rx * 1.15,
      c.dy - ry,
      c.dx + rx * 1.05,
      c.dy + ry * 0.15,
      c.dx,
      c.dy + ry,
    );
    p.cubicTo(
      c.dx - rx * 1.05,
      c.dy + ry * 0.15,
      c.dx - rx * 1.15,
      c.dy - ry,
      c.dx,
      c.dy - ry,
    );
    p.close();
    return p;
  }

  Path _diamond(Offset c, double rx, double ry) {
    final soft = Path();
    soft.moveTo(c.dx, c.dy - ry);
    soft.quadraticBezierTo(c.dx + rx * 0.85, c.dy - ry * 0.35, c.dx + rx, c.dy);
    soft.quadraticBezierTo(
        c.dx + rx * 0.55, c.dy + ry * 0.55, c.dx, c.dy + ry * 0.95);
    soft.quadraticBezierTo(
        c.dx - rx * 0.55, c.dy + ry * 0.55, c.dx - rx, c.dy);
    soft.quadraticBezierTo(c.dx - rx * 0.85, c.dy - ry * 0.35, c.dx, c.dy - ry);
    soft.close();
    return soft;
  }

  void _drawGuides(Canvas canvas, Offset c, Size size) {
    final eyeY = c.dy - size.height * 0.06;
    final eyeDx = size.width * 0.14;
    final eyePaint = Paint()
      ..color = OptikAdminTokens.ice
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - eyeDx, eyeY),
        width: size.width * 0.12,
        height: size.height * 0.045,
      ),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + eyeDx, eyeY),
        width: size.width * 0.12,
        height: size.height * 0.045,
      ),
      eyePaint,
    );
    // Nose hint
    canvas.drawLine(
      Offset(c.dx, eyeY + size.height * 0.04),
      Offset(c.dx, eyeY + size.height * 0.14),
      Paint()
        ..color = OptikAdminTokens.ice
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawFrame(Canvas canvas, Offset c, Size size) {
    final style = _frameStyle(shape, frameVariant);
    final eyeY = c.dy - size.height * 0.07;
    final halfGap = size.width * 0.035;
    final lensW = size.width * style.lensW;
    final lensH = size.height * style.lensH;
    final leftCx = c.dx - halfGap - lensW / 2;
    final rightCx = c.dx + halfGap + lensW / 2;

    final stroke = Paint()
      ..color = OptikAdminTokens.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.bold ? 3.2 : 2.2
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = OptikAdminTokens.navy.withOpacity(0.13)
      ..style = PaintingStyle.fill;

    Path lens(double cx) {
      final rect = Rect.fromCenter(
        center: Offset(cx, eyeY),
        width: lensW,
        height: lensH,
      );
      switch (style.kind) {
        case _LensKind.round:
          return Path()..addOval(rect);
        case _LensKind.rect:
          return Path()
            ..addRRect(RRect.fromRectAndRadius(
              rect,
              Radius.circular(style.corner),
            ));
        case _LensKind.catEye:
          final p = Path();
          p.moveTo(rect.left, rect.center.dy);
          p.quadraticBezierTo(
              rect.left, rect.top, rect.center.dx - 2, rect.top + 2);
          p.quadraticBezierTo(
              rect.right - 4, rect.top - 4, rect.right + 2, rect.top + 6);
          p.quadraticBezierTo(
              rect.right, rect.bottom, rect.center.dx, rect.bottom);
          p.quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.center.dy);
          p.close();
          return p;
        case _LensKind.aviator:
          final p = Path();
          p.moveTo(rect.left, rect.top + lensH * 0.25);
          p.lineTo(rect.right, rect.top + lensH * 0.18);
          p.quadraticBezierTo(
              rect.right + 2, rect.bottom, rect.center.dx, rect.bottom);
          p.quadraticBezierTo(
              rect.left - 2, rect.bottom, rect.left, rect.top + lensH * 0.25);
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

    // Bridge
    canvas.drawLine(
      Offset(leftCx + lensW / 2, eyeY),
      Offset(rightCx - lensW / 2, eyeY),
      stroke,
    );

    // Temples
    final templeY = eyeY - lensH * 0.05;
    canvas.drawLine(
      Offset(leftCx - lensW / 2, templeY),
      Offset(leftCx - lensW / 2 - size.width * 0.08, templeY - 2),
      stroke,
    );
    canvas.drawLine(
      Offset(rightCx + lensW / 2, templeY),
      Offset(rightCx + lensW / 2 + size.width * 0.08, templeY - 2),
      stroke,
    );

    if (style.browline) {
      canvas.drawLine(
        Offset(leftCx - lensW / 2, eyeY - lensH / 2),
        Offset(leftCx + lensW / 2, eyeY - lensH / 2),
        Paint()
          ..color = OptikAdminTokens.navy
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(rightCx - lensW / 2, eyeY - lensH / 2),
        Offset(rightCx + lensW / 2, eyeY - lensH / 2),
        Paint()
          ..color = OptikAdminTokens.navy
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  _FrameStyle _frameStyle(FaceShapeType shape, int variant) {
    switch (shape) {
      case FaceShapeType.oval:
        return variant == 0
            ? const _FrameStyle(
                kind: _LensKind.rect,
                lensW: 0.28,
                lensH: 0.14,
                corner: 8,
                bold: true,
              )
            : const _FrameStyle(
                kind: _LensKind.round,
                lensW: 0.26,
                lensH: 0.16,
                corner: 99,
              );
      case FaceShapeType.round:
        return variant == 0
            ? const _FrameStyle(
                kind: _LensKind.rect,
                lensW: 0.30,
                lensH: 0.13,
                corner: 6,
                bold: true,
              )
            : const _FrameStyle(
                kind: _LensKind.rect,
                lensW: 0.28,
                lensH: 0.14,
                corner: 4,
                browline: true,
                bold: true,
              );
      case FaceShapeType.square:
        return variant == 0
            ? const _FrameStyle(
                kind: _LensKind.round,
                lensW: 0.27,
                lensH: 0.17,
                corner: 99,
              )
            : const _FrameStyle(
                kind: _LensKind.catEye,
                lensW: 0.29,
                lensH: 0.14,
                corner: 10,
              );
      case FaceShapeType.heart:
        return variant == 0
            ? const _FrameStyle(
                kind: _LensKind.aviator,
                lensW: 0.30,
                lensH: 0.16,
                corner: 8,
              )
            : const _FrameStyle(
                kind: _LensKind.round,
                lensW: 0.26,
                lensH: 0.16,
                corner: 99,
              );
      case FaceShapeType.diamond:
        return variant == 0
            ? const _FrameStyle(
                kind: _LensKind.catEye,
                lensW: 0.29,
                lensH: 0.14,
                corner: 10,
              )
            : const _FrameStyle(
                kind: _LensKind.round,
                lensW: 0.27,
                lensH: 0.15,
                corner: 99,
              );
      case FaceShapeType.oblong:
        return variant == 0
            ? const _FrameStyle(
                kind: _LensKind.rect,
                lensW: 0.34,
                lensH: 0.12,
                corner: 8,
                bold: true,
              )
            : const _FrameStyle(
                kind: _LensKind.rect,
                lensW: 0.32,
                lensH: 0.13,
                corner: 6,
                bold: true,
              );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceShapePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.showFrame != showFrame ||
      oldDelegate.frameVariant != frameVariant;
}

enum _LensKind { round, rect, catEye, aviator }

class _FrameStyle {
  const _FrameStyle({
    required this.kind,
    required this.lensW,
    required this.lensH,
    required this.corner,
    this.bold = false,
    this.browline = false,
  });

  final _LensKind kind;
  final double lensW;
  final double lensH;
  final double corner;
  final bool bold;
  final bool browline;
}

/// Label singkat gaya frame yang digambar.
String faceShapeFrameLabel(FaceShapeType shape, {int variant = 0}) {
  switch (shape) {
    case FaceShapeType.oval:
      return variant == 0 ? 'Rectangle / wayfarer' : 'Round';
    case FaceShapeType.round:
      return variant == 0 ? 'Rectangle / square' : 'Browline';
    case FaceShapeType.square:
      return variant == 0 ? 'Round / oval' : 'Cat-eye lembut';
    case FaceShapeType.heart:
      return variant == 0 ? 'Aviator' : 'Round ringan';
    case FaceShapeType.diamond:
      return variant == 0 ? 'Cat-eye / oval' : 'Thin round';
    case FaceShapeType.oblong:
      return variant == 0 ? 'Wide / oversize' : 'Square pendek';
  }
}

/// Grid kecil untuk overview (wajah saja).
class FaceShapeIcon extends StatelessWidget {
  const FaceShapeIcon({super.key, required this.shape, this.size = 56});

  final FaceShapeType shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FaceShapeVisual(
      shape: shape,
      size: size,
      showFrame: false,
    );
  }
}
