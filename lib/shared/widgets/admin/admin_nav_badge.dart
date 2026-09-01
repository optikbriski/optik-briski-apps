import 'package:flutter/material.dart';

import '../../theme.dart';

/// Titik merah + angka untuk navigasi Admin (sidebar / tab).
class AdminNavBadge extends StatelessWidget {
  const AdminNavBadge({
    super.key,
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    final minSide = compact ? 16.0 : 18.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 5,
        vertical: compact ? 2 : 3,
      ),
      constraints: BoxConstraints(minWidth: minSide, minHeight: minSide),
      decoration: const BoxDecoration(
        color: OptikAdminTokens.danger,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: OptikAdminTokens.snow,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// Badge di sudut ikon (sidebar collapsed).
class AdminNavBadgeOverlay extends StatelessWidget {
  const AdminNavBadgeOverlay({
    super.key,
    required this.count,
    required this.child,
  });

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: AdminNavBadge(count: count, compact: true),
          ),
      ],
    );
  }
}
