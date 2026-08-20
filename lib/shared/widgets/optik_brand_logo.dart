import 'package:flutter/material.dart';

import '../brand/brand_service.dart';

/// Logo merek (aset lokal; nama merek dari app_brand).
/// - [OptikLogoTone.color] → `logo-web.png` (biru/merah) untuk latar terang
/// - [OptikLogoTone.white] → `logo-web-white.png` untuk latar gelap / biru
enum OptikLogoTone { color, white }

class OptikBrandLogo extends StatelessWidget {
  const OptikBrandLogo({
    super.key,
    this.tone = OptikLogoTone.color,
    this.height = 40,
    this.width,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
  });

  /// Shortcut: logo putih untuk header gelap / biru.
  const OptikBrandLogo.white({
    super.key,
    this.height = 40,
    this.width,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
  }) : tone = OptikLogoTone.white;

  /// Shortcut: logo berwarna untuk latar putih / canvas.
  const OptikBrandLogo.color({
    super.key,
    this.height = 40,
    this.width,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
  }) : tone = OptikLogoTone.color;

  final OptikLogoTone tone;
  final double height;
  final double? width;
  final Alignment alignment;
  final BoxFit fit;

  static const colorAsset = 'assets/images/logo-web.png';
  static const whiteAsset = 'assets/images/logo-web-white.png';

  String get asset =>
      tone == OptikLogoTone.white ? whiteAsset : colorAsset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      height: height,
      width: width,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Text(
        BrandService.name.toUpperCase(),
        style: TextStyle(
          color: tone == OptikLogoTone.white
              ? Colors.white
              : const Color(0xFF1D4ED8),
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          fontSize: height * 0.38,
        ),
      ),
    );
  }
}
