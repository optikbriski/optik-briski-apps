import 'package:flutter/material.dart';

/// Breakpoint Member: HP vs tablet (Android & iPhone/iPad).
/// Pakai [shortestSide] supaya portrait/landscape tetap konsisten.
abstract final class MemberLayout {
  static const double tabletShortestSide = 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tabletShortestSide;

  static bool isPhone(BuildContext context) => !isTablet(context);

  static MemberLayoutMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tablet = size.shortestSide >= tabletShortestSide;
    final wide = size.width >= 900;
    return MemberLayoutMetrics(
      isTablet: tablet,
      pagePadding: tablet ? 28 : 16,
      sectionGap: tablet ? 18 : 12,
      maxContentWidth: tablet ? (wide ? 920 : 720) : double.infinity,
      heroTitleSize: tablet ? 22 : 17,
      heroSubtitleSize: tablet ? 14.5 : 13,
      menuTitleSize: tablet ? 16.5 : 14.5,
      menuSubtitleSize: tablet ? 13.5 : 12,
      bodySize: tablet ? 15 : 13.5,
      labelSize: tablet ? 14 : 12.5,
      iconSize: tablet ? 26 : 22,
      menuColumns: tablet ? 2 : 1,
      formColumns: tablet ? 2 : 1,
      navLabelSize: tablet ? 12 : 10.5,
      navIconSize: tablet ? 24 : 22,
      bottomNavHeight: tablet ? 68 : 62,
      useNavigationRail: tablet && size.width >= 840,
    );
  }

  /// Bungkus konten biar di tablet tidak melebar penuh layar.
  static Widget constrain(BuildContext context, Widget child) {
    final m = of(context);
    if (!m.isTablet) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: m.maxContentWidth),
        child: child,
      ),
    );
  }
}

class MemberLayoutMetrics {
  const MemberLayoutMetrics({
    required this.isTablet,
    required this.pagePadding,
    required this.sectionGap,
    required this.maxContentWidth,
    required this.heroTitleSize,
    required this.heroSubtitleSize,
    required this.menuTitleSize,
    required this.menuSubtitleSize,
    required this.bodySize,
    required this.labelSize,
    required this.iconSize,
    required this.menuColumns,
    required this.formColumns,
    required this.navLabelSize,
    required this.navIconSize,
    required this.bottomNavHeight,
    required this.useNavigationRail,
  });

  final bool isTablet;
  final double pagePadding;
  final double sectionGap;
  final double maxContentWidth;
  final double heroTitleSize;
  final double heroSubtitleSize;
  final double menuTitleSize;
  final double menuSubtitleSize;
  final double bodySize;
  final double labelSize;
  final double iconSize;
  final int menuColumns;
  final int formColumns;
  final double navLabelSize;
  final double navIconSize;
  final double bottomNavHeight;
  final bool useNavigationRail;
}
