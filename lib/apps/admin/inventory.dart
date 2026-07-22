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
