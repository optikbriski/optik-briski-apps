import 'package:flutter/material.dart';
import '../../theme.dart';

class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(left: 2, bottom: 14, top: 4),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: OptikAdminTokens.navy,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: OptikAdminTokens.slate.withOpacity(0.95),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    OptikAdminTokens.ice.withOpacity(0.85),
                    OptikAdminTokens.ice.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
