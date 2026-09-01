import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/admin/admin_nav_badge.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/premium_icon_badge.dart';
import 'admin_dash_nav.dart';

/// Sidebar navigasi Admin: grup + item. Isi halaman di panel kanan.
class AdminNavSidebar extends StatelessWidget {
  const AdminNavSidebar({
    super.key,
    required this.groups,
    required this.openGroupId,
    required this.expanded,
    required this.onSelectGroup,
    this.selectedItemId,
    this.onOpenItem,
    this.showItems = true,
    this.showHeader = true,
    this.onClose,
    this.badgeCounts = const {},
    this.onMarkItemUnread,
  });

  final List<AdminDashNavGroup> groups;
  final String? openGroupId;
  final String? selectedItemId;
  final bool expanded;
  final ValueChanged<String> onSelectGroup;
  final ValueChanged<AdminDashNavItem>? onOpenItem;
  final ValueChanged<String>? onMarkItemUnread;
  final bool showItems;
  final bool showHeader;
  final VoidCallback? onClose;
  final Map<String, int> badgeCounts;

  static const double widthExpanded = 276;
  static const double widthCollapsed = 76;

  int _groupBadge(AdminDashNavGroup group) {
    var sum = 0;
    for (final item in group.items) {
      sum += badgeCounts[item.id] ?? 0;
    }
    return sum;
  }

  Future<void> _showMarkUnreadMenu(
    BuildContext context,
    AdminDashNavItem item,
  ) async {
    if (onMarkItemUnread == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + box.size.height,
        pos.dx + box.size.width,
        pos.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'unread',
          child: Text('admin_nav_mark_unread'.tr()),
        ),
      ],
    );
    if (selected == 'unread') onMarkItemUnread!(item.id);
  }

  Widget _itemInkWell({
    required BuildContext context,
    required AdminDashNavItem item,
    required VoidCallback onTap,
    required Widget child,
    double borderRadius = 12,
  }) {
    final markUnread = onMarkItemUnread;
    Widget tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: markUnread == null
            ? null
            : () => _showMarkUnreadMenu(context, item),
        onSecondaryTap: markUnread == null
            ? null
            : () => _showMarkUnreadMenu(context, item),
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
    );
    if (markUnread == null) return tile;
    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showMarkUnreadMenu(context, item);
        }
      },
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = expanded ? widthExpanded : widthCollapsed;
    final kombo = OptikAdminTokens.isKombo;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: kombo ? OptikAdminTokens.bg : null,
        gradient: kombo
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(
                      OptikAdminTokens.bgMid, OptikAdminTokens.ice, 0.28)!,
                  OptikAdminTokens.bgMid,
                  Color.lerp(
                      OptikAdminTokens.bgMid, OptikAdminTokens.ice, 0.18)!,
                ],
              ),
        border: Border(
          right: BorderSide(
            color: OptikAdminTokens.chromeEdge,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: OptikAdminTokens.navy.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader && expanded) _header(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                expanded ? 12 : 10,
                expanded ? 8 : 16,
                expanded ? 12 : 10,
                20,
              ),
              children: [
                for (final g in groups) ...[
                  if (g.directItem)
                    _directRow(context, g)
                  else ...[
                    _groupRow(g),
                    if (expanded && showItems && openGroupId == g.id)
                      ...g.items.map((item) => _itemRow(context, item)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'dash_navigasi_menu'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.72),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'dash_nav_close'.tr(),
              onPressed: onClose,
              icon: Icon(
                Icons.close_rounded,
                color: OptikAdminTokens.slate,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _directRow(BuildContext context, AdminDashNavGroup group) {
    if (group.items.isEmpty) return const SizedBox.shrink();
    final item = group.items.first;
    final selected = selectedItemId == item.id;
    final kombo = OptikAdminTokens.isKombo;
    final selectedFill = !selected
        ? (kombo ? Colors.transparent : OptikAdminTokens.card.withOpacity(0.45))
        : (kombo
            ? OptikAdminTokens.navy
            : OptikAdminTokens.ice.withOpacity(0.38));
    final selectedInk =
        selected && kombo ? OptikAdminTokens.onHighlight : OptikAdminTokens.navy;
    final tile = _itemInkWell(
      context: context,
      item: item,
      onTap: () => onOpenItem?.call(item),
      borderRadius: 14,
      child: Ink(
        padding: EdgeInsets.symmetric(
          horizontal: expanded ? 10 : 8,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selectedFill,
          border: Border.all(
            color: selected
                ? (kombo
                    ? OptikAdminTokens.navy
                    : OptikAdminTokens.navy.withOpacity(0.28))
                : OptikAdminTokens.navy.withOpacity(kombo ? 0.32 : 0.55),
          ),
        ),
        child: expanded
            ? Row(
                children: [
                  PremiumIconBadge(
                    icon: group.icon,
                    size: 36,
                    color: selected && kombo
                        ? OptikAdminTokens.onHighlight
                        : OptikAdminTokens.navy,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      group.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selectedInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  AdminNavBadge(count: badgeCounts[item.id] ?? 0),
                ],
              )
            : AdminNavBadgeOverlay(
                count: badgeCounts[item.id] ?? 0,
                child: Center(
                  child: PremiumIconBadge(
                    icon: group.icon,
                    size: 40,
                    color: selected && kombo
                        ? OptikAdminTokens.onHighlight
                        : OptikAdminTokens.navy,
                  ),
                ),
              ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: expanded ? 10 : 8),
      child: expanded ? tile : Tooltip(message: group.label, child: tile),
    );
  }

  Widget _groupRow(AdminDashNavGroup group) {
    final open = openGroupId == group.id;
    final kombo = OptikAdminTokens.isKombo;
    final selectedFill = !open
        ? (kombo ? Colors.transparent : OptikAdminTokens.card.withOpacity(0.45))
        : (kombo
            ? OptikAdminTokens.navy
            : OptikAdminTokens.ice.withOpacity(0.38));
    final selectedInk =
        open && kombo ? OptikAdminTokens.onHighlight : OptikAdminTokens.navy;
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelectGroup(group.id),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 10 : 8,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selectedFill,
            border: Border.all(
              color: open
                  ? (kombo
                      ? OptikAdminTokens.navy
                      : OptikAdminTokens.navy.withOpacity(0.28))
                  : OptikAdminTokens.navy.withOpacity(kombo ? 0.32 : 0.55),
            ),
          ),
          child: expanded
              ? Row(
                  children: [
                    PremiumIconBadge(
                      icon: group.icon,
                      size: 36,
                      color: open && kombo
                          ? OptikAdminTokens.onHighlight
                          : OptikAdminTokens.navy,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        group.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selectedInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    AdminNavBadge(count: _groupBadge(group)),
                    if (_groupBadge(group) == 0) ...[
                      Text(
                        '${group.items.length}',
                        style: TextStyle(
                          color: selectedInk.withOpacity(0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ] else
                      const SizedBox(width: 4),
                    Icon(
                      open
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: selectedInk,
                    ),
                  ],
                )
              : AdminNavBadgeOverlay(
                  count: _groupBadge(group),
                  child: Center(
                    child: PremiumIconBadge(
                      icon: group.icon,
                      size: 40,
                      color: open && kombo
                          ? OptikAdminTokens.onHighlight
                          : OptikAdminTokens.navy,
                    ),
                  ),
                ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: expanded ? 6 : 8),
      child: expanded ? tile : Tooltip(message: group.label, child: tile),
    );
  }

  Widget _itemRow(BuildContext context, AdminDashNavItem item) {
    final selected = selectedItemId == item.id;
    final badge = badgeCounts[item.id] ?? 0;
    final kombo = OptikAdminTokens.isKombo;
    final ink = selected && kombo
        ? OptikAdminTokens.onHighlight
        : OptikAdminTokens.navy;
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 2, right: 2),
      child: _itemInkWell(
        context: context,
        item: item,
        onTap: () => onOpenItem?.call(item),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: !selected
                ? Colors.transparent
                : (kombo
                    ? OptikAdminTokens.navy
                    : OptikAdminTokens.ice.withOpacity(0.42)),
            border: Border.all(
              color: selected
                  ? (kombo
                      ? OptikAdminTokens.navy
                      : OptikAdminTokens.navy.withOpacity(0.22))
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: ink.withOpacity(kombo && selected ? 0.18 : 0.12),
                ),
                child: Icon(
                  item.icon,
                  size: 15,
                  color: ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              AdminNavBadge(count: badge),
            ],
          ),
        ),
      ),
    );
  }
}
