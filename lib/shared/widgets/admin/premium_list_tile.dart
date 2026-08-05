import 'package:flutter/material.dart';
import '../../theme.dart';
import 'premium_icon_badge.dart';

class PremiumListTile extends StatelessWidget {
  const PremiumListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = OptikAdminTokens.ice,
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
              horizontal: 16,
              vertical: dense ? 12 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: OptikAdminTokens.card,
              border: Border.all(
                color: OptikAdminTokens.ice.withOpacity(0.4),
              ),
              boxShadow: OptikAdminTokens.cardShadow,
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
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          height: 1.25,
                          letterSpacing: -0.15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: OptikAdminTokens.slate.withOpacity(0.95),
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      color: OptikAdminTokens.slate.withOpacity(0.45),
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
