import 'package:flutter/material.dart';

import '../brand/rekasa_tokens.dart';

/// Lockup etalase opsi 3: nama lengkap, tanpa kotak R lama.
/// Bukan merek Optik.
class RekasaMark extends StatelessWidget {
  const RekasaMark({
    super.key,
    this.height = 32,
    this.showWordmark = true,
    this.wordmarkColor,
  });

  static const String legalName = 'REKASA KARYA INDONESIA';
  static const String assetPath = 'assets/images/brand/rekasa-lockup.png';

  final double height;
  final bool showWordmark;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      assetPath,
      height: showWordmark ? height : height * 0.72,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: legalName,
      errorBuilder: (_, __, ___) => Text(
        legalName,
        style: TextStyle(
          color: wordmarkColor ?? RekasaTokens.ink,
          fontWeight: FontWeight.w800,
          fontSize: height * 0.42,
          height: 1.05,
          letterSpacing: -0.4,
        ),
      ),
    );
    if (wordmarkColor == null) return img;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(wordmarkColor!, BlendMode.srcIn),
      child: img,
    );
  }
}
