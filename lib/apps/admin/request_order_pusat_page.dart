import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/logistics/kurir_pick_dialog.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/logistics/request_order_rules.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/responsive.dart';
import '../../shared/widgets/premium_date_range_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Board pipeline Request Order untuk Admin Pusat.
/// Tabs: Approval → Disiapkan → Perjalanan → Histori
class RequestOrderPusatPage extends StatefulWidget {
  const RequestOrderPusatPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<RequestOrderPusatPage> createState() => _RequestOrderPusatPageState();
}

class _RequestOrderPusatPageState extends State<RequestOrderPusatPage>
    with SingleTickerProviderStateMixin {
  final _svc = RequestOrderService();
  final _dtFmt = DateFormat('d MMM yyyy HH:mm', 'id_ID');
  final _dayFmt = DateFormat('d MMM yyyy', 'id_ID');
  late final TabController _tabs;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pipeline = [];
  List<Map<String, dynamic>> _history = [];
  final Map<int, ({int stock, int reserved, int available})> _snap = {};

  /// Filter Histori: tanggal (opsional) + multi toko.
  /// Tab lain: hanya multi toko (maks. 5).
  late DateTime _histStart;
  late DateTime _histEnd;
  String _histPresetId = 'last7';
  bool _histUseDate = true;
  final List<String> _filterTokoIds = [];
  List<Map<String, dynamic>> _tokoOptions = [];
  static const _maxFilterToko = 5;

  static const _bg = OptikAdminTokens.bg;
  static const _panel = OptikAdminTokens.panel;
  static const _panelSoft = OptikAdminTokens.panel;
  static const _line = OptikAdminTokens.cardElevated;

  static const _tabLabels = ['Approval', 'Disiapkan', 'Perjalanan', 'Histori'];
  static const _tabHints = [
    'Menunggu keputusan Pusat',
    'Reservasi aktif — siapkan barang',
    'Dalam perjalanan · cabang terima di Verifikasi Terima',
    'Selesai diterima atau ditolak',
  ];
  static const _tabIcons = [
    Icons.fact_check_outlined,
    Icons.inventory_2_outlined,
    Icons.local_shipping_outlined,
    Icons.history_rounded,
  ];
  static const _tabColors = [
    OptikAdminTokens.ice,
    OptikAdminTokens.warning,
    OptikAdminTokens.ice,
    OptikAdminTokens.textMuted,
  ];

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String get _histTriggerLabel {
    if (!_histUseDate) return 'Semua tanggal';
    final range = '${_dayFmt.format(_histStart)} – ${_dayFmt.format(_histEnd)}';
    const labels = {
      'last7': '7 hari terakhir',
      'last30': '30 hari terakhir',
      'last60': '60 hari terakhir',
      'last90': '90 hari terakhir',
      'thisMonth': 'Bulan ini',
      'lastMonth': 'Bulan lalu',
      'lastYear': 'Tahun lalu',
    };
    final name = labels[_histPresetId];
    if (name != null) return '$name: $range';
    return range;
  }

  String _tokoLabel(String id) {
    for (final t in _tokoOptions) {
      if (t['id']?.toString() == id) {
        final nama = t['toko_id']?.toString() ?? '';
        if (nama.isNotEmpty && nama != id) return '$nama ($id)';
        return id;
      }
    }
    return id;
  }

  @override
  void initState() {
    super.initState();
    final now = _dateOnly(DateTime.now());
    _histEnd = now;
    _histStart = now.subtract(const Duration(days: 6));
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!RequestOrderRules.bolehProsesPusat(widget.profile)) {
      setState(() {
        _loading = false;
        _error = 'Hanya gudang Pusat yang boleh proses Request Order.';
        _pipeline = [];
        _history = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        await _svc.migrateLegacyApproved();
      } catch (_) {}

      _pipeline = await _svc.listByStatuses([
        'PENDING',
        'SENT_TO_HQ',
        'APPROVED',
        'PREPARING',
        'SHIPPING',
      ]);
      if (_tokoOptions.isEmpty) {
        try {
          _tokoOptions = await _svc.listTokoOptions();
        } catch (_) {
          _tokoOptions = [];
        }
      }

      _history = await _svc.listHistory(
        from: _histUseDate ? _histStart : null,
        to: _histUseDate ? _histEnd : null,
        tokoIds:
            _filterTokoIds.isEmpty ? null : List<String>.from(_filterTokoIds),
      );
      if (_histUseDate) {
        _history = _history.where(_inHistRange).toList();
      }
      if (_filterTokoIds.isNotEmpty) {
        final set = _filterTokoIds.toSet();
        _history = _history
            .where((r) => set.contains(r['toko_id']?.toString()))
            .toList();
      }
      _snap.clear();

      final open = _pipeline.where((r) {
        final s = (r['status'] ?? '').toString().toUpperCase();
        return s == 'PENDING' ||
            s == 'SENT_TO_HQ' ||
            s == 'APPROVED' ||
            s == 'PREPARING';
      }).toList();

      // Parallel snapshot — hindari N+1 lambat di antrian besar.
      final snaps = await Future.wait(open.map((r) async {
        final id = RequestOrderService.requestIdOf(r);
        if (id == null) return null;
        final snap = await _svc.stockSnapshot(
          sku: r['sku']?.toString(),
          namaProduk: r['nama_produk']?.toString(),
          excludeRequestId: id,
        );
        final own = RequestOrderRules.qtyOf(r['reserved_qty']);
        final status = (r['status'] ?? '').toString().toUpperCase();
        final reservedShown = (status == 'APPROVED' || status == 'PREPARING')
            ? snap.reserved + own
            : snap.reserved;
        final availableForThis = status == 'APPROVED' || status == 'PREPARING'
            ? snap.stock - reservedShown
            : snap.available;
        return MapEntry(id, (
          stock: snap.stock,
          reserved: reservedShown < 0 ? 0 : reservedShown,
          available: availableForThis < 0 ? 0 : availableForThis,
        ));
      }));
      for (final e in snaps) {
        if (e != null) _snap[e.key] = e.value;
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _inHistRange(Map<String, dynamic> r) {
    final raw = (r['reviewed_at'] ?? r['created_at'])?.toString();
    final d = DateTime.tryParse(raw ?? '');
    if (d == null) return false;
    final local = d.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final start = _dateOnly(_histStart);
    final end = _dateOnly(_histEnd);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  Future<void> _openHistRangePicker() async {
    final result = await showPremiumDateRangePicker(
      context: context,
      initialStart: _histStart,
      initialEnd: _histEnd,
      initialPresetId: _histUseDate ? _histPresetId : 'custom',
    );
    if (result == null) return;
    setState(() {
      _histUseDate = true;
      _histStart = _dateOnly(result.start);
      _histEnd = _dateOnly(result.end);
      _histPresetId = result.presetId;
    });
    await _load();
  }

  Future<void> _openTokoPicker() async {
    if (_tokoOptions.isEmpty) {
      try {
        _tokoOptions = await _svc.listTokoOptions();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal muat daftar toko: $e')),
        );
        return;
      }
    }

    if (!mounted) return;

    final options = _tokoOptions
        .map((t) {
          final id = t['id']?.toString() ?? '';
          return AdminPickerOption<String>(
            value: id,
            label: _tokoLabel(id),
            subtitle: 'Kode: $id',
            icon: Icons.storefront_rounded,
          );
        })
        .toList();

    final result = await showAdminMultiPicker<String>(
      context: context,
      title: 'Pilih toko (maks. 5)',
      options: options,
      selected: _filterTokoIds.toSet(),
      maxSelect: _maxFilterToko,
      searchHint: 'Cari nama / kode toko…',
    );

    if (result == null) return;
    setState(() {
      _filterTokoIds
        ..clear()
        ..addAll(result);
    });
    await _load();
  }

  List<Map<String, dynamic>> _applyTokoFilter(List<Map<String, dynamic>> rows) {
    if (_filterTokoIds.isEmpty) return rows;
    final set = _filterTokoIds.toSet();
    return rows
        .where((r) => set.contains(r['toko_id']?.toString()))
        .toList();
  }

  List<Map<String, dynamic>> _forTab(int i) {
    List<Map<String, dynamic>> rows;
    switch (i) {
      case 0:
        rows = _pipeline
            .where((r) {
              final s = (r['status'] ?? '').toString().toUpperCase();
              return s == 'SENT_TO_HQ' || s == 'PENDING';
            })
            .toList();
        break;
      case 1:
        rows = _pipeline
            .where((r) {
              final s = (r['status'] ?? '').toString().toUpperCase();
              return s == 'PREPARING' || s == 'APPROVED';
            })
            .toList();
        break;
      case 2:
        rows = _pipeline
            .where((r) =>
                (r['status'] ?? '').toString().toUpperCase() == 'SHIPPING')
            .toList();
        break;
      default:
        rows = List<Map<String, dynamic>>.from(_history);
        rows.sort((a, b) {
          final ra = (a['reviewed_at'] ?? a['created_at'] ?? '').toString();
          final rb = (b['reviewed_at'] ?? b['created_at'] ?? '').toString();
          return rb.compareTo(ra);
        });
        return _applyTokoFilter(rows);
    }

    rows = _applyTokoFilter(rows);
    rows.sort((a, b) {
      final t = (a['toko_id'] ?? '')
          .toString()
          .compareTo((b['toko_id'] ?? '').toString());
      if (t != 0) return t;
      return (a['created_at'] ?? '')
          .toString()
          .compareTo((b['created_at'] ?? '').toString());
    });
    return rows;
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(okMsg),
          backgroundColor: OptikAdminTokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Gagal: $e\nPaste seal 000045 (list_request_orders) jika belum.'),
          backgroundColor: OptikAdminTokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmReject(Map<String, dynamic> req) async {
    if (!RequestOrderRules.bolehTolak(
      profile: widget.profile,
      status: req['status']?.toString(),
    )) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tolak request?',
            style: TextStyle(color: OptikAdminTokens.navy, fontWeight: FontWeight.w700)),
        content: Text(
          '${req['nama_produk']} • ${req['qty_request']} pcs\n'
          'Cabang: ${RequestOrderService.tokoLabel(req['toko_id']?.toString())}\n\n'
          'Akan masuk Histori sebagai ditolak.',
          style: const TextStyle(color: OptikAdminTokens.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OptikAdminTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _svc.reject(req), 'Request ditolak → Histori.');
    }
  }

  Future<void> _confirmShip(Map<String, dynamic> req) async {
    if (!RequestOrderRules.bolehKirim(
      profile: widget.profile,
      status: req['status']?.toString(),
    )) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Kirim ke cabang?',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: R.constrainedDialog(
          context: context,
          preferWidth: 400,
          child: Text(
            'Stok Pusat dipotong ${req['qty_request']} pcs.\n'
            'Surat jalan TRANSIT ke ${RequestOrderService.tokoLabel(req['toko_id']?.toString())}.\n'
            'Reservasi RO dilepas. Cabang terima di Verifikasi Terima.',
            style: const TextStyle(
              color: OptikAdminTokens.textSecondary,
              height: 1.4,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OptikAdminTokens.navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kirim sekarang'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final kurirPick = await showKurirPickDialog(
      context,
      service: LogisticsTrackingService(),
      pusatOnly: true,
      title: 'Pilih kurir RO (opsional)',
    );
    if (kurirPickCancelled(kurirPick) || !mounted) return;
    try {
      final resi = await _svc.ship(
        req,
        kurirKaryawanId: kurirPickSkipped(kurirPick)
            ? null
            : kurirPick!['id']?.toString(),
        kurirNama: kurirPickSkipped(kurirPick)
            ? null
            : kurirPick!['nama']?.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil dikirim · Resi $resi'),
          backgroundColor: OptikAdminTokens.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim: $e'),
          backgroundColor: OptikAdminTokens.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _fmtWhen(dynamic v) {
    if (v == null) return '-';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return v.toString();
    return _dtFmt.format(d.toLocal());
  }

  String _historyOutcome(Map<String, dynamic> req) {
    final s = (req['status'] ?? '').toString().toUpperCase();
    if (s == 'SUCCESS') {
      return 'Cabang sudah terima'
          '${req['stock_move_resi'] != null ? ' • ${req['stock_move_resi']}' : ''}';
    }
    if (s == 'REJECTED') return 'Ditolak dari pipeline';
    return RequestOrderService.labelStatus(s);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED':
      case 'PREPARING':
        return OptikAdminTokens.warning;
      case 'SHIPPING':
        return OptikAdminTokens.ice;
      case 'SUCCESS':
        return OptikAdminTokens.success;
      case 'REJECTED':
        return OptikAdminTokens.danger;
      case 'SENT_TO_HQ':
      case 'PENDING':
        return OptikAdminTokens.ice;
      default:
        return OptikAdminTokens.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _tabs.index;

    return PremiumScaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(),
            if (!_loading && _error == null) ...[
              _pipelineSummary(),
              _stageHeader(idx),
            ],
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: OptikAdminTokens.ice))
                  : _error != null
                      ? _errorState()
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            for (var i = 0; i < _tabLabels.length; i++)
                              _buildList(_forTab(i), tabIndex: i),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: OptikAdminTokens.navy),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request Order',
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Gudang Pusat • pipeline logistik',
                  style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _load,
            style: IconButton.styleFrom(
              backgroundColor: _panel,
              side: const BorderSide(color: _line),
            ),
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.textSecondary, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _pipelineSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: PremiumPanel(
        padding: const EdgeInsets.all(10),
        borderRadius: 20,
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 520;
            final tiles = List.generate(_tabLabels.length, (i) {
              final count = _forTab(i).length;
              final active = _tabs.index == i;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  child: Material(
                    color: active
                        ? _tabColors[i].withOpacity(0.14)
                        : _panelSoft,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _tabs.animateTo(i),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: narrow ? 10 : 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active
                                ? _tabColors[i].withOpacity(0.55)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(_tabIcons[i],
                                size: 18,
                                color: active
                                    ? _tabColors[i]
                                    : OptikAdminTokens.textMuted),
                            const SizedBox(height: 6),
                            Text(
                              '$count',
                              style: TextStyle(
                                color: active
                                    ? OptikAdminTokens.navy
                                    : OptikAdminTokens.textSecondary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _tabLabels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? _tabColors[i]
                                    : OptikAdminTokens.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            });
            return Row(children: tiles);
          },
        ),
      ),
    );
  }

  Widget _stageHeader(int idx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: _tabColors[idx],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tabLabels[idx],
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  idx == 3
                      ? [
                          if (_histUseDate)
                            '${_dayFmt.format(_histStart)} → ${_dayFmt.format(_histEnd)}'
                          else
                            'Semua tanggal',
                          if (_filterTokoIds.isNotEmpty)
                            '${_filterTokoIds.length} toko',
                        ].join(' • ')
                      : _filterTokoIds.isEmpty
                          ? _tabHints[idx]
                          : '${_tabHints[idx]} • ${_filterTokoIds.length} toko',
                  style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return PremiumEmptyState(
      message: _error ?? 'Terjadi kesalahan',
      icon: Icons.error_outline_rounded,
      action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
    );
  }

  Widget _emptyState(int tabIndex) {
    return PremiumEmptyState(
      message: tabIndex == 3
          ? 'Tidak ada histori di rentang ini. Coba ubah tanggal dan/atau filter toko.'
          : 'Antrian ${_tabLabels[tabIndex]} kosong. ${_tabHints[tabIndex]}',
      icon: _tabIcons[tabIndex],
    );
  }

  Widget _buildList(List<Map<String, dynamic>> rows, {required int tabIndex}) {
    final isHistory = tabIndex == 3;
    final children = <Widget>[
      if (isHistory) _historyFilterBar() else _tokoOnlyFilterBar(),
      const SizedBox(height: 8),
    ];

    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (isHistory) _historyFilterBar() else _tokoOnlyFilterBar(),
          const SizedBox(height: 24),
          SizedBox(height: 280, child: _emptyState(tabIndex)),
        ],
      );
    }

    String? lastToko;
    for (final req in rows) {
      if (!isHistory) {
        final toko = req['toko_id']?.toString() ?? '-';
        if (toko != lastToko) {
          lastToko = toko;
          final count =
              rows.where((r) => r['toko_id']?.toString() == toko).length;
          children.add(_tokoHeader(toko, count));
        }
      }
      children.add(
        isHistory ? _historyCard(req) : _orderCard(req, tabIndex: tabIndex),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: children,
    );
  }

  Widget _tokoOnlyFilterBar() {
    return PremiumPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PremiumSectionHeader(
            label: 'Filter toko',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 4),
          const Text(
            'Kosong = semua toko. Pilih hingga 5 toko untuk mempersempit antrian.',
            style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          _tokoPickerChip(),
          if (_filterTokoIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            _selectedTokoChips(),
          ],
        ],
      ),
    );
  }

  Widget _historyFilterBar() {
    return PremiumPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PremiumSectionHeader(
            label: 'Filter histori',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: OptikAdminTokens.spaceMd),
          const Text(
            'Tanggal saja = semua toko. Toko saja = semua tanggal. '
            'Keduanya = order toko terpilih di rentang tanggal. Maks. 5 toko.',
            style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: OptikAdminTokens.spaceSm),
          PremiumDateRangeTrigger(
            label: _histTriggerLabel,
            onTap: _openHistRangePicker,
          ),
          const SizedBox(height: OptikAdminTokens.spaceMd),
          AdminPickerField(
            label: 'Rentang tanggal',
            valueText:
                _histUseDate ? 'Pakai tanggal' : 'Semua tanggal',
            icon: Icons.date_range_rounded,
            onTap: () async {
              final sel = await showAdminPicker<bool>(
                context: context,
                title: 'Filter tanggal histori',
                searchable: false,
                selected: _histUseDate,
                headerIcon: Icons.date_range_rounded,
                options: const [
                  AdminPickerOption(
                    value: true,
                    label: 'Pakai tanggal',
                    subtitle: 'Filter order menurut rentang tanggal',
                    icon: Icons.event_available_rounded,
                  ),
                  AdminPickerOption(
                    value: false,
                    label: 'Semua tanggal',
                    subtitle: 'Tampilkan semua tanggal',
                    icon: Icons.event_busy_rounded,
                  ),
                ],
              );
              if (sel == null || sel.isClear) return;
              setState(() => _histUseDate = sel.value!);
              await _load();
            },
          ),
          const SizedBox(height: OptikAdminTokens.spaceMd),
          _tokoPickerChip(),
          if (_filterTokoIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            _selectedTokoChips(),
          ],
          const SizedBox(height: 8),
          Text(
            _histSummaryCount,
            style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _tokoPickerChip() {
    return AdminPickerField(
      label: 'Filter toko',
      valueText: _filterTokoIds.isEmpty
          ? 'Cari / pilih toko'
          : '${_filterTokoIds.length} toko dipilih',
      hint: 'Cari / pilih toko',
      icon: Icons.storefront_rounded,
      onTap: _openTokoPicker,
    );
  }

  Widget _selectedTokoChips() {
    return Column(
      children: [
        for (final id in _filterTokoIds)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  setState(() => _filterTokoIds.remove(id));
                  await _load();
                },
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: OptikAdminTokens.snow,
                    border: Border.all(color: OptikAdminTokens.ice),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_rounded,
                          size: 18, color: OptikAdminTokens.navy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _tokoLabel(id),
                          style: const TextStyle(
                            fontSize: 13,
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.close_rounded,
                          size: 18, color: OptikAdminTokens.slate),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _histSummaryCount {
    final parts = <String>['${_history.length} order'];
    if (_histUseDate) {
      parts.add('di rentang tanggal');
    } else {
      parts.add('semua tanggal');
    }
    if (_filterTokoIds.isEmpty) {
      parts.add('• semua toko');
    } else {
      parts.add('• ${_filterTokoIds.length} toko');
    }
    return parts.join(' ');
  }

  Widget _tokoHeader(String toko, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: OptikAdminTokens.cardElevated.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: OptikAdminTokens.textSecondary, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              RequestOrderService.tokoLabel(toko),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Text(
            '$count item',
            style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> req, {required int tabIndex}) {
    final id = RequestOrderService.requestIdOf(req);
    final snap = id == null ? null : _snap[id];
    final status = (req['status'] ?? '').toString().toUpperCase();
    final color = _statusColor(status);
    final qty = req['qty_request'];
    final canApprove = tabIndex == 0 &&
        RequestOrderRules.bolehApprove(
          profile: widget.profile,
          status: status,
        );
    final canShip = tabIndex == 1 &&
        RequestOrderRules.bolehKirim(
          profile: widget.profile,
          status: status,
        );
    final showReject = RequestOrderRules.bolehTolak(
      profile: widget.profile,
      status: status,
    );
    final availLow = snap != null &&
        canApprove &&
        snap.available < RequestOrderRules.qtyOf(req['qty_request']);

    return PremiumPanel(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      margin: const EdgeInsets.only(bottom: 10),
      borderColor: availLow
          ? OptikAdminTokens.warning.withOpacity(0.45)
          : OptikAdminTokens.lineStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              color: _panelSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    RequestOrderService.labelStatus(status),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Text(
                  '#$id',
                  style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 11),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req['nama_produk']?.toString() ?? '-',
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: OptikAdminTokens.spaceSm),
                PremiumChipWrap(
                  children: [
                    _metaPill(Icons.numbers_rounded, '$qty pcs'),
                    if (req['sku'] != null)
                      _metaPill(Icons.qr_code_2_rounded, '${req['sku']}'),
                    _metaPill(Icons.receipt_long_outlined,
                        '${req['no_invoice'] ?? '-'}'),
                    _metaPill(Icons.person_outline_rounded,
                        '${req['nama_pelanggan'] ?? '-'}'),
                  ],
                ),
                if (snap != null) ...[
                  const SizedBox(height: 12),
                  _stockRow(snap, highlightLow: availLow),
                ],
                if (req['stock_move_resi'] != null) ...[
                  const SizedBox(height: 10),
                  _resiRow('${req['stock_move_resi']}'),
                ],
                if (tabIndex == 2) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Menunggu cabang konfirmasi terima di Verifikasi Terima.',
                    style: TextStyle(
                        color: OptikAdminTokens.textMuted, fontSize: 12, height: 1.35),
                  ),
                ],
                if (canApprove || canShip || showReject) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: _line),
                  const SizedBox(height: 12),
                  _actions(
                    canApprove: canApprove,
                    canShip: canShip,
                    showReject: showReject,
                    req: req,
                    snap: snap,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line.withOpacity(0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: OptikAdminTokens.textMuted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockRow(
    ({int stock, int reserved, int available}) snap, {
    bool highlightLow = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlightLow
              ? OptikAdminTokens.warning.withOpacity(0.4)
              : _line.withOpacity(0.7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stockCell(
                'Stok fisik', '${snap.stock}', OptikAdminTokens.navy),
          ),
          _vDivider(),
          Expanded(
            child: _stockCell(
                'Booking', '${snap.reserved}', OptikAdminTokens.warning),
          ),
          _vDivider(),
          Expanded(
            child: _stockCell(
              'Tersedia',
              '${snap.available}',
              highlightLow
                  ? OptikAdminTokens.danger
                  : OptikAdminTokens.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 28,
        color: _line.withOpacity(0.8),
      );

  Widget _stockCell(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _resiRow(String resi) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: OptikAdminTokens.accentSoft.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OptikAdminTokens.accentSoft.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined,
              size: 15, color: OptikAdminTokens.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Resi $resi',
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions({
    required bool canApprove,
    required bool canShip,
    required bool showReject,
    required Map<String, dynamic> req,
    required ({int stock, int reserved, int available})? snap,
  }) {
    final narrow = R.isNarrow(context);
    final buttons = <Widget>[
      if (canApprove)
        _primaryAction(
          label: 'Setujui → Disiapkan',
          icon: Icons.check_circle_outline,
          color: OptikAdminTokens.slate,
          onTap: () {
            final q = RequestOrderRules.qtyOf(req['qty_request']);
            final avail = snap?.available ?? 0;
            if (avail < q) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Stok tersedia $avail < minta $q. Tidak bisa setujui.'),
                  backgroundColor: OptikAdminTokens.training,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            _run(
              () => _svc.approve(req),
              'Disetujui → Disiapkan (reservasi aktif).',
            );
          },
        ),
      if (canShip)
        _primaryAction(
          label: 'Kirim (perjalanan)',
          icon: Icons.local_shipping_rounded,
          color: OptikAdminTokens.accentDeep,
          onTap: () => _confirmShip(req),
        ),
      if (showReject)
        _secondaryAction(
          label: 'Tolak',
          icon: Icons.close_rounded,
          onTap: () => _confirmReject(req),
        ),
    ];

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buttons[i],
          ]
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: buttons[i]),
        ]
      ],
    );
  }

  Widget _primaryAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: OptikAdminTokens.snow,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _secondaryAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: OptikAdminTokens.danger,
        side: const BorderSide(color: OptikAdminTokens.danger),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _historyCard(Map<String, dynamic> req) {
    final status = (req['status'] ?? '').toString().toUpperCase();
    final color = _statusColor(status);
    final ok = status == 'SUCCESS';

    return PremiumPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      margin: const EdgeInsets.only(bottom: 10),
      borderColor: color.withOpacity(0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 13,
                        color: color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        RequestOrderService.labelStatus(status),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    req['toko_id']?.toString() ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: OptikAdminTokens.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              req['nama_produk']?.toString() ?? '-',
              style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              '${req['qty_request']} pcs'
              '${req['sku'] != null ? ' • ${req['sku']}' : ''}'
              ' • Invoice ${req['no_invoice'] ?? '-'}',
              style: const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              _historyOutcome(req),
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Dibuat ${_fmtWhen(req['created_at'])}'
              '${req['reviewed_at'] != null ? '  ·  Diproses ${_fmtWhen(req['reviewed_at'])}' : ''}',
              style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 10),
            ),
          ],
        ),
    );
  }
}
