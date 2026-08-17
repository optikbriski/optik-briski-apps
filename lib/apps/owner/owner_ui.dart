import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme.dart';
import 'owner_service.dart';

/// Shared Owner chrome — Frozen Lake + mobile polish (not generic Material cards).
abstract final class OwnerUi {
  static TextStyle display(double size, {Color color = OptikAdminTokens.navy}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.15,
      );

  static TextStyle label({Color color = OptikAdminTokens.slate}) => TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle body({
    Color color = OptikAdminTokens.textSecondary,
    double size = 14,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(color: color, fontSize: size, fontWeight: weight, height: 1.35);

  static Color moneyColor(num? v) {
    final n = (v ?? 0).toDouble();
    if (n < 0) return OptikAdminTokens.danger;
    if (n > 0) return OptikAdminTokens.navy;
    return OptikAdminTokens.slate;
  }

  static Widget moneyText(
    num? v, {
    double size = 22,
    FontWeight weight = FontWeight.w700,
    int maxLines = 1,
  }) {
    return Text(
      OwnerService.formatRp(v),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: display(size, color: moneyColor(v)).copyWith(fontWeight: weight),
    );
  }

  static BoxDecoration panel({bool elevated = false}) => BoxDecoration(
        gradient: OptikAdminTokens.cardSheen,
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
        border: Border.all(color: OptikAdminTokens.line),
        boxShadow: elevated ? OptikAdminTokens.cardShadowHover : OptikAdminTokens.cardShadow,
      );

  static BoxDecoration hero() => BoxDecoration(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF000080),
            Color(0xFF123A7A),
            Color(0xFF2A6B8A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: OptikAdminTokens.navy.withOpacity(0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      );
}

class OwnerPageFrame extends StatelessWidget {
  const OwnerPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.onRefresh,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final body = DecoratedBox(
      decoration: BoxDecoration(gradient: OptikAdminTokens.bgGradient),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikAdminTokens.ice.withOpacity(0.35),
                ),
              ),
            ),
          ),
          Positioned(
            top: 120,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikAdminTokens.accentSoft.withOpacity(0.45),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: top + 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: OwnerUi.display(28)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!, style: OwnerUi.label()),
                          ],
                        ],
                      ),
                    ),
                    ...?actions,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ],
      ),
    );

    if (onRefresh == null) return body;
    return RefreshIndicator(
      color: OptikAdminTokens.navy,
      onRefresh: onRefresh!,
      child: body,
    );
  }
}

class OwnerSectionLabel extends StatelessWidget {
  const OwnerSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: OwnerUi.label(color: OptikAdminTokens.navy).copyWith(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class OwnerEmptyState extends StatelessWidget {
  const OwnerEmptyState(this.message, {super.key, this.icon});
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.inbox_outlined,
              size: 40,
              color: OptikAdminTokens.ice,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: OwnerUi.body(color: OptikAdminTokens.slate),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerListCard extends StatelessWidget {
  const OwnerListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: OwnerUi.panel(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ] else if (accent != null) ...[
                  Container(
                    width: 4,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: OwnerUi.body(
                          color: OptikAdminTokens.navy,
                          weight: FontWeight.w700,
                          size: 15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: OwnerUi.label()),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
