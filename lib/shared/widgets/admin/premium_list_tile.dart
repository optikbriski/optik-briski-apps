import 'package:flutter/material.dart';
import '../../theme.dart';
import 'premium_icon_badge.dart';

/// Feature row — Training Mode module chip / dialog list language.
class PremiumListTile extends StatelessWidget {
  const PremiumListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = OptikAdminTokens.accentSoft,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.margin = const EdgeInsets.only(bottom: OptikAdminTokens.spaceSm),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final lead = leading ??
        (icon != null
            ? PremiumIconBadge(
                icon: icon!,
                color: iconColor,
                size: dense ? 40 : 44,
              )
            : null);

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: dense ? 12 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OptikAdminTokens.card.withOpacity(0.96),
                  OptikAdminTokens.panel.withOpacity(0.98),
                ],
              ),
              border: Border.all(color: iconColor.withOpacity(0.28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                if (lead != null) ...[
                  lead,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: OptikAdminTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: OptikAdminTokens.textMuted,
                      size: 20,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
