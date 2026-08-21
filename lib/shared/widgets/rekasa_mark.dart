import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../brand/rekasa_tokens.dart';

/// Tanda Rekasa: kotak biru royal + R putih + wordmark.
class RekasaMark extends StatelessWidget {
  const RekasaMark({
    super.key,
    this.height = 32,
    this.showWordmark = true,
    this.wordmarkColor,
  });

  final double height;
  final bool showWordmark;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: height,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: RekasaTokens.badgeFill,
        borderRadius: BorderRadius.circular(height * 0.22),
        boxShadow: [
          BoxShadow(
            color: RekasaTokens.ink.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        'R',
        style: GoogleFonts.plusJakartaSans(
          color: RekasaTokens.paper,
          fontWeight: FontWeight.w800,
          fontSize: height * 0.54,
          height: 1,
        ),
      ),
    );
    if (!showWordmark) return badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        SizedBox(width: height * 0.34),
        Text(
          'Rekasa',
          style: GoogleFonts.plusJakartaSans(
            color: wordmarkColor ?? RekasaTokens.ink,
            fontWeight: FontWeight.w800,
            fontSize: height * 0.68,
            letterSpacing: -0.4,
            height: 1,
          ),
        ),
      ],
    );
  }
}
