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
import 'request_order_page.dart';
import 'request_order_pusat_page.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/logistics/stock_actor_gate.dart';
import '../../shared/logistics/stock_integrity_service.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/qr/product_code.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

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
      0; // Akun [1105] - Nilai Total Kapitalisasi Uang di Aset Barang
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
    final allowed = await StockActorGate.requireMatchingViaKaryawanQr(
      context: context,
      profile: widget.profile,
      actionLabel: 'write-off stok rusak',
    );
    if (!allowed || !mounted) return;

    final skuCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final alasanCtrl = TextEditingController();
    final toko =
        (widget.profile['toko_id'] ?? 'PUSAT').toString().toUpperCase();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text('Stok Rusak / Write-off',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Toko: $toko',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: skuCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'SKU / Barcode',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Qty rusak',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            TextField(
              controller: alasanCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan (wajib)',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('BATAL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PROSES'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      skuCtrl.dispose();
      qtyCtrl.dispose();
      alasanCtrl.dispose();
      return;
    }

    try {
      final raw = skuCtrl.text.trim();
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      final alasan = alasanCtrl.text.trim();
      skuCtrl.dispose();
      qtyCtrl.dispose();
      alasanCtrl.dispose();

      final prod = await ProductIdentity.findAtToko(
        tokoId: toko,
        sku: raw,
        barcode: raw,
      );
      final sku = ProductIdentity.normalizeSku(prod?['sku']) ??
          ProductIdentity.normalizeSku(raw) ??
          ProductIdentity.normalizeBarcode(raw);
      if (sku == null) throw 'Produk/SKU tidak ditemukan di $toko.';

      await StockMutationService().writeOff(
        tokoId: toko,
        sku: sku,
        qty: qty,
        alasan: alasan,
        actorNama:
            (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stok rusak tercatat di ledger.'),
        backgroundColor: Colors.green,
      ));
      _fetchInventoryFinancials();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal write-off: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _runIntegrityCheck() async {
    final progress = ValueNotifier<StockLeakProgress>(
      const StockLeakProgress(
        percent: 0,
        phase: 'Menyiapkan mesin audit…',
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
      final report = await StockIntegrityService().runLeakCheck(
        onProgress: (p) {
          progress.value = p;
        },
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
          'Pastikan SQL 00012 sudah dijalankan di Supabase.',
        ),
        backgroundColor: Colors.redAccent,
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
                      ? const Color(0xFF14B8A6)
                      : Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  report.isClean ? 'SELESAI' : 'TUTUP',
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: alasanCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Penjelasan selisih (wajib)',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CATAT'),
          ),
        ],
      ),
    );
    final alasan = alasanCtrl.text;
    alasanCtrl.dispose();
    if (ok != true || !mounted) return;

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
        backgroundColor: Colors.green,
      ));
      await _runIntegrityCheck();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Gagal catat selisih: $e\n'
          'Jalankan juga SQL 00013 di Supabase.',
        ),
        backgroundColor: Colors.redAccent,
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
      String userTokoId =
          widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      bool isPusat = userTokoId == 'PUSAT';

      // Query dinamis: Pusat memantau total aset konsolidasian seluruh ruko, cabang mengunci aset wilayahnya
      var query =
          supabase.from('products').select('stock, harga_modal, harga_jual');
      if (!isPusat) {
        query = query.eq('toko_id', userTokoId);
      }

      final res = await query;
      final List<Map<String, dynamic>> dataProducts =
          List<Map<String, dynamic>>.from(res);

      int akumulasiHppAset = 0;
      int akumulasiOmzetAset = 0;
      int akumulasiVolume = 0;

      for (var product in dataProducts) {
        int stok = int.tryParse(product['stock']?.toString() ?? '0') ?? 0;
        int hargaBeli =
            int.tryParse(product['harga_modal']?.toString() ?? '0') ?? 0;
        int hargaJual =
            int.tryParse(product['harga_jual']?.toString() ?? '0') ?? 0;

        // Formula Akuntansi Aset Persediaan Korporat
        if (stok > 0) {
          akumulasiHppAset += (stok *
              hargaBeli); // Nilai riil buku aset persediaan barang dagang
          akumulasiOmzetAset +=
              (stok * hargaJual); // Potensi likuidasi penjualan bruto
          akumulasiVolume += stok;
        }
      }

      setState(() {
        totalAssetValuation = akumulasiHppAset;
        totalPotentialRevenue = akumulasiOmzetAset;
        totalPotentialMargin = akumulasiOmzetAset - akumulasiHppAset;
        totalVolumeItem = akumulasiVolume;
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
                color: Colors.white, size: 20),
            onPressed: _fetchInventoryFinancials,
          )
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: OptikAdminTokens.accentSoft))
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
                      color: OptikAdminTokens.accentSoft,
                    ),
                    PremiumStatItem(
                      label: 'Potensi Omzet',
                      value: _formatRupiah(totalPotentialRevenue),
                      color: OptikAdminTokens.success,
                    ),
                    PremiumStatItem(
                      label: 'Proyeksi Margin',
                      value: _formatRupiah(totalPotentialMargin),
                      color: Colors.tealAccent,
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
                  iconColor: OptikAdminTokens.accentSoft,
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
                  iconColor: Colors.cyanAccent,
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
                  title: 'Stok Rusak / Write-off',
                  subtitle: 'Kurangi stok dengan alasan wajib (tercatat ledger)',
                  icon: Icons.report_gmailerrorred_rounded,
                  iconColor: Colors.orangeAccent,
                  onTap: _showWriteOffDialog,
                ),

                PremiumListTile(
                  title: 'Cek Kebocoran Stok',
                  subtitle:
                      'Deteksi selisih stok vs jejak ledger — wajib 0 selisih',
                  icon: Icons.fact_check_rounded,
                  iconColor: Colors.lightGreenAccent,
                  onTap: _runIntegrityCheck,
                ),

                PremiumListTile(
                  title: 'Tracking Logistics',
                  subtitle:
                      'Peta OSM gratis · status DO/RO/Retur · assign kurir',
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

                PremiumListTile(
                  title: isPusat
                      ? 'Request Order Pusat'
                      : 'Request Order Cabang',
                  subtitle: isPusat
                      ? 'Approval → Preparing → Shipping → Success + reservasi stok'
                      : 'Kirim antrean ke Pusat & lacak status',
                  icon: Icons.assignment_turned_in_rounded,
                  iconColor: OptikAdminTokens.trainingSoft,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => isPusat
                            ? RequestOrderPusatPage(profile: widget.profile)
                            : RequestOrderPage(profile: widget.profile),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),
                PremiumSectionHeader(label: "inv_quick_tools".tr()),

                PremiumListTile(
                  title: "inv_quick_scan".tr(),
                  subtitle: "inv_quick_scan_desc".tr(),
                  icon: Icons.qr_code_scanner_rounded,
                  iconColor: OptikAdminTokens.success,
                  onTap: () {
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
      final parsed = ProductCode.parse(code);
      final sku = (parsed?.sku ?? ProductCode.resolveSku(code) ?? '').trim();
      final productId = parsed?.productId;
      final tokoId = widget.profile['toko_id'];

      Map<String, dynamic>? res;
      if (productId != null && productId.isNotEmpty) {
        res = await supabase
            .from('products')
            .select()
            .eq('id', productId)
            .eq('toko_id', tokoId)
            .maybeSingle();
      }
      if (res == null && sku.isNotEmpty) {
        res = await supabase
            .from('products')
            .select()
            .eq('sku', sku)
            .eq('toko_id', tokoId)
            .maybeSingle();
      }
      if (res == null && sku.isNotEmpty) {
        res = await supabase
            .from('products')
            .select()
            .eq('barcode', sku)
            .eq('toko_id', tokoId)
            .maybeSingle();
      }

      if (!context.mounted) return;

      final product = res;
      if (product != null) {
        int modal =
            int.tryParse(product['harga_modal']?.toString() ?? '0') ?? 0;
        int jual = int.tryParse(product['harga_jual']?.toString() ?? '0') ?? 0;
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
                    color: Colors.blueAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(product['nama'] ?? 'inv_detail_produk'.tr(),
                        style: const TextStyle(
                            color: Colors.white,
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
                        Colors.greenAccent),
                    _infoRow(
                        'Pending',
                        "${StockQty.pendingOf(Map<String, dynamic>.from(product))} PCS",
                        Colors.orangeAccent),
                    _infoRow(
                        'Tersedia / Total jual',
                        "${StockQty.availableOf(Map<String, dynamic>.from(product))} PCS",
                        const Color(0xFF2DD4BF)),
                    _infoRow("inv_kategori".tr(), product['kategori'] ?? '-',
                        Colors.white70),
                    const Divider(color: Colors.white10, height: 16),
                    const Text("📊 STRUKTUR AKUNTANSI ASSET PROD",
                        style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    _infoRow("Harga Pokok (HPP)", _formatRupiah(modal),
                        Colors.white),
                    _infoRow("Harga Jual Retail", _formatRupiah(jual),
                        Colors.blueAccent),
                    _infoRow("Margin Bersih / Pcs", _formatRupiah(marginItem),
                        Colors.tealAccent),
                    _infoRow(
                        "Gross Profit Margin",
                        "${pctMargin.toStringAsFixed(1)} %",
                        pctMargin >= 50
                            ? Colors.greenAccent
                            : Colors.orangeAccent),
                    const Divider(color: Colors.white10, height: 16),
                    if (product['kategori'] == 'Frame' &&
                        product['warna'] != null)
                      _infoRow("inv_warna_frame".tr(), product['warna'],
                          Colors.orangeAccent),
                    if (product['kategori'] == 'Lensa') ...[
                      _infoRow("inv_jenis_lensa".tr(),
                          product['jenis_lensa'] ?? '-', Colors.orangeAccent),
                      _infoRow("SPH", _formatOpticLocal(product['sph_r']),
                          Colors.cyanAccent),
                      _infoRow("CYL", _formatOpticLocal(product['cyl_r']),
                          Colors.cyanAccent),
                      if (product['jenis_lensa'] == 'Progresif' ||
                          product['jenis_lensa'] == 'Kryptok')
                        _infoRow("ADD", _formatOpticLocal(product['add_r']),
                            Colors.purpleAccent),
                    ],
                    const SizedBox(height: 12),
                    if (product['image_url'] != null &&
                        product['image_url'] != '-')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(product['image_url'],
                            height: 110,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(
                                Icons.image_not_supported,
                                color: Colors.white10,
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
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)))
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("inv_not_found".tr()),
            backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      debugPrint("❌ Gagal rekonsiliasi data audit item: $e");
    }
  }

  Widget _infoRow(String label, String val, Color valColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
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
    final accent = clean ? const Color(0xFF34D399) : const Color(0xFFFBBF24);
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
                Colors.white.withOpacity(0.02),
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
                clean ? 'SISTEM AMAN' : 'ADA INDIKASI BOCOR',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                report.verdict,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${report.checkedProducts} baris dicek · ketuk kategori di bawah untuk detail',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
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
            color: Colors.white.withOpacity(0.45),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),

        _categoryTile(
          keyName: 'transit',
          icon: Icons.local_shipping_rounded,
          title: 'Transit',
          countLabel: '${report.openTransitQty}',
          unit: 'pcs',
          color: Colors.lightBlueAccent,
          detail: _transitDetail(),
        ),
        _categoryTile(
          keyName: 'pusat',
          icon: Icons.warehouse_rounded,
          title: 'Stok Pusat',
          countLabel: '$pusatQty',
          unit: 'pcs',
          color: const Color(0xFF2DD4BF),
          detail: _stockLinesDetail('PUSAT'),
        ),
        _categoryTile(
          keyName: 'cabang',
          icon: Icons.store_mall_directory_rounded,
          title: 'Stok Cabang',
          countLabel: '$cabangTotal',
          unit: '${cabangEntries.length} lokasi',
          color: const Color(0xFF60A5FA),
          detail: _cabangStockDetail(cabangEntries),
        ),
        _categoryTile(
          keyName: 'pos',
          icon: Icons.point_of_sale_rounded,
          title: 'Terjual POS (30 hari)',
          countLabel: '${report.totalSold30d}',
          unit: 'pcs',
          color: const Color(0xFFFBBF24),
          detail: _posDetail(soldEntries),
        ),
        _categoryTile(
          keyName: 'selisih',
          icon: Icons.warning_amber_rounded,
          title: 'Selisih / Bocor',
          countLabel: '${report.mismatches.length}',
          unit: 'item',
          color: report.mismatches.isEmpty
              ? const Color(0xFF34D399)
              : const Color(0xFFFBBF24),
          detail: _selisihDetail(),
        ),
        _categoryTile(
          keyName: 'nosku',
          icon: Icons.qr_code_2_rounded,
          title: 'SKU Lemah / NOSKU',
          countLabel: '${report.missingSkuCount}',
          unit: 'produk',
          color: report.missingSkuCount == 0
              ? Colors.white60
              : Colors.orangeAccent,
          detail: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              report.missingSkuCount == 0
                  ? 'Semua produk punya SKU valid.'
                  : '${report.missingSkuCount} baris produk tanpa SKU / NOSKU. '
                      'Lengkapi di Product Master agar jejak ledger bisa dilacak.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
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
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            'Rumus: stok toko = Σ ledger (+/−) per SKU. '
            'Bedanya angka = kebocoran.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
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
        color: Colors.white.withOpacity(open ? 0.05 : 0.03),
        border: Border.all(
          color: open ? color.withOpacity(0.45) : Colors.white10,
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
                          color: Colors.white,
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
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.white54,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: Colors.white.withOpacity(0.08)),
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
          color: Colors.white.withOpacity(0.45),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _transitDetail() {
    final items = report.openTransitItems;
    if (items.isEmpty) {
      return _emptyDetail('Tidak ada paket sedang transit / preparing.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        children: items.map((t) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.03),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.resi,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_tokoLabel(t.fromToko)} → ${_tokoLabel(t.toToko)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.status,
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
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
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
                  color: Colors.white.withOpacity(0.4),
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
              border: Border.all(color: Colors.white10),
              color: Colors.white.withOpacity(0.02),
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
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value} pcs',
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Icon(
                          (_expandedKey == nestedKey)
                              ? Icons.expand_less
                              : Icons.chevron_right,
                          color: Colors.white38,
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
              border: Border.all(color: Colors.white10),
              color: Colors.white.withOpacity(0.02),
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
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value} terjual',
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Icon(
                          (_expandedKey == nestedKey)
                              ? Icons.expand_less
                              : Icons.chevron_right,
                          color: Colors.white38,
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
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sku,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$qty $unit',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
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
              color: Colors.white.withOpacity(0.03),
              border: Border.all(
                color: const Color(0xFFFBBF24).withOpacity(0.28),
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
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      'Δ $deltaLabel',
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'SKU ${e.sku} · ${_tokoLabel(e.tokoId)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.38),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stok ${e.stock}  vs  Ledger ${e.ledgerSum}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  e.diagnosis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
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
                          ? const Color(0xFFF87171)
                          : const Color(0xFF2DD4BF);
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
                        size: 16, color: Color(0xFF2DD4BF)),
                    label: const Text(
                      'CATAT SELISIH',
                      style: TextStyle(
                        color: Color(0xFF2DD4BF),
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
    final accent = pct >= 1.0 ? Colors.greenAccent : const Color(0xFF2DD4BF);

    return SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Audit Kebocoran Stok',
            style: TextStyle(
              color: Colors.white,
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
              color: Colors.white.withOpacity(0.45),
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
                        backgroundColor: Colors.white.withOpacity(0.08),
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
                              : 'scan',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
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
              color: Colors.white,
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
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                progress.currentLabel!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
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
                  Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(
                  'Selisih',
                  '${progress.foundLeaks}',
                  progress.foundLeaks > 0
                      ? Colors.orangeAccent
                      : Colors.greenAccent,
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
              backgroundColor: Colors.white.withOpacity(0.08),
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
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
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
