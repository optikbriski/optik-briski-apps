import 'package:flutter/material.dart';
import '../../theme.dart';

class PremiumPrimaryButton extends StatelessWidget {
  const PremiumPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.gradient,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    final child = loading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: OptikAdminTokens.snow,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: OptikAdminTokens.snow),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: OptikAdminTokens.snow,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  fontSize: 14,
                ),
              ),
            ],
          );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: expand ? double.infinity : null,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: OptikAdminTokens.navy,
              gradient: gradient,
              boxShadow: OptikAdminTokens.glow(OptikAdminTokens.navy),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
