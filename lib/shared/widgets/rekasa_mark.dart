import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../brand/rekasa_tokens.dart';

/// Lockup resmi etalase: badge R + nama lengkap.
/// Bukan merek Optik. Favicon tetap badge saja.
class RekasaMark extends StatelessWidget {
  const RekasaMark({
    super.key,
    this.height = 32,
    this.showWordmark = true,
    this.wordmarkColor,
  });

  static const String legalName = 'REKASA KARYA INDONESIA';
  static const String primaryLine = 'REKASA';
  static const String secondaryLine = 'KARYA INDONESIA';

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

    final primary = wordmarkColor ?? RekasaTokens.ink;
    final secondary = wordmarkColor?.withOpacity(0.72) ?? RekasaTokens.muted;

    return Semantics(
      label: legalName,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          badge,
          SizedBox(width: height * 0.32),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primaryLine,
                style: GoogleFonts.plusJakartaSans(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: height * 0.48,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
              SizedBox(height: height * 0.08),
              Text(
                secondaryLine,
                style: GoogleFonts.plusJakartaSans(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: height * 0.26,
                  letterSpacing: 1.15,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
