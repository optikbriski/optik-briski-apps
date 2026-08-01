import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme.dart';
import '../member_layout.dart';

/// Picker jam 09:00–20:30, interval 30 menit.
/// Scroll default. Ketuk kotak jam / double-tap wheel → ketik bebas, lalu snap.
Future<TimeOfDay?> showMemberHalfHourTimePicker(
  BuildContext context, {
  TimeOfDay? initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HalfHourTimeSheet(initial: initial),
  );
}

class _HalfHourTimeSheet extends StatefulWidget {
  const _HalfHourTimeSheet({this.initial});

  final TimeOfDay? initial;

  @override
  State<_HalfHourTimeSheet> createState() => _HalfHourTimeSheetState();
}

class _HalfHourTimeSheetState extends State<_HalfHourTimeSheet> {
  /// Jam buka 09–20; slot terakhir 20:30.
  static const _hours = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
  static const _minutes = [0, 30];

  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  late final TextEditingController _hourTypeCtrl;
  late final TextEditingController _minuteTypeCtrl;
  final _hourFocus = FocusNode();
  final _minuteFocus = FocusNode();
  late int _hour;
  late int _minute;
  bool _typing = false;
  /// Hindari onSelectedItemChanged menimpa jam saat jump/animate programmatic.
  bool _ignoreWheel = false;
  String? _typeError;

  @override
  void initState() {
    super.initState();
    final snap = _snap(widget.initial ?? const TimeOfDay(hour: 10, minute: 0));
    _hour = snap.hour;
    _minute = snap.minute;
    _hourCtrl = FixedExtentScrollController(
      initialItem: _hours.indexOf(_hour).clamp(0, _hours.length - 1),
    );
    _minuteCtrl = FixedExtentScrollController(
      initialItem: _minutes.indexOf(_minute).clamp(0, _minutes.length - 1),
    );
    _hourTypeCtrl = TextEditingController(text: '$_hour');
    _minuteTypeCtrl =
        TextEditingController(text: _minute.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _hourTypeCtrl.dispose();
    _minuteTypeCtrl.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  /// Aturan snap:
  /// - jam < 9 → 9; jam > 20 → 20
  /// - menit < 15 → 00; selain itu → 30
  TimeOfDay _snap(TimeOfDay t) {
    var h = t.hour;
    var m = t.minute;
    if (h < 9) h = 9;
    if (h > 20) h = 20;
    m = m < 15 ? 0 : 30;
    return TimeOfDay(hour: h, minute: m);
  }

  String _label(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  void _applySnapped(TimeOfDay t, {bool syncWheels = true}) {
    final s = _snap(t);
    setState(() {
      _hour = s.hour;
      _minute = s.minute;
      _typeError = null;
    });
    if (!syncWheels) return;

    final hi = _hours.indexOf(_hour);
    final mi = _minutes.indexOf(_minute);
    _ignoreWheel = true;
    if (_hourCtrl.hasClients && hi >= 0) {
      _hourCtrl.jumpToItem(hi);
    }
    if (_minuteCtrl.hasClients && mi >= 0) {
      _minuteCtrl.jumpToItem(mi);
    }
    // Lepas flag setelah frame agar event wheel intermediate diabaikan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ignoreWheel = false;
    });

    // Jangan timpa teks saat user masih mengetik di field.
    if (!_typing) {
      _hourTypeCtrl.text = '$_hour';
      _minuteTypeCtrl.text = _minute.toString().padLeft(2, '0');
    }
  }

  void _enterTyping({bool focusMinute = false}) {
    _hourTypeCtrl.text = '$_hour';
    _minuteTypeCtrl.text = _minute.toString().padLeft(2, '0');
    setState(() {
      _typing = true;
      _typeError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = focusMinute ? _minuteFocus : _hourFocus;
      node.requestFocus();
      final ctrl = focusMinute ? _minuteTypeCtrl : _hourTypeCtrl;
      ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: ctrl.text.length,
      );
    });
  }

  /// Terapkan angka yang diketik (bebas), baru di-snap.
  bool _commitTyped() {
    final hText = _hourTypeCtrl.text.trim();
    final mText = _minuteTypeCtrl.text.trim();
    final hRaw = int.tryParse(hText);
    final mRaw = int.tryParse(mText);

    if (hText.isEmpty && mText.isEmpty) {
      setState(() => _typeError = 'Isi jam atau menit');
      return false;
    }
    if (hText.isNotEmpty && hRaw == null) {
      setState(() => _typeError = 'Jam tidak valid');
      return false;
    }
    if (mText.isNotEmpty && mRaw == null) {
      setState(() => _typeError = 'Menit tidak valid');
      return false;
    }

    final snapped = _snap(
      TimeOfDay(
        hour: hRaw ?? _hour,
        minute: mRaw ?? _minute,
      ),
    );
    // Update state + wheel dulu, teks diisi setelah keluar mode ketik.
    _ignoreWheel = true;
    setState(() {
      _hour = snapped.hour;
      _minute = snapped.minute;
      _typeError = null;
    });
    final hi = _hours.indexOf(_hour);
    final mi = _minutes.indexOf(_minute);
    if (_hourCtrl.hasClients && hi >= 0) _hourCtrl.jumpToItem(hi);
    if (_minuteCtrl.hasClients && mi >= 0) _minuteCtrl.jumpToItem(mi);
    return true;
  }

  void _exitTyping() {
    if (!_commitTyped()) return;
    _hourFocus.unfocus();
    _minuteFocus.unfocus();
    _hourTypeCtrl.text = '$_hour';
    _minuteTypeCtrl.text = _minute.toString().padLeft(2, '0');
    setState(() {
      _typing = false;
      _typeError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ignoreWheel = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: m.isTablet ? 480 : double.infinity,
          ),
          child: Material(
            color: OptikMemberTokens.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          color: OptikMemberTokens.blue,
                          size: m.iconSize,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Jam kunjungan',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: m.isTablet ? 20 : 17,
                              color: OptikMemberTokens.blueDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _typing
                            ? 'Ketik bebas — otomatis dibulatkan ke slot terdekat'
                            : 'Scroll · ketuk kotak jam / double-tap untuk ketik',
                        style: TextStyle(
                          color: OptikMemberTokens.inkMuted,
                          fontSize: m.menuSubtitleSize,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_typing)
                      _typingRow(m)
                    else
                      Material(
                        color: OptikMemberTokens.blueMist,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => _enterTyping(),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              vertical: m.isTablet ? 16 : 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: OptikMemberTokens.lineSoft,
                              ),
                            ),
                            child: Text(
                              _label(_hour, _minute),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: m.isTablet ? 32 : 28,
                                fontWeight: FontWeight.w800,
                                color: OptikMemberTokens.blue,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_typeError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _typeError!,
                        style: TextStyle(
                          color: OptikMemberTokens.danger,
                          fontSize: m.menuSubtitleSize,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      height: m.isTablet ? 180 : 160,
                      child: Opacity(
                        opacity: _typing ? 0.4 : 1,
                        child: Row(
                          children: [
                            Expanded(
                              child: _wheelColumn(
                                label: 'Jam',
                                controller: _hourCtrl,
                                itemCount: _hours.length,
                                labelOf: (i) =>
                                    _hours[i].toString().padLeft(2, '0'),
                                onSelected: (i) {
                                  if (_typing || _ignoreWheel) return;
                                  _applySnapped(
                                    TimeOfDay(hour: _hours[i], minute: _minute),
                                  );
                                },
                                metrics: m,
                                onDoubleTap: () => _enterTyping(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 22),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  fontSize: m.isTablet ? 28 : 24,
                                  fontWeight: FontWeight.w800,
                                  color: OptikMemberTokens.blueDeep,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _wheelColumn(
                                label: 'Menit',
                                controller: _minuteCtrl,
                                itemCount: _minutes.length,
                                labelOf: (i) =>
                                    _minutes[i].toString().padLeft(2, '0'),
                                onSelected: (i) {
                                  if (_typing || _ignoreWheel) return;
                                  _applySnapped(
                                    TimeOfDay(
                                      hour: _hour,
                                      minute: _minutes[i],
                                    ),
                                  );
                                },
                                metrics: m,
                                onDoubleTap: () =>
                                    _enterTyping(focusMinute: true),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (_typing && !_commitTyped()) return;
                              Navigator.pop(
                                context,
                                TimeOfDay(hour: _hour, minute: _minute),
                              );
                            },
                            child: const Text('Pakai jam ini'),
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
      ),
    );
  }

  Widget _typingRow(MemberLayoutMetrics m) {
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: OptikMemberTokens.blueMist,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _hourTypeCtrl,
            focusNode: _hourFocus,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: m.isTablet ? 28 : 24,
              fontWeight: FontWeight.w800,
              color: OptikMemberTokens.blue,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: dec('Jam'),
            onSubmitted: (_) => _minuteFocus.requestFocus(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18, left: 6, right: 6),
          child: Text(
            ':',
            style: TextStyle(
              fontSize: m.isTablet ? 28 : 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _minuteTypeCtrl,
            focusNode: _minuteFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: m.isTablet ? 28 : 24,
              fontWeight: FontWeight.w800,
              color: OptikMemberTokens.blue,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: dec('Menit'),
            onSubmitted: (_) => _exitTyping(),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filled(
            tooltip: 'Terapkan',
            onPressed: _exitTyping,
            icon: const Icon(Icons.check_rounded),
          ),
        ),
      ],
    );
  }

  Widget _wheelColumn({
    required String label,
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) labelOf,
    required ValueChanged<int> onSelected,
    required MemberLayoutMetrics metrics,
    required VoidCallback onDoubleTap,
  }) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: metrics.menuSubtitleSize,
              color: OptikMemberTokens.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                NotificationListener<ScrollNotification>(
                  onNotification: (_) => false,
                  child: ListWheelScrollView.useDelegate(
                    controller: controller,
                    itemExtent: 40,
                    perspective: 0.003,
                    diameterRatio: 1.2,
                    physics: _typing
                        ? const NeverScrollableScrollPhysics()
                        : const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: onSelected,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: itemCount,
                      builder: (context, i) => Center(
                        child: Text(
                          labelOf(i),
                          style: TextStyle(
                            fontSize: metrics.isTablet ? 22 : 20,
                            fontWeight: FontWeight.w800,
                            color: OptikMemberTokens.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
