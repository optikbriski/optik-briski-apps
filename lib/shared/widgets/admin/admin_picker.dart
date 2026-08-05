import 'package:flutter/material.dart';

import '../../theme.dart';
import 'premium_icon_badge.dart';

/// Opsi tunggal untuk [showAdminPicker] / [showAdminMultiPicker].
class AdminPickerOption<T> {
  const AdminPickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
}

/// Hasil picker tunggal. `null` dari Future = dibatalkan.
class AdminPickerSelection<T> {
  const AdminPickerSelection(this.value) : isClear = false;
  const AdminPickerSelection.clear()
      : value = null,
        isClear = true;

  final T? value;
  final bool isClear;
}

/// Field pemicu Frozen Lake (bukan DropdownButton).
class AdminPickerField extends StatelessWidget {
  const AdminPickerField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTap,
    this.icon = Icons.list_alt_rounded,
    this.badgeColor = OptikAdminTokens.ice,
    this.enabled = true,
    this.hint,
  });

  final String label;
  final String valueText;
  final VoidCallback? onTap;
  final IconData icon;
  final Color badgeColor;
  final bool enabled;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canTap ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: OptikAdminTokens.snow,
            border: Border.all(
              color: canTap
                  ? OptikAdminTokens.ice
                  : OptikAdminTokens.lineStrong,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              PremiumIconBadge(
                icon: icon,
                color: badgeColor,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: valueText == (hint ?? '')
                            ? OptikAdminTokens.slate
                            : OptikAdminTokens.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: canTap
                    ? OptikAdminTokens.navy
                    : OptikAdminTokens.slate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog picker Frozen Lake — tunggal, opsional clear + search.
Future<AdminPickerSelection<T>?> showAdminPicker<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<AdminPickerOption<T>> options,
  T? selected,
  bool searchable = true,
  String searchHint = 'Cari…',
  String? clearLabel,
  String? clearSubtitle,
  IconData? clearIcon,
  IconData headerIcon = Icons.list_alt_rounded,
  Color headerBadgeColor = OptikAdminTokens.ice,
  bool Function(AdminPickerOption<T> option, String query)? filterOption,
}) {
  return showDialog<AdminPickerSelection<T>>(
    context: context,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final q = query.trim().toLowerCase();
          final filtered = options.where((o) {
            if (q.isEmpty) return true;
            if (filterOption != null) return filterOption(o, q);
            final hay = '${o.label} ${o.subtitle ?? ''}'.toLowerCase();
            return hay.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
              side: const BorderSide(color: OptikAdminTokens.ice, width: 1.2),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Row(
              children: [
                PremiumIconBadge(
                  icon: headerIcon,
                  color: headerBadgeColor,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: OptikAdminTokens.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded,
                      color: OptikAdminTokens.slate),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: searchable ? 460 : 400,
              child: Column(
                children: [
                  if (searchable) ...[
                    TextField(
                      autofocus: true,
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: searchHint,
                        hintStyle: TextStyle(
                          color: OptikAdminTokens.slate.withOpacity(0.85),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: OptikAdminTokens.navy,
                        ),
                        filled: true,
                        fillColor: OptikAdminTokens.snow,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OptikAdminTokens.radiusSm,
                          ),
                          borderSide:
                              const BorderSide(color: OptikAdminTokens.ice),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OptikAdminTokens.radiusSm,
                          ),
                          borderSide:
                              const BorderSide(color: OptikAdminTokens.ice),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OptikAdminTokens.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: OptikAdminTokens.navy,
                            width: 1.4,
                          ),
                        ),
                      ),
                      onChanged: (v) => setModal(() => query = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.bgMid,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OptikAdminTokens.ice),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          if (clearLabel != null)
                            _AdminPickerTile(
                              label: clearLabel,
                              subtitle: clearSubtitle,
                              icon: clearIcon ?? Icons.apps_rounded,
                              selected: selected == null,
                              onTap: () => Navigator.pop(
                                ctx,
                                AdminPickerSelection<T>.clear(),
                              ),
                            ),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: Text(
                                  'Tidak ada opsi cocok.',
                                  style: TextStyle(
                                    color: OptikAdminTokens.slate,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...filtered.map((o) {
                              final isSelected = selected != null &&
                                  selected == o.value;
                              return _AdminPickerTile(
                                label: o.label,
                                subtitle: o.subtitle,
                                icon: o.icon ?? Icons.circle_outlined,
                                trailing: o.trailing,
                                selected: isSelected,
                                onTap: () => Navigator.pop(
                                  ctx,
                                  AdminPickerSelection<T>(o.value),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.slate,
                ),
                child: const Text('Batal'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Multi-select Frozen Lake. `null` = dibatalkan.
Future<Set<T>?> showAdminMultiPicker<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<AdminPickerOption<T>> options,
  Set<T>? selected,
  int? maxSelect,
  bool searchable = true,
  String searchHint = 'Cari…',
  IconData headerIcon = Icons.checklist_rounded,
  String confirmLabel = 'Terapkan',
}) {
  return showDialog<Set<T>>(
    context: context,
    builder: (ctx) {
      var query = '';
      final chosen = <T>{...(selected ?? {})};
      return StatefulBuilder(
        builder: (ctx, setModal) {
          final q = query.trim().toLowerCase();
          final filtered = options.where((o) {
            if (q.isEmpty) return true;
            final hay = '${o.label} ${o.subtitle ?? ''}'.toLowerCase();
            return hay.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
              side: const BorderSide(color: OptikAdminTokens.ice, width: 1.2),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Row(
              children: [
                PremiumIconBadge(
                  icon: headerIcon,
                  color: OptikAdminTokens.ice,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ??
                            (maxSelect == null
                                ? '${chosen.length} dipilih'
                                : '${chosen.length}/$maxSelect dipilih'),
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded,
                      color: OptikAdminTokens.slate),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 460,
              child: Column(
                children: [
                  if (searchable) ...[
                    TextField(
                      autofocus: true,
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: searchHint,
                        hintStyle: TextStyle(
                          color: OptikAdminTokens.slate.withOpacity(0.85),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: OptikAdminTokens.navy,
                        ),
                        filled: true,
                        fillColor: OptikAdminTokens.snow,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OptikAdminTokens.radiusSm,
                          ),
                          borderSide:
                              const BorderSide(color: OptikAdminTokens.ice),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OptikAdminTokens.radiusSm,
                          ),
                          borderSide:
                              const BorderSide(color: OptikAdminTokens.ice),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            OptikAdminTokens.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: OptikAdminTokens.navy,
                            width: 1.4,
                          ),
                        ),
                      ),
                      onChanged: (v) => setModal(() => query = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.bgMid,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OptikAdminTokens.ice),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: Text(
                                  'Tidak ada opsi cocok.',
                                  style: TextStyle(
                                    color: OptikAdminTokens.slate,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...filtered.map((o) {
                              final on = chosen.contains(o.value);
                              return _AdminPickerTile(
                                label: o.label,
                                subtitle: o.subtitle,
                                icon: o.icon ?? Icons.circle_outlined,
                                trailing: o.trailing,
                                selected: on,
                                multiCheck: true,
                                onTap: () {
                                  setModal(() {
                                    if (on) {
                                      chosen.remove(o.value);
                                    } else {
                                      if (maxSelect != null &&
                                          chosen.length >= maxSelect) {
                                        return;
                                      }
                                      chosen.add(o.value);
                                    }
                                  });
                                },
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.slate,
                ),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, Set<T>.from(chosen)),
                style: FilledButton.styleFrom(
                  backgroundColor: OptikAdminTokens.navy,
                  foregroundColor: OptikAdminTokens.snow,
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

class _AdminPickerTile extends StatelessWidget {
  const _AdminPickerTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.trailing,
    this.multiCheck = false,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final bool selected;
  final bool multiCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? OptikAdminTokens.ice.withOpacity(0.35)
                  : OptikAdminTokens.card,
              border: Border.all(
                color: selected
                    ? OptikAdminTokens.navy.withOpacity(0.55)
                    : OptikAdminTokens.ice,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                if (multiCheck)
                  Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 22,
                    color: selected
                        ? OptikAdminTokens.navy
                        : OptikAdminTokens.slate,
                  )
                else
                  Icon(
                    icon ?? Icons.circle_outlined,
                    size: 22,
                    color: selected
                        ? OptikAdminTokens.navy
                        : OptikAdminTokens.slate,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: OptikAdminTokens.slate,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
                if (!multiCheck)
                  selected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: OptikAdminTokens.navy,
                          size: 20,
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          color: OptikAdminTokens.slate.withOpacity(0.55),
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
