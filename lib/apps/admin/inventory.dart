// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'delivery_order.dart';
import 'logistics_tracking_page.dart';
import 'stock_move_report.dart';
import 'barcode_scanner.dart';
import 'restore_operation.dart';
import 'global_notification.dart';
import 'request_order_page.dart';
import 'request_order_pusat_page.dart';
import 'verifikasi_terima.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/logistics/stock_actor_gate.dart';
import '../../shared/logistics/stock_integrity_service.dart';
import '../../shared/logistics/logistics_tracking_rules.dart';
import '../../shared/logistics/quick_stock_scan_rules.dart';
import '../../shared/logistics/quick_stock_scan_service.dart';
import '../../shared/logistics/request_order_rules.dart';
import '../../shared/logistics/stock_leak_rules.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/logistics/warehouse_asset_rules.dart';
import '../../shared/logistics/write_off_rules.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'write_off_dialog.dart';

// ============================================================================
// MODUL 05: ENTERPRISE INVENTORY ASSET CONTROL & VALUATION SYSTEM
// ============================================================================
class InventoryOverview extends StatefulWidget {
  final Map<String, dynamic> profile;
  const InventoryOverview({super.key, required this.profile});

  @override
  State<InventoryOverview> createState() => _InventoryOverviewState();
}

class _InventoryOverviewState extends State<InventoryOverview> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = true;

  // --- CORPORATE INVENTORY ACCOUNTING MATRIX STATE ---
  int totalAssetValuation =
      0; // Aset pokok gudang = stok fisik × harga_modal (bukan GL 1201)
  int totalPotentialRevenue =
      0; // Estimasi total nilai omzet jika seluruh barang terjual habis
  int totalPotentialMargin =
      0; // Proyeksi total laba kotor yang bisa diraih gudang
  int totalVolumeItem = 0; // Akumulasi kuantitas fisik seluruh barang (PCS)

  @override
  void initState() {
    super.initState();
    _fetchInventoryFinancials();
  }

  // Helper untuk memformat angka integer menjadi mata uang Rupiah lokal nasional
  String _formatRupiah(int nominal) {
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
        .format(nominal);
  }

  Future<void> _showWriteOffDialog() async {
    final toko = AttendanceAdminScope.tokoOf(widget.profile).toUpperCase();
    if (!WriteOffRules.bolehWriteOffToko(widget.profile, toko)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Hanya admin toko/cabang ini yang boleh catat stok rusak.',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    final ok = await showWriteOffDialog(
      context: context,
      profile: widget.profile,
    );
    if (ok && mounted) {
      _fetchInventoryFinancials();
    }
  }

  Future<void> _runIntegrityCheck() async {
    if (!StockLeakRules.bolehBuka(widget.profile)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Hanya admin toko/pusat yang boleh cek kebocoran stok.',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    final progress = ValueNotifier<StockLeakProgress>(
      const StockLeakProgress(
        percent: 0,
        phase: 'Menyiapkan pengecekan…',
      ),
    );

    // Dialog progress premium — bukan spinner "lemot"
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: R.constrainedDialog(
          context: ctx,
          preferWidth: 420,
          child: AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: ValueListenableBuilder<StockLeakProgress>(
              valueListenable: progress,
              builder: (_, p, __) => _LeakCheckProgressBody(progress: p),
            ),
          ),
        ),
      ),
    );

    try {
      final toko = AttendanceAdminScope.tokoOf(widget.profile).toUpperCase();
      final hub = StockLeakRules.scanSemuaToko(widget.profile);
      final report = await StockIntegrityService().runLeakCheck(
        onProgress: (p) {
          progress.value = p;
        },
        tokoIds: hub ? null : AttendanceAdminScope.storeIdAliases(toko),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // tutup progress
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _showLeakReportDialog(report);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Gagal cek kebocoran: $e\n'
          'Paste seal 000043 (stock_leak_scan) di SQL Editor jika belum.',
        ),
        backgroundColor: OptikAdminTokens.danger,
      ));
    } finally {
      progress.dispose();
    }
  }

  Future<void> _showLeakReportDialog(StockLeakReport report) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => R.constrainedDialog(
        context: ctx,
        preferWidth: 560,
        child: AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          actionsPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 14),
          content: SizedBox(
            width: double.maxFinite,
            height: 620,
            child: _LeakCheckResultBody(
              report: report,
              onRecognize: (issue) async {
                Navigator.pop(ctx);
                await _reconcileLeak(issue);
              },
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: report.isClean
                      ? OptikAdminTokens.navy
                      : OptikAdminTokens.warning,
                  foregroundColor: OptikAdminTokens.bg,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  report.isClean ? 'Selesai' : 'Tutup',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reconcileLeak(StockIntegrityIssue issue) async {
    if (!StockLeakRules.bolehRecognizeToko(widget.profile, issue.tokoId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Hanya admin toko/cabang ini yang boleh catat selisih stok.',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    final allowed = await StockActorGate.requireMatchingViaKaryawanQr(
      context: context,
      profile: widget.profile,
      actionLabel: 'catat selisih kebocoran stok',
    );
    if (!allowed || !mounted) return;

    final alasanCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Catat selisih ke ledger',
          style: TextStyle(color: OptikAdminTokens.navy, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${issue.sku} @ ${issue.tokoId}\n'
              'Stok fisik tetap ${issue.stock}.\n'
              'Jejak ledger ${issue.ledgerSum} akan ditambah '
              'catatan selisih ${issue.delta > 0 ? '+' : ''}${issue.delta} '
              'agar rumus stok = jejak kembali cocok.\n\n'
              'Ini TIDAK mengubah jumlah barang di rak — hanya melengkapi '
              'jejak supaya kebocoran terdata.',
              style: const TextStyle(color: OptikAdminTokens.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: alasanCtrl,
              style: const TextStyle(color: OptikAdminTokens.navy),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Penjelasan selisih (wajib)',
                labelStyle: TextStyle(color: OptikAdminTokens.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Catat'),
          ),
        ],
      ),
    );
    final alasan = alasanCtrl.text;
    alasanCtrl.dispose();
    if (ok != true || !mounted) return;
    if (!StockLeakRules.alasanCukup(alasan)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Alasan wajib diisi (min. ${StockLeakRules.minAlasanChars} karakter).',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }

    try {
      await StockIntegrityService().recognizeVariance(
        issue: issue,
        alasan: alasan,
        actorNama:
            (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selisih tercatat. Cek ulang untuk pastikan AMAN.'),
        backgroundColor: OptikAdminTokens.success,
      ));
      await _runIntegrityCheck();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Gagal catat selisih: $e\n'
          'Paste seal 000043 (recognize_stock_variance) di SQL Editor jika belum.',
        ),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  // Helper mengubah nilai ukuran lensa optik agar seragam (+0.25 / -1.00)
  String _formatOpticLocal(dynamic val) {
    if (val == null || val.toString().isEmpty) return "0.00";
    double v = double.tryParse(val.toString()) ?? 0.00;
    if (v == 0) return "0.00";
    return v >= 0 ? "+${v.toStringAsFixed(2)}" : v.toStringAsFixed(2);
  }

  // 🏛️ ENTERPRISE ENGINE: Agregasi Nilai Finansial Aset Persediaan Langsung dari Database
  Future<void> _fetchInventoryFinancials() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final userTokoId =
          AttendanceAdminScope.tokoOf(widget.profile).toUpperCase();
      final isPusat = userTokoId == 'PUSAT' || userTokoId == 'CABANG-PUSAT';
      final tenant = AttendanceAdminScope.tenantIdOf(widget.profile);

      var totals = const (aset: 0, omzet: 0, margin: 0, volume: 0);
      var fromRpc = false;
      try {
        final raw = await supabase.rpc(
          'warehouse_asset_neraca',
          params: {'p_toko': isPusat ? 'PUSAT' : userTokoId},
        );
        final parsed = WarehouseAssetRules.fromRpc(raw);
        if (parsed != null) {
          totals = parsed;
          fromRpc = true;
        }
      } catch (e) {
        debugPrint('warehouse_asset_neraca: $e');
      }

      if (!fromRpc) {
        const pageSize = 1000;
        var from = 0;
        final rows = <Map<String, dynamic>>[];
        while (true) {
          var query = supabase
              .from('products')
              .select(
                'stock, reserved_qty, harga_modal, harga, harga_jual, toko_id',
              );
          if (tenant != null && tenant.isNotEmpty) {
            query = query.eq('tenant_id', tenant);
          }
          if (!isPusat) {
            query = query.eq('toko_id', userTokoId);
          }
          final res = await query.range(from, from + pageSize - 1);
          final chunk = List<Map<String, dynamic>>.from(res as List);
          rows.addAll(chunk);
          if (chunk.length < pageSize) break;
          from += pageSize;
        }
        totals = WarehouseAssetRules.fromProducts(rows);
      }

      setState(() {
        totalAssetValuation = totals.aset;
        totalPotentialRevenue = totals.omzet;
        totalPotentialMargin = totals.margin;
        totalVolumeItem = totals.volume;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("❌ Gagal menyusun neraca aset persediaan: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isPusat = widget.profile['toko_id'] == 'PUSAT';

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "inv_title".tr(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: OptikAdminTokens.navy, size: 20),
            onPressed: _fetchInventoryFinancials,
          )
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                PremiumSectionHeader(
                  label: 'Neraca kapitalisasi aset gudang',
                  padding: const EdgeInsets.only(bottom: 12),
                ),
                PremiumStatGrid(
                  items: [
                    PremiumStatItem(
                      label: 'Aset Pokok (HPP)',
                      value: _formatRupiah(totalAssetValuation),
                      color: OptikAdminTokens.navy,
                    ),
                    PremiumStatItem(
                      label: 'Potensi Omzet',
                      value: _formatRupiah(totalPotentialRevenue),
                      color: OptikAdminTokens.success,
                    ),
                    PremiumStatItem(
                      label: 'Proyeksi Margin',
                      value: _formatRupiah(totalPotentialMargin),
                      color: OptikAdminTokens.navy,
                    ),
                    PremiumStatItem(
                      label: 'Total Volume',
                      value: '$totalVolumeItem PCS',
                      color: OptikAdminTokens.textPrimary,
                    ),
                  ],
                ),

                const SizedBox(height: 22),
                PremiumSectionHeader(label: "inv_logistics".tr()),

                PremiumListTile(
                  title: isPusat ? "inv_do_title".tr() : "inv_retur_title".tr(),
                  subtitle: isPusat ? "inv_do_desc".tr() : "inv_retur_desc".tr(),
                  icon: isPusat
                      ? Icons.local_shipping_rounded
                      : Icons.assignment_return_rounded,
                  iconColor: OptikAdminTokens.navy,
                  onTap: () {
                    if (isPusat) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              OutgoingOperation(profile: widget.profile),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              RestoreOperation(profile: widget.profile),
                        ),
                      );
                    }
                  },
                ),

                PremiumListTile(
                  title: "inv_smr_title".tr(),
                  subtitle: "inv_smr_desc".tr(),
                  icon: Icons.receipt_long_rounded,
                  iconColor: OptikAdminTokens.navy,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) =>
                            StockMoveReport(profile: widget.profile),
                      ),
                    );
                  },
                ),

                PremiumListTile(
                  title: 'Verifikasi Terima Barang',
                  subtitle:
                      'Antrian DO · RO · Retur masuk cabang — foto + stok',
                  icon: Icons.fact_check_outlined,
                  iconColor: OptikAdminTokens.warning,
                  trailing: GlobalNotificationIcon(profile: widget.profile),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) =>
                            IncomingVerification(profile: widget.profile),
                      ),
                    );
                  },
                ),

                if (WriteOffRules.bolehBuka(widget.profile))
                  PremiumListTile(
                    title: 'Stok Rusak / Write-off',
                    subtitle:
                        'Scan produk · potong stok tersedia · nilai modal · jejak WRITE_OFF',
                    icon: Icons.report_gmailerrorred_rounded,
                    iconColor: OptikAdminTokens.warning,
                    onTap: _showWriteOffDialog,
                  ),

                if (StockLeakRules.bolehBuka(widget.profile))
                  PremiumListTile(
                    title: 'Cek Kebocoran Stok',
                    subtitle:
                        'Audit stok vs ledger · WRITE_OFF · paket perjalanan · POS',
                    icon: Icons.fact_check_rounded,
                    iconColor: OptikAdminTokens.success,
                    onTap: _runIntegrityCheck,
                  ),

                if (LogisticsTrackingRules.bolehBuka(widget.profile))
                  PremiumListTile(
                    title: 'Tracking Logistics',
                    subtitle:
                        'Daftar surat jalan · peta Google setelah tiba di kota tujuan',
                    icon: Icons.map_rounded,
                    iconColor: OptikAdminTokens.warning,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              LogisticsTrackingPage(profile: widget.profile),
                        ),
                      );
                    },
                  ),

                if (RequestOrderRules.bolehProsesPusat(widget.profile) ||
                    RequestOrderRules.bolehBukaCabang(widget.profile))
                  PremiumListTile(
                    title: RequestOrderRules.bolehProsesPusat(widget.profile)
                        ? 'Request Order Pusat'
                        : 'Request Order Cabang',
                    subtitle: RequestOrderRules.bolehProsesPusat(widget.profile)
                        ? 'Approval → Disiapkan → Perjalanan → Diterima'
                        : 'Kirim antrian ke Pusat · lacak · terima di Verifikasi',
                    icon: Icons.assignment_turned_in_rounded,
                    iconColor: OptikAdminTokens.trainingSoft,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) =>
                              RequestOrderRules.bolehProsesPusat(widget.profile)
                                  ? RequestOrderPusatPage(
                                      profile: widget.profile)
                                  : RequestOrderPage(profile: widget.profile),
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 12),
                PremiumSectionHeader(label: "inv_quick_tools".tr()),

                if (QuickStockScanRules.bolehBuka(widget.profile))
                  PremiumListTile(
                    title: "inv_quick_scan".tr(),
                    subtitle: "inv_quick_scan_desc".tr(),
                    icon: Icons.qr_code_scanner_rounded,
                    iconColor: OptikAdminTokens.success,
                    onTap: () {
                      if (!QuickStockScanRules.bolehScanToko(
                        widget.profile,
                        AttendanceAdminScope.tokoOf(widget.profile),
                      )) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Hanya admin toko/cabang ini yang boleh pindai stok.',
                            ),
                            backgroundColor: OptikAdminTokens.warning,
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => OptikBRiskiScanner(
                            onDetect: (code) async {
                              _handleQuickCheck(context, code);
                            },
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

// 🔥 FUNGSI CEK DATA STOK REAL-TIME KORPORAT BERBASIS FINANCIAL AUDIT HARGA MODAL & MARGIN PROFIT
  Future<void> _handleQuickCheck(BuildContext context, String code) async {
    try {
      final product = await QuickStockScanService().lookup(
        profile: widget.profile,
        code: code,
      );

      if (!context.mounted) return;
      if (product != null) {
        int modal = ProductIdentity.modalPriceOf(
          Map<String, dynamic>.from(product),
        );
        int jual = ProductIdentity.sellPriceOf(product);
        int marginItem = jual - modal;
        double pctMargin = jual > 0 ? (marginItem / jual) * 100 : 0.0;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Row(
              children: [
                const Icon(Icons.analytics_rounded,
                    color: OptikAdminTokens.navy, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(product['nama'] ?? 'inv_detail_produk'.tr(),
                        style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontSize: 14,
                            fontWeight: FontWeight.bold))),
              ],
            ),
            content: R.constrainedDialog(
              context: context,
              preferWidth: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(
                        'Real',
                        "${StockQty.realOf(Map<String, dynamic>.from(product))} PCS",
                        OptikAdminTokens.success),
                    _infoRow(
                        'Booking',
                        "${StockQty.pendingOf(Map<String, dynamic>.from(product))} PCS",
                        OptikAdminTokens.warning),
                    _infoRow(
                        'Tersedia',
                        "${StockQty.availableOf(Map<String, dynamic>.from(product))} PCS",
                        OptikAdminTokens.ice),
                    _infoRow("inv_kategori".tr(), product['kategori'] ?? '-',
                        OptikAdminTokens.textSecondary),
                    const Divider(color: OptikAdminTokens.line, height: 16),
                    const Text("📊 STRUKTUR AKUNTANSI ASSET PROD",
                        style: TextStyle(
                            color: OptikAdminTokens.warning,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    _infoRow("Harga Pokok (HPP)", _formatRupiah(modal),
                        OptikAdminTokens.snow),
                    _infoRow("Harga Jual Retail", _formatRupiah(jual),
                        OptikAdminTokens.ice),
                    _infoRow("Margin Bersih / Pcs", _formatRupiah(marginItem),
                        OptikAdminTokens.ice),
                    _infoRow(
                        "Gross Profit Margin",
                        "${pctMargin.toStringAsFixed(1)} %",
                        pctMargin >= 50
                            ? OptikAdminTokens.success
                            : OptikAdminTokens.warning),
                    const Divider(color: OptikAdminTokens.line, height: 16),
                    if (product['kategori'] == 'Frame' &&
                        product['warna'] != null)
                      _infoRow("inv_warna_frame".tr(), product['warna'],
                          OptikAdminTokens.warning),
                    if (product['kategori'] == 'Lensa') ...[
                      _infoRow("inv_jenis_lensa".tr(),
                          product['jenis_lensa'] ?? '-', OptikAdminTokens.warning),
                      _infoRow("SPH", _formatOpticLocal(product['sph_r']),
                          OptikAdminTokens.ice),
                      _infoRow("CYL", _formatOpticLocal(product['cyl_r']),
                          OptikAdminTokens.ice),
                      if (product['jenis_lensa'] == 'Progresif' ||
                          product['jenis_lensa'] == 'Kryptok')
                        _infoRow("ADD", _formatOpticLocal(product['add_r']),
                            OptikAdminTokens.slate),
                    ],
                    const SizedBox(height: 12),
                    if (ProductIdentity.catalogImageOf(product).isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                            ProductIdentity.catalogImageOf(product),
                            height: 110,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(
                                Icons.image_not_supported,
                                color: OptikAdminTokens.line,
                                size: 40)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("inv_mengerti".tr(),
                      style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)))
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("inv_not_found".tr()),
            backgroundColor: OptikAdminTokens.danger));
      }
    } catch (e) {
      debugPrint("❌ Gagal rekonsiliasi data audit item: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
    }
  }

  Widget _infoRow(String label, String val, Color valColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11.5)),
          Text(val,
              style: TextStyle(
                  color: valColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

}

/// Hasil audit kebocoran — kategori ringkas, ketuk untuk lihat detail.
class _LeakCheckResultBody extends StatefulWidget {
  const _LeakCheckResultBody({
    required this.report,
    required this.onRecognize,
  });

  final StockLeakReport report;
  final Future<void> Function(StockIntegrityIssue issue) onRecognize;

  @override
  State<_LeakCheckResultBody> createState() => _LeakCheckResultBodyState();
}

class _LeakCheckResultBodyState extends State<_LeakCheckResultBody> {
  String? _expandedKey;

  StockLeakReport get report => widget.report;

  String _tokoLabel(String id) {
    final t = id.trim().toUpperCase();
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  List<MapEntry<String, int>> _sortedDesc(Map<String, int> map) {
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  void _toggle(String key) {
    setState(() => _expandedKey = _expandedKey == key ? null : key);
  }

  @override
  Widget build(BuildContext context) {
    final clean = report.isClean;
    final accent = clean ? OptikAdminTokens.success : OptikAdminTokens.warning;
    final pusatQty = report.stockByToko['PUSAT'] ?? 0;
    final cabangEntries = _sortedDesc(
      Map.fromEntries(
        report.stockByToko.entries.where((e) => e.key != 'PUSAT'),
      ),
    );
    final cabangTotal =
        cabangEntries.fold<int>(0, (s, e) => s + e.value);
    final soldEntries = _sortedDesc(report.soldByToko30d);

    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withOpacity(0.18),
                accent.withOpacity(0.04),
                OptikAdminTokens.snow.withOpacity(0.02),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.15),
                  border: Border.all(color: accent.withOpacity(0.5), width: 2),
                ),
                child: Icon(
                  clean
                      ? Icons.verified_user_rounded
                      : Icons.warning_amber_rounded,
                  color: accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                clean ? 'Sistem aman' : 'Ada indikasi bocor',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                report.verdict,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikAdminTokens.navy.withOpacity(0.72),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${report.checkedProducts} baris dicek · ketuk kategori di bawah untuk detail',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikAdminTokens.navy.withOpacity(0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'HASIL PER KATEGORI',
          style: TextStyle(
            color: OptikAdminTokens.navy.withOpacity(0.45),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Paket perjalanan = normal (bukan bocor). Selisih = stok ≠ jejak ledger.',
          style: TextStyle(
            color: OptikAdminTokens.navy.withOpacity(0.38),
            fontSize: 11,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),

        _categoryTile(
          keyName: 'transit',
          icon: Icons.local_shipping_rounded,
          title: 'Paket perjalanan',
          countLabel: '${report.openTransitQty}',
          unit: 'pcs',
          color: OptikAdminTokens.navy,
          detail: _transitDetail(),
        ),
        _categoryTile(
          keyName: 'pusat',
          icon: Icons.warehouse_rounded,
          title: 'Stok Pusat',
          countLabel: '$pusatQty',
          unit: 'pcs',
          color: OptikAdminTokens.navy,
          detail: _stockLinesDetail('PUSAT'),
        ),
        _categoryTile(
          keyName: 'cabang',
          icon: Icons.store_mall_directory_rounded,
          title: 'Stok Cabang',
          countLabel: '$cabangTotal',
          unit: '${cabangEntries.length} lokasi',
          color: OptikAdminTokens.navy,
          detail: _cabangStockDetail(cabangEntries),
        ),
        _categoryTile(
          keyName: 'pos',
          icon: Icons.point_of_sale_rounded,
          title: 'Terjual POS (30 hari)',
          countLabel: '${report.totalSold30d}',
          unit: 'pcs',
          color: OptikAdminTokens.warning,
          detail: _posDetail(soldEntries),
        ),
        _categoryTile(
          keyName: 'writeoff',
          icon: Icons.report_gmailerrorred_rounded,
          title: 'Stok rusak / WRITE_OFF',
          countLabel: '${report.writeOffQty}',
          unit: 'pcs',
          color: report.writeOffQty == 0
              ? OptikAdminTokens.textSecondary
              : OptikAdminTokens.warning,
          detail: _emptyDetail(
            report.writeOffQty == 0
                ? 'Belum ada jejak WRITE_OFF di toko ini. '
                    'Catat rusak lewat Stok Rusak — bukan lewat selisih kebocoran.'
                : '${report.writeOffQty} pcs sudah dipotong write_off_stock '
                    'dan masuk Σ ledger. Ini jejak resmi — bukan kebocoran.',
          ),
        ),
        _categoryTile(
          keyName: 'selisih',
          icon: Icons.warning_amber_rounded,
          title: 'Selisih / Bocor',
          countLabel: '${report.mismatches.length}',
          unit: 'item',
          color: report.mismatches.isEmpty
              ? OptikAdminTokens.success
              : OptikAdminTokens.warning,
          detail: _selisihDetail(),
        ),
        _categoryTile(
          keyName: 'nosku',
          icon: Icons.qr_code_2_rounded,
          title: 'SKU Lemah / NOSKU',
          countLabel: '${report.missingSkuCount}',
          unit: 'produk',
          color: report.missingSkuCount == 0
              ? OptikAdminTokens.textSecondary
              : OptikAdminTokens.warning,
          detail: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              report.missingSkuCount == 0
                  ? 'Semua produk punya SKU valid.'
                  : '${report.missingSkuCount} baris produk tanpa SKU / NOSKU. '
                      'Lengkapi di Master Produk agar jejak ledger bisa dilacak.',
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.55),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: OptikAdminTokens.navy.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OptikAdminTokens.line),
          ),
          child: Text(
            'Rumus: stok toko = Σ ledger (+/−) per SKU · lokasi, termasuk WRITE_OFF. '
            'Stok rusak yang sudah dicatat bukan bocor. '
            'Angka beda = kebocoran. Catat selisih melengkapi jejak tanpa mengubah stok rak.',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.4),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryTile({
    required String keyName,
    required IconData icon,
    required String title,
    required String countLabel,
    required String unit,
    required Color color,
    required Widget detail,
  }) {
    final open = _expandedKey == keyName ||
        (_expandedKey?.startsWith('$keyName-') ?? false);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: OptikAdminTokens.navy.withOpacity(open ? 0.05 : 0.03),
        border: Border.all(
          color: open ? color.withOpacity(0.45) : OptikAdminTokens.line,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                // Collapse nested → parent, or toggle parent closed.
                if (_expandedKey == keyName ||
                    (_expandedKey?.startsWith('$keyName-') ?? false)) {
                  setState(() => _expandedKey = null);
                } else {
                  _toggle(keyName);
                }
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        color: color.withOpacity(0.14),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Text(
                        countLabel,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      unit,
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.4),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: OptikAdminTokens.textMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: OptikAdminTokens.navy.withOpacity(0.08)),
            detail,
          ],
        ],
      ),
    );
  }

  Widget _emptyDetail(String msg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Text(
        msg,
        style: TextStyle(
          color: OptikAdminTokens.navy.withOpacity(0.45),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _transitDetail() {
    final items = report.openTransitItems;
    if (items.isEmpty) {
      return _emptyDetail(
        'Tidak ada paket Disiapkan / dalam perjalanan. Ini normal — bukan kebocoran.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              'Informasi saja — stok sudah / sedang dipindah lewat DO·RO·Retur.',
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.42),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
          ...items.map((t) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: OptikAdminTokens.navy.withOpacity(0.03),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: OptikAdminTokens.navy.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                t.kindLabel,
                                style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                t.resi,
                                style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_tokoLabel(t.fromToko)} → ${_tokoLabel(t.toToko)}',
                          style: TextStyle(
                            color: OptikAdminTokens.navy.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.statusLabel,
                          style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${t.qty} pcs',
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _stockLinesDetail(String tokoId) {
    final lines = report.stockLinesByToko[tokoId] ?? const [];
    if (lines.isEmpty) {
      return _emptyDetail('Tidak ada SKU berstok di lokasi ini.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        children: [
          ...lines.take(30).map((l) => _skuLine(l.nama, l.sku, l.qty, 'pcs')),
          if (lines.length > 30)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${lines.length - 30} SKU lain (top 30 ditampilkan)',
                style: TextStyle(
                  color: OptikAdminTokens.navy.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cabangStockDetail(List<MapEntry<String, int>> cabangEntries) {
    if (cabangEntries.isEmpty) {
      return _emptyDetail('Belum ada stok di cabang.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        children: cabangEntries.map((e) {
          final nestedKey = 'cabang-${e.key}';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikAdminTokens.line),
              color: OptikAdminTokens.navy.withOpacity(0.02),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    // Keep parent 'cabang' conceptually open by using nested key
                    // that still shows parent because parent detail contains this.
                    setState(() {
                      if (_expandedKey == nestedKey) {
                        _expandedKey = 'cabang';
                      } else {
                        _expandedKey = nestedKey;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tokoLabel(e.key),
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value} pcs',
                          style: const TextStyle(
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Icon(
                          (_expandedKey == nestedKey)
                              ? Icons.expand_less
                              : Icons.chevron_right,
                          color: OptikAdminTokens.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expandedKey == nestedKey) _stockLinesDetail(e.key),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _posDetail(List<MapEntry<String, int>> soldEntries) {
    if (soldEntries.isEmpty) {
      return _emptyDetail('Belum ada jejak SALE 30 hari terakhir.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        children: soldEntries.map((e) {
          final nestedKey = 'pos-${e.key}';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikAdminTokens.line),
              color: OptikAdminTokens.navy.withOpacity(0.02),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (_expandedKey == nestedKey) {
                        _expandedKey = 'pos';
                      } else {
                        _expandedKey = nestedKey;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'POS ${_tokoLabel(e.key)}',
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value} terjual',
                          style: const TextStyle(
                            color: OptikAdminTokens.warning,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Icon(
                          (_expandedKey == nestedKey)
                              ? Icons.expand_less
                              : Icons.chevron_right,
                          color: OptikAdminTokens.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expandedKey == nestedKey)
                  _soldLinesDetail(e.key),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _soldLinesDetail(String tokoId) {
    final lines = report.soldLinesByToko30d[tokoId] ?? const [];
    if (lines.isEmpty) {
      return _emptyDetail('Tidak ada rincian SKU penjualan.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        children: lines
            .take(30)
            .map((l) => _skuLine(l.nama, l.sku, l.qty, 'terjual'))
            .toList(),
      ),
    );
  }

  Widget _skuLine(String nama, String sku, int qty, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sku,
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.35),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$qty $unit',
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.85),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _selisihDetail() {
    if (report.mismatches.isEmpty) {
      return _emptyDetail(
          'Tidak ada selisih. Stok sinkron penuh dengan jejak ledger.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        children: report.mismatches.take(40).map((e) {
          final deltaLabel = '${e.delta > 0 ? '+' : ''}${e.delta}';
          final reasonChips = e.ledgerByReason.entries.toList()
            ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: OptikAdminTokens.navy.withOpacity(0.03),
              border: Border.all(
                color: OptikAdminTokens.warning.withOpacity(0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.nama ?? e.sku,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      'Δ $deltaLabel',
                      style: const TextStyle(
                        color: OptikAdminTokens.warning,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'SKU ${e.sku} · ${_tokoLabel(e.tokoId)}',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.38),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stok ${e.stock}  vs  Ledger ${e.ledgerSum}',
                  style: const TextStyle(
                    color: OptikAdminTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  e.diagnosis,
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.5),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                if (reasonChips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: reasonChips.map((r) {
                      final sign = r.value > 0 ? '+' : '';
                      final c = r.value < 0
                          ? OptikAdminTokens.danger
                          : OptikAdminTokens.ice;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.withOpacity(0.4)),
                        ),
                        child: Text(
                          '${r.key} $sign${r.value}',
                          style: TextStyle(
                            color: c,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => widget.onRecognize(e),
                    icon: const Icon(Icons.playlist_add_check_rounded,
                        size: 16, color: OptikAdminTokens.navy),
                    label: const Text(
                      'Catat selisih',
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// UI progress premium untuk Cek Kebocoran Stok (persen nyata + fase).
class _LeakCheckProgressBody extends StatelessWidget {
  const _LeakCheckProgressBody({required this.progress});

  final StockLeakProgress progress;

  @override
  Widget build(BuildContext context) {
    final pct = progress.percent.clamp(0.0, 1.0);
    final pctLabel = progress.percentInt;
    final accent = pct >= 1.0 ? OptikAdminTokens.success : OptikAdminTokens.ice;

    return SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Audit Kebocoran Stok',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sedang memverifikasi jejak',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.45),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 148,
            height: 148,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 148,
                      height: 148,
                      child: CircularProgressIndicator(
                        value: value <= 0 ? null : value,
                        strokeWidth: 8,
                        backgroundColor: OptikAdminTokens.snow.withOpacity(0.08),
                        color: accent,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$pctLabel%',
                          style: TextStyle(
                            color: accent,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          progress.total > 0
                              ? '${progress.checked}/${progress.total}'
                              : 'memuat',
                          style: TextStyle(
                            color: OptikAdminTokens.navy.withOpacity(0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(
            progress.phase,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
          if ((progress.currentLabel ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Text(
                progress.currentLabel!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: OptikAdminTokens.navy.withOpacity(0.65),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Terverifikasi',
                  '${progress.checked}',
                  OptikAdminTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'Selisih',
                  '${progress.foundLeaks}',
                  progress.foundLeaks > 0
                      ? OptikAdminTokens.warning
                      : OptikAdminTokens.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct <= 0 ? null : pct,
              minHeight: 5,
              backgroundColor: OptikAdminTokens.snow.withOpacity(0.08),
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: OptikAdminTokens.navy.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
