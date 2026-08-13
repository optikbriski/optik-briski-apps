import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/theme.dart';
import '../member_layout.dart';

const _hariPendek = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _hari = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// Date picker premium Member (putih–biru), bottom sheet.
Future<DateTime?> showMemberDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Pilih tanggal',
}) {
  var seed = initialDate;
  if (seed.isBefore(firstDate)) seed = firstDate;
  if (seed.isAfter(lastDate)) seed = lastDate;

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MemberDateSheet(
      initialDate: seed,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _MemberDateSheet extends StatefulWidget {
  const _MemberDateSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_MemberDateSheet> createState() => _MemberDateSheetState();
}

class _MemberDateSheetState extends State<_MemberDateSheet> {
  late DateTime _month;
  late DateTime _selected;
  bool _pickingYear = false;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _month = DateTime(_selected.year, _selected.month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _enabled(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final first = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
      widget.firstDate.day,
    );
    final last = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
      widget.lastDate.day,
    );
    return !day.isBefore(first) && !day.isAfter(last);
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final firstMonth =
        DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(firstMonth) || next.isAfter(lastMonth)) return;
    setState(() => _month = next);
  }

  void _pickYear(int year) {
    var next = DateTime(year, _month.month);
    final firstMonth =
        DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(firstMonth)) next = firstMonth;
    if (next.isAfter(lastMonth)) next = lastMonth;
    setState(() {
      _month = next;
      _pickingYear = false;
    });
  }

  List<DateTime?> _daysInGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <DateTime?>[];
    for (var i = 0; i < lead; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(_month.year, _month.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final monthLabel = DateFormat('MMMM yyyy').format(_month);
    final selectedLabel =
        '${_hari[_selected.weekday - 1]}, ${DateFormat('d MMMM yyyy').format(_selected)}';
    final years = [
      for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
    ];

    // macOS / short viewports: sheet must scroll — fixed Column overflowed by ~12px.
    final maxSheetH = MediaQuery.sizeOf(context).height * 0.92;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: m.isTablet ? 480 : double.infinity,
          maxHeight: maxSheetH,
        ),
        child: Material(
          color: OptikMemberTokens.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                m.pagePadding,
                12,
                m.pagePadding,
                m.isTablet ? 18 : 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: OptikMemberTokens.blue,
                        ),
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
                              selectedLabel,
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
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
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (!_pickingYear)
                              IconButton(
                                onPressed: () => _shiftMonth(-1),
                                icon: const Icon(Icons.chevron_left_rounded),
                                color: OptikMemberTokens.blueDeep,
                              )
                            else
                              const SizedBox(width: 48),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(
                                  () => _pickingYear = !_pickingYear,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _pickingYear ? 'Pilih tahun' : monthLabel,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: m.isTablet ? 17 : 15.5,
                                          color: OptikMemberTokens.blueDeep,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        _pickingYear
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        color: OptikMemberTokens.blue,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (!_pickingYear)
                              IconButton(
                                onPressed: () => _shiftMonth(1),
                                icon: const Icon(Icons.chevron_right_rounded),
                                color: OptikMemberTokens.blueDeep,
                              )
                            else
                              const SizedBox(width: 48),
                          ],
                        ),
                        if (_pickingYear)
                          SizedBox(
                            height: 260,
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                              itemCount: years.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 1.6,
                              ),
                              itemBuilder: (context, i) {
                                final y = years[years.length - 1 - i];
                                final selected = y == _month.year;
                                return Material(
                                  color: selected
                                      ? OptikMemberTokens.blueDeep
                                      : OptikMemberTokens.white,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () => _pickYear(y),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: selected
                                              ? OptikMemberTokens.blueDeep
                                              : OptikMemberTokens.lineSoft,
                                        ),
                                      ),
                                      child: Text(
                                        '$y',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : OptikMemberTokens.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        else ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              for (final h in _hariPendek)
                                Expanded(
                                  child: Text(
                                    h,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: OptikMemberTokens.inkMuted,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final cells = _daysInGrid();
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: cells.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisSpacing: 4,
                                  crossAxisSpacing: 4,
                                ),
                                itemBuilder: (context, i) {
                                  final day = cells[i];
                                  if (day == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final enabled = _enabled(day);
                                  final selected = _sameDay(day, _selected);
                                  final isToday = _sameDay(day, todayDay);

                                  return Material(
                                    color: selected
                                        ? OptikMemberTokens.blueDeep
                                        : Colors.transparent,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: enabled
                                          ? () =>
                                              setState(() => _selected = day)
                                          : null,
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: isToday && !selected
                                              ? Border.all(
                                                  color: OptikMemberTokens.blue,
                                                  width: 1.4,
                                                )
                                              : null,
                                        ),
                                        child: Text(
                                          '${day.day}',
                                          style: TextStyle(
                                            fontWeight: selected || isToday
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            fontSize: 13.5,
                                            color: !enabled
                                                ? OptikMemberTokens.inkMuted
                                                    .withOpacity(0.35)
                                                : selected
                                                    ? Colors.white
                                                    : OptikMemberTokens.ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ],
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
                          onPressed: () => Navigator.pop(context, _selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: OptikMemberTokens.blueDeep,
                            minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Pakai tanggal'),
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
