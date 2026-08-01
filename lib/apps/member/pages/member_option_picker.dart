import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../member_layout.dart';

class MemberPickerOption<T> {
  const MemberPickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

/// Bottom sheet pilihan tunggal — gaya premium Member (putih–biru).
Future<T?> showMemberOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<MemberPickerOption<T>> options,
  T? selected,
  String? subtitle,
  IconData icon = Icons.playlist_add_check_rounded,
  bool? searchable,
  String searchHint = 'Cari…',
}) {
  if (options.isEmpty) return Future.value(null);

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MemberOptionSheet<T>(
      title: title,
      subtitle: subtitle,
      icon: icon,
      options: options,
      selected: selected,
      searchable: searchable ?? options.length > 8,
      searchHint: searchHint,
    ),
  );
}

class _MemberOptionSheet<T> extends StatefulWidget {
  const _MemberOptionSheet({
    required this.title,
    required this.options,
    required this.icon,
    required this.searchable,
    required this.searchHint,
    this.selected,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<MemberPickerOption<T>> options;
  final T? selected;
  final bool searchable;
  final String searchHint;

  @override
  State<_MemberOptionSheet<T>> createState() => _MemberOptionSheetState<T>();
}

class _MemberOptionSheetState<T> extends State<_MemberOptionSheet<T>> {
  late T? _selected;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<MemberPickerOption<T>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) {
      final hay = '${o.label} ${o.subtitle ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  String get _selectedLabel {
    for (final o in widget.options) {
      if (o.value == _selected) return o.label;
    }
    return 'Belum dipilih';
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final filtered = _filtered;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: m.isTablet ? 480 : double.infinity,
        height: maxH,
        child: Material(
          color: OptikMemberTokens.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                m.pagePadding,
                12,
                m.pagePadding,
                m.isTablet ? 18 : 12,
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.lineSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: OptikMemberTokens.blueSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: OptikMemberTokens.blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: m.isTablet ? 20 : 17,
                                color: OptikMemberTokens.blueDeep,
                              ),
                            ),
                            Text(
                              widget.subtitle ?? _selectedLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: m.menuSubtitleSize,
                                color: OptikMemberTokens.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.searchable) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: m.bodySize),
                      decoration: InputDecoration(
                        hintText: widget.searchHint,
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: OptikMemberTokens.blue,
                        ),
                        filled: true,
                        fillColor: OptikMemberTokens.blueMist,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: OptikMemberTokens.lineSoft,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: OptikMemberTokens.lineSoft,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: OptikMemberTokens.blue,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            OptikMemberTokens.blueMist,
                            OptikMemberTokens.white,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: OptikMemberTokens.lineSoft),
                        boxShadow: OptikMemberTokens.cardShadow,
                      ),
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(28),
                              child: Center(
                                child: Text(
                                  'Tidak ada hasil',
                                  style: TextStyle(
                                    color: OptikMemberTokens.inkMuted,
                                    fontWeight: FontWeight.w600,
                                    fontSize: m.bodySize,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, i) {
                                final o = filtered[i];
                                final selected = o.value == _selected;
                                return Material(
                                  color: selected
                                      ? OptikMemberTokens.blueDeep
                                      : OptikMemberTokens.white,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () =>
                                        setState(() => _selected = o.value),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? Colors.white
                                                      .withOpacity(0.18)
                                                  : OptikMemberTokens.blueSoft,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              o.icon ?? Icons.check_rounded,
                                              size: 18,
                                              color: selected
                                                  ? Colors.white
                                                  : OptikMemberTokens.blue,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  o.label,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: m.bodySize,
                                                    color: selected
                                                        ? Colors.white
                                                        : OptikMemberTokens
                                                            .ink,
                                                  ),
                                                ),
                                                if (o.subtitle != null &&
                                                    o.subtitle!
                                                        .trim()
                                                        .isNotEmpty)
                                                  Text(
                                                    o.subtitle!,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize:
                                                          m.menuSubtitleSize,
                                                      color: selected
                                                          ? Colors.white
                                                              .withOpacity(0.8)
                                                          : OptikMemberTokens
                                                              .inkMuted,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (selected)
                                            const Icon(
                                              Icons.check_circle_rounded,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
                            side: const BorderSide(
                              color: OptikMemberTokens.blue,
                            ),
                            foregroundColor: OptikMemberTokens.blueDeep,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _selected == null
                              ? null
                              : () => Navigator.pop(context, _selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: OptikMemberTokens.blueDeep,
                            disabledBackgroundColor: OptikMemberTokens.blueSoft,
                            minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Pakai'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Field tap-to-open untuk picker premium Member.
class MemberPickerField extends StatelessWidget {
  const MemberPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.valueLabel,
    this.placeholder,
    this.enabled = true,
    this.metrics,
  });

  final String label;
  final IconData icon;
  final String? valueLabel;
  final String? placeholder;
  final VoidCallback? onTap;
  final bool enabled;
  final MemberLayoutMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics ?? MemberLayout.of(context);
    final hasValue = valueLabel != null && valueLabel!.trim().isNotEmpty;
    final text = hasValue ? valueLabel! : (placeholder ?? 'Pilih $label');

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(fontSize: m.labelSize),
              prefixIcon: Icon(icon, color: OptikMemberTokens.blue),
              suffixIcon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: enabled
                    ? OptikMemberTokens.blue
                    : OptikMemberTokens.inkMuted,
              ),
              filled: true,
              fillColor: OptikMemberTokens.blueMist,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: OptikMemberTokens.lineSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: OptikMemberTokens.lineSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: OptikMemberTokens.blue,
                  width: 1.6,
                ),
              ),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasValue
                    ? OptikMemberTokens.ink
                    : OptikMemberTokens.inkMuted,
                fontWeight: FontWeight.w600,
                fontSize: m.bodySize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Format nama wilayah API (ACEH → Aceh, DKI JAKARTA → DKI Jakarta).
String formatWilayahLabel(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return t;
  final lower = t.toLowerCase();
  String title(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
  if (lower.startsWith('dki ')) return 'DKI ${title(lower.substring(4))}';
  return title(lower);
}
