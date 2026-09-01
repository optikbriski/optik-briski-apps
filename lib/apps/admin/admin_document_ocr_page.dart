import 'dart:math' as math;
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/ocr/document_ocr_flow.dart';
import '../../shared/ocr/google_vision_ocr_service.dart';
import '../../shared/ocr/vision_table_grid.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Scan tulisan tangan / form / nota → teks draf atau tabel kolom.
class AdminDocumentOcrPage extends StatefulWidget {
  const AdminDocumentOcrPage({super.key});

  @override
  State<AdminDocumentOcrPage> createState() => _AdminDocumentOcrPageState();
}

class _AdminDocumentOcrPageState extends State<AdminDocumentOcrPage> {
  final _text = TextEditingController();
  final _countCtrl = TextEditingController(text: '3');
  final List<TextEditingController> _headers = [];
  List<List<TextEditingController>> _cells = [];
  Uint8List? _preview;
  bool _busy = false;
  bool _tableMode = true;
  bool _skipHeader = false;
  int? _confirmedCount;
  bool _fullscreenOpen = false;

  static const _colWidth = 188.0;
  static const _titleCardHeight = 108.0;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  TextEditingController _bind([String text = '']) {
    final c = TextEditingController(text: text);
    c.addListener(_onText);
    return c;
  }

  void _disposeCtrl(TextEditingController c) {
    c.removeListener(_onText);
    c.dispose();
  }

  int get _colCount => _headers.length;

  int get _draftCount {
    final n = int.tryParse(_countCtrl.text.trim());
    if (n == null) return _confirmedCount ?? 3;
    return n.clamp(VisionTableGrid.minColumns, VisionTableGrid.maxColumns);
  }

  bool get _titlesReady =>
      _confirmedCount != null && _confirmedCount == _draftCount;

  void _syncCountField(int n) {
    final s = '$n';
    if (_countCtrl.text == s) return;
    _countCtrl.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }

  void _bumpCount(int delta) {
    final n = (_draftCount + delta).clamp(
      VisionTableGrid.minColumns,
      VisionTableGrid.maxColumns,
    );
    _syncCountField(n);
    setState(() {});
  }

  void _confirmCount() {
    final n = _draftCount;
    _syncCountField(n);
    while (_headers.length < n) {
      _headers.add(_bind());
    }
    while (_headers.length > n) {
      _disposeCtrl(_headers.removeLast());
    }
    if (_cells.isEmpty) {
      _cells = [
        [for (var i = 0; i < n; i++) _bind()],
      ];
    } else {
      for (final row in _cells) {
        while (row.length < n) {
          row.add(_bind());
        }
        while (row.length > n) {
          _disposeCtrl(row.removeLast());
        }
      }
    }
    if (!mounted) return;
    setState(() => _confirmedCount = n);
  }

  List<String> get _headerValues =>
      [for (final h in _headers) h.text.trim()];

  List<List<String>> get _cellValues => [
        for (final row in _cells)
          [for (final c in row) c.text],
      ];

  void _setRows(List<List<String>> rows) {
    final n = _colCount;
    if (n <= 0) return;
    for (final row in _cells) {
      for (final c in row) {
        _disposeCtrl(c);
      }
    }
    _cells = [
      for (final row in rows)
        [
          for (var i = 0; i < n; i++) _bind(i < row.length ? row[i] : ''),
        ],
    ];
    if (_cells.isEmpty) {
      _cells = [
        [for (var i = 0; i < n; i++) _bind()],
      ];
    }
  }

  void _addRow() {
    setState(() {
      _cells.add([for (var i = 0; i < _colCount; i++) _bind()]);
    });
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    _countCtrl.dispose();
    for (final h in _headers) {
      _disposeCtrl(h);
    }
    for (final row in _cells) {
      for (final c in row) {
        _disposeCtrl(c);
      }
    }
    super.dispose();
  }

  Future<void> _scan() async {
    if (_tableMode && !_titlesReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ocr_need_confirm'.tr())),
      );
      return;
    }
    try {
      final bytes = await scanDocumentPreviewBytes(
        context: context,
        cropTitle: 'ocr_crop_title'.tr(),
      );
      if (bytes == null || !mounted) return;
      setState(() {
        _busy = true;
        _preview = bytes;
      });
      final draft = await GoogleVisionOcrService().readDocument(
        bytes: bytes,
        kind: 'handwriting',
      );
      if (!mounted) return;
      final nextText = draft.text.trim().isEmpty ? '' : draft.text;
      List<List<String>>? grid;
      if (_tableMode) {
        grid = draft.tokens.isNotEmpty
            ? VisionTableGrid.fromTokens(
                tokens: draft.tokens,
                columns: _colCount,
                skipFirstRow: _skipHeader,
              )
            : VisionTableGrid.fromPlainText(draft.text, _colCount);
      }
      setState(() {
        _text.text = nextText;
        if (grid != null) _setRows(grid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.text.trim().isEmpty
                ? 'ocr_empty'.tr()
                : (_tableMode ? 'ocr_ok_table'.tr() : 'ocr_ok_edit'.tr()),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ocr_fail'.tr(namedArgs: {'error': '$e'})),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final t = _tableMode
        ? VisionTableGrid.toTsv(_headerValues, _cellValues)
        : _text.text.trim();
    if (t.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tableMode ? 'ocr_copied_table'.tr() : 'ocr_copied'.tr()),
      ),
    );
  }

  Future<void> _openFullscreen() async {
    if (!_titlesReady || _headers.isEmpty) return;
    setState(() => _fullscreenOpen = true);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _OcrTableFullscreenPage(
          headers: _headers,
          cells: _cells,
          onAddRow: _addRow,
          onCopy: _copy,
        ),
      ),
    );
    if (mounted) setState(() => _fullscreenOpen = false);
  }

  bool get _copyEnabled {
    if (_busy) return false;
    if (_tableMode) {
      return _cellValues.any((r) => r.any((c) => c.trim().isNotEmpty));
    }
    return _text.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'ocr_admin_title'.tr(),
        subtitle: 'ocr_admin_sub'.tr(),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
        children: [
          _intro(),
          const SizedBox(height: 16),
          PremiumPanel(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            showAccentBar: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PremiumSectionHeader(
                  label: 'ocr_mode'.tr(),
                  padding: const EdgeInsets.only(bottom: 12),
                ),
                _modeSwitch(),
                if (_tableMode) ...[
                  const SizedBox(height: 22),
                  PremiumSectionHeader(
                    label: 'ocr_step_layout'.tr(),
                    padding: const EdgeInsets.only(bottom: 12),
                  ),
                  Text(
                    'ocr_table_hint'.tr(),
                    style: TextStyle(
                      color: OptikAdminTokens.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _countStepper(),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: const ValueKey('ocr-confirm-cols'),
                    child: PremiumPrimaryButton(
                      label: 'ocr_confirm_cols'.tr(),
                      icon: Icons.check_rounded,
                      onPressed: _busy ? null : _confirmCount,
                    ),
                  ),
                  if (_titlesReady) ...[
                    const SizedBox(height: 22),
                    PremiumSectionHeader(
                      label: 'ocr_step_titles'.tr(),
                      padding: const EdgeInsets.only(bottom: 12),
                    ),
                    Text(
                      'ocr_titles_label'.tr(),
                      style: TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _titleStrip(),
                  ],
                  const SizedBox(height: 8),
                  _skipHeaderRow(),
                ],
                if (_busy) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: OptikAdminTokens.navy,
                      backgroundColor: OptikAdminTokens.ice,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'ocr_loading'.tr(),
                    style: TextStyle(
                      color: OptikAdminTokens.slate,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                PremiumSectionHeader(
                  label: 'ocr_step_capture'.tr(),
                  padding: const EdgeInsets.only(bottom: 12),
                ),
                if (_preview != null) ...[
                  _previewFrame(),
                  const SizedBox(height: 12),
                ],
                PremiumPrimaryButton(
                  label: 'ocr_scan'.tr(),
                  icon: Icons.document_scanner_outlined,
                  onPressed:
                      _busy || (_tableMode && !_titlesReady) ? null : _scan,
                ),
                const SizedBox(height: 22),
                PremiumSectionHeader(
                  label: 'ocr_step_result'.tr(),
                  padding: const EdgeInsets.only(bottom: 12),
                  trailing: _tableMode && _titlesReady
                      ? IconButton(
                          key: const ValueKey('ocr-fullscreen'),
                          tooltip: 'ocr_fullscreen'.tr(),
                          onPressed: _openFullscreen,
                          icon: Icon(
                            Icons.fullscreen_rounded,
                            color: OptikAdminTokens.navy,
                          ),
                        )
                      : null,
                ),
                if (_tableMode)
                  _titlesReady
                      ? (_fullscreenOpen
                          ? _resultPlaceholder()
                          : _OcrScrollTable(
                              headers: _headers,
                              cells: _cells,
                              colWidth: _colWidth,
                              maxHeight: 360,
                              onAddRow: _addRow,
                            ))
                      : _resultPlaceholder()
                else
                  _buildText(),
                const SizedBox(height: 14),
                PremiumPrimaryButton(
                  label: _tableMode ? 'ocr_copy_table'.tr() : 'ocr_copy'.tr(),
                  icon: Icons.copy_rounded,
                  onPressed: _copyEnabled ? _copy : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PremiumIconBadge(
          icon: Icons.document_scanner_outlined,
          size: 48,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'ocr_admin_hint'.tr(),
            style: TextStyle(
              color: OptikAdminTokens.textSecondary,
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeSwitch() {
    return Row(
      children: [
        Expanded(
          child: _ModeTile(
            selected: !_tableMode,
            icon: Icons.notes_rounded,
            label: 'ocr_mode_text'.tr(),
            onTap: _busy ? null : () => setState(() => _tableMode = false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ModeTile(
            selected: _tableMode,
            icon: Icons.table_chart_outlined,
            label: 'ocr_mode_table'.tr(),
            onTap: _busy ? null : () => setState(() => _tableMode = true),
          ),
        ),
      ],
    );
  }

  Widget _countStepper() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: OptikAdminTokens.ice.withOpacity(
          OptikAdminTokens.isDark ? 0.12 : 0.55,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OptikAdminTokens.chromeEdge),
      ),
      child: Column(
        children: [
          Text(
            'ocr_cols'.tr(),
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _roundIconBtn(
                icon: Icons.remove_rounded,
                enabled:
                    !_busy && _draftCount > VisionTableGrid.minColumns,
                onTap: () => _bumpCount(-1),
              ),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _countCtrl,
                    enabled: !_busy,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: OptikAdminTokens.navy,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              _roundIconBtn(
                icon: Icons.add_rounded,
                enabled:
                    !_busy && _draftCount < VisionTableGrid.maxColumns,
                onTap: () => _bumpCount(1),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ocr_cols_help'.tr(),
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundIconBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: OptikAdminTokens.card,
            border: Border.all(color: OptikAdminTokens.lineStrong),
          ),
          child: Icon(
            icon,
            color: enabled
                ? OptikAdminTokens.navy
                : OptikAdminTokens.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _titleStrip() {
    if (_headers.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: _titleCardHeight,
      child: ListView.separated(
        key: const ValueKey('ocr-title-strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        itemCount: _headers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          return SizedBox(
            width: 176,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: OptikAdminTokens.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      color: OptikAdminTokens.chromeGarnish,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('ocr-title-$i'),
                      controller: _headers[i],
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        contentPadding: const EdgeInsets.only(top: 4),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'ocr_col_hint'.tr(
                          namedArgs: {'n': '${i + 1}'},
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _skipHeaderRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.horizontal_rule_rounded,
            size: 18,
            color: OptikAdminTokens.slate,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ocr_skip_header'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: OptikAdminTokens.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: _skipHeader,
            onChanged:
                _busy ? null : (v) => setState(() => _skipHeader = v),
          ),
        ],
      ),
    );
  }

  Widget _previewFrame() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Image.memory(
            _preview!,
            height: 168,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy.withOpacity(0.78),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'ocr_step_capture'.tr(),
                style: TextStyle(
                  color: OptikAdminTokens.onHighlight,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptikAdminTokens.line),
        color: OptikAdminTokens.ice.withOpacity(
          OptikAdminTokens.isDark ? 0.08 : 0.35,
        ),
      ),
      child: Text(
        'ocr_need_confirm'.tr(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: OptikAdminTokens.textMuted,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildText() {
    return TextField(
      controller: _text,
      maxLines: 12,
      decoration: InputDecoration(
        labelText: 'ocr_draft'.tr(),
        alignLabelWithHint: true,
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.selected,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? OptikAdminTokens.navy.withOpacity(
                    OptikAdminTokens.isDark ? 0.35 : 0.08,
                  )
                : OptikAdminTokens.card,
            border: Border.all(
              color: selected
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? OptikAdminTokens.navy
                    : OptikAdminTokens.slate,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected
                      ? OptikAdminTokens.navy
                      : OptikAdminTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OcrScrollTable extends StatefulWidget {
  const _OcrScrollTable({
    required this.headers,
    required this.cells,
    required this.colWidth,
    required this.onAddRow,
    this.maxHeight,
    this.expand = false,
  });

  final List<TextEditingController> headers;
  final List<List<TextEditingController>> cells;
  final double colWidth;
  final VoidCallback onAddRow;
  final double? maxHeight;
  final bool expand;

  @override
  State<_OcrScrollTable> createState() => _OcrScrollTableState();
}

class _OcrScrollTableState extends State<_OcrScrollTable> {
  final _h = ScrollController();
  final _v = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.headers.length;
    if (n == 0) return const SizedBox.shrink();

    final framed = Container(
      key: const ValueKey('ocr-result-table'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptikAdminTokens.lineStrong),
        color: OptikAdminTokens.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Text(
              'ocr_slide_hint'.tr(),
              style: TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = math.max(
                  n * widget.colWidth,
                  constraints.maxWidth,
                );
                return Scrollbar(
                  controller: _h,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  notificationPredicate: (notif) =>
                      notif.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      height: constraints.maxHeight,
                      child: Scrollbar(
                        controller: _v,
                        thumbVisibility: true,
                        notificationPredicate: (notif) =>
                            notif.metrics.axis == Axis.vertical,
                        child: ListView(
                          controller: _v,
                          padding: EdgeInsets.zero,
                          children: [
                            _headerRow(),
                            for (var r = 0; r < widget.cells.length; r++)
                              _dataRow(r),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: const ValueKey('ocr-add-row'),
                                  onPressed: widget.onAddRow,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text('ocr_add_row'.tr()),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (widget.expand) return framed;
    return SizedBox(height: widget.maxHeight ?? 320, child: framed);
  }

  Widget _headerRow() {
    return Container(
      decoration: BoxDecoration(
        color: OptikAdminTokens.navy.withOpacity(
          OptikAdminTokens.isDark ? 0.28 : 0.07,
        ),
      ),
      child: Row(
        children: [
          for (final h in widget.headers)
            SizedBox(
              width: widget.colWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Text(
                  h.text.trim().isEmpty ? '—' : h.text.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: OptikAdminTokens.navy,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(int r) {
    final row = widget.cells[r];
    return Container(
      color: r.isOdd
          ? OptikAdminTokens.ice.withOpacity(
              OptikAdminTokens.isDark ? 0.06 : 0.28,
            )
          : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.headers.length; i++)
            SizedBox(
              width: widget.colWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: i < row.length
                    ? TextField(
                        key: ValueKey('ocr-cell-$r-$i'),
                        controller: row[i],
                        minLines: 1,
                        maxLines: widget.expand ? 10 : 5,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                        ),
                      )
                    : const SizedBox(height: 40),
              ),
            ),
        ],
      ),
    );
  }
}

class _OcrTableFullscreenPage extends StatefulWidget {
  const _OcrTableFullscreenPage({
    required this.headers,
    required this.cells,
    required this.onAddRow,
    required this.onCopy,
  });

  final List<TextEditingController> headers;
  final List<List<TextEditingController>> cells;
  final VoidCallback onAddRow;
  final VoidCallback onCopy;

  @override
  State<_OcrTableFullscreenPage> createState() =>
      _OcrTableFullscreenPageState();
}

class _OcrTableFullscreenPageState extends State<_OcrTableFullscreenPage> {
  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'ocr_fullscreen'.tr(),
        subtitle: 'ocr_slide_hint'.tr(),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            tooltip: 'ocr_copy_table'.tr(),
            onPressed: widget.onCopy,
            icon: Icon(Icons.copy_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      body: Column(
        children: [
          Expanded(
            child: _OcrScrollTable(
              headers: widget.headers,
              cells: widget.cells,
              colWidth: 220,
              expand: true,
              onAddRow: () {
                widget.onAddRow();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 12),
          PremiumPrimaryButton(
            label: 'ocr_copy_table'.tr(),
            icon: Icons.copy_rounded,
            onPressed: widget.onCopy,
          ),
        ],
      ),
    );
  }
}
