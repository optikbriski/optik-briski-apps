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

  Future<void> _showReviseStockDialog() async {
    final allowed = await StockActorGate.requireMatchingViaKaryawanQr(
      context: context,
      profile: widget.profile,
      actionLabel: 'revisi stok',
    );
    if (!allowed || !mounted) return;

    final skuCtrl = TextEditingController();
    final newStockCtrl = TextEditingController();
    final alasanCtrl = TextEditingController();
    final toko =
        (widget.profile['toko_id'] ?? 'PUSAT').toString().toUpperCase();
    String? previewText;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> lookup() async {
              final raw = skuCtrl.text.trim();
              if (raw.isEmpty) return;
              final prod = await ProductIdentity.findAtToko(
                tokoId: toko,
                sku: raw,
                barcode: raw,
              );
              if (!ctx.mounted) return;
              if (prod == null) {
                setLocal(() => previewText = 'Produk tidak ditemukan di $toko');
                return;
              }
              final stok =
                  int.tryParse(prod['stock']?.toString() ?? '0') ?? 0;
              setLocal(() {
                previewText =
                    '${prod['nama']} · stok sekarang: $stok pcs';
                if (newStockCtrl.text.trim().isEmpty) {
                  newStockCtrl.text = stok.toString();
                }
              });
            }

            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              title: const Text(
                'Revisi Stok',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Toko: $toko\n'
                    'Isi stok hasil hitung fisik. Sistem hitung selisih '
                    'otomatis dan catat sebagai ADJUST (wajib alasan).',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: skuCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'SKU / Barcode',
                      labelStyle: const TextStyle(color: Colors.white54),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search, color: Colors.white54),
                        onPressed: lookup,
                      ),
                    ),
                    onSubmitted: (_) => lookup(),
                  ),
                  if (previewText != null) ...[
                    const SizedBox(height: 8),
                    Text(previewText!,
                        style: const TextStyle(
                            color: Colors.tealAccent, fontSize: 12)),
                  ],
                  TextField(
                    controller: newStockCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Stok baru (hasil hitung)',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                  TextField(
                    controller: alasanCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alasan revisi (wajib)',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Contoh: stock opname Maret / selisih fisik',
                      hintStyle: TextStyle(color: Colors.white24),
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
                  child: const Text('SIMPAN REVISI'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) {
      skuCtrl.dispose();
      newStockCtrl.dispose();
      alasanCtrl.dispose();
      return;
    }

    try {
      final raw = skuCtrl.text.trim();
      final newStock = int.tryParse(newStockCtrl.text.trim());
      final alasan = alasanCtrl.text.trim();
      skuCtrl.dispose();
      newStockCtrl.dispose();
      alasanCtrl.dispose();

      if (newStock == null) throw 'Stok baru tidak valid.';
      final prod = await ProductIdentity.findAtToko(
        tokoId: toko,
        sku: raw,
        barcode: raw,
      );
      final sku = ProductIdentity.normalizeSku(prod?['sku']) ??
          ProductIdentity.normalizeSku(raw) ??
          ProductIdentity.normalizeBarcode(raw);
      if (sku == null) throw 'Produk/SKU tidak ditemukan di $toko.';

      final before = int.tryParse(prod?['stock']?.toString() ?? '0') ?? 0;
      await StockMutationService().reviseTo(
        tokoId: toko,
        sku: sku,
        newStock: newStock,
        alasan: alasan,
        actorNama:
            (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString(),
      );

      if (!mounted) return;
      final delta = newStock - before;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Revisi tercatat: $before → $newStock '
          '(${delta >= 0 ? '+' : ''}$delta) · alasan wajib tersimpan.',
        ),
        backgroundColor: Colors.green,
      ));
      _fetchInventoryFinancials();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal revisi stok: $e'),
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
            height: 520,
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
                  title: 'Revisi Stok',
                  subtitle:
                      'Stock opname / koreksi: set stok baru + alasan (ADJUST)',
                  icon: Icons.edit_note_rounded,
                  iconColor: Colors.amberAccent,
                  onTap: _showReviseStockDialog,
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
                    _infoRow("inv_stok_saat_ini".tr(),
                        "${product['stock'] ?? 0} PCS", Colors.greenAccent),
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

/// Hasil audit kebocoran — tampilan premium (status hero + kartu metrik).
class _LeakCheckResultBody extends StatelessWidget {
  const _LeakCheckResultBody({
    required this.report,
    required this.onRecognize,
  });

  final StockLeakReport report;
  final Future<void> Function(StockIntegrityIssue issue) onRecognize;

  @override
  Widget build(BuildContext context) {
    final clean = report.isClean;
    final accent = clean ? const Color(0xFF34D399) : const Color(0xFFFBBF24);

    return ListView(
      children: [
        // Hero status
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
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.15),
                  border: Border.all(color: accent.withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.25),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  clean
                      ? Icons.verified_user_rounded
                      : Icons.warning_amber_rounded,
                  color: accent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                clean ? 'SISTEM AMAN' : 'ADA INDIKASI BOCOR',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                report.verdict,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Metric grid
        Row(
          children: [
            Expanded(
              child: _resultStat(
                'Dicek',
                '${report.checkedProducts}',
                'baris',
                const Color(0xFF2DD4BF),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _resultStat(
                'Selisih',
                '${report.mismatches.length}',
                'bocor',
                report.mismatches.isEmpty
                    ? const Color(0xFF34D399)
                    : const Color(0xFFFBBF24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _resultStat(
                'SKU lemah',
                '${report.missingSkuCount}',
                'NOSKU',
                report.missingSkuCount == 0
                    ? Colors.white60
                    : Colors.orangeAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _resultStat(
                'Transit',
                '${report.openTransitQty}',
                'pcs (normal)',
                Colors.lightBlueAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Formula card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.functions_rounded,
                      size: 16, color: Colors.white.withOpacity(0.55)),
                  const SizedBox(width: 6),
                  Text(
                    'RUMUS AUDIT',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'stok toko  =  Σ ledger (+/−) per SKU',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Setiap jual, kirim, retur, rusak, dan revisi wajib punya jejak. '
                'Bedanya angka = kebocoran.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (clean)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF34D399).withOpacity(0.35)),
              color: const Color(0xFF34D399).withOpacity(0.08),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Color(0xFF34D399), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tidak ada selisih. Stok sinkron penuh dengan jejak ledger.',
                    style: TextStyle(
                      color: Color(0xFFA7F3D0),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Text(
            'DETAIL SELISIH',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          ...report.mismatches.take(40).map((e) {
            final deltaLabel =
                '${e.delta > 0 ? '+' : ''}${e.delta}';
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
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFFFBBF24).withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          'Δ $deltaLabel',
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SKU ${e.sku} · ${e.tokoId}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _miniCompare('Stok', '${e.stock}'),
                      ),
                      Icon(Icons.arrow_forward_rounded,
                          size: 14, color: Colors.white.withOpacity(0.25)),
                      Expanded(
                        child: _miniCompare('Ledger', '${e.ledgerSum}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.diagnosis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => onRecognize(e),
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
          }),
        ],
      ],
    );
  }

  Widget _resultStat(
      String label, String value, String unit, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCompare(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
            'Sedang memverifikasi jejak — bukan loading lemot',
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
