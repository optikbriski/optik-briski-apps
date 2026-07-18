import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Helper layout aman untuk web + HP.
class R {
  R._();

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isNarrow(BuildContext context) => widthOf(context) < 480;
  static bool isCompact(BuildContext context) => widthOf(context) < 720;

  static int gridCols(BuildContext context,
      {int phone = 2, int tablet = 3, int desktop = 4}) {
    final w = widthOf(context);
    if (w < 420) return phone;
    if (w < 720) return tablet;
    return desktop;
  }

  static double dialogMaxWidth(BuildContext context, [double prefer = 420]) {
    final w = widthOf(context);
    return math.min(prefer, w - 32).clamp(240.0, prefer);
  }

  /// Bungkus child supaya dialog tidak melebihi layar.
  static Widget constrainedDialog({
    required BuildContext context,
    required Widget child,
    double preferWidth = 420,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: dialogMaxWidth(context, preferWidth),
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: child,
    );
  }
}

/// Scroll horizontal aman untuk tabel lebar.
class HScroll extends StatelessWidget {
  const HScroll({super.key, required this.child, this.minWidth = 520});

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: math.max(c.maxWidth, minWidth)),
            child: child,
          ),
        );
      },
    );
  }
}
