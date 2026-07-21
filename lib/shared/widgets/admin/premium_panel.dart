import 'package:flutter/material.dart';
import '../../theme.dart';

/// Glass-soft content panel for Admin surfaces.
class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? OptikAdminTokens.radiusLg;
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: OptikAdminTokens.card.withOpacity(0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: OptikAdminTokens.line),
        gradient: OptikAdminTokens.cardSheen,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// KPI / omzet hero card with accent gradient.
class PremiumStatCard extends StatelessWidget {
  const PremiumStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.trending_up_rounded,
    this.loading = false,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool loading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: OptikAdminTokens.accentGradient,
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusXl),
        boxShadow: OptikAdminTokens.glow(OptikAdminTokens.accent),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              trailing ??
                  Icon(
                    icon,
                    color: Colors.white.withOpacity(0.55),
                    size: 18,
                  ),
            ],
          ),
          const SizedBox(height: 12),
          loading
              ? const SizedBox(
                  height: 30,
                  width: 30,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
        ],
      ),
    );
  }
}
