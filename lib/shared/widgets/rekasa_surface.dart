import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../brand/rekasa_tokens.dart';

/// Kartu kertas: rambut sky, bayangan dalam, aksen atas.
class RekasaSurface extends StatelessWidget {
  const RekasaSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 20),
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
      border: Border.all(color: RekasaTokens.line, width: 0.8),
      boxShadow: RekasaTokens.lift,
    );
    final inner = Container(
      padding: padding,
      decoration: box,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RekasaTokens.radiusCard),
        border: const Border(
          top: BorderSide(color: Color(0x998BB4E8), width: 1.2),
        ),
      ),
      child: child,
    );
    if (onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RekasaTokens.radiusCard),
        child: inner,
      ),
    );
  }
}

/// Ubin ikon: kobalt + kilau atas, bukan kotak datar.
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
    final radius = BorderRadius.circular(size * 0.26);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RekasaTokens.badgeFill,
        borderRadius: radius,
        border: Border.all(color: RekasaTokens.paper.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: RekasaTokens.inkSoft.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size * 0.48,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
            Icon(icon, color: RekasaTokens.paper, size: size * 0.44),
          ],
        ),
      ),
      ),
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
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            color: RekasaTokens.inkSoft,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: SizedBox(
            height: 1,
            child: ColoredBox(color: RekasaTokens.sky),
          ),
        ),
      ],
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
      color: filled ? RekasaTokens.inkSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: filled ? RekasaTokens.inkSoft : RekasaTokens.sky,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: filled ? RekasaTokens.paper : RekasaTokens.inkSoft,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.35,
            ),
          ),
        ),
      ),
    );
  }
}
