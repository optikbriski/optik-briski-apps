import 'package:flutter/material.dart';
import '../../theme.dart';

/// Elevated snow surface — hairline ice edge + soft depth.
class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.onTap,
    this.showAccentBar = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool showAccentBar;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? 20.0;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: OptikAdminTokens.cardSheen,
      border: Border.all(
        color: borderColor ?? OptikAdminTokens.ice.withOpacity(0.4),
        width: 1,
      ),
      boxShadow: OptikAdminTokens.cardShadow,
    );

    Widget content = child;
    if (showAccentBar) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    OptikAdminTokens.navy,
                    OptikAdminTokens.ice,
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: child),
          ],
        ),
      );
    }

    final Widget panel = onTap == null
        ? Container(
            padding: padding,
            decoration: decoration,
            child: content,
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
                child: content,
              ),
            ),
          );

    if (margin == null) return panel;
    return Padding(padding: margin!, child: panel);
  }
}

class PremiumStatCard extends StatelessWidget {
  const PremiumStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.trending_up_rounded,
    this.loading = false,
    this.trailing,
    this.accent = OptikAdminTokens.ice,
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
      padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
      borderRadius: 20,
      showAccentBar: true,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: OptikAdminTokens.ice.withOpacity(0.35),
              border: Border.all(
                color: OptikAdminTokens.ice,
              ),
            ),
            child: Icon(icon, color: OptikAdminTokens.navy, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: OptikAdminTokens.slate.withOpacity(0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 8),
                loading
                    ? const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          color: OptikAdminTokens.navy,
                          strokeWidth: 2.2,
                        ),
                      )
                    : Text(
                        value,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.0,
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
