import 'package:flutter/material.dart';
import '../../theme.dart';

class PremiumIconBadge extends StatelessWidget {
  const PremiumIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 48,
    this.iconSize,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final c = color ?? OptikAdminTokens.ice;
    final semantic = c == OptikAdminTokens.success ||
        c == OptikAdminTokens.warning ||
        c == OptikAdminTokens.danger ||
        c == OptikAdminTokens.training ||
        c == OptikAdminTokens.trainingSoft;
    final snowOnHighlight = c == OptikAdminTokens.snow;

    if (snowOnHighlight) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          color: OptikAdminTokens.navy.withOpacity(0.18),
          border: Border.all(color: OptikAdminTokens.snow.withOpacity(0.45)),
        ),
        child: Icon(
          icon,
          color: OptikAdminTokens.snow,
          size: iconSize ?? size * 0.48,
        ),
      );
    }

    if (semantic) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          color: c.withOpacity(0.18),
          border: Border.all(color: c.withOpacity(0.85)),
        ),
        child: Icon(
          icon,
          color: c,
          size: iconSize ?? size * 0.48,
        ),
      );
    }

    final isWash = c == OptikAdminTokens.ice ||
        c == OptikAdminTokens.navy ||
        c == OptikAdminTokens.slate ||
        c == OptikAdminTokens.accentSoft ||
        c == OptikAdminTokens.accentDeep;
    final wash = OptikAdminTokens.isKombo
        ? OptikAdminTokens.navy
        : OptikAdminTokens.ice;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: wash.withOpacity(isWash ? (OptikAdminTokens.isKombo ? 0.14 : 0.48) : 0.18),
        border: Border.all(
          color: wash.withOpacity(
            OptikAdminTokens.isDark
                ? 0.0
                : (isWash ? (OptikAdminTokens.isKombo ? 0.35 : 1) : 0.85),
          ),
        ),
      ),
      child: Icon(
        icon,
        color: isWash ? OptikAdminTokens.navy : c,
        size: iconSize ?? size * 0.48,
      ),
    );
  }
}
