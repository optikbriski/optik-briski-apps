import 'package:flutter/material.dart';
import '../../theme.dart';

class PremiumIconBadge extends StatelessWidget {
  const PremiumIconBadge({
    super.key,
    required this.icon,
    this.color = OptikAdminTokens.ice,
    this.size = 48,
    this.iconSize,
  });

  final IconData icon;
  /// Aksen badge (ice / success / warning / danger). Wash + border mengikuti ini.
  final Color color;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final isIce = color == OptikAdminTokens.ice ||
        color == OptikAdminTokens.accentSoft ||
        color == OptikAdminTokens.accentDeep;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: color.withOpacity(isIce ? 0.32 : 0.16),
        border: Border.all(color: color.withOpacity(isIce ? 1 : 0.85)),
      ),
      child: Icon(
        icon,
        // Ice wash → navy; semantic accent → warna itu sendiri.
        color: isIce ? OptikAdminTokens.navy : color,
        size: iconSize ?? size * 0.48,
      ),
    );
  }
}
