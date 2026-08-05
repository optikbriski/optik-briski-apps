import 'package:flutter/material.dart';
import '../../theme.dart';

class PremiumEmptyState extends StatelessWidget {
  const PremiumEmptyState({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.inbox_rounded,
    this.action,
    this.accent = OptikAdminTokens.ice,
  });

  final String message;
  /// Judul singkat di atas [message] (opsional).
  final String? title;
  final IconData icon;
  final Widget? action;

  /// Aksen lingkaran ikon. Ice → ikon navy; semantik (warning/…) → warna itu.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isIce = accent == OptikAdminTokens.ice ||
        accent == OptikAdminTokens.accentSoft ||
        accent == OptikAdminTokens.accentDeep;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withOpacity(isIce ? 0.35 : 0.18),
                    accent.withOpacity(isIce ? 0.08 : 0.04),
                  ],
                ),
                border: Border.all(
                  color: accent.withOpacity(isIce ? 0.85 : 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: OptikAdminTokens.navy.withOpacity(0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 34,
                color: isIce ? OptikAdminTokens.navy : accent,
              ),
            ),
            const SizedBox(height: 20),
            if (title != null && title!.trim().isNotEmpty) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.92),
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
