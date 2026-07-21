import 'package:flutter/material.dart';
import '../../theme.dart';

/// Glass panel — same language as Training Mode dialog surface.
class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? 22.0;
    final border = borderColor ?? OptikAdminTokens.lineStrong;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          OptikAdminTokens.card.withOpacity(0.97),
          OptikAdminTokens.panel.withOpacity(0.99),
        ],
      ),
      border: Border.all(color: border, width: 1.1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.4),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    );

    final Widget panel = onTap == null
        ? Container(
            padding: padding,
            decoration: decoration,
            child: child,
          )
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: Ink(
                padding: padding,
                decoration: decoration,
                child: child,
              ),
            ),
          );

    if (margin == null) return panel;
    return Padding(padding: margin!, child: panel);
  }
}

/// KPI card — glass surface + accent badge (not a solid blue slab).
class PremiumStatCard extends StatelessWidget {
  const PremiumStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.trending_up_rounded,
    this.loading = false,
    this.trailing,
    this.accent = OptikAdminTokens.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool loading;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      borderRadius: 22,
      borderColor: accent.withOpacity(0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OptikAdminTokens.accentSoft,
                  accent,
                  OptikAdminTokens.accentDeep,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: OptikAdminTokens.accentSoft.withOpacity(0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                loading
                    ? const SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(
                          color: OptikAdminTokens.accentSoft,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        value,
                        style: const TextStyle(
                          color: OptikAdminTokens.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.1,
                        ),
                      ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
