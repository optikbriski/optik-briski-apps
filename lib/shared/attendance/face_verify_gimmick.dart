import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Overlay gimmick "memverifikasi wajah" setelah liveness.
/// Bukan biometrik nyata — selalu sukses setelah animasi singkat.
Future<void> showFaceVerifyGimmick(
  BuildContext context, {
  required Uint8List photoBytes,
  Duration duration = const Duration(milliseconds: 2000),
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => FaceVerifyGimmickPage(
        photoBytes: photoBytes,
        duration: duration,
      ),
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

class FaceVerifyGimmickPage extends StatefulWidget {
  const FaceVerifyGimmickPage({
    super.key,
    required this.photoBytes,
    this.duration = const Duration(milliseconds: 2000),
  });

  final Uint8List photoBytes;
  final Duration duration;

  @override
  State<FaceVerifyGimmickPage> createState() => _FaceVerifyGimmickPageState();
}

class _FaceVerifyGimmickPageState extends State<FaceVerifyGimmickPage>
    with TickerProviderStateMixin {
  late final AnimationController _scan;
  late final AnimationController _progress;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _progress = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();

    Future<void>.delayed(widget.duration, () async {
      if (!mounted) return;
      setState(() => _done = true);
      _scan.stop();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _scan.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF38BDF8);
    const ok = Color(0xFF4ADE80);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _done
                        ? 'web_liveness_verify_ok'.tr()
                        : 'web_liveness_capturing'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _done ? ok : accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 260,
                    height: 320,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_scan, _progress]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _ScanOvalPainter(
                            scanT: _scan.value,
                            progress: _progress.value,
                            done: _done,
                            accent: accent,
                            ok: ok,
                          ),
                          child: ClipPath(
                            clipper: _OvalClipper(),
                            child: Image.memory(
                              widget.photoBytes,
                              fit: BoxFit.cover,
                              width: 260,
                              height: 320,
                              gaplessPlayback: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_done)
                    const Icon(Icons.check_circle_rounded, color: ok, size: 48)
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 220,
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (_, __) => LinearProgressIndicator(
                            value: _progress.value,
                            minHeight: 6,
                            backgroundColor: Colors.white12,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'web_liveness_verify_hint'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OvalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..addOval(Rect.fromLTWH(8, 8, size.width - 16, size.height - 16));
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ScanOvalPainter extends CustomPainter {
  _ScanOvalPainter({
    required this.scanT,
    required this.progress,
    required this.done,
    required this.accent,
    required this.ok,
  });

  final double scanT;
  final double progress;
  final bool done;
  final Color accent;
  final Color ok;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = (done ? ok : accent).withValues(alpha: 0.95);
    canvas.drawOval(oval, ring);

    if (!done) {
      final y = oval.top + oval.height * scanT;
      final scan = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(oval.left, y - 14, oval.width, 28));
      canvas.save();
      canvas.clipPath(Path()..addOval(oval));
      canvas.drawRect(Rect.fromLTWH(oval.left, y - 14, oval.width, 28), scan);
      canvas.restore();

      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.7);
      canvas.drawArc(oval.inflate(6), -1.57, progress * 6.28, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanOvalPainter old) =>
      old.scanT != scanT ||
      old.progress != progress ||
      old.done != done;
}
