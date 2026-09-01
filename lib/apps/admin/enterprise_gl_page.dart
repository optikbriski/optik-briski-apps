// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/admin/admin_format.dart';

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
  NumberFormat get _rp => AdminFormat.currency(context);
  DateFormat _df(String pattern) => AdminFormat.date(context, pattern);

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
    final m = _df('MMMM yyyy')
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
      title: 'admin_auto_37a41325d9'.tr(),
      searchable: true,
      headerIcon: Icons.calendar_month_rounded,
      selected: '$_tahun-$_bulan',
      options: [
        for (final y in years)
          for (var m = 12; m >= 1; m--)
            AdminPickerOption(
              value: '$y-$m',
              label: _df('MMMM yyyy').format(DateTime(y, m)),
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

  String _periodStatusCode(int y, int m) {
    for (final p in _periods) {
      if (p['tahun'] == y && p['bulan'] == m) {
        return p['status'] == 'CLOSED' ? 'CLOSED' : 'OPEN';
      }
    }
    return 'NONE';
  }

  String _periodStatus(int y, int m) {
    switch (_periodStatusCode(y, m)) {
      case 'CLOSED':
        return 'admin_lbl_ditutup'.tr();
      case 'OPEN':
        return 'admin_lbl_terbuka'.tr();
      default:
        return 'admin_lbl_belum_dibuat'.tr();
    }
  }

  Future<void> _backfill() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text('admin_auto_cbca5abeef'.tr(),
            style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        content: Text(
          'admin_gl_row_8127856e60'.tr(),
          style: TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('admin_btn_sinkronkan'.tr()),
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
        content: Text('admin_auto_bf1c3e0034'.tr(namedArgs: {'error': '$e'})),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  Future<void> _closePeriod() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text('admin_auto_269eddd101'.tr(namedArgs: {'period': _periodLabel}),
            style: TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        content: Text(
          'admin_gl_msg_period_closed'.tr(),
          style: TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('admin_auto_8219933f3d'.tr()),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_8530c4ae9d'.tr()),
        backgroundColor: OptikAdminTokens.navy,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_25bc916884'.tr(namedArgs: {'error': '$e'})),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  Future<void> _reopenPeriod() async {
    try {
      await _poster.reopenPeriod(tahun: _tahun, bulan: _bulan);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_d322e92ee5'.tr()),
        backgroundColor: OptikAdminTokens.navy,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_c13d511dbd'.tr(namedArgs: {'error': '$e'})),
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
              Icon(Icons.calendar_month_rounded,
                  size: 15, color: OptikAdminTokens.navy),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  '$_periodLabel · $_tokoContextLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
      ('admin_gl_tab_coa'.tr(), Icons.account_tree_rounded),
      ('admin_gl_tab_journal'.tr(), Icons.menu_book_rounded),
      ('admin_gl_tab_trial_balance'.tr(), Icons.table_chart_rounded),
      ('admin_gl_tab_pl'.tr(), Icons.show_chart_rounded),
      ('admin_gl_tab_balance_sheet'.tr(), Icons.balance_rounded),
      ('admin_gl_tab_consolidation'.tr(), Icons.hub_rounded),
      ('admin_gl_tab_aging'.tr(), Icons.hourglass_bottom_rounded),
      ('admin_gl_tab_bank'.tr(), Icons.account_balance_rounded),
      ('admin_gl_tab_budget'.tr(), Icons.insights_rounded),
      ('admin_gl_tab_efaktur'.tr(), Icons.receipt_long_rounded),
      ('admin_gl_tab_period'.tr(), Icons.lock_clock_rounded),
      ('admin_gl_tab_audit'.tr(), Icons.fact_check_rounded),
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
        appBar: PremiumAppBar(
          title: 'admin_auto_99df167760'.tr(),
          centerTitle: true,
        ),
        body: PremiumEmptyState(
          message:
              'General Ledger hanya untuk Owner / Pusat.\nCabang memakai menu Keuangan & Kas.',
          icon: Icons.lock_outline_rounded,
          accent: OptikAdminTokens.warning,
          action: PremiumPrimaryButton(
            label: 'leave_discard_sure_no'.tr(),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
      );
    }

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'admin_auto_99df167760'.tr(),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _periodChip(),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'admin_auto_bd55324eb3'.tr(),
            icon: Icon(Icons.sync_rounded, color: OptikAdminTokens.navy),
            onPressed: _backfill,
          ),
          IconButton(
            tooltip: 'admin_btn_refresh'.tr(),
            icon: Icon(Icons.refresh_rounded,
                color: OptikAdminTokens.navy),
            onPressed: _reload,
          ),
        ],
        bottom: _glTabBar(),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : _error != null
              ? PremiumEmptyState(
                  message:
                      'Gagal memuat GL. Pastikan migrasi enterprise sudah diterapkan.\n$_error',
                  icon: Icons.error_outline_rounded,
                  accent: OptikAdminTokens.warning,
                  action: PremiumPrimaryButton(
                    label: 'common_retry'.tr(),
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
      title: 'admin_auto_d294bedfd8'.tr(namedArgs: {'k': k}),
      subtitle: 'admin_auto_4c6c8ff79c'.tr(namedArgs: {'period': _periodLabel, 'tokoContextLabel': _tokoContextLabel}),
      icon: Icons.tag_rounded,
      rows: [
        ('admin_gl_row_25cf262d90'.tr(), k),
        ('admin_auto_c6e88f1b17'.tr(), 'Tidak ada di bagan akun lokal'),
        ('admin_lbl_catatan'.tr(), 'Muat ulang COA atau cek migrasi seed.'),
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
      title: 'admin_gl_journal_title'.tr(namedArgs: {'source': '${je['sumber'] ?? '-'}'}),
      subtitle: '${je['tanggal']} · ${je['toko_id']} · ${je['status']}',
      icon: voided ? Icons.block_rounded : Icons.menu_book_rounded,
      rows: [
        ('smr_id'.tr(), je['id']?.toString() ?? '-'),
        ('invoice_hub_status'.tr(), je['status']?.toString() ?? '-'),
        ('admin_gl_row_d435393ca3'.tr(), je['sumber']?.toString() ?? '-'),
        ('admin_gl_row_7a12cb6c8f'.tr(), (je['referensi_id'] ?? '-').toString()),
        ('admin_gl_row_53b1a0b1fe'.tr(), (je['memo'] ?? '-').toString()),
        ('admin_gl_row_af7fd0e818'.tr(), _fmt(totalD)),
        ('admin_gl_row_26d01a8786'.tr(), _fmt(totalK)),
        ('admin_gl_row_4d28f474ed'.tr(), '${lines.length}'),
        ...lineRows,
      ],
    );
  }

  Future<void> _openBalanceDetail(GlAccountBalance r) async {
    await _openAccountByKode(r.kode);
  }

  Future<void> _openAgingDetail(GlAgingRow r, {required bool piutang}) async {
    await _showInfoDetail(
      title: piutang ? 'admin_lbl_detail_piutang'.tr() : 'admin_lbl_detail_hutang'.tr(),
      subtitle: '${r.bucket} · ${r.umurHari} hari',
      icon: piutang
          ? Icons.hourglass_bottom_rounded
          : Icons.receipt_long_rounded,
      rows: [
        ('admin_gl_row_7a12cb6c8f'.tr(), r.ref),
        ('admin_auto_c6e88f1b17'.tr(), r.nama),
        ('admin_auto_a5629553de'.tr(), r.tokoId),
        ('fin_tanggal'.tr(), _df('dd MMM yyyy').format(r.tanggal)),
        ('profil_label_umur'.tr(), '${r.umurHari} hari'),
        ('admin_lbl_bucket'.tr(), r.bucket),
        ('admin_auto_8c28d7c312'.tr(), _fmt(r.nominal)),
        ('admin_lbl_jenis'.tr(), piutang ? 'Piutang usaha' : 'Hutang usaha'),
      ],
      actions: [
        if (piutang && r.ref.trim().isNotEmpty)
          PremiumPrimaryButton(
            label: 'admin_auto_485e4b9b94'.tr(),
            onPressed: () {
              Navigator.pop(context);
              _openAccountByKode('1103');
            },
          ),
        if (!piutang)
          PremiumPrimaryButton(
            label: 'admin_auto_a0fb079673'.tr(),
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
      title: 'admin_lbl_konsolidasi_toko'.tr(namedArgs: {'toko': c.tokoId}),
      subtitle: _periodLabel,
      icon: Icons.hub_rounded,
      rows: [
        ('admin_auto_a5629553de'.tr(), c.tokoId),
        ('admin_auto_ec0673e5d8'.tr(), _fmt(c.pendapatan)),
        ('admin_auto_2d1b44e2d2'.tr(), _fmt(c.beban)),
        ('admin_gl_row_250bbb14f2'.tr(), _fmt(c.laba)),
        ('admin_gl_row_d50276d77f'.tr(), _fmt(c.kasBank)),
        ('admin_lbl_piutang'.tr(), _fmt(c.piutang)),
        ('admin_lbl_hutang'.tr(), _fmt(c.hutang)),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'admin_auto_5358bd9ae2'.tr(),
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
      title: b['nama']?.toString() ?? 'admin_lbl_rekening_bank'.tr(),
      subtitle: b['toko_id']?.toString() ?? _tokoContextLabel,
      icon: Icons.account_balance_rounded,
      rows: [
        ('smr_id'.tr(), b['id']?.toString() ?? '-'),
        ('admin_auto_c6e88f1b17'.tr(), b['nama']?.toString() ?? '-'),
        ('admin_gl_tab_bank'.tr(), b['bank_name']?.toString() ?? '-'),
        ('admin_auto_6d1d6fbe3b'.tr(), b['no_rekening']?.toString() ?? '-'),
        ('admin_gl_row_cd1a97ee26'.tr(), b['akun_gl']?.toString() ?? '1102'),
        ('admin_auto_a5629553de'.tr(), b['toko_id']?.toString() ?? '-'),
        ('admin_lbl_aktif'.tr(), b['aktif'] == true ? 'Ya' : 'Tidak'),
        ('admin_gl_row_beb39ac37f'.tr(), '${_bankLines.length} baris'),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'admin_auto_7e94e1d1ef'.tr(),
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
      title: 'admin_auto_54a7803b8f'.tr(),
      subtitle: l['tanggal']?.toString() ?? _periodLabel,
      icon: Icons.account_balance_wallet_rounded,
      rows: [
        ('smr_id'.tr(), l['id']?.toString() ?? '-'),
        ('fin_tanggal'.tr(), l['tanggal']?.toString() ?? '-'),
        ('admin_gl_row_cb3572abdb'.tr(), l['deskripsi']?.toString() ?? '-'),
        ('admin_auto_009534719f'.tr(), d > 0 ? _fmt(d) : '-'),
        ('admin_gl_row_aa9bb38bf8'.tr(), k > 0 ? _fmt(k) : '-'),
        ('invoice_hub_status'.tr(), l['status']?.toString() ?? '-'),
        ('admin_gl_row_6b7ad510b4'.tr(), l['matched_journal_id']?.toString() ?? '-'),
        ('admin_gl_row_7ec35321dd'.tr(), l['bank_account_id']?.toString() ?? '-'),
      ],
    );
  }

  Future<void> _openBudgetDetail(GlBudgetRow b) async {
    await _showInfoDetail(
      title: '${b.akunKode} · ${b.akunNama}',
      subtitle: 'admin_auto_cd0b5e94bc'.tr(namedArgs: {'period': _periodLabel}),
      icon: Icons.insights_rounded,
      rows: [
        ('admin_gl_row_2799e7f29b'.tr(), '${b.akunKode} ${b.akunNama}'),
        ('admin_gl_tab_budget'.tr(), _fmt(b.anggaran)),
        ('admin_gl_row_59de6f9595'.tr(), _fmt(b.aktual)),
        ('admin_gl_row_d0e2ca844b'.tr(), _fmt(b.selisih)),
        ('admin_gl_row_a354b9f123'.tr(), b.anggaran <= 0
            ? '-'
            : '${((b.aktual / b.anggaran) * 100).toStringAsFixed(1)}%'),
        ('admin_gl_row_1b23c1bf25'.tr(), _tokoContextLabel),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'admin_auto_ed7274f697'.tr(),
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
      title: e['no_invoice']?.toString() ?? 'admin_lbl_efaktur_fallback'.tr(),
      subtitle: e['status']?.toString() ?? '-',
      icon: Icons.receipt_long_rounded,
      rows: [
        ('smr_id'.tr(), e['id']?.toString() ?? '-'),
        ('admin_gl_row_466eadd40b'.tr(), e['no_invoice']?.toString() ?? '-'),
        ('admin_gl_row_4cf0d83de6'.tr(), e['nama_pembeli']?.toString() ?? '-'),
        ('admin_gl_row_a21fc8d16d'.tr(), e['npwp_pembeli']?.toString() ?? '-'),
        ('fin_tanggal'.tr(), e['tanggal']?.toString() ?? '-'),
        ('admin_auto_a5629553de'.tr(), e['toko_id']?.toString() ?? '-'),
        ('admin_gl_row_07b4f3d54b'.tr(), _fmt(int.tryParse('${e['dpp'] ?? 0}') ?? 0)),
        ('admin_gl_row_d78752bf2e'.tr(), _fmt(int.tryParse('${e['ppn'] ?? 0}') ?? 0)),
        ('invoice_hub_status'.tr(), e['status']?.toString() ?? '-'),
        ('admin_gl_row_af6d67da82'.tr(), e['sale_id']?.toString() ?? '-'),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'admin_auto_dec1ec3e54'.tr(),
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
        _df('MMMM yyyy').format(DateTime(y, m));
    await _showInfoDetail(
      title: label,
      subtitle: st == 'CLOSED' ? 'admin_lbl_ditutup'.tr() : 'admin_lbl_terbuka'.tr(),
      icon: st == 'CLOSED' ? Icons.lock_rounded : Icons.lock_open_rounded,
      rows: [
        ('admin_lbl_tahun'.tr(), '$y'),
        ('admin_lbl_bulan_short'.tr(), '$m'),
        ('invoice_hub_status'.tr(), st == 'CLOSED' ? 'admin_lbl_status_closed_full'.tr() : 'admin_lbl_status_open_full'.tr()),
        ('admin_gl_row_421902d8f2'.tr(), p['closed_at']?.toString() ?? '-'),
        ('admin_gl_row_b0810d0148'.tr(), p['closed_by']?.toString() ?? '-'),
        ('admin_gl_row_bca9e80a76'.tr(), p['id']?.toString() ?? '-'),
      ],
      actions: [
        PremiumPrimaryButton(
          label: 'admin_auto_ffa9c4028d'.tr(),
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
      title: 'admin_auto_871b8ecd59'.tr(),
      subtitle: 'admin_auto_4c6c8ff79c'.tr(namedArgs: {'period': _periodLabel, 'tokoContextLabel': _tokoContextLabel}),
      icon: Icons.show_chart_rounded,
      rows: [
        ('admin_auto_ec0673e5d8'.tr(), _fmt(pendapatan)),
        ('admin_gl_row_579211bae2'.tr(), _fmt(beban)),
        ('admin_auto_37dd72eafb'.tr(), _fmt(pendapatan - beban)),
        ('admin_gl_row_458c422fc6'.tr(), '${_pl.length}'),
        (
          'Catatan HPP',
          'Akun 5100 baru terisi jika jurnal HPP/persediaan sudah di-post.'
        ),
      ],
    );
  }

  Future<void> _openBsSummaryDetail() async {
    await _showInfoDetail(
      title: 'admin_auto_c291d8714b'.tr(),
      subtitle: 'admin_auto_4c6c8ff79c'.tr(namedArgs: {'period': _periodLabel, 'tokoContextLabel': _tokoContextLabel}),
      icon: Icons.balance_rounded,
      rows: [
        ('admin_auto_7c3f655331'.tr(), _fmt(_labaBerjalan)),
        ('admin_gl_row_16445e4564'.tr(), '${_bs.length}'),
        ('admin_gl_row_c46beb1b37'.tr(),
            '${_bs.where((e) => e.tipe == 'ASSET').length}'),
        ('admin_gl_row_fac642eecc'.tr(),
            '${_bs.where((e) => e.tipe == 'LIABILITY').length}'),
        ('admin_gl_row_0e1de39ac6'.tr(),
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
      return PremiumEmptyState(
        message: 'admin_auto_342e85bdd2'.tr(),
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
                              style: TextStyle(
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
                            _metaChip('admin_gl_row_bf50d5e661'.tr(), OptikAdminTokens.navy),
                          if (a['aktif'] != true)
                            _metaChip('admin_gl_row_af5dff8c9e'.tr(), OptikAdminTokens.danger),
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
        message: 'admin_auto_999ff59ef9'.tr(),
        icon: Icons.menu_book_outlined,
        action: _isOwnerOrPusat
            ? PremiumPrimaryButton(
                label: 'admin_auto_ed8217c023'.tr(),
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
                      style: TextStyle(
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
                  style: TextStyle(
                      color: OptikAdminTokens.textSecondary, fontSize: 11)),
              if ((je['referensi_id'] ?? '').toString().isNotEmpty)
                Text('Ref: ${je['referensi_id']}',
                    style: TextStyle(
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
                            style: TextStyle(
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
        title: 'admin_auto_412d96eda7'.tr(),
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
                  label: 'admin_auto_ec0673e5d8'.tr(),
                  value: _fmt(pendapatan),
                  color: OptikAdminTokens.success,
                  onTap: _openPlSummaryDetail),
              PremiumStatItem(
                  label: 'admin_auto_2d1b44e2d2'.tr(),
                  value: _fmt(beban),
                  color: OptikAdminTokens.danger,
                  onTap: _openPlSummaryDetail),
              PremiumStatItem(
                  label: 'admin_auto_37dd72eafb'.tr(),
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
              title: 'admin_auto_9e57093419'.tr(),
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
                Text('admin_auto_7c3f655331'.tr(),
                    style: TextStyle(
                        color: OptikAdminTokens.textSecondary, fontSize: 12)),
                Row(
                  children: [
                    Text(_fmt(_labaBerjalan),
                        style: TextStyle(
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
              title: 'admin_auto_601ff9152d'.tr(),
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
            tooltip: 'admin_auto_3fbb445bd2'.tr(),
            onPressed: () async {
              try {
                await onExport();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('admin_auto_d21f848032'.tr(namedArgs: {'error': '$e'})),
                  backgroundColor: OptikAdminTokens.danger,
                ));
              }
            },
            icon: Icon(Icons.download_rounded,
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
                          style: TextStyle(
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
                          style: TextStyle(
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
        Text('admin_auto_e86e75c9e7'.tr(),
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
                  title: 'admin_lbl_aging_piutang'.tr(namedArgs: {'label': b.label}),
                  icon: Icons.hourglass_bottom_rounded,
                  rows: [
                    ('admin_lbl_bucket'.tr(), b.label),
                    ('admin_lbl_jumlah_dokumen'.tr(), '${b.count}'),
                    ('fin_total'.tr(), _fmt(b.amount)),
                    ('admin_lbl_jenis'.tr(), 'admin_lbl_piutang'.tr()),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_arRows.isEmpty)
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('admin_auto_8192548cae'.tr(),
                style: TextStyle(color: OptikAdminTokens.textMuted)),
          )
        else
          ..._arRows
              .take(40)
              .map((r) => _agingTile(r, piutang: true)),
        const SizedBox(height: 20),
        Text('admin_auto_d88370aba1'.tr(),
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
                  title: 'admin_lbl_aging_hutang'.tr(namedArgs: {'label': b.label}),
                  icon: Icons.receipt_long_rounded,
                  rows: [
                    ('admin_lbl_bucket'.tr(), b.label),
                    ('admin_lbl_jumlah_dokumen'.tr(), '${b.count}'),
                    ('fin_total'.tr(), _fmt(b.amount)),
                    ('admin_lbl_jenis'.tr(), 'admin_lbl_hutang'.tr()),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_apRows.isEmpty)
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('admin_auto_518f0a2408'.tr(),
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
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: OptikAdminTokens.navy,
                        fontSize: 12)),
                Text(
                  '${r.ref} · ${r.tokoId} · ${r.umurHari} hari · ${r.bucket}',
                  style: TextStyle(
                      color: OptikAdminTokens.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(_fmt(r.nominal),
              style: TextStyle(
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
      return PremiumEmptyState(
        message: 'admin_auto_fdf3cdd6ef'.tr(),
        icon: Icons.lock_outline_rounded,
      );
    }
    if (_consol.isEmpty) {
      return PremiumEmptyState(
        message: 'admin_auto_a36089960f'.tr(),
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
                label: 'work_sum_toko'.tr(),
                value: '${_consol.length}',
                color: OptikAdminTokens.navy,
                onTap: () => _showInfoDetail(
                  title: 'admin_auto_ec35d8b532'.tr(),
                  icon: Icons.hub_rounded,
                  rows: [
                    ('admin_gl_row_8aa60f05d2'.tr(), '${_consol.length}'),
                    ('admin_auto_4973cedec9'.tr(), _fmt(totalLaba)),
                    ('admin_gl_tab_period'.tr(), _periodLabel),
                    for (final c in _consol.take(12))
                      (c.tokoId, 'Laba ${_fmt(c.laba)}'),
                  ],
                ),
              ),
              PremiumStatItem(
                label: 'admin_auto_4973cedec9'.tr(),
                value: _fmt(totalLaba),
                color: OptikAdminTokens.success,
                onTap: () => _showInfoDetail(
                  title: 'admin_auto_af2661f403'.tr(),
                  icon: Icons.show_chart_rounded,
                  rows: [
                    ('admin_auto_4973cedec9'.tr(), _fmt(totalLaba)),
                    ('admin_lbl_cabang'.tr(), '${_consol.length}'),
                    ('admin_gl_tab_period'.tr(), _periodLabel),
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
                              style: TextStyle(
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
                            style: TextStyle(
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
            Expanded(
              child: Text('admin_auto_10de71d44c'.tr(),
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: _addBankAccount,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('admin_lbl_rekening'.tr()),
            ),
            TextButton.icon(
              onPressed: _selectedBankId == null ? null : _addBankLine,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: Text('admin_lbl_mutasi'.tr()),
            ),
          ],
        ),
        if (_bankAccounts.isEmpty)
          PremiumEmptyState(
            message: 'admin_auto_318580f609'.tr(),
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
            Text('admin_auto_550fcce865'.tr(),
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
        title: Text('admin_auto_001b2a5883'.tr(),
            style: TextStyle(
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: namaCtrl,
                decoration: InputDecoration(labelText: 'admin_auto_557b80293a'.tr())),
            TextField(
                controller: rekCtrl,
                decoration: InputDecoration(labelText: 'admin_auto_6d1d6fbe3b'.tr())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('btn_simpan'.tr())),
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
          title: Text('admin_auto_bc12a78c37'.tr(),
              style: TextStyle(
                  color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: deskCtrl,
                  decoration: InputDecoration(labelText: 'admin_auto_6bd515e701'.tr())),
              TextField(
                  controller: nomCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'admin_auto_8c28d7c312'.tr())),
              SwitchListTile(
                title: Text(isKredit ? 'admin_lbl_kredit_masuk'.tr() : 'admin_lbl_debit_keluar'.tr()),
                value: isKredit,
                onChanged: (v) => setInner(() => isKredit = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('appr_btn_batal'.tr())),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('btn_simpan'.tr())),
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
            Expanded(
              child: Text('admin_auto_f5bfb6eccc'.tr(),
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            if (_isOwnerOrPusat || _tokoFilter != null)
              TextButton.icon(
                onPressed: _addBudget,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('admin_lbl_anggaran'.tr()),
              ),
          ],
        ),
        if (_budgets.isEmpty)
          PremiumEmptyState(
            message: 'admin_auto_3e7c8c0bed'.tr(),
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
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: OptikAdminTokens.navy,
                                  fontSize: 12)),
                          Text(
                            'Anggaran ${_fmt(b.anggaran)} · Aktual ${_fmt(b.aktual)}',
                            style: TextStyle(
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
      title: 'admin_auto_2026becb41'.tr(),
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
        title: Text('admin_auto_a99959bace'.tr(),
            style: TextStyle(
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nomCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'admin_auto_532b77b54d'.tr()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('btn_simpan'.tr())),
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
            Expanded(
              child: Text('admin_auto_3631853eb1'.tr(),
                  style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: _buildEfaktur,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('admin_btn_generate'.tr()),
            ),
            TextButton.icon(
              onPressed: _exportEfaktur,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text('admin_auto_54f775e776'.tr()),
            ),
          ],
        ),
        Text(
          'admin_gl_msg_efaktur_draft'.tr(),
          style: TextStyle(fontSize: 11, color: OptikAdminTokens.textMuted),
        ),
        const SizedBox(height: 10),
        if (_efaktur.isEmpty)
          PremiumEmptyState(
            message: 'admin_auto_3ba356a8ff'.tr(),
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
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: OptikAdminTokens.navy,
                                  fontSize: 12)),
                          Text(
                            'DPP ${_fmt(int.tryParse('${e['dpp'] ?? 0}') ?? 0)} · PPN ${_fmt(int.tryParse('${e['ppn'] ?? 0}') ?? 0)} · ${e['status']}',
                            style: TextStyle(
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
        content: Text('admin_msg_efaktur_created'.tr(namedArgs: {'n': '${res.created}'})),
        backgroundColor: OptikAdminTokens.navy,
      ));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_add0b5e698'.tr(namedArgs: {'error': '$e'})),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_auto_2325fe5fad'.tr()),
      ));
      return;
    }
    await _reports.markEfakturExported(ids);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('admin_msg_draft_exported'.tr(namedArgs: {'n': '${ids.length}'})),
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
              Text(
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
                style: TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Angka dihitung ulang dari sales/FT vs jurnal GL (bukan ringkasan palsu). Temuan = selisih nyata.',
                style: TextStyle(
                  color: OptikAdminTokens.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 14),
              PremiumPrimaryButton(
                label: 'admin_auto_79ce3597b2'.tr(),
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
                label: 'invoice_hub_status'.tr(),
                value: report.allClear ? 'CLEAR' : 'TEMUAN',
                color: report.allClear
                    ? OptikAdminTokens.success
                    : OptikAdminTokens.danger,
              ),
              PremiumStatItem(
                label: 'admin_auto_278d01e5af'.tr(),
                value: '${report.criticalFailed}',
                color: OptikAdminTokens.danger,
              ),
              PremiumStatItem(
                label: 'admin_auto_655d20c1ca'.tr(),
                value: '${report.highFailed}',
                color: const Color(0xFFE67E22),
              ),
              PremiumStatItem(
                label: 'admin_auto_87f8a6ab85'.tr(),
                value: '${report.mediumFailed}',
                color: OptikAdminTokens.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Dihasilkan: ${_df('dd MMM yyyy HH:mm').format(report.generatedAt.toLocal())}'
            ' · Cek: ${report.checksRun} · Scope: ${report.scopeToko}'
            '${report.finance != null ? ' · Periode ${report.finance!.periode}' : ''}',
            style: TextStyle(
              color: OptikAdminTokens.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          ...report.checks.map(_buildAuditCheckCard),
        ] else if (!_auditRunning) ...[
          const SizedBox(height: 24),
          PremiumEmptyState(
            message:
                'Belum ada hasil audit.\nTekan “Jalankan audit penuh” untuk memeriksa seluruh toko.',
            icon: Icons.fact_check_outlined,
          ),
        ],
        if (_auditRunning) ...[
          const SizedBox(height: 32),
          Center(
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
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
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
                label: 'admin_auto_53db4186a8'.tr(),
                value: _fmt(f.omzetBrutoGl),
                color: matchColor(f.omzetBrutoMatch),
              ),
              PremiumStatItem(
                label: 'admin_auto_71780c5700'.tr(),
                value: _fmt(f.omzetDppGl),
                color: matchColor(f.omzetDppMatch),
              ),
              PremiumStatItem(
                label: 'admin_auto_7c80ed9f78'.tr(),
                value: _fmt(f.pengeluaranGl),
                color: OptikAdminTokens.navy,
              ),
              PremiumStatItem(
                label: 'admin_auto_ab18da4943'.tr(),
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
            style: TextStyle(
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
                    style: TextStyle(
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
              style: TextStyle(
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
              style: TextStyle(
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
                      style: TextStyle(
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
                                  style: TextStyle(
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
                                ('admin_auto_a5629553de'.tr(), f.tokoId),
                                ('admin_gl_row_60baadb22e'.tr(), f.ref),
                                ('admin_btn_detail'.tr(), f.detail),
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
                                    style: TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    f.detail,
                                    style: TextStyle(
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
                          style: TextStyle(
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
    final closed = _periodStatusCode(_tahun, _bulan) == 'CLOSED';
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
                          ('invoice_hub_status'.tr(), _periodStatus(_tahun, _bulan)),
                          ('admin_lbl_tahun'.tr(), '$_tahun'),
                          ('admin_lbl_bulan_short'.tr(), '$_bulan'),
                          (
                            'Catatan',
                            'admin_gl_msg_period_missing'.tr()
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
                              Text('admin_auto_1a0a0a952d'.tr(namedArgs: {'period': _periodLabel}),
                                  style: TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14)),
                              const SizedBox(height: 6),
                              Text('admin_auto_76590d5f97'.tr(namedArgs: {'status': _periodStatus(_tahun, _bulan)}),
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
                    label: 'admin_auto_4cf38f08ca'.tr(),
                    onPressed: _closePeriod,
                  )
                else
                  PremiumPrimaryButton(
                    label: 'admin_auto_7e3e3fcc77'.tr(),
                    onPressed: _reopenPeriod,
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _backfill,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text('admin_auto_bd55324eb3'.tr()),
                ),
              ] else
                Text(
                  'Hanya owner yang dapat menutup/membuka periode.',
                  style: TextStyle(
                      color: OptikAdminTokens.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('admin_auto_a954223199'.tr(),
            style: TextStyle(
                color: OptikAdminTokens.textSecondary,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._periods.take(24).map((p) {
          final y = p['tahun'];
          final m = p['bulan'];
          final st = p['status']?.toString() ?? '';
          return PremiumListTile(
            title: _df('MMMM yyyy')
                .format(DateTime(y as int, m as int)),
            subtitle: st == 'CLOSED' ? 'admin_lbl_ditutup'.tr() : 'admin_lbl_terbuka'.tr(),
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
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
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
                  icon: Icon(Icons.close_rounded,
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
                                  style: TextStyle(
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
        AdminFormat.date(context, 'EEEE, dd MMMM yyyy').format(line.tanggal);

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
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Mutasi akun ${line.akunKode}',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
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
                      _field('admin_gl_row_2799e7f29b'.tr(), line.akunKode),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field(
                        'Referensi',
                        line.referensiId.isEmpty ? '-' : line.referensiId,
                      ),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('admin_gl_row_4c09cd0949'.tr(),
                          line.lineMemo.isEmpty ? '-' : line.lineMemo),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('admin_gl_row_241b210f93'.tr(),
                          line.entryMemo.isEmpty ? '-' : line.entryMemo),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('admin_gl_row_9390efb0ab'.tr(), _shortId(line.entryId), mono: true),
                      Divider(height: 1, color: OptikAdminTokens.ice.withOpacity(0.55)),
                      _field('admin_gl_row_7bc1046ea8'.tr(), _shortId(line.id), mono: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PremiumPrimaryButton(
                  label: 'admin_btn_close'.tr(),
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
      decoration: BoxDecoration(
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
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.periodLabel} · ${widget.tokoLabel}',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
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
                  _chip('admin_gl_row_af5dff8c9e'.tr(), OptikAdminTokens.danger),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _kpi('admin_auto_009534719f'.tr(), widget.fmt(_totalDebit),
                      OptikAdminTokens.navy),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpi('admin_gl_row_aa9bb38bf8'.tr(), widget.fmt(_totalKredit),
                      OptikAdminTokens.danger),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _kpi('fin_saldo'.tr(), widget.fmt(_saldo),
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
                  Text(
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
                              style: TextStyle(
                                color: OptikAdminTokens.navy,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            c['is_postable'] == true ? 'Postable' : 'Header',
                            style: TextStyle(
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
                                style: TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: OptikAdminTokens.slate),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
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
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    IconButton(
                      tooltip: 'admin_btn_refresh'.tr(),
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      color: OptikAdminTokens.navy,
                    ),
                  ],
                ),
                if (_loading)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: OptikAdminTokens.ice),
                    ),
                  )
                else if (_error != null)
                  PremiumEmptyState(
                    message: 'admin_err_load_mutasi'.tr(namedArgs: {'error': '$_error'}),
                    icon: Icons.error_outline_rounded,
                    accent: OptikAdminTokens.warning,
                    action: PremiumPrimaryButton(
                      label: 'common_retry'.tr(),
                      onPressed: _load,
                    ),
                  )
                else if (widget.ledgerCodes.isEmpty)
                  PremiumEmptyState(
                    message:
                        'Header ini belum punya akun postable di bawahnya.',
                    icon: Icons.account_tree_outlined,
                  )
                else if (_lines.isEmpty)
                  PremiumEmptyState(
                    message: 'admin_auto_882280b7b1'.tr(),
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
                                  AdminFormat.date(context, 'dd MMM yyyy')
                                      .format(l.tanggal),
                                  style: TextStyle(
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
                              Icon(Icons.chevron_right_rounded,
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
                                style: TextStyle(
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
