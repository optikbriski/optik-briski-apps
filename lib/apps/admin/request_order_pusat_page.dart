import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/logistics/request_order_service.dart';
import '../../shared/responsive.dart';
import '../../shared/widgets/premium_date_range_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Board pipeline Request Order untuk Admin Pusat.
/// Tabs: Approval → Preparing → Shipping → Histori
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

  static const _bg = Color(0xFF0B1220);
  static const _panel = Color(0xFF152033);
  static const _panelSoft = Color(0xFF1A2740);
  static const _line = Color(0xFF2A3A55);

  static const _tabLabels = ['Approval', 'Preparing', 'Shipping', 'Histori'];
  static const _tabHints = [
    'Menunggu keputusan Pusat',
    'Reservasi aktif — siapkan barang',
    'Dalam perjalanan ke cabang',
    'Selesai diterima atau ditolak',
  ];
  static const _tabIcons = [
    Icons.fact_check_outlined,
    Icons.inventory_2_outlined,
    Icons.local_shipping_outlined,
    Icons.history_rounded,
  ];
  static const _tabColors = [
    Color(0xFF38BDF8),
    Color(0xFFFBBF24),
    Color(0xFF60A5FA),
    Color(0xFF94A3B8),
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
      });
      for (final r in open) {
        final id = r['id'] as int;
        final snap = await _svc.stockSnapshot(
          sku: r['sku']?.toString(),
          namaProduk: r['nama_produk']?.toString(),
          excludeRequestId: id,
        );
        final own = (r['reserved_qty'] as num?)?.toInt() ?? 0;
        final status = (r['status'] ?? '').toString().toUpperCase();
        final reservedShown = (status == 'APPROVED' || status == 'PREPARING')
            ? snap.reserved + own
            : snap.reserved;
        final availableForThis = status == 'APPROVED' || status == 'PREPARING'
            ? snap.stock - reservedShown
            : snap.available;
        _snap[id] = (
          stock: snap.stock,
          reserved: reservedShown < 0 ? 0 : reservedShown,
          available: availableForThis < 0 ? 0 : availableForThis,
        );
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
    final draft = List<String>.from(_filterTokoIds);
    var query = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final q = query.trim().toLowerCase();
            final filtered = _tokoOptions.where((t) {
              if (q.isEmpty) return true;
              final id = (t['id'] ?? '').toString().toLowerCase();
              final nama = (t['toko_id'] ?? '').toString().toLowerCase();
              return id.contains(q) || nama.contains(q);
            }).toList();

            return AlertDialog(
              backgroundColor: _panel,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Pilih toko (maks. 5)',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              content: SizedBox(
                width: R.dialogMaxWidth(context, 420),
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Cari nama / kode toko…',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white54),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _line),
                        ),
                      ),
                      onChanged: (v) => setModal(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Terpilih ${draft.length}/$_maxFilterToko',
                        style: TextStyle(
                          color: draft.length >= _maxFilterToko
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('Tidak ada toko cocok.',
                                  style: TextStyle(color: Colors.white38)))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final t = filtered[i];
                                final id = t['id']?.toString() ?? '';
                                final selected = draft.contains(id);
                                final locked = !selected &&
                                    draft.length >= _maxFilterToko;
                                return CheckboxListTile(
                                  dense: true,
                                  value: selected,
                                  activeColor: const Color(0xFF3B82F6),
                                  checkColor: Colors.white,
                                  enabled: !locked,
                                  title: Text(
                                    _tokoLabel(id),
                                    style: TextStyle(
                                      color: locked
                                          ? Colors.white30
                                          : Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text('Kode: $id',
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11)),
                                  onChanged: locked
                                      ? null
                                      : (v) {
                                          setModal(() {
                                            if (v == true) {
                                              if (draft.length <
                                                  _maxFilterToko) {
                                                draft.add(id);
                                              }
                                            } else {
                                              draft.remove(id);
                                            }
                                          });
                                        },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    draft.clear();
                    setModal(() {});
                  },
                  child: const Text('Hapus semua'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6)),
                  child: const Text('Terapkan'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _filterTokoIds
          ..clear()
          ..addAll(draft);
      });
      await _load();
    }
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
          backgroundColor: const Color(0xFF0F766E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Gagal: $e\nPastikan migration request_order_pipeline sudah dijalankan.'),
          backgroundColor: const Color(0xFFB91C1C),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmReject(Map<String, dynamic> req) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tolak request?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          '${req['nama_produk']} • ${req['qty_request']} pcs\n'
          'Cabang: ${req['toko_id']}\n\n'
          'Akan masuk Histori sebagai ditolak.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Kirim (Shipping)?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: R.constrainedDialog(
          context: context,
          preferWidth: 400,
          child: Text(
            'Stok Pusat dipotong ${req['qty_request']} pcs.\n'
            'Mutasi TRANSIT ke ${req['toko_id']}.\n'
            'Reservasi dilepas. Cabang terima via Stock Move Report.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kirim sekarang'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resi = await _svc.ship(req);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shipping sukses • Resi $resi'),
          backgroundColor: const Color(0xFF0F766E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal shipping: $e'),
          backgroundColor: const Color(0xFFB91C1C),
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
        return const Color(0xFFFBBF24);
      case 'SHIPPING':
        return const Color(0xFF60A5FA);
      case 'SUCCESS':
        return const Color(0xFF34D399);
      case 'REJECTED':
        return const Color(0xFFF87171);
      case 'SENT_TO_HQ':
      case 'PENDING':
        return const Color(0xFF38BDF8);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _tabs.index;

    return PremiumScaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            if (!_loading && _error == null) ...[
              _pipelineSummary(),
              _stageHeader(idx),
            ],
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
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
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request Order',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Gudang Pusat • pipeline logistik',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _pipelineSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
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
                                    : const Color(0xFF94A3B8)),
                            const SizedBox(height: 6),
                            Text(
                              '$count',
                              style: TextStyle(
                                color: active ? Colors.white : Colors.white70,
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
                                    : const Color(0xFF94A3B8),
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
                    color: Colors.white,
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
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 36),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFF87171), height: 1.4)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(int tabIndex) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _line),
              ),
              child: Icon(_tabIcons[tabIndex],
                  color: _tabColors[tabIndex].withOpacity(0.8), size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              tabIndex == 3
                  ? 'Tidak ada histori di rentang ini'
                  : 'Antrian ${_tabLabels[tabIndex]} kosong',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              tabIndex == 3
                  ? 'Coba ubah tanggal dan/atau filter toko.'
                  : _tabHints[tabIndex],
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), height: 1.35),
            ),
          ],
        ),
      ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filter toko',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Kosong = semua toko. Pilih hingga 5 toko untuk mempersempit antrian.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.35),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filter histori',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tanggal saja = semua toko. Toko saja = semua tanggal. '
            'Keduanya = order toko terpilih di rentang tanggal. Maks. 5 toko.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          PremiumDateRangeTrigger(
            label: _histTriggerLabel,
            onTap: _openHistRangePicker,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: _histUseDate,
                label: Text(_histUseDate ? 'Pakai tanggal' : 'Semua tanggal'),
                onSelected: (v) async {
                  setState(() => _histUseDate = v);
                  await _load();
                },
                selectedColor: const Color(0xFF3B82F6).withOpacity(0.25),
                backgroundColor: _panelSoft,
                checkmarkColor: const Color(0xFF60A5FA),
                labelStyle: TextStyle(
                  color: _histUseDate
                      ? const Color(0xFF93C5FD)
                      : const Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: _histUseDate ? const Color(0xFF3B82F6) : _line,
                ),
              ),
              _tokoPickerChip(),
            ],
          ),
          if (_filterTokoIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            _selectedTokoChips(),
          ],
          const SizedBox(height: 8),
          Text(
            _histSummaryCount,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _tokoPickerChip() {
    return ActionChip(
      avatar: const Icon(Icons.storefront_rounded,
          size: 16, color: Color(0xFF60A5FA)),
      label: Text(
        _filterTokoIds.isEmpty
            ? 'Cari / pilih toko'
            : '${_filterTokoIds.length} toko dipilih',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      onPressed: _openTokoPicker,
      backgroundColor: _panelSoft,
      side: const BorderSide(color: _line),
    );
  }

  Widget _selectedTokoChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in _filterTokoIds)
          InputChip(
            label: Text(
              _tokoLabel(id),
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
            deleteIconColor: Colors.white54,
            onDeleted: () async {
              setState(() => _filterTokoIds.remove(id));
              await _load();
            },
            backgroundColor: const Color(0xFF1E3A5F),
            side: const BorderSide(color: Color(0xFF334155)),
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
              color: const Color(0xFF334155).withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: Color(0xFFCBD5E1), size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              toko,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Text(
            '$count item',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> req, {required int tabIndex}) {
    final id = req['id'] as int;
    final snap = _snap[id];
    final status = (req['status'] ?? '').toString().toUpperCase();
    final color = _statusColor(status);
    final qty = req['qty_request'];
    final canApprove = tabIndex == 0;
    final canShip = tabIndex == 1;
    final showReject = tabIndex == 0 || tabIndex == 1;
    final availLow = snap != null &&
        canApprove &&
        snap.available < ((req['qty_request'] as num?)?.toInt() ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: availLow ? const Color(0xFFF59E0B).withOpacity(0.45) : _line,
        ),
      ),
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
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                    'Menunggu cabang konfirmasi terima di Stock Move Report.',
                    style: TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 12, height: 1.35),
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
          Icon(icon, size: 13, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
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
              ? const Color(0xFFF59E0B).withOpacity(0.4)
              : _line.withOpacity(0.7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stockCell('Stok fisik', '${snap.stock}', const Color(0xFFE2E8F0)),
          ),
          _vDivider(),
          Expanded(
            child: _stockCell(
                'Reservasi', '${snap.reserved}', const Color(0xFFFBBF24)),
          ),
          _vDivider(),
          Expanded(
            child: _stockCell(
              'Available',
              '${snap.available}',
              highlightLow
                  ? const Color(0xFFF87171)
                  : const Color(0xFF34D399),
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
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
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
        color: const Color(0xFF0EA5E9).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined,
              size: 15, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Resi $resi',
              style: const TextStyle(
                color: Color(0xFF7DD3FC),
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
          label: 'Approve → Preparing',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF0D9488),
          onTap: () {
            final q = (req['qty_request'] as num?)?.toInt() ?? 0;
            final avail = snap?.available ?? 0;
            if (avail < q) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Available $avail < minta $q. Tidak bisa approve.'),
                  backgroundColor: const Color(0xFFB45309),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            _run(
              () => _svc.approve(req),
              'Disetujui → Preparing (reservasi aktif).',
            );
          },
        ),
      if (canShip)
        _primaryAction(
          label: 'Shipping',
          icon: Icons.local_shipping_rounded,
          color: const Color(0xFF2563EB),
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
        foregroundColor: Colors.white,
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
        foregroundColor: const Color(0xFFF87171),
        side: const BorderSide(color: Color(0xFF7F1D1D)),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                        color: Color(0xFF94A3B8),
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
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              '${req['qty_request']} pcs'
              '${req['sku'] != null ? ' • ${req['sku']}' : ''}'
              ' • Invoice ${req['no_invoice'] ?? '-'}',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
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
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
