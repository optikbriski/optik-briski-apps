import 'package:flutter/material.dart';
import '../../theme.dart';

/// Wrap for action/filter chips with guaranteed gutters (anti-nempel).
class PremiumChipWrap extends StatelessWidget {
  const PremiumChipWrap({
    super.key,
    required this.children,
    this.spacing = OptikAdminTokens.spaceSm,
    this.runSpacing = OptikAdminTokens.spaceSm,
    this.alignment = WrapAlignment.start,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        alignment: alignment,
        children: children,
      ),
    );
  }
}

/// Outlined action chip with comfortable padding (not shrink-wrapped flush).
class PremiumActionChip extends StatelessWidget {
  const PremiumActionChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: icon == null
          ? null
          : Icon(icon, size: 16, color: OptikAdminTokens.textSecondary),
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: OptikAdminTokens.card,
      side: const BorderSide(color: OptikAdminTokens.lineStrong),
      labelStyle: const TextStyle(
        color: OptikAdminTokens.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }
}
