// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'delivery_order.dart';
import 'stock_move_report.dart';
import 'barcode_scanner.dart';
import 'restore_operation.dart';
import 'request_order_page.dart';
import 'request_order_pusat_page.dart';
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
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 📊 EXECUTIVE INVENTORY ACCOUNTING BOARD (TOP 4 TIER MATRIX)
                const Text("🏛️ NERACA KAPITALISASI ASET GUDANG",
                    style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildAssetCard("Aset Pokok (HPP)",
                        _formatRupiah(totalAssetValuation), Colors.blueAccent),
                    const SizedBox(width: 6),
                    _buildAssetCard(
                        "Potensi Omzet",
                        _formatRupiah(totalPotentialRevenue),
                        Colors.greenAccent),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildAssetCard("Proyeksi Margin",
                        _formatRupiah(totalPotentialMargin), Colors.tealAccent),
                    const SizedBox(width: 6),
                    _buildAssetCard(
                        "Total Volume", "$totalVolumeItem PCS", Colors.white),
                  ],
                ),

                const SizedBox(height: 25),
                Text("inv_logistics".tr(),
                    style: const TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2)),

                // MENU 1: OPERASI MUTASI (DELIVERY ORDER / RETUR BARANG)
                _opTile(
                  context,
                  isPusat ? "inv_do_title".tr() : "inv_retur_title".tr(),
                  isPusat ? "inv_do_desc".tr() : "inv_retur_desc".tr(),
                  isPusat
                      ? Icons.local_shipping_rounded
                      : Icons.assignment_return_rounded,
                  Colors.blue,
                  () {
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

                // MENU 2: LAPORAN MUTASI (STOCK MOVE REPORT)
                _opTile(
                  context,
                  "inv_smr_title".tr(),
                  "inv_smr_desc".tr(),
                  Icons.receipt_long_rounded,
                  Colors.cyan,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) =>
                            StockMoveReport(profile: widget.profile),
                      ),
                    );
                  },
                ),

                // MENU: REQUEST ORDER PIPELINE
                _opTile(
                  context,
                  isPusat
                      ? 'Request Order Pusat'
                      : 'Request Order Cabang',
                  isPusat
                      ? 'Approval → Preparing → Shipping → Success + reservasi stok'
                      : 'Kirim antrean ke Pusat & lacak status',
                  Icons.assignment_turned_in_rounded,
                  Colors.orangeAccent,
                  () {
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

                const SizedBox(height: 25),
                Text("inv_quick_tools".tr(),
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2)),

                // MENU 3: QUICK SCAN BARCODE PRODUK
                _opTile(
                  context,
                  "inv_quick_scan".tr(),
                  "inv_quick_scan_desc".tr(),
                  Icons.qr_code_scanner_rounded,
                  Colors.greenAccent,
                  () {
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

  Widget _buildAssetCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OptikAdminTokens.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 12.5, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

// 🔥 FUNGSI CEK DATA STOK REAL-TIME KORPORAT BERBASIS FINANCIAL AUDIT HARGA MODAL & MARGIN PROFIT
  Future<void> _handleQuickCheck(BuildContext context, String code) async {
    try {
      final res = await supabase
          .from('products')
          .select()
          .eq('sku',
              code) // 🎯 FIX SAKTI: Ganti dari 'barcode' ke 'sku' agar sinkron dengan database harian lo!
          .eq('toko_id', widget.profile['toko_id'])
          .maybeSingle();

      if (!context.mounted) return;

      if (res != null) {
        int modal = int.tryParse(res['harga_modal']?.toString() ?? '0') ?? 0;
        int jual = int.tryParse(res['harga_jual']?.toString() ?? '0') ?? 0;
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
                    child: Text(res['nama'] ?? 'inv_detail_produk'.tr(),
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
                        "${res['stock'] ?? 0} PCS", Colors.greenAccent),
                    _infoRow("inv_kategori".tr(), res['kategori'] ?? '-',
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
                    if (res['kategori'] == 'Frame' && res['warna'] != null)
                      _infoRow("inv_warna_frame".tr(), res['warna'],
                          Colors.orangeAccent),
                    if (res['kategori'] == 'Lensa') ...[
                      _infoRow("inv_jenis_lensa".tr(),
                          res['jenis_lensa'] ?? '-', Colors.orangeAccent),
                      _infoRow("SPH", _formatOpticLocal(res['sph_r']),
                          Colors.cyanAccent),
                      _infoRow("CYL", _formatOpticLocal(res['cyl_r']),
                          Colors.cyanAccent),
                      if (res['jenis_lensa'] == 'Progresif' ||
                          res['jenis_lensa'] == 'Kryptok')
                        _infoRow("ADD", _formatOpticLocal(res['add_r']),
                            Colors.purpleAccent),
                    ],
                    const SizedBox(height: 12),
                    if (res['image_url'] != null && res['image_url'] != '-')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(res['image_url'],
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

  Widget _opTile(BuildContext context, String t, String s, IconData i, Color c,
      VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(top: 15),
      color: OptikAdminTokens.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white10, width: 0.5)),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(i, color: c, size: 22)),
        title: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: Colors.white)),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(s,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, height: 1.2))),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 12, color: Colors.white24),
      ),
    );
  }
}
