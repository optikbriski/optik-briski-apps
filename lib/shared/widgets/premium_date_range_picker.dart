import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Hasil rentang tanggal dari picker bergaya Meta Ads.
class DateRangePick {
  const DateRangePick({
    required this.start,
    required this.end,
    required this.presetId,
  });

  final DateTime start;
  final DateTime end;
  final String presetId;
}

/// Dialog/popover date range: sidebar preset + 2 kalender + Update.
Future<DateRangePick?> showPremiumDateRangePicker({
  required BuildContext context,
  required DateTime initialStart,
  required DateTime initialEnd,
  String initialPresetId = 'custom',
  String timezoneNote = 'Tanggal ditampilkan dalam Waktu Jakarta',
}) {
  return showDialog<DateRangePick>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: _PremiumDateRangeSheet(
        initialStart: initialStart,
        initialEnd: initialEnd,
        initialPresetId: initialPresetId,
        timezoneNote: timezoneNote,
      ),
    ),
  );
}

class _Preset {
  const _Preset(this.id, this.label, this.range);
  final String id;
  final String label;
  final DateTimeRange Function() range;
}

class _PremiumDateRangeSheet extends StatefulWidget {
  const _PremiumDateRangeSheet({
    required this.initialStart,
    required this.initialEnd,
    required this.initialPresetId,
    required this.timezoneNote,
  });

  final DateTime initialStart;
  final DateTime initialEnd;
  final String initialPresetId;
  final String timezoneNote;

  @override
  State<_PremiumDateRangeSheet> createState() => _PremiumDateRangeSheetState();
}

class _PremiumDateRangeSheetState extends State<_PremiumDateRangeSheet> {
  static const _bg = Color(0xFF152033);
  static const _panel = Color(0xFF1A2740);
  static const _line = Color(0xFF2A3A55);
  static const _accent = Color(0xFF3B82F6);
  static const _accentSoft = Color(0xFF1D4ED8);

  final _dayFmt = DateFormat('d MMM yyyy', 'id_ID');
  final _monthFmt = DateFormat('MMMM yyyy', 'id_ID');

  late DateTime _start;
  late DateTime _end;
  late String _presetId;
  late DateTime _leftMonth; // first day of left calendar month
  DateTime? _hoverDay;
  bool _pickingEnd = false;

  late final List<_Preset> _presets;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  static DateTime _addMonths(DateTime d, int months) {
    var y = d.year;
    var m = d.month + months;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > last ? last : d.day);
  }

  @override
  void initState() {
    super.initState();
    _start = _d(widget.initialStart);
    _end = _d(widget.initialEnd);
    if (_end.isBefore(_start)) _end = _start;
    _presetId = widget.initialPresetId;
    _leftMonth = DateTime(_end.year, _end.month, 1);
    // Show end month on the right; left is previous month.
    _leftMonth = DateTime(_leftMonth.year, _leftMonth.month - 1, 1);

    final now = _d(DateTime.now());
    _presets = [
      _Preset('last7', '7 hari terakhir', () {
        return DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
      }),
      _Preset('last30', '30 hari terakhir', () {
        return DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now);
      }),
      _Preset('last60', '60 hari terakhir', () {
        return DateTimeRange(start: now.subtract(const Duration(days: 59)), end: now);
      }),
      _Preset('last90', '90 hari terakhir', () {
        return DateTimeRange(start: now.subtract(const Duration(days: 89)), end: now);
      }),
      _Preset('thisMonth', 'Bulan ini', () {
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      }),
      _Preset('lastMonth', 'Bulan lalu', () {
        final firstThis = DateTime(now.year, now.month, 1);
        final lastPrev = firstThis.subtract(const Duration(days: 1));
        final firstPrev = DateTime(lastPrev.year, lastPrev.month, 1);
        return DateTimeRange(start: firstPrev, end: lastPrev);
      }),
      _Preset('lastYear', 'Tahun lalu', () {
        return DateTimeRange(
          start: _addMonths(now, -12),
          end: now,
        );
      }),
      _Preset('custom', 'Kustom', () => DateTimeRange(start: _start, end: _end)),
    ];
  }

  void _applyPreset(String id) {
    final p = _presets.firstWhere((e) => e.id == id);
    if (id == 'custom') {
      setState(() {
        _presetId = 'custom';
        _pickingEnd = false;
      });
      return;
    }
    final r = p.range();
    setState(() {
      _presetId = id;
      _start = _d(r.start);
      _end = _d(r.end);
      _pickingEnd = false;
      _leftMonth = DateTime(_end.year, _end.month - 1, 1);
    });
  }

  void _onDayTap(DateTime day) {
    final d = _d(day);
    setState(() {
      _presetId = 'custom';
      if (!_pickingEnd) {
        _start = d;
        _end = d;
        _pickingEnd = true;
      } else {
        if (d.isBefore(_start)) {
          _end = _start;
          _start = d;
        } else {
          _end = d;
        }
        _pickingEnd = false;
      }
    });
  }

  void _shiftMonths(int delta) {
    setState(() {
      _leftMonth = DateTime(_leftMonth.year, _leftMonth.month + delta, 1);
    });
  }

  String get _rangeLabel =>
      '${_dayFmt.format(_start)} – ${_dayFmt.format(_end)}';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Material(
      color: _bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 780 : 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 200, child: _presetSidebar()),
                        Container(width: 1, color: _line),
                        Expanded(child: _calendarsPane(wide: true)),
                      ],
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        _presetSidebar(horizontal: true),
                        const Divider(height: 1, color: _line),
                        _calendarsPane(wide: false),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _line)),
                color: _panel,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _rangeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.timezoneNote,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Batal',
                            style: TextStyle(
                                color: Color(0xFF60A5FA),
                                fontWeight: FontWeight.w700)),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            DateRangePick(
                              start: _start,
                              end: _end,
                              presetId: _presetId,
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Update',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetSidebar({bool horizontal = false}) {
    if (horizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            for (final p in _presets) ...[
              _presetTile(p, compact: true),
              const SizedBox(width: 8),
            ]
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      children: [
        for (final p in _presets) _presetTile(p),
      ],
    );
  }

  Widget _presetTile(_Preset p, {bool compact = false}) {
    final selected = _presetId == p.id;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 4),
      child: Material(
        color: selected ? _accent.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _applyPreset(p.id),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 10,
              vertical: compact ? 10 : 11,
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: selected ? _accent : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                Text(
                  p.label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFCBD5E1),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _calendarsPane({required bool wide}) {
    final rightMonth = DateTime(_leftMonth.year, _leftMonth.month + 1, 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonths(-1),
                icon: const Icon(Icons.chevron_left_rounded,
                    color: Colors.white70),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _shiftMonths(1),
                icon: const Icon(Icons.chevron_right_rounded,
                    color: Colors.white70),
              ),
            ],
          ),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _monthGrid(_leftMonth)),
                const SizedBox(width: 12),
                Expanded(child: _monthGrid(rightMonth)),
              ],
            )
          else ...[
            _monthGrid(_leftMonth),
            const SizedBox(height: 12),
            _monthGrid(rightMonth),
          ],
          const SizedBox(height: 8),
          Text(
            _pickingEnd
                ? 'Pilih tanggal akhir rentang'
                : 'Klik tanggal mulai, lalu tanggal akhir (atau pilih preset)',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _monthGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    // Monday-first grid (Min=7 → index 6 for Sunday if we use weekday)
    // Indonesian UI in screenshot: Min Sen Sel... so Sunday first.
    final lead = first.weekday % 7; // Sunday=0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[];
    for (var i = 0; i < lead; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(month.year, month.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    const weekdays = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];

    return Column(
      children: [
        Text(
          _monthFmt.format(month),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < cells.length / 7; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _dayCell(cells[r * 7 + c])),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(DateTime? day) {
    if (day == null) {
      return const SizedBox(height: 36);
    }
    final d = _d(day);
    final inRange = !d.isBefore(_start) && !d.isAfter(_end);
    final isStart = d == _start;
    final isEnd = d == _end;
    final isEdge = isStart || isEnd;
    final today = d == _d(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onDayTap(d),
          onHover: (h) => setState(() => _hoverDay = h ? d : null),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isEdge
                  ? _accent
                  : inRange
                      ? _accentSoft.withOpacity(0.35)
                      : (_hoverDay == d ? Colors.white10 : null),
              borderRadius: isEdge
                  ? BorderRadius.circular(8)
                  : inRange
                      ? BorderRadius.zero
                      : BorderRadius.circular(8),
            ),
            child: Text(
              '${d.day}',
              style: TextStyle(
                color: isEdge
                    ? Colors.white
                    : inRange
                        ? const Color(0xFFBFDBFE)
                        : today
                            ? _accent
                            : const Color(0xFFE2E8F0),
                fontWeight:
                    isEdge || today ? FontWeight.w800 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol pemicu rentang tanggal (seperti Meta Ads).
class PremiumDateRangeTrigger extends StatelessWidget {
  const PremiumDateRangeTrigger({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A2740),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A3A55)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_rounded,
                  size: 18, color: Color(0xFF60A5FA)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const Icon(Icons.expand_more_rounded,
                  color: Color(0xFF94A3B8), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
