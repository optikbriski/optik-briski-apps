import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../brand/rekasa_tokens.dart';

/// Kartu putih — sudut logo, bayangan pelan.
class RekasaSurface extends StatelessWidget {
  const RekasaSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: RekasaTokens.paper,
      borderRadius: BorderRadius.circular(RekasaTokens.radiusCard),
      border: Border.all(color: RekasaTokens.line),
      boxShadow: RekasaTokens.lift,
    );
    if (onTap == null) {
      return Container(padding: padding, decoration: box, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RekasaTokens.radiusCard),
        child: Ink(padding: padding, decoration: box, child: child),
      ),
    );
  }
}

/// Ubin ikon = geometri logo (kotak rounded, isi biru, glyph putih).
class RekasaIconTile extends StatelessWidget {
  const RekasaIconTile({
    super.key,
    required this.icon,
    this.size = 48,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: RekasaTokens.badgeFill,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: RekasaTokens.inkSoft.withOpacity(0.28),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: RekasaTokens.paper, size: size * 0.48),
    );
  }
}

class RekasaPage extends StatelessWidget {
  const RekasaPage({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: RekasaTokens.maxWidth),
        child: Padding(
          padding: padding ?? const EdgeInsets.fromLTRB(22, 8, 22, 36),
          child: child,
        ),
      ),
    );
  }
}

class RekasaEyebrow extends StatelessWidget {
  const RekasaEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        color: RekasaTokens.inkSoft,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    );
  }
}

class RekasaPillButton extends StatelessWidget {
  const RekasaPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? RekasaTokens.inkSoft : RekasaTokens.paper,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: RekasaTokens.inkSoft,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: filled ? RekasaTokens.paper : RekasaTokens.inkSoft,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
