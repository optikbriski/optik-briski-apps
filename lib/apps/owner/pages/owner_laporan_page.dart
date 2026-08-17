import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_session.dart';
import '../owner_ui.dart';

enum _LaporanGranularity { harian, bulanan, tahunan }

/// Owner read-only Laporan + Finance ledger (tracking only — no Catat kas).
class OwnerLaporanPage extends StatefulWidget {
  const OwnerLaporanPage({super.key});

  @override
  State<OwnerLaporanPage> createState() => _OwnerLaporanPageState();
}

class _OwnerLaporanPageState extends State<OwnerLaporanPage> {
  final _svc = OwnerService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _snapshot;
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _cabang = [];

  _LaporanGranularity _gran = _LaporanGranularity.harian;
  String? _tokoId;
  DateTime _anchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    final ids = OwnerSession.instance.tokoIds;
    _tokoId = ids.isNotEmpty ? ids.first : null;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final cabang = await _svc.listCabang();
      if (!mounted) return;
      setState(() {
        _cabang = cabang;
        if (_tokoId == null && cabang.isNotEmpty) {
          _tokoId = cabang.first['toko_id']?.toString();
        }
      });
    } catch (_) {}
    await _load();
  }

  String get _anchorDate {
    final d = _anchor;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  String get _periodeYm {
    final m = _anchor.month.toString().padLeft(2, '0');
    return '${_anchor.year}-$m';
  }

  Future<void> _load() async {
    final toko = _tokoId;
    if (toko == null || toko.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Belum ada cabang di scope Owner.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> report;
      DateTime from;
      DateTime to;
      switch (_gran) {
        case _LaporanGranularity.harian:
          report = await _svc.laporanHarian(tokoId: toko, date: _anchorDate);
          from = DateTime(_anchor.year, _anchor.month, _anchor.day);
          to = from;
          break;
        case _LaporanGranularity.bulanan:
          report = await _svc.laporanBulanan(tokoId: toko, periodeYm: _periodeYm);
          from = DateTime(_anchor.year, _anchor.month, 1);
          to = DateTime(_anchor.year, _anchor.month + 1, 0);
          break;
        case _LaporanGranularity.tahunan:
          report = await _svc.laporanTahunan(tokoId: toko, year: _anchor.year);
          from = DateTime(_anchor.year, 1, 1);
          to = DateTime(_anchor.year, 12, 31);
          break;
      }

      final fromStr =
          '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
      final toStr =
          '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';

      final snap = await _svc.financeSnapshot(
        tokoId: toko,
        from: fromStr,
        to: toStr,
      );
      final ledger = await _svc.listFinanceLedger(
        tokoId: toko,
        from: fromStr,
        to: toStr,
        limit: 80,
      );

      if (!mounted) return;
      setState(() {
        _report = report;
        _snapshot = snap;
        _ledger = ledger;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  num _n(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> get _series {
    final raw = _report?['series'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _pickDate() async {
    if (_gran == _LaporanGranularity.tahunan) {
      final years = List.generate(6, (i) => DateTime.now().year - i);
      final picked = await showModalBottomSheet<int>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text('Pilih tahun', style: OwnerUi.display(20)),
              for (final y in years)
                ListTile(
                  title: Text('$y'),
                  onTap: () => Navigator.pop(ctx, y),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      setState(() => _anchor = DateTime(picked, _anchor.month, 1));
      await _load();
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: _gran == _LaporanGranularity.bulanan ? 'Pilih bulan' : 'Pilih tanggal',
    );
    if (picked == null) return;
    setState(() => _anchor = picked);
    await _load();
  }

  String get _periodLabel {
    switch (_gran) {
      case _LaporanGranularity.harian:
        return _anchorDate;
      case _LaporanGranularity.bulanan:
        return _periodeYm;
      case _LaporanGranularity.tahunan:
        return '${_anchor.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokoIds = _cabang.isNotEmpty
        ? _cabang.map((e) => '${e['toko_id']}').toList()
        : OwnerSession.instance.tokoIds;

    return OwnerPageFrame(
      title: 'Laporan',
      subtitle: 'Tracking only · mirror Buku Besar',
      onRefresh: _load,
      actions: [
        if (tokoIds.length > 1)
          PopupMenuButton<String>(
            tooltip: 'Cabang',
            initialValue: _tokoId,
            onSelected: (v) {
              setState(() => _tokoId = v);
              _load();
            },
            itemBuilder: (_) => [
              for (final t in tokoIds)
                PopupMenuItem(value: t, child: Text(t)),
            ],
            child: Container(
              margin: const EdgeInsets.only(right: 4, top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OptikAdminTokens.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: const Icon(Icons.storefront_rounded, size: 18, color: OptikAdminTokens.navy),
            ),
          ),
        IconButton(
          tooltip: 'Pilih periode',
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month_rounded, color: OptikAdminTokens.navy),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy))
          : _error != null
              ? OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    _GranularitySwitch(
                      value: _gran,
                      onChanged: (g) {
                        setState(() => _gran = g);
                        _load();
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      decoration: OwnerUi.hero(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _periodLabel,
                                style: OwnerUi.label(color: OptikAdminTokens.ice),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _tokoId ?? '-',
                                  style: OwnerUi.label(color: OptikAdminTokens.snow),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Omzet',
                            style: OwnerUi.label(color: OptikAdminTokens.ice.withOpacity(0.9)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            OwnerService.formatRp(_report?['omzet']),
                            style: OwnerUi.display(34, color: OptikAdminTokens.snow),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.12)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _HeroMini(
                                    label: 'Laba',
                                    value: OwnerService.formatRp(
                                      _report?['laba'] ?? _report?['laba_bersih_est'],
                                    ),
                                    negative: _n(_report?['laba'] ?? _report?['laba_bersih_est']) < 0,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 36,
                                  color: Colors.white.withOpacity(0.18),
                                ),
                                Expanded(
                                  child: _HeroMini(
                                    label: 'Invoice',
                                    value: '${_report?['invoice_count'] ?? 0}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const OwnerSectionLabel('Breakdown'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      decoration: OwnerUi.panel(),
                      child: Column(
                        children: [
                          _Row('HPP', _n(_report?['hpp'])),
                          _Row('Opex / hutang', _n(_report?['opex'])),
                          if (_gran != _LaporanGranularity.harian)
                            _Row('Gaji (est.)', _n(_report?['gaji'])),
                          _Row('Pemasukan kas', _n(_report?['pemasukan'])),
                          if (_gran == _LaporanGranularity.harian) ...[
                            _Row('Kas in', _n(_report?['kas_in'])),
                            _Row('Kas out', _n(_report?['kas_out']), last: true),
                          ] else
                            _Row(
                              'Bagi 50/50 est.',
                              _n(_report?['bagi_utama_est']),
                              last: true,
                            ),
                        ],
                      ),
                    ),
                    if (_series.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      OwnerSectionLabel(
                        _gran == _LaporanGranularity.tahunan ? 'Per bulan' : 'Per hari (aktif)',
                      ),
                      for (final s in _series.take(31))
                        OwnerListCard(
                          accent: _n(s['laba']) < 0
                              ? OptikAdminTokens.danger
                              : OptikAdminTokens.success,
                          title:
                              '${s['bucket'] ?? s['label']} · ${OwnerService.formatRp(s['omzet'])}',
                          subtitle:
                              'Laba ${OwnerService.formatRp(s['laba'])} · Inv ${s['invoice_count'] ?? 0}'
                              '${_n(s['opex']) > 0 ? ' · Opex ${OwnerService.formatRp(s['opex'])}' : ''}',
                        ),
                    ],
                    const SizedBox(height: 18),
                    const OwnerSectionLabel('Finance ledger'),
                    if (_snapshot != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: OwnerUi.panel(elevated: true),
                        child: Row(
                          children: [
                            Expanded(
                              child: _SnapCell('Kas in', _n(_snapshot?['kas_in'])),
                            ),
                            Expanded(
                              child: _SnapCell('Kas out', _n(_snapshot?['kas_out'])),
                            ),
                            Expanded(
                              child: _SnapCell(
                                'Pending',
                                _n(_snapshot?['pending_count']),
                                asMoney: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_ledger.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: OwnerUi.panel(),
                        child: Text(
                          'Tidak ada transaksi di periode ini. (Read-only — tidak ada Catat kas.)',
                          style: OwnerUi.label(),
                        ),
                      )
                    else
                      for (final tx in _ledger)
                        OwnerListCard(
                          accent: _ledgerAccent(tx),
                          title:
                              '${tx['jenis_transaksi'] ?? '-'} · ${OwnerService.formatRp(tx['nominal'])}',
                          subtitle:
                              '${tx['tanggal_transaksi'] ?? '-'} · ${tx['status_konfirmasi'] ?? '-'}\n'
                              '${tx['kategori'] ?? tx['deskripsi'] ?? '-'}',
                        ),
                  ],
                ),
    );
  }

  Color _ledgerAccent(Map<String, dynamic> tx) {
    final jenis = '${tx['jenis_transaksi'] ?? ''}'.toUpperCase();
    final st = '${tx['status_konfirmasi'] ?? ''}'.toUpperCase();
    if (st == 'PENDING' || st == 'MENUNGGU') return OptikAdminTokens.warning;
    if (jenis == 'PEMASUKAN' || jenis == 'PIUTANG') return OptikAdminTokens.success;
    return OptikAdminTokens.danger;
  }
}

class _GranularitySwitch extends StatelessWidget {
  const _GranularitySwitch({required this.value, required this.onChanged});
  final _LaporanGranularity value;
  final ValueChanged<_LaporanGranularity> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(_LaporanGranularity g, String label) {
      final selected = value == g;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(g),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? OptikAdminTokens.navy : OptikAdminTokens.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? OptikAdminTokens.navy : OptikAdminTokens.line,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: OwnerUi.label(
                color: selected ? OptikAdminTokens.snow : OptikAdminTokens.navy,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_LaporanGranularity.harian, 'Harian'),
        const SizedBox(width: 8),
        chip(_LaporanGranularity.bulanan, 'Bulanan'),
        const SizedBox(width: 8),
        chip(_LaporanGranularity.tahunan, 'Tahunan'),
      ],
    );
  }
}

class _HeroMini extends StatelessWidget {
  const _HeroMini({
    required this.label,
    required this.value,
    this.negative = false,
  });

  final String label;
  final String value;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: OwnerUi.label(color: OptikAdminTokens.ice.withOpacity(0.85))),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OwnerUi.display(
              18,
              color: negative ? const Color(0xFFFFB4B4) : OptikAdminTokens.snow,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.last = false});
  final String label;
  final num value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: OptikAdminTokens.line)),
      ),
      child: Row(
        children: [
          Text(label, style: OwnerUi.body(weight: FontWeight.w600)),
          const Spacer(),
          Text(
            OwnerService.formatRp(value),
            style: OwnerUi.body(
              color: OptikAdminTokens.navy,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapCell extends StatelessWidget {
  const _SnapCell(this.label, this.value, {this.asMoney = true});
  final String label;
  final num value;
  final bool asMoney;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: OwnerUi.label()),
        const SizedBox(height: 4),
        Text(
          asMoney ? OwnerService.formatRp(value) : value.round().toString(),
          style: OwnerUi.body(
            color: OptikAdminTokens.navy,
            weight: FontWeight.w800,
            size: 13,
          ),
        ),
      ],
    );
  }
}
