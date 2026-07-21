import 'package:flutter/material.dart';
import '../../theme.dart';

/// Consistent Admin AppBar with optional subtitle under the title.
class PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PremiumAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.height,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final double? height;

  @override
  Size get preferredSize {
    final base = height ?? (subtitle == null ? kToolbarHeight : 72);
    final bottomH = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(base + bottomH);
  }

  @override
  Widget build(BuildContext context) {
    final titleWidget = subtitle == null
        ? Text(
            title,
            style: const TextStyle(
              color: OptikAdminTokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: centerTitle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: OptikAdminTokens.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: OptikAdminTokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          );

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      title: titleWidget,
      actions: actions,
      bottom: bottom,
      iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
    );
  }
}
