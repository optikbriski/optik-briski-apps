import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme.dart';

/// White canvas with a quiet Frozen Lake atmosphere.
class PremiumScaffold extends StatelessWidget {
  const PremiumScaffold({
    super.key,
    this.scaffoldKey,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
    this.padding,
  });

  final GlobalKey<ScaffoldState>? scaffoldKey;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: OptikAdminTokens.bg,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      drawer: drawer,
      endDrawer: endDrawer,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation:
          floatingActionButtonLocation ?? FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          IgnorePointer(
            child: ColoredBox(
              color: OptikAdminTokens.bg,
              child: OptikAdminTokens.isKombo
                  ? const SizedBox.expand()
                  : const _PremiumBackdrop(),
            ),
          ),
          padding == null ? body : Padding(padding: padding!, child: body),
        ],
      ),
    );
  }
}

class _PremiumBackdrop extends StatelessWidget {
  const _PremiumBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: OptikAdminTokens.bgGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.85, -1.05),
                radius: 1.15,
                colors: [
                  OptikAdminTokens.ice.withOpacity(0.34),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.1, -0.2),
                radius: 0.95,
                colors: [
                  OptikAdminTokens.navy.withOpacity(0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _IceGrainPainter(
                  ink: OptikAdminTokens.navy,
                  frost: OptikAdminTokens.ice,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fine ice grain so the canvas is not a flat pale wash.
class _IceGrainPainter extends CustomPainter {
  const _IceGrainPainter({required this.ink, required this.frost});

  final Color ink;
  final Color frost;

  @override
  void paint(Canvas canvas, Size size) {
    final inkPaint = Paint()..color = ink.withOpacity(0.028);
    final frostPaint = Paint()..color = frost.withOpacity(0.22);
    const step = 6.0;
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        final n = _hash(x, y);
        if (n > 0.72) {
          canvas.drawCircle(
            Offset(x + n * 2.4, y + (1 - n) * 2.1),
            n > 0.9 ? 1.15 : 0.65,
            n > 0.88 ? frostPaint : inkPaint,
          );
        }
      }
    }
  }

  static double _hash(double x, double y) {
    final v = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant _IceGrainPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.frost != frost;
}

