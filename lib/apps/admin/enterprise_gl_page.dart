// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/export/gl_report_pdf_service.dart';
import '../../shared/finance/gl_posting_service.dart';
import '../../shared/finance/gl_report_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Modul Akuntansi Enterprise: COA, Jurnal, Trial Balance, LR, Neraca, Aging, Periode.
class EnterpriseGlPage extends StatefulWidget {
  const EnterpriseGlPage({
    super.key,
    required this.profile,
    this.initialTokoId,
  });

  final Map<String, dynamic> profile;
  final String? initialTokoId;

  @override
  State<EnterpriseGlPage> createState() => _EnterpriseGlPageState();
}

class _EnterpriseGlPageState extends State<EnterpriseGlPage>
    with SingleTickerProviderStateMixin {
  final _reports = GlReportService();
  final _poster = GlPostingService();
  final _rp = NumberFormat.currency(
      locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  late TabController _tabs;
  bool _loading = true;
  String? _error;
  String? _tokoFilter;
  int _tahun = DateTime.now().year;
  int _bulan = DateTime.now().month;

  List<Map<String, dynamic>> _coa = [];
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _journals = [];
  List<GlAccountBalance> _trial = [];
  List<GlAccountBalance> _pl = [];
  List<GlAccountBalance> _bs = [];
  int _labaBerjalan = 0;
  List<GlAgingRow> _arRows = [];
  List<GlAgingBucket> _arBuckets = [];
  List<GlAgingRow> _apRows = [];
  List<GlAgingBucket> _apBuckets = [];
  List<GlTokoConsolidate> _consol = [];
  List<GlBudgetRow> _budgets = [];
  List<Map<String, dynamic>> _bankAccounts = [];
  List<Map<String, dynamic>> _bankLines = [];
  String? _selectedBankId;
  List<Map<String, dynamic>> _efaktur = [];

  GlAuditReport? _auditReport;
  bool _auditRunning = false;
  String? _auditError;

  bool get _isOwner =>
      (widget.profile['role']?.toString().toLowerCase() ?? '') == 'owner';

  bool get _isOwnerOrPusat {
    if (_isOwner) return true;
    final role =
        (widget.profile['role']?.toString().toLowerCase() ?? '');
    if (role == 'superadmin') return true;
    final toko =
        (widget.profile['toko_id']?.toString().toUpperCase() ?? '');
    return toko == 'PUSAT';
  }

  String get _periodLabel {
    final m = DateFormat('MMMM yyyy', 'id_ID')
        .format(DateTime(_tahun, _bulan));
    return m;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 12, vsync: this);
    _tokoFilter = widget.initialTokoId;
    if (_isOwnerOrPusat) {
      _reload();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final coa = await _reports.fetchCoa();
      final periods = await _reports.fetchPeriods();
      final journals = await _reports.fetchJournals(tokoId: _tokoFilter);
      final trial = await _reports.trialBalance(
          tokoId: _tokoFilter, tahun: _tahun, bulan: _bulan);
      final pl = await _reports.incomeStatement(
          tokoId: _tokoFilter, tahun: _tahun, bulan: _bulan);
      final bs = await _reports.balanceSheet(
          tokoId: _tokoFilter, tahun: _tahun, bulan: _bulan);
      final ar = await _reports.agingPiutang(tokoId: _tokoFilter);
      final ap = await _reports.agingHutang(tokoId: _tokoFilter);

      List<GlTokoConsolidate> consol = [];
      if (_isOwnerOrPusat) {
        try {
          consol = await _reports.consolidateByToko(
              tahun: _tahun, bulan: _bulan);
        } catch (_) {}
      }

      List<GlBudgetRow> budgets = [];
      try {
        budgets = await _reports.budgetVsActual(
            tokoId: _tokoFilter, tahun: _tahun, bulan: _bulan);
      } catch (_) {}

      List<Map<String, dynamic>> banks = [];
      List<Map<String, dynamic>> bankLines = [];
      try {
        banks = await _reports.fetchBankAccounts(tokoId: _tokoFilter);
        if (banks.isNotEmpty) {
          _selectedBankId ??= banks.first['id']?.toString();
          if (_selectedBankId != null) {
            bankLines = await _reports.fetchBankStatements(
                bankAccountId: _selectedBankId!);
          }
        }
      } catch (_) {}

      List<Map<String, dynamic>> efaktur = [];
      try {
        efaktur = await _reports.fetchEfaktur(tokoId: _tokoFilter);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _coa = coa;
        _periods = periods;
        _journals = journals;
        _trial = trial;
        _pl = pl;
        _bs = bs.rows;
        _labaBerjalan = bs.labaBerjalan;
        _arRows = ar.rows;
        _arBuckets = ar.buckets;
        _apRows = ap.rows;
        _apBuckets = ap.buckets;
        _consol = consol;
        _budgets = budgets;
        _bankAccounts = banks;
        _bankLines = bankLines;
        _efaktur = efaktur;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _fmt(int v) => _rp.format(v);

  Future<void> _pickPeriod() async {
    final years = {
      for (final p in _periods) p['tahun'] as int,
      DateTime.now().year,
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih periode',
      searchable: true,
      headerIcon: Icons.calendar_month_rounded,
      selected: '$_tahun-$_bulan',
      options: [
        for (final y in years)
          for (var m = 12; m >= 1; m--)
            AdminPickerOption(
              value: '$y-$m',
              label: DateFormat('MMMM yyyy', 'id_ID').format(DateTime(y, m)),
              subtitle: _periodStatus(y, m),
            ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    final parts = sel.value!.split('-');
    setState(() {
      _tahun = int.parse(parts[0]);
      _bulan = int.parse(parts[1]);
    });
    await _reload();
  }

  String _periodStatus(int y, int m) {
    for (final p in _periods) {
      if (p['tahun'] == y && p['bulan'] == m) {
        return p['status'] == 'CLOSED' ? 'Ditutup' : 'Terbuka';
      }
    }
    return 'Belum dibuat';
  }

  Future<void> _backfill() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text('Sinkronkan GL historis?',
            style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        content: const Text(
          'Sistem akan mem-posting ulang penjualan & transaksi kas yang belum masuk jurnal GL. Aman dijalankan berulang (idempotent).',
          style: TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sinkronkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      final res = await _poster.backfillHistoris(
        tokoId: _tokoFilter,
        createdBy: widget.profile['nama']?.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'GL: ${res.posted} diposting, ${res.skipped} dilewati, ${res.failed} gagal'),
        backgroundColor: OptikAdminTokens.navy,
      ));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal sinkron GL: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  Future<void> _closePeriod() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text('Tutup periode $_periodLabel?',
            style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        content: const Text(
          'Setelah ditutup, tidak ada jurnal baru yang bisa diposting ke bulan ini.',
          style: TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tutup periode'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _poster.closePeriod(
        tahun: _tahun,
        bulan: _bulan,
        closedBy: widget.profile['nama']?.toString(),
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Periode berhasil ditutup'),
        backgroundColor: OptikAdminTokens.navy,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal menutup periode: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  Future<void> _reopenPeriod() async {
    try {
      await _poster.reopenPeriod(tahun: _tahun, bulan: _bulan);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Periode dibuka kembali'),
        backgroundColor: OptikAdminTokens.navy,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal membuka periode: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  String get _tokoContextLabel {
    if (_tokoFilter == null || _tokoFilter!.isEmpty) {
      return _isOwnerOrPusat ? 'Semua cabang' : 'Toko aktif';
    }
    return _tokoFilter!;
  }

  Color _tipeColor(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'ASSET':
        return OptikAdminTokens.navy;
      case 'LIABILITY':
        return OptikAdminTokens.danger;
      case 'EQUITY':
        return const Color(0xFF3D5A80);
      case 'REVENUE':
        return OptikAdminTokens.success;
      case 'COGS':
        return OptikAdminTokens.warning;
      case 'EXPENSE':
        return const Color(0xFF8B6F5C);
      default:
        return OptikAdminTokens.slate;
    }
  }

  IconData _tipeIcon(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'ASSET':
        return Icons.account_balance_wallet_rounded;
      case 'LIABILITY':
        return Icons.credit_card_rounded;
      case 'EQUITY':
        return Icons.pie_chart_rounded;
      case 'REVENUE':
        return Icons.trending_up_rounded;
      case 'COGS':
        return Icons.inventory_2_rounded;
      case 'EXPENSE':
        return Icons.payments_rounded;
      default:
        return Icons.tag_rounded;
    }
  }

  String _tipeLabel(String? tipe) {
    switch ((tipe ?? '').toUpperCase()) {
      case 'ASSET':
        return 'Aset';
      case 'LIABILITY':
        return 'Kewajiban';
      case 'EQUITY':
        return 'Ekuitas';
      case 'REVENUE':
        return 'Pendapatan';
      case 'COGS':
        return 'HPP';
      case 'EXPENSE':
        return 'Beban';
      default:
        return tipe ?? '-';
    }
  }

  int _coaDepth(Map<String, dynamic> a) {
    final parent = (a['parent_kode'] ?? '').toString();
    if (parent.isEmpty) return 0;
    final grand = _coa.cast<Map<String, dynamic>?>().firstWhere(
          (x) => x!['kode']?.toString() == parent,
          orElse: () => null,
        );
    if (grand == null) return 1;
    return (grand['parent_kode']?.toString().isNotEmpty ?? false) ? 2 : 1;
  }

  Widget _periodChip() {
    return Material(
      color: OptikAdminTokens.accentSoft.withOpacity(0.65),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _pickPeriod,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month_rounded,
                  size: 15, color: OptikAdminTokens.navy),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  '$_periodLabel · $_tokoContextLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _glTabBar() {
    // Anggaran: insights (bukan celengan babi) — cocok "anggaran vs aktual".
    final tabs = <(String, IconData)>[
      ('Bagan akun', Icons.account_tree_rounded),
      ('Jurnal', Icons.menu_book_rounded),
      ('Neraca saldo', Icons.table_chart_rounded),
      ('Laba rugi', Icons.show_chart_rounded),
      ('Neraca', Icons.balance_rounded),
      ('Konsolidasi', Icons.hub_rounded),
      ('Aging', Icons.hourglass_bottom_rounded),
      ('Bank', Icons.account_balance_rounded),
      ('Anggaran', Icons.insights_rounded),
      ('e-Faktur', Icons.receipt_long_rounded),
      ('Periode', Icons.lock_clock_rounded),
      ('Audit', Icons.fact_check_rounded),
    ];
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Desktop/web lebar: sebar merata ujung ke ujung.
          final fill = constraints.maxWidth >= 960;
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: OptikAdminTokens.ice.withOpacity(0.55)),
              ),
            ),
            child: TabBar(
              controller: _tabs,
              isScrollable: !fill,
              tabAlignment: fill ? TabAlignment.fill : TabAlignment.start,
              padding: EdgeInsets.symmetric(horizontal: fill ? 4 : 8),
              labelPadding: EdgeInsets.symmetric(horizontal: fill ? 2 : 8),
              labelColor: OptikAdminTokens.navy,
              unselectedLabelColor: OptikAdminTokens.slate,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: fill ? 11 : 12,
              ),
              unselectedLabelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: fill ? 11 : 12,
              ),
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: OptikAdminTokens.accentSoft.withOpacity(0.85),
                border:
                    Border.all(color: OptikAdminTokens.ice.withOpacity(0.9)),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(999),
              tabs: [
                for (final t in tabs)
                  Tab(
                    height: 44,
                    child: fill
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(t.$2, size: 16),
                                const SizedBox(height: 2),
                                Text(t.$1, textAlign: TextAlign.center),
                              ],
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.$2, size: 15),
                              const SizedBox(width: 5),
                              Text(t.$1),
                            ],
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOwnerOrPusat) {
      return PremiumScaffold(
        appBar: const PremiumAppBar(
          title: 'General Ledger',
          centerTitle: true,
        ),
        body: PremiumEmptyState(
          message:
              'General Ledger hanya untuk Owner / Pusat.\nCabang memakai menu Keuangan & Kas.',
          icon: Icons.lock_outline_rounded,
          accent: OptikAdminTokens.warning,
          action: PremiumPrimaryButton(
            label: 'Kembali',
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
      );
    }

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'General Ledger',
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _periodChip(),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Sinkronkan GL historis',
            icon: const Icon(Icons.sync_rounded, color: OptikAdminTokens.navy),
            onPressed: _backfill,
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded,
                color: OptikAdminTokens.navy),
            onPressed: _reload,
          ),
        ],
        bottom: _glTabBar(),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : _error != null
              ? PremiumEmptyState(
                  message:
                      'Gagal memuat GL. Pastikan migrasi enterprise sudah diterapkan.\n$_error',
                  icon: Icons.error_outline_rounded,
                  accent: OptikAdminTokens.warning,
                  action: PremiumPrimaryButton(
                    label: 'Coba lagi',
                    onPressed: _reload,
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildCoaTab(),
                    _buildJournalTab(),
                    _buildTrialTab(),
                    _buildPlTab(),
                    _buildBsTab(),
                    _buildConsolTab(),
                    _buildAgingTab(),
                    _buildBankTab(),
                    _buildBudgetTab(),
                    _buildEfakturTab(),
                    _buildPeriodTab(),
                    _buildAuditTab(),
                  ],
                ),
    );
  }

  List<String> _postableCodesUnder(String rootKode) {
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final a in _coa) {
      final p = (a['parent_kode'] ?? '').toString();
      byParent.putIfAbsent(p, () => []).add(a);
    }
    final codes = <String>[];
    void walk(String parent) {
      for (final a in byParent[parent] ?? const []) {
        final kode = a['kode']?.toString() ?? '';
        if (kode.isEmpty) continue;
        if (a['is_postable'] == true) codes.add(kode);
        walk(kode);
      }
    }

    final self = _coa.cast<Map<String, dynamic>?>().firstWhere(
          (x) => x!['kode']?.toString() == rootKode,
          orElse: () => null,
        );
    if (self != null && self['is_postable'] == true) {
      codes.add(rootKode);
    }
    walk(rootKode);
    return codes.toSet().toList()..sort();
  }

  List<Map<String, dynamic>> _directChildren(String parentKode) {
    return _coa
        .where((a) => a['parent_kode']?.toString() == parentKode)
        .toList();
  }

  Future<void> _openCoaDetail(Map<String, dynamic> account) async {
    final kode = account['kode']?.toString() ?? '';
    if (kode.isEmpty) return;
    final postable = account['is_postable'] == true;
    final ledgerCodes = postable ? [kode] : _postableCodesUnder(kode);
    final children = _directChildren(kode);
    final start = DateTime(_tahun, _bulan, 1);
    final end = DateTime(_tahun, _bulan + 1, 0);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _CoaDetailSheet(
          account: account,
          periodLabel: _periodLabel,
          tokoLabel: _tokoContextLabel,
          children: children,
          ledgerCodes: ledgerCodes,
          trial: _trial,
          fmt: _fmt,
          tipeColor: _tipeColor,
          tipeIcon: _tipeIcon,
          tipeLabel: _tipeLabel,
          onOpenChild: (child) {
            Navigator.pop(ctx);
            _openCoaDetail(child);
          },
          loadLedger: () => _reports.fetchAccountLedger(
            akunKodes: ledgerCodes,
            tokoId: _tokoFilter,
            start: start,
            end: end,
          ),
        );
      },
    );
  }

  Future<void> _openAccountByKode(String kode) async {
    final k = kode.trim();
    if (k.isEmpty) return;
    final found = _coa.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a!['kode']?.toString() == k,
          orElse: () => null,
        );
    if (found != null) {
      await _openCoaDetail(found);
      return;
    }
    await _showInfoDetail(
      title: 'Akun $k',
      subtitle: '$_periodLabel · $_tokoContextLabel',
      icon: Icons.tag_rounded,
      rows: [
        ('Kode', k),
        ('Nama', 'Tidak ada di bagan akun lokal'),
        ('Catatan', 'Muat ulang COA atau cek migrasi seed.'),
      ],
    );
  }

  Future<void> _showInfoDetail({
    required String title,
    String? subtitle,
    IconData icon = Icons.info_outline_rounded,
    required List<(String, String)> rows,
    List<Widget>? actions,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlInfoDetailSheet(
        title: title,
        subtitle: subtitle ?? '$_periodLabel · $_tokoContextLabel',
        icon: icon,
        rows: rows,
        actions: actions,
      ),
    );
  }

  Future<void> _openJournalDetail(Map<String, dynamic> je) async {
    final lines = (je['journal_lines'] as List?) ?? const [];
    final voided = je['status']?.toString() == 'VOID';
    var totalD = 0;
    var totalK = 0;
    final lineRows = <(String, String)>[];
    for (final raw in lines) {
      final l = Map<String, dynamic>.from(raw as Map);
      final d = int.tryParse('${l['debit']}') ?? 0;
      final k = int.tryParse('${l['kredit']}') ?? 0;
      totalD += d;
      totalK += k;
      final coa = l['chart_of_accounts'];
      final nama = coa is Map ? coa['nama']?.toString() : '';
      lineRows.add((
        '${l['akun_kode']} ${nama ?? ''}'.trim(),
        d > 0 ? 'D ${_fmt(d)}' : 'K ${_fmt(k)}',
      ));
    }
    await _showInfoDetail(
      title: 'Jurnal ${je['sumber'] ?? '-'}',
      subtitle: '${je['tanggal']} · ${je['toko_id']} · ${je['status']}',
      icon: voided ? Icons.block_rounded : Icons.menu_book_rounded,
      rows: [
        ('ID', je['id']?.toString() ?? '-'),
        ('Status', je['status']?.toString() ?? '-'),
        ('Sumber', je['sumber']?.toString() ?? '-'),
        ('Referensi', (je['referensi_id'] ?? '-').toString()),
        ('Memo', (je['memo'] ?? '-').toString()),
        ('Total debit', _fmt(totalD)),
        ('Total kredit', _fmt(totalK)),
        ('Jumlah baris', '${lines.length}'),
        ...lineRows,
      ],
    );
  }

  Future<void> _openBalanceDetail(GlAccountBalance r) async {
    await _openAccountByKode(r.kode);
  }

  Future<void> _openAgingDetail(GlAgingRow r, {required bool piutang}) async {
    await _showInfoDetail(
      title: piutang ? 'Detail piutang' : 'Detail hutang',
      subtitle: '${r.bucket} · ${r.umurHari} hari',
      icon: piutang
          ? Icons.hourglass_bottom_rounded
          : Icons.receipt_long_rounded,
      rows: [
        ('Referensi', r.ref),
        ('Nama', r.nama),
        ('Toko', r.tokoId),
        ('Tanggal', DateFormat('dd MMM yyyy', 'id_ID').format(r.tanggal)),
        ('Umur', '${r.umurHari} hari'),
        ('Bucket', r.bucket),
        ('Nominal', _fmt(r.nominal)),
        ('Jenis', piutang ? 'Piutang usaha' : 'Hutang usaha'),
      ],
      actions: [
        if (piutang && r.ref.trim().isNotEmpty)
          PremiumPrimaryButton(
            label: 'Lihat akun piutang (1103)',
            onPressed: () {
              Navigator.pop(context);
              _openAccountByKode('1103');
            },
          ),
        if (!piutang)
          PremiumPrimaryButton(
            label: 'Lihat akun hutang (2101)',
            onPressed: () {
              Navigator.pop(context);
              _openAccountByKode('2101');
            },
          ),
      ],
    );
  }

  Future<void> _openConsolDetail(GlTokoConsolidate c) async {
    await _showInfoDetail(
      title: 'Konsolidasi ${c.tokoId}',
      subtitle: _periodLabel,
      icon: Icons.hub_rounded,
      rows: [
        ('Toko', c.tokoId),
        ('Pendapatan', _fmt(c.pendapatan)),
        ('Beban', _fmt(c.beban)),
        ('Laba', _fmt(c.laba)),
        ('Kas/Bank', _fmt(c.kasBank)),
        ('Piutang', _fmt(c.piutang)),
        ('Hutang', _fmt(c.hutang)),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'Filter ke toko ini',
          onPressed: () {
            Navigator.pop(context);
            setState(() => _tokoFilter = c.tokoId);
            _reload();
          },
        ),
      ],
    );
  }

  Future<void> _openBankAccountDetail(Map<String, dynamic> b) async {
    await _showInfoDetail(
      title: b['nama']?.toString() ?? 'Rekening bank',
      subtitle: b['toko_id']?.toString() ?? _tokoContextLabel,
      icon: Icons.account_balance_rounded,
      rows: [
        ('ID', b['id']?.toString() ?? '-'),
        ('Nama', b['nama']?.toString() ?? '-'),
        ('Bank', b['bank_name']?.toString() ?? '-'),
        ('No. rekening', b['no_rekening']?.toString() ?? '-'),
        ('Akun GL', b['akun_gl']?.toString() ?? '1102'),
        ('Toko', b['toko_id']?.toString() ?? '-'),
        ('Aktif', b['aktif'] == true ? 'Ya' : 'Tidak'),
        ('Mutasi termuat', '${_bankLines.length} baris'),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'Lihat akun Bank (1102)',
          onPressed: () {
            Navigator.pop(context);
            _openAccountByKode((b['akun_gl'] ?? '1102').toString());
          },
        ),
      ],
    );
  }

  Future<void> _openBankLineDetail(Map<String, dynamic> l) async {
    final d = int.tryParse('${l['debit'] ?? 0}') ?? 0;
    final k = int.tryParse('${l['kredit'] ?? 0}') ?? 0;
    await _showInfoDetail(
      title: 'Mutasi bank',
      subtitle: l['tanggal']?.toString() ?? _periodLabel,
      icon: Icons.account_balance_wallet_rounded,
      rows: [
        ('ID', l['id']?.toString() ?? '-'),
        ('Tanggal', l['tanggal']?.toString() ?? '-'),
        ('Deskripsi', l['deskripsi']?.toString() ?? '-'),
        ('Debit', d > 0 ? _fmt(d) : '-'),
        ('Kredit', k > 0 ? _fmt(k) : '-'),
        ('Status', l['status']?.toString() ?? '-'),
        ('Match journal', l['matched_journal_id']?.toString() ?? '-'),
        ('Bank account', l['bank_account_id']?.toString() ?? '-'),
      ],
    );
  }

  Future<void> _openBudgetDetail(GlBudgetRow b) async {
    await _showInfoDetail(
      title: '${b.akunKode} · ${b.akunNama}',
      subtitle: 'Anggaran $_periodLabel',
      icon: Icons.insights_rounded,
      rows: [
        ('Akun', '${b.akunKode} ${b.akunNama}'),
        ('Anggaran', _fmt(b.anggaran)),
        ('Aktual', _fmt(b.aktual)),
        ('Selisih', _fmt(b.selisih)),
        ('% pakai', b.anggaran <= 0
            ? '-'
            : '${((b.aktual / b.anggaran) * 100).toStringAsFixed(1)}%'),
        ('Konteks', _tokoContextLabel),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'Lihat mutasi akun',
          onPressed: () {
            Navigator.pop(context);
            _openAccountByKode(b.akunKode);
          },
        ),
      ],
    );
  }

  Future<void> _openEfakturDetail(Map<String, dynamic> e) async {
    await _showInfoDetail(
      title: e['no_invoice']?.toString() ?? 'e-Faktur',
      subtitle: e['status']?.toString() ?? '-',
      icon: Icons.receipt_long_rounded,
      rows: [
        ('ID', e['id']?.toString() ?? '-'),
        ('Invoice', e['no_invoice']?.toString() ?? '-'),
        ('Pembeli', e['nama_pembeli']?.toString() ?? '-'),
        ('NPWP', e['npwp_pembeli']?.toString() ?? '-'),
        ('Tanggal', e['tanggal']?.toString() ?? '-'),
        ('Toko', e['toko_id']?.toString() ?? '-'),
        ('DPP', _fmt(int.tryParse('${e['dpp'] ?? 0}') ?? 0)),
        ('PPN', _fmt(int.tryParse('${e['ppn'] ?? 0}') ?? 0)),
        ('Status', e['status']?.toString() ?? '-'),
        ('Sale ID', e['sale_id']?.toString() ?? '-'),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'Lihat akun PPN (2102)',
          onPressed: () {
            Navigator.pop(context);
            _openAccountByKode('2102');
          },
        ),
      ],
    );
  }

  Future<void> _openPeriodDetail(Map<String, dynamic> p) async {
    final y = p['tahun'] as int;
    final m = p['bulan'] as int;
    final st = p['status']?.toString() ?? '';
    final label =
        DateFormat('MMMM yyyy', 'id_ID').format(DateTime(y, m));
    await _showInfoDetail(
      title: label,
      subtitle: st == 'CLOSED' ? 'Ditutup' : 'Terbuka',
      icon: st == 'CLOSED' ? Icons.lock_rounded : Icons.lock_open_rounded,
      rows: [
        ('Tahun', '$y'),
        ('Bulan', '$m'),
        ('Status', st == 'CLOSED' ? 'CLOSED (Ditutup)' : 'OPEN (Terbuka)'),
        ('Closed at', p['closed_at']?.toString() ?? '-'),
        ('Closed by', p['closed_by']?.toString() ?? '-'),
        ('ID periode', p['id']?.toString() ?? '-'),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'Jadikan periode aktif',
          onPressed: () {
            Navigator.pop(context);
            setState(() {
              _tahun = y;
              _bulan = m;
            });
            _reload();
          },
        ),
      ],
    );
  }

  Future<void> _openPlSummaryDetail() async {
    var pendapatan = 0;
    var beban = 0;
    for (final r in _pl) {
      if (r.tipe == 'REVENUE') {
        pendapatan += r.kredit - r.debit;
      } else {
        beban += r.debit - r.kredit;
      }
    }
    await _showInfoDetail(
      title: 'Ringkasan laba rugi',
      subtitle: '$_periodLabel · $_tokoContextLabel',
      icon: Icons.show_chart_rounded,
      rows: [
        ('Pendapatan', _fmt(pendapatan)),
        ('Beban (+HPP)', _fmt(beban)),
        ('Laba bersih', _fmt(pendapatan - beban)),
        ('Jumlah akun', '${_pl.length}'),
        (
          'Catatan HPP',
          'Akun 5100 baru terisi jika jurnal HPP/persediaan sudah di-post.'
        ),
      ],
    );
  }

  Future<void> _openBsSummaryDetail() async {
    await _showInfoDetail(
      title: 'Ringkasan neraca',
      subtitle: '$_periodLabel · $_tokoContextLabel',
      icon: Icons.balance_rounded,
      rows: [
        ('Laba berjalan', _fmt(_labaBerjalan)),
        ('Jumlah akun neraca', '${_bs.length}'),
        ('Aset lines',
            '${_bs.where((e) => e.tipe == 'ASSET').length}'),
        ('Kewajiban lines',
            '${_bs.where((e) => e.tipe == 'LIABILITY').length}'),
        ('Ekuitas lines',
            '${_bs.where((e) => e.tipe == 'EQUITY').length}'),
      ],
    );
  }

  Widget _detailChevron() => Icon(
        Icons.chevron_right_rounded,
        color: OptikAdminTokens.slate.withOpacity(0.85),
        size: 22,
      );

  Widget _buildCoaTab() {
    if (_coa.isEmpty) {
      return const PremiumEmptyState(
        message: 'Bagan akun belum tersedia.',
        icon: Icons.account_tree_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: _coa.length,
      itemBuilder: (_, i) {
        final a = _coa[i];
        final postable = a['is_postable'] == true;
        final tipe = a['tipe']?.toString();
        final color = _tipeColor(tipe);
        final depth = _coaDepth(a);
        final indent = 10.0 + (depth * 16.0);

        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 10),
          child: PremiumPanel(
            onTap: () => _openCoaDetail(a),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            borderRadius: postable ? 18 : 16,
            borderColor: postable
                ? OptikAdminTokens.ice.withOpacity(0.45)
                : OptikAdminTokens.navy.withOpacity(0.12),
            showAccentBar: !postable,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: color.withOpacity(postable ? 0.10 : 0.14),
                    border: Border.all(color: color.withOpacity(0.22)),
                  ),
                  child: Icon(_tipeIcon(tipe), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: OptikAdminTokens.bgMid,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: OptikAdminTokens.lineStrong),
                            ),
                            child: Text(
                              a['kode']?.toString() ?? '',
                              style: const TextStyle(
                                color: OptikAdminTokens.navy,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              a['nama']?.toString() ?? '',
                              style: TextStyle(
                                color: postable
                                    ? OptikAdminTokens.navy
                                    : OptikAdminTokens.textSecondary,
                                fontWeight:
                                    postable ? FontWeight.w700 : FontWeight.w800,
                                fontSize: postable ? 13 : 13.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _metaChip(_tipeLabel(tipe), color),
                          _metaChip(
                            a['normal_balance']?.toString() == 'CREDIT'
                                ? 'Kredit'
                                : 'Debit',
                            OptikAdminTokens.slate,
                          ),
                          if (!postable)
                            _metaChip('Header', OptikAdminTokens.navy),
                          if (a['aktif'] != true)
                            _metaChip('Nonaktif', OptikAdminTokens.danger),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: OptikAdminTokens.slate.withOpacity(0.85),
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metaChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildJournalTab() {
    if (_journals.isEmpty) {
      return PremiumEmptyState(
        message: 'Belum ada jurnal. Jalankan sinkron GL historis atau buat transaksi baru.',
        icon: Icons.menu_book_outlined,
        action: _isOwnerOrPusat
            ? PremiumPrimaryButton(
                label: 'Sinkronkan GL',
                onPressed: _backfill,
              )
            : null,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _journals.length,
      itemBuilder: (_, i) {
        final je = _journals[i];
        final lines = (je['journal_lines'] as List?) ?? const [];
        final voided = je['status']?.toString() == 'VOID';
        return PremiumPanel(
          onTap: () => _openJournalDetail(je),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          borderColor: voided
              ? OptikAdminTokens.danger.withOpacity(0.35)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${je['tanggal']} · ${je['sumber']} · ${je['toko_id']}',
                      style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                  ),
                  Text(je['status']?.toString() ?? '',
                      style: TextStyle(
                          color: voided
                              ? OptikAdminTokens.danger
                              : OptikAdminTokens.success,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  _detailChevron(),
                ],
              ),
              const SizedBox(height: 4),
              Text(je['memo']?.toString() ?? '-',
                  style: const TextStyle(
                      color: OptikAdminTokens.textSecondary, fontSize: 11)),
              if ((je['referensi_id'] ?? '').toString().isNotEmpty)
                Text('Ref: ${je['referensi_id']}',
                    style: const TextStyle(
                        color: OptikAdminTokens.textMuted, fontSize: 10)),
              const SizedBox(height: 8),
              ...lines.map((raw) {
                final l = Map<String, dynamic>.from(raw as Map);
                final coa = l['chart_of_accounts'];
                final nama = coa is Map ? coa['nama']?.toString() : null;
                final d = int.tryParse('${l['debit']}') ?? 0;
                final k = int.tryParse('${l['kredit']}') ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l['akun_kode']} ${nama ?? ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(d > 0 ? _fmt(d) : '',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11,
                                color: OptikAdminTokens.navy)),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(k > 0 ? _fmt(k) : '',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11,
                                color: OptikAdminTokens.danger)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrialTab() {
    return _balanceList(
      rows: _trial,
      empty: 'Tidak ada mutasi di periode ini.',
      onExport: () => GlReportPdfService.shareTrialBalance(
        title: 'Neraca saldo',
        subtitle: '$_periodLabel${_tokoFilter != null ? ' · $_tokoFilter' : ''}',
        rows: _trial,
      ),
      valueOf: (r) => null,
      showDk: true,
    );
  }

  Widget _buildPlTab() {
    var pendapatan = 0;
    var beban = 0;
    for (final r in _pl) {
      if (r.tipe == 'REVENUE') {
        pendapatan += r.kredit - r.debit;
      } else {
        beban += r.debit - r.kredit;
      }
    }
    final laba = pendapatan - beban;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: PremiumStatGrid(
            padding: EdgeInsets.zero,
            items: [
              PremiumStatItem(
                  label: 'Pendapatan',
                  value: _fmt(pendapatan),
                  color: OptikAdminTokens.success,
                  onTap: _openPlSummaryDetail),
              PremiumStatItem(
                  label: 'Beban',
                  value: _fmt(beban),
                  color: OptikAdminTokens.danger,
                  onTap: _openPlSummaryDetail),
              PremiumStatItem(
                  label: 'Laba bersih',
                  value: _fmt(laba),
                  color: OptikAdminTokens.navy,
                  onTap: _openPlSummaryDetail),
            ],
          ),
        ),
        Expanded(
          child: _balanceList(
            rows: _pl,
            empty: 'Belum ada akun laba rugi di periode ini.',
            onExport: () => GlReportPdfService.shareIncomeStatement(
              title: 'Laba rugi',
              subtitle:
                  '$_periodLabel${_tokoFilter != null ? ' · $_tokoFilter' : ''}',
              rows: _pl,
              labaBersih: laba,
            ),
            valueOf: (r) => r.tipe == 'REVENUE'
                ? (r.kredit - r.debit)
                : (r.debit - r.kredit),
            showDk: false,
          ),
        ),
      ],
    );
  }

  Widget _buildBsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: PremiumPanel(
            onTap: _openBsSummaryDetail,
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Laba berjalan',
                    style: TextStyle(
                        color: OptikAdminTokens.textSecondary, fontSize: 12)),
                Row(
                  children: [
                    Text(_fmt(_labaBerjalan),
                        style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w900,
                            fontSize: 14)),
                    const SizedBox(width: 4),
                    _detailChevron(),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _balanceList(
            rows: _bs,
            empty: 'Belum ada akun neraca di periode ini.',
            onExport: () => GlReportPdfService.shareBalanceSheet(
              title: 'Neraca',
              subtitle:
                  '$_periodLabel${_tokoFilter != null ? ' · $_tokoFilter' : ''}',
              rows: _bs,
              labaBerjalan: _labaBerjalan,
            ),
            valueOf: (r) => r.saldo,
            showDk: false,
          ),
        ),
      ],
    );
  }

  Widget _balanceList({
    required List<GlAccountBalance> rows,
    required String empty,
    required Future<void> Function() onExport,
    required int? Function(GlAccountBalance) valueOf,
    required bool showDk,
  }) {
    if (rows.isEmpty) {
      return PremiumEmptyState(message: empty, icon: Icons.table_chart_outlined);
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Ekspor PDF',
            onPressed: () async {
              try {
                await onExport();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Gagal ekspor: $e'),
                  backgroundColor: OptikAdminTokens.danger,
                ));
              }
            },
            icon: const Icon(Icons.download_rounded,
                color: OptikAdminTokens.navy),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final v = valueOf(r);
              return PremiumPanel(
                onTap: () => _openBalanceDetail(r),
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(r.kode,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: OptikAdminTokens.navy,
                              fontSize: 11)),
                    ),
                    Expanded(
                      child: Text(r.nama,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    if (showDk) ...[
                      SizedBox(
                        width: 80,
                        child: Text(_fmt(r.debit),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11)),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(_fmt(r.kredit),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11,
                                color: OptikAdminTokens.danger)),
                      ),
                    ] else
                      Text(_fmt(v ?? r.saldo),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: OptikAdminTokens.navy,
                              fontSize: 12)),
                    _detailChevron(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAgingTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        const Text('Aging piutang',
            style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        const SizedBox(height: 8),
        PremiumStatGrid(
          padding: EdgeInsets.zero,
          items: [
            for (final b in _arBuckets)
              PremiumStatItem(
                label: b.label,
                value: _fmt(b.amount),
                color: OptikAdminTokens.warning,
                onTap: () => _showInfoDetail(
                  title: 'Aging piutang ${b.label}',
                  icon: Icons.hourglass_bottom_rounded,
                  rows: [
                    ('Bucket', b.label),
                    ('Jumlah dokumen', '${b.count}'),
                    ('Total', _fmt(b.amount)),
                    ('Jenis', 'Piutang'),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_arRows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Tidak ada piutang terbuka.',
                style: TextStyle(color: OptikAdminTokens.textMuted)),
          )
        else
          ..._arRows
              .take(40)
              .map((r) => _agingTile(r, piutang: true)),
        const SizedBox(height: 20),
        const Text('Aging hutang',
            style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        const SizedBox(height: 8),
        PremiumStatGrid(
          padding: EdgeInsets.zero,
          items: [
            for (final b in _apBuckets)
              PremiumStatItem(
                label: b.label,
                value: _fmt(b.amount),
                color: OptikAdminTokens.danger,
                onTap: () => _showInfoDetail(
                  title: 'Aging hutang ${b.label}',
                  icon: Icons.receipt_long_rounded,
                  rows: [
                    ('Bucket', b.label),
                    ('Jumlah dokumen', '${b.count}'),
                    ('Total', _fmt(b.amount)),
                    ('Jenis', 'Hutang'),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_apRows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Tidak ada hutang terbuka.',
                style: TextStyle(color: OptikAdminTokens.textMuted)),
          )
        else
          ..._apRows
              .take(40)
              .map((r) => _agingTile(r, piutang: false)),
      ],
    );
  }

  Widget _agingTile(GlAgingRow r, {required bool piutang}) {
    return PremiumPanel(
      onTap: () => _openAgingDetail(r, piutang: piutang),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.nama,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: OptikAdminTokens.navy,
                        fontSize: 12)),
                Text(
                  '${r.ref} · ${r.tokoId} · ${r.umurHari} hari · ${r.bucket}',
                  style: const TextStyle(
                      color: OptikAdminTokens.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(_fmt(r.nominal),
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: OptikAdminTokens.navy,
                  fontSize: 12)),
          _detailChevron(),
        ],
      ),
    );
  }


  Widget _buildConsolTab() {
    if (!_isOwnerOrPusat) {
      return const PremiumEmptyState(
        message: 'Konsolidasi multi-cabang hanya untuk owner/pusat.',
        icon: Icons.lock_outline_rounded,
      );
    }
    if (_consol.isEmpty) {
      return const PremiumEmptyState(
        message: 'Belum ada data konsolidasi periode ini. Jalankan sinkron GL historis.',
        icon: Icons.hub_outlined,
      );
    }
    final totalLaba = _consol.fold<int>(0, (s, e) => s + e.laba);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: PremiumStatGrid(
            padding: EdgeInsets.zero,
            items: [
              PremiumStatItem(
                label: 'Cabang',
                value: '${_consol.length}',
                color: OptikAdminTokens.navy,
                onTap: () => _showInfoDetail(
                  title: 'Konsolidasi cabang',
                  icon: Icons.hub_rounded,
                  rows: [
                    ('Jumlah cabang', '${_consol.length}'),
                    ('Total laba', _fmt(totalLaba)),
                    ('Periode', _periodLabel),
                    for (final c in _consol.take(12))
                      (c.tokoId, 'Laba ${_fmt(c.laba)}'),
                  ],
                ),
              ),
              PremiumStatItem(
                label: 'Total laba',
                value: _fmt(totalLaba),
                color: OptikAdminTokens.success,
                onTap: () => _showInfoDetail(
                  title: 'Total laba konsolidasi',
                  icon: Icons.show_chart_rounded,
                  rows: [
                    ('Total laba', _fmt(totalLaba)),
                    ('Cabang', '${_consol.length}'),
                    ('Periode', _periodLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: _consol.length,
            itemBuilder: (_, i) {
              final c = _consol[i];
              return PremiumPanel(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                onTap: () => _openConsolDetail(c),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.tokoId,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: OptikAdminTokens.navy,
                                  fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(
                            'Laba ${_fmt(c.laba)} · Pendapatan ${_fmt(c.pendapatan)} · Beban ${_fmt(c.beban)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Kas/Bank ${_fmt(c.kasBank)} · Piutang ${_fmt(c.piutang)} · Hutang ${_fmt(c.hutang)}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: OptikAdminTokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _detailChevron(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBankTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Rekonsiliasi bank',
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: _addBankAccount,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Rekening'),
            ),
            TextButton.icon(
              onPressed: _selectedBankId == null ? null : _addBankLine,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: const Text('Mutasi'),
            ),
          ],
        ),
        if (_bankAccounts.isEmpty)
          const PremiumEmptyState(
            message: 'Belum ada rekening bank. Tambah rekening per toko.',
            icon: Icons.account_balance_outlined,
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bankAccounts.map((b) {
              final id = b['id']?.toString();
              final selected = id == _selectedBankId;
              return ActionChip(
                avatar: Icon(
                  selected
                      ? Icons.account_balance_rounded
                      : Icons.account_balance_outlined,
                  size: 16,
                  color: OptikAdminTokens.navy,
                ),
                label: Text(
                  '${b['nama']}',
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: OptikAdminTokens.navy,
                  ),
                ),
                backgroundColor: selected
                    ? OptikAdminTokens.accentSoft.withOpacity(0.7)
                    : OptikAdminTokens.bgMid,
                side: BorderSide(
                  color: selected
                      ? OptikAdminTokens.navy.withOpacity(0.35)
                      : OptikAdminTokens.ice.withOpacity(0.7),
                ),
                onPressed: () async {
                  setState(() => _selectedBankId = id);
                  if (id != null) {
                    final lines = await _reports.fetchBankStatements(
                        bankAccountId: id);
                    if (!mounted) return;
                    setState(() => _bankLines = lines);
                  }
                  await _openBankAccountDetail(b);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (_bankLines.isEmpty)
            const Text('Belum ada mutasi bank.',
                style: TextStyle(color: OptikAdminTokens.textMuted))
          else
            ..._bankLines.map((l) {
              final d = int.tryParse('${l['debit'] ?? 0}') ?? 0;
              final k = int.tryParse('${l['kredit'] ?? 0}') ?? 0;
              final st = l['status']?.toString() ?? 'OPEN';
              return PremiumPanel(
                onTap: () => _openBankLineDetail(l),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l['tanggal']} · ${l['deskripsi'] ?? '-'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12)),
                          Text(st,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: st == 'MATCHED'
                                      ? OptikAdminTokens.success
                                      : OptikAdminTokens.warning)),
                        ],
                      ),
                    ),
                    Text(d > 0 ? '- ${_fmt(d)}' : '+ ${_fmt(k)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: d > 0
                                ? OptikAdminTokens.danger
                                : OptikAdminTokens.success)),
                    _detailChevron(),
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }

  Future<void> _addBankAccount() async {
    final namaCtrl = TextEditingController();
    final rekCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text('Tambah rekening bank',
            style: TextStyle(
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: namaCtrl,
                decoration: const InputDecoration(labelText: 'Nama rekening')),
            TextField(
                controller: rekCtrl,
                decoration: const InputDecoration(labelText: 'No. rekening')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || namaCtrl.text.trim().isEmpty) return;
    final toko = _tokoFilter ??
        widget.profile['toko_id']?.toString() ??
        'PUSAT';
    await _reports.addBankAccount(
      tokoId: toko,
      nama: namaCtrl.text.trim(),
      bankName: 'BCA',
      noRekening: rekCtrl.text.trim(),
    );
    await _reload();
  }

  Future<void> _addBankLine() async {
    if (_selectedBankId == null) return;
    final deskCtrl = TextEditingController();
    final nomCtrl = TextEditingController();
    var isKredit = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          title: const Text('Tambah mutasi bank',
              style: TextStyle(
                  color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: deskCtrl,
                  decoration: const InputDecoration(labelText: 'Keterangan')),
              TextField(
                  controller: nomCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal')),
              SwitchListTile(
                title: Text(isKredit ? 'Kredit (masuk)' : 'Debit (keluar)'),
                value: isKredit,
                onChanged: (v) => setInner(() => isKredit = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(nomCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (n <= 0) return;
    await _reports.addBankStatementLine(
      bankAccountId: _selectedBankId!,
      tanggal: DateTime.now(),
      deskripsi: deskCtrl.text.trim(),
      debit: isKredit ? 0 : n,
      kredit: isKredit ? n : 0,
    );
    await _reload();
  }

  Widget _buildBudgetTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Anggaran vs aktual',
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            if (_isOwnerOrPusat || _tokoFilter != null)
              TextButton.icon(
                onPressed: _addBudget,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Anggaran'),
              ),
          ],
        ),
        if (_budgets.isEmpty)
          const PremiumEmptyState(
            message: 'Belum ada anggaran periode ini.',
            icon: Icons.insights_outlined,
          )
        else
          ..._budgets.map((b) => PremiumPanel(
                onTap: () => _openBudgetDetail(b),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${b.akunKode} ${b.akunNama}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: OptikAdminTokens.navy,
                                  fontSize: 12)),
                          Text(
                            'Anggaran ${_fmt(b.anggaran)} · Aktual ${_fmt(b.aktual)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: OptikAdminTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(_fmt(b.selisih),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: b.selisih >= 0
                                ? OptikAdminTokens.success
                                : OptikAdminTokens.danger)),
                    _detailChevron(),
                  ],
                ),
              )),
      ],
    );
  }

  Future<void> _addBudget() async {
    final postable = _coa.where((a) => a['is_postable'] == true).toList();
    if (postable.isEmpty) return;
    final akunSel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih akun',
      searchable: true,
      options: [
        for (final a in postable)
          AdminPickerOption(
            value: a['kode']?.toString() ?? '',
            label: '${a['kode']} ${a['nama']}',
          ),
      ],
    );
    if (akunSel == null || akunSel.isClear || akunSel.value == null) return;
    final nomCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text('Set anggaran',
            style: TextStyle(
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nomCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nominal anggaran'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(nomCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final toko = _tokoFilter ??
        widget.profile['toko_id']?.toString() ??
        'PUSAT';
    await _reports.upsertBudget(
      tokoId: toko,
      tahun: _tahun,
      bulan: _bulan,
      akunKode: akunSel.value!,
      anggaran: n,
    );
    await _reload();
  }

  Widget _buildEfakturTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Draft e-Faktur',
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: _buildEfaktur,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Generate'),
            ),
            TextButton.icon(
              onPressed: _exportEfaktur,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Tandai ekspor'),
            ),
          ],
        ),
        const Text(
          'Draft siap unggah ke DJP. Integrasi API Coretax/e-Faktur tetap manual di portal.',
          style: TextStyle(fontSize: 11, color: OptikAdminTokens.textMuted),
        ),
        const SizedBox(height: 10),
        if (_efaktur.isEmpty)
          const PremiumEmptyState(
            message: 'Belum ada draft e-Faktur periode/toko ini.',
            icon: Icons.receipt_long_outlined,
          )
        else
          ..._efaktur.map((e) => PremiumPanel(
                onTap: () => _openEfakturDetail(e),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e['no_invoice']} · ${e['nama_pembeli'] ?? '-'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: OptikAdminTokens.navy,
                                  fontSize: 12)),
                          Text(
                            'DPP ${_fmt(int.tryParse('${e['dpp'] ?? 0}') ?? 0)} · PPN ${_fmt(int.tryParse('${e['ppn'] ?? 0}') ?? 0)} · ${e['status']}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: OptikAdminTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    _detailChevron(),
                  ],
                ),
              )),
      ],
    );
  }

  Future<void> _buildEfaktur() async {
    setState(() => _loading = true);
    try {
      final res = await _reports.buildEfaktur(
        tahun: _tahun,
        bulan: _bulan,
        tokoId: _tokoFilter,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('e-Faktur: ${res.created} dibuat'),
        backgroundColor: OptikAdminTokens.navy,
      ));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal generate e-Faktur: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  Future<void> _exportEfaktur() async {
    final ids = _efaktur
        .where((e) => (e['status']?.toString() ?? '') != 'EXPORTED')
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada draft siap ditandai ekspor'),
      ));
      return;
    }
    await _reports.markEfakturExported(ids);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${ids.length} draft ditandai EXPORTED'),
      backgroundColor: OptikAdminTokens.navy,
    ));
  }

  Future<void> _runFullAudit() async {
    if (_auditRunning) return;
    setState(() {
      _auditRunning = true;
      _auditError = null;
    });
    try {
      final report = await _reports.runFullAudit(
        tokoId: _tokoFilter,
        limitPerCheck: 80,
        tahun: _tahun,
        bulan: _bulan,
      );
      if (!mounted) return;
      setState(() {
        _auditReport = report;
        _auditRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auditRunning = false;
        _auditError = e.toString();
      });
    }
  }

  Color _auditSeverityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return OptikAdminTokens.danger;
      case 'HIGH':
        return const Color(0xFFE67E22);
      case 'MEDIUM':
        return OptikAdminTokens.warning;
      default:
        return OptikAdminTokens.slate;
    }
  }

  Widget _buildAuditTab() {
    final report = _auditReport;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PremiumPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audit E2E General Ledger',
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _tokoFilter == null || _tokoFilter!.isEmpty
                    ? 'Scope: SEMUA TOKO · $_periodLabel · cek angka + integritas'
                    : 'Scope: ${_tokoFilter!.toUpperCase()} · $_periodLabel · cek angka + integritas',
                style: const TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Angka dihitung ulang dari sales/FT vs jurnal GL (bukan ringkasan palsu). Temuan = selisih nyata.',
                style: TextStyle(
                  color: OptikAdminTokens.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 14),
              PremiumPrimaryButton(
                label: 'Jalankan audit penuh',
                loading: _auditRunning,
                onPressed: _runFullAudit,
              ),
              if (_auditError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _auditError!,
                  style: const TextStyle(
                    color: OptikAdminTokens.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (report != null) ...[
          const SizedBox(height: 14),
          if (report.finance != null) ...[
            _buildAuditFinancePanel(report.finance!),
            const SizedBox(height: 12),
          ],
          PremiumStatGrid(
            items: [
              PremiumStatItem(
                label: 'Status',
                value: report.allClear ? 'CLEAR' : 'TEMUAN',
                color: report.allClear
                    ? OptikAdminTokens.success
                    : OptikAdminTokens.danger,
              ),
              PremiumStatItem(
                label: 'Critical',
                value: '${report.criticalFailed}',
                color: OptikAdminTokens.danger,
              ),
              PremiumStatItem(
                label: 'High',
                value: '${report.highFailed}',
                color: const Color(0xFFE67E22),
              ),
              PremiumStatItem(
                label: 'Medium',
                value: '${report.mediumFailed}',
                color: OptikAdminTokens.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Dihasilkan: ${DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(report.generatedAt.toLocal())}'
            ' · Cek: ${report.checksRun} · Scope: ${report.scopeToko}'
            '${report.finance != null ? ' · Periode ${report.finance!.periode}' : ''}',
            style: const TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          ...report.checks.map(_buildAuditCheckCard),
        ] else if (!_auditRunning) ...[
          const SizedBox(height: 24),
          const PremiumEmptyState(
            message:
                'Belum ada hasil audit.\nTekan “Jalankan audit penuh” untuk memeriksa seluruh toko.',
            icon: Icons.fact_check_outlined,
          ),
        ],
        if (_auditRunning) ...[
          const SizedBox(height: 32),
          const Center(
            child: CircularProgressIndicator(color: OptikAdminTokens.ice),
          ),
        ],
      ],
    );
  }

  Widget _buildAuditFinancePanel(GlAuditFinance f) {
    Color matchColor(bool ok) =>
        ok ? OptikAdminTokens.success : OptikAdminTokens.danger;
    return PremiumPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Angka periode ${f.periode} · ${f.scopeToko}',
            style: const TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sales/FT di kiri · GL di kanan · harus sama (selisih 0)',
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          PremiumStatGrid(
            items: [
              PremiumStatItem(
                label: 'Omzet bruto GL',
                value: _fmt(f.omzetBrutoGl),
                color: matchColor(f.omzetBrutoMatch),
              ),
              PremiumStatItem(
                label: 'Omzet DPP GL',
                value: _fmt(f.omzetDppGl),
                color: matchColor(f.omzetDppMatch),
              ),
              PremiumStatItem(
                label: 'Pengeluaran GL',
                value: _fmt(f.pengeluaranGl),
                color: OptikAdminTokens.navy,
              ),
              PremiumStatItem(
                label: 'Bersih GL',
                value: _fmt(f.bersihGl),
                color: f.bersihGl >= 0
                    ? OptikAdminTokens.success
                    : OptikAdminTokens.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _auditCompareRow(
            'Omzet bruto',
            f.omzetBrutoSales,
            f.omzetBrutoGl,
            f.selisihOmzetBruto,
          ),
          _auditCompareRow(
            'Omzet DPP',
            f.omzetDppSales,
            f.omzetDppGl,
            f.selisihOmzetDpp,
          ),
          _auditCompareRow(
            'PPN',
            f.ppnSales,
            f.ppnGl,
            f.ppnGl - f.ppnSales,
          ),
          _auditCompareRow(
            'Pengeluaran (FT vs MANUAL)',
            f.pengeluaranFt,
            f.pengeluaranManualFt,
            f.selisihPengeluaran,
          ),
          const SizedBox(height: 8),
          Text(
            'Bersih ops (DPP sales − FT): ${_fmt(f.bersihOps)}'
            ' · Semua beban GL: ${_fmt(f.pengeluaranGl)}',
            style: const TextStyle(
              color: OptikAdminTokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _auditCompareRow(
    String label,
    int sumber,
    int gl,
    int selisih,
  ) {
    final ok = selisih == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: (ok ? OptikAdminTokens.success : OptikAdminTokens.danger)
              .withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (ok ? OptikAdminTokens.success : OptikAdminTokens.danger)
                .withOpacity(0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  ok ? 'COCOK' : 'SELISIH ${_fmt(selisih)}',
                  style: TextStyle(
                    color: ok
                        ? OptikAdminTokens.success
                        : OptikAdminTokens.danger,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sumber ${_fmt(sumber)}  →  GL ${_fmt(gl)}',
              style: const TextStyle(
                color: OptikAdminTokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditCheckCard(GlAuditCheck check) {
    final color = _auditSeverityColor(check.severity);
    GlAuditMetric? highlightMetric;
    for (final m in check.metrics) {
      if (m.key.contains('selisih') ||
          m.key.contains('omzet') ||
          m.key.contains('pengeluaran') ||
          m.key.contains('bersih') ||
          m.key.contains('nominal') ||
          m.key.contains('hilang') ||
          m.key == 'ar') {
        highlightMetric = m;
        break;
      }
    }
    highlightMetric ??= check.metrics.isEmpty ? null : check.metrics.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumPanel(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: !check.passed &&
                check.severity.toUpperCase() != 'INFO',
            leading: Icon(
              check.passed
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: check.passed ? OptikAdminTokens.success : color,
            ),
            title: Text(
              check.title,
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _auditChip(check.severity, color),
                      _auditChip(
                        check.passed ? 'LOLOS' : '${check.count} temuan',
                        check.passed
                            ? OptikAdminTokens.success
                            : OptikAdminTokens.danger,
                      ),
                      _auditChip(check.id, OptikAdminTokens.slate),
                    ],
                  ),
                  if (highlightMetric != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${highlightMetric.label}: ${_fmt(highlightMetric.amount)}',
                      style: TextStyle(
                        color: check.passed
                            ? OptikAdminTokens.textSecondary
                            : OptikAdminTokens.danger,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      check.definition,
                      style: const TextStyle(
                        color: OptikAdminTokens.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if (check.metrics.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...check.metrics.map((m) {
                        final isSelisih = m.key.contains('selisih') ||
                            m.key.contains('mismatch') ||
                            m.key.contains('hilang') ||
                            m.key.contains('over');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.label,
                                  style: const TextStyle(
                                    color: OptikAdminTokens.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _fmt(m.amount),
                                style: TextStyle(
                                  color: isSelisih && m.amount != 0
                                      ? OptikAdminTokens.danger
                                      : OptikAdminTokens.navy,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    if (check.findings.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...check.findings.take(80).map((f) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _showInfoDetail(
                              title: '${f.tokoId} · ${f.ref}',
                              icon: Icons.fact_check_rounded,
                              rows: [
                                ('Toko', f.tokoId),
                                ('Ref', f.ref),
                                ('Detail', f.detail),
                                for (final e in f.raw.entries)
                                  if (![
                                    'toko_id',
                                    'ref',
                                    'detail',
                                  ].contains(e.key))
                                    (e.key, '${e.value}'),
                              ],
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: OptikAdminTokens.ice.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      OptikAdminTokens.ice.withOpacity(0.8),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${f.tokoId} · ${f.ref}',
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    f.detail,
                                    style: const TextStyle(
                                      color: OptikAdminTokens.textSecondary,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      if (check.count > check.findings.length)
                        Text(
                          'Menampilkan ${check.findings.length} dari ${check.count} temuan (batas RPC).',
                          style: const TextStyle(
                            color: OptikAdminTokens.textMuted,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _auditChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildPeriodTab() {
    final status = _periodStatus(_tahun, _bulan);
    final closed = status == 'Ditutup';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PremiumPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final cur =
                        _periods.cast<Map<String, dynamic>?>().firstWhere(
                              (p) =>
                                  p!['tahun'] == _tahun && p['bulan'] == _bulan,
                              orElse: () => null,
                            );
                    if (cur != null) {
                      _openPeriodDetail(cur);
                    } else {
                      _showInfoDetail(
                        title: _periodLabel,
                        icon: Icons.lock_clock_rounded,
                        rows: [
                          ('Status', status),
                          ('Tahun', '$_tahun'),
                          ('Bulan', '$_bulan'),
                          (
                            'Catatan',
                            'Periode belum ada di tabel fiscal_periods.'
                          ),
                        ],
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Periode aktif: $_periodLabel',
                                  style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14)),
                              const SizedBox(height: 6),
                              Text('Status: $status',
                                  style: TextStyle(
                                      color: closed
                                          ? OptikAdminTokens.danger
                                          : OptikAdminTokens.success,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        _detailChevron(),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_isOwnerOrPusat) ...[
                if (!closed)
                  PremiumPrimaryButton(
                    label: 'Tutup periode ini',
                    onPressed: _closePeriod,
                  )
                else
                  PremiumPrimaryButton(
                    label: 'Buka kembali periode',
                    onPressed: _reopenPeriod,
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _backfill,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sinkronkan GL historis'),
                ),
              ] else
                const Text(
                  'Hanya owner yang dapat menutup/membuka periode.',
                  style: TextStyle(
                      color: OptikAdminTokens.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Riwayat periode',
            style: TextStyle(
                color: OptikAdminTokens.textSecondary,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._periods.take(24).map((p) {
          final y = p['tahun'];
          final m = p['bulan'];
          final st = p['status']?.toString() ?? '';
          return PremiumListTile(
            title: DateFormat('MMMM yyyy', 'id_ID')
                .format(DateTime(y as int, m as int)),
            subtitle: st == 'CLOSED' ? 'Ditutup' : 'Terbuka',
            icon: st == 'CLOSED'
                ? Icons.lock_rounded
                : Icons.lock_open_rounded,
            iconColor: st == 'CLOSED'
                ? OptikAdminTokens.danger
                : OptikAdminTokens.success,
            onTap: () => _openPeriodDetail(p),
          );
        }),
      ],
    );
  }
}

class _GlInfoDetailSheet extends StatelessWidget {
  const _GlInfoDetailSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rows,
    this.actions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<(String, String)> rows;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: h * 0.82,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            OptikAdminTokens.snow,
            OptikAdminTokens.bgMid,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.55)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: OptikAdminTokens.lineStrong,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        OptikAdminTokens.navy.withOpacity(0.92),
                        OptikAdminTokens.navy.withOpacity(0.72),
                      ],
                    ),
                    boxShadow: OptikAdminTokens.glow(OptikAdminTokens.ice),
                  ),
                  child: Icon(icon, color: OptikAdminTokens.snow, size: 22),
                ),
                const SizedBox(width: 12),
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
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
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
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: OptikAdminTokens.navy),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                PremiumPanel(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                  borderRadius: 18,
                  showAccentBar: true,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 8,
                            endIndent: 8,
                            color: OptikAdminTokens.ice.withOpacity(0.55),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 11, 10, 11),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 112,
                                child: Text(
                                  rows[i].$1.toUpperCase(),
                                  style: TextStyle(
                                    color: OptikAdminTokens.slate
                                        .withOpacity(0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  rows[i].$2,
                                  style: const TextStyle(
                                    color: OptikAdminTokens.navy,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ...actions!.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: w,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlLedgerLineDetailSheet extends StatelessWidget {
  const _GlLedgerLineDetailSheet({
    required this.line,
    required this.fmt,
  });

  final GlLedgerLine line;
  final String Function(int) fmt;

  String _shortId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
  }

  Widget _metaChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _field(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: mono ? 'monospace' : null,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDebit = line.debit > 0;
    final amount = isDebit ? line.debit : line.kredit;
    final accent = isDebit ? OptikAdminTokens.navy : OptikAdminTokens.danger;
    final h = MediaQuery.sizeOf(context).height;
    final dateLabel =
        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(line.tanggal);

    return Container(
      height: h * 0.72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [OptikAdminTokens.snow, OptikAdminTokens.bgMid],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.55)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: OptikAdminTokens.lineStrong,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: accent.withOpacity(0.12),
                    border: Border.all(color: accent.withOpacity(0.25)),
                  ),
                  child: Icon(
                    isDebit
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Mutasi akun ${line.akunKode}',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: OptikAdminTokens.navy),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PremiumPanel(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              borderRadius: 18,
              showAccentBar: true,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDebit ? 'DEBIT' : 'KREDIT',
                          style: TextStyle(
                            color: OptikAdminTokens.slate.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          fmt(amount),
                          style: TextStyle(
                            color: accent,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      _metaChip(line.sumber, OptikAdminTokens.navy),
                      _metaChip(line.tokoId, OptikAdminTokens.slate),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                PremiumPanel(
                  padding: EdgeInsets.zero,
                  borderRadius: 18,
                  child: Column(
                    children: [
                      _field('Akun', line.akunKode),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field(
                        'Referensi',
                        line.referensiId.isEmpty ? '-' : line.referensiId,
                      ),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('Memo baris',
                          line.lineMemo.isEmpty ? '-' : line.lineMemo),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('Memo jurnal',
                          line.entryMemo.isEmpty ? '-' : line.entryMemo),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('Entry ID', _shortId(line.entryId), mono: true),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('Line ID', _shortId(line.id), mono: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PremiumPrimaryButton(
                  label: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoaDetailSheet extends StatefulWidget {
  const _CoaDetailSheet({
    required this.account,
    required this.periodLabel,
    required this.tokoLabel,
    required this.children,
    required this.ledgerCodes,
    required this.trial,
    required this.fmt,
    required this.tipeColor,
    required this.tipeIcon,
    required this.tipeLabel,
    required this.loadLedger,
    this.onOpenChild,
  });

  final Map<String, dynamic> account;
  final String periodLabel;
  final String tokoLabel;
  final List<Map<String, dynamic>> children;
  final List<String> ledgerCodes;
  final List<GlAccountBalance> trial;
  final String Function(int) fmt;
  final Color Function(String?) tipeColor;
  final IconData Function(String?) tipeIcon;
  final String Function(String?) tipeLabel;
  final Future<List<GlLedgerLine>> Function() loadLedger;
  final void Function(Map<String, dynamic> child)? onOpenChild;

  @override
  State<_CoaDetailSheet> createState() => _CoaDetailSheetState();
}

class _CoaDetailSheetState extends State<_CoaDetailSheet> {
  bool _loading = true;
  String? _error;
  List<GlLedgerLine> _lines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = widget.ledgerCodes.isEmpty
          ? <GlLedgerLine>[]
          : await widget.loadLedger();
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  int get _totalDebit => _lines.fold(0, (s, l) => s + l.debit);
  int get _totalKredit => _lines.fold(0, (s, l) => s + l.kredit);

  int get _saldo {
    final normal =
        widget.account['normal_balance']?.toString() ?? 'DEBIT';
    final net = _totalDebit - _totalKredit;
    return normal == 'DEBIT' ? net : -net;
  }

  GlAccountBalance? _trialFor(String kode) {
    for (final t in widget.trial) {
      if (t.kode == kode) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final tipe = a['tipe']?.toString();
    final color = widget.tipeColor(tipe);
    final postable = a['is_postable'] == true;
    final h = MediaQuery.sizeOf(context).height;

    return Container(
      height: h * 0.88,
      decoration: const BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: OptikAdminTokens.lineStrong,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: color.withOpacity(0.12),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Icon(widget.tipeIcon(tipe), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a['kode']} · ${a['nama']}',
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.periodLabel} · ${widget.tokoLabel}',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: OptikAdminTokens.navy),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(widget.tipeLabel(tipe), color),
                _chip(
                  a['normal_balance']?.toString() == 'CREDIT'
                      ? 'Normal Kredit'
                      : 'Normal Debit',
                  OptikAdminTokens.slate,
                ),
                _chip(postable ? 'Postable' : 'Header', OptikAdminTokens.navy),
                if (a['aktif'] != true)
                  _chip('Nonaktif', OptikAdminTokens.danger),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _kpi('Debit', widget.fmt(_totalDebit),
                      OptikAdminTokens.navy),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpi('Kredit', widget.fmt(_totalKredit),
                      OptikAdminTokens.danger),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpi('Saldo', widget.fmt(_saldo),
                      OptikAdminTokens.success),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                if (!postable && widget.children.isNotEmpty) ...[
                  const Text(
                    'Akun turunan',
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final c in widget.children)
                    PremiumPanel(
                      onTap: widget.onOpenChild == null
                          ? null
                          : () => widget.onOpenChild!(c),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      borderRadius: 16,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c['kode']}  ${c['nama']}',
                              style: const TextStyle(
                                color: OptikAdminTokens.navy,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            c['is_postable'] == true ? 'Postable' : 'Header',
                            style: const TextStyle(
                              color: OptikAdminTokens.slate,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_trialFor(c['kode']?.toString() ?? '') != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                widget.fmt(
                                  _trialFor(c['kode']?.toString() ?? '')!
                                      .saldo,
                                ),
                                style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          const Icon(Icons.chevron_right_rounded,
                              size: 20, color: OptikAdminTokens.slate),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mutasi periode',
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (!_loading)
                      Text(
                        '${_lines.length} baris',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Muat ulang',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      color: OptikAdminTokens.navy,
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: OptikAdminTokens.ice),
                    ),
                  )
                else if (_error != null)
                  PremiumEmptyState(
                    message: 'Gagal memuat mutasi.\n$_error',
                    icon: Icons.error_outline_rounded,
                    accent: OptikAdminTokens.warning,
                    action: PremiumPrimaryButton(
                      label: 'Coba lagi',
                      onPressed: _load,
                    ),
                  )
                else if (widget.ledgerCodes.isEmpty)
                  const PremiumEmptyState(
                    message:
                        'Header ini belum punya akun postable di bawahnya.',
                    icon: Icons.account_tree_outlined,
                  )
                else if (_lines.isEmpty)
                  const PremiumEmptyState(
                    message: 'Belum ada mutasi di periode ini.',
                    icon: Icons.receipt_long_outlined,
                  )
                else
                  for (final l in _lines)
                    PremiumPanel(
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) => _GlLedgerLineDetailSheet(
                            line: l,
                            fmt: widget.fmt,
                          ),
                        );
                      },
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      borderRadius: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('dd MMM yyyy', 'id_ID')
                                      .format(l.tanggal),
                                  style: const TextStyle(
                                    color: OptikAdminTokens.navy,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (l.debit > 0
                                          ? OptikAdminTokens.navy
                                          : OptikAdminTokens.danger)
                                      .withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  l.debit > 0
                                      ? 'D ${widget.fmt(l.debit)}'
                                      : 'K ${widget.fmt(l.kredit)}',
                                  style: TextStyle(
                                    color: l.debit > 0
                                        ? OptikAdminTokens.navy
                                        : OptikAdminTokens.danger,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 18, color: OptikAdminTokens.slate),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _miniChip(l.sumber, OptikAdminTokens.navy),
                              _miniChip(l.tokoId, OptikAdminTokens.slate),
                              if (!postable)
                                _miniChip(l.akunKode, OptikAdminTokens.slate),
                              if (l.referensiId.isNotEmpty)
                                _miniChip(l.referensiId, OptikAdminTokens.slate),
                            ],
                          ),
                          if ((l.lineMemo.isNotEmpty
                                  ? l.lineMemo
                                  : l.entryMemo)
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                l.lineMemo.isNotEmpty
                                    ? l.lineMemo
                                    : l.entryMemo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: OptikAdminTokens.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return PremiumPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: OptikAdminTokens.slate.withOpacity(0.9),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
