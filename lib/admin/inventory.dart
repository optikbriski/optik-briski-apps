import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'delivery_order.dart';
import 'stock_move_report.dart';
import 'barcode_scanner.dart';
import 'restore_operation.dart';

// ============================================================================
// 5. INVENTORY MODULE (OVERVIEW) REVISI TOTAL (OPTICAL DETAIL - FULLY UNLOCKED)
// ============================================================================
class InventoryOverview extends StatelessWidget {
  final Map<String, dynamic> profile;
  const InventoryOverview({super.key, required this.profile});

  // Helper local untuk memformat nilai ukuran optik agar rapi (+0.25 / -1.00)
  String _formatOpticLocal(dynamic val) {
    if (val == null || val.toString().isEmpty) return "0.00";
    double v = double.tryParse(val.toString()) ?? 0.00;
    if (v == 0) return "0.00";
    return v >= 0 ? "+${v.toStringAsFixed(2)}" : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    // Logika Unit Pusat vs Cabang
    bool isPusat = profile['toko_id'] == 'PUSAT';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text("inv_title".tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          Text("inv_logistics".tr(),
              style: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.5)),

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
                // ✅ AKTIF: Kembali menggunakan OutgoingOperation yang sudah steril
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OutgoingOperation(profile: profile),
                  ),
                );
              } else {
                // ✅ AKTIF: Masuk ke halaman Retur Barang dari Cabang ke Pusat
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RestoreOperation(profile: profile),
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
              // ✅ AKTIF: Masuk ke Laporan Manajemen Perpindahan Stok GridView
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => StockMoveReport(profile: profile),
                ),
              );
            },
          ),

          const SizedBox(height: 35),
          Text("inv_quick_tools".tr(),
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.5)),

          // MENU 3: QUICK SCAN BARCODE PRODUK
          _opTile(
            context,
            "inv_quick_scan".tr(),
            "inv_quick_scan_desc".tr(),
            Icons.qr_code_scanner_rounded,
            Colors.greenAccent,
            () {
              // ✅ AKTIF: Kembali menggunakan OptikBRiskiScanner yang sudah steril
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

  // FUNGSI CEK DATA STOK REAL-TIME KE DATABASE SUPABASE
  Future<void> _handleQuickCheck(BuildContext context, String code) async {
    try {
      final res = await Supabase.instance.client
          .from('products')
          .select()
          .eq('barcode', code)
          .eq('toko_id', profile['toko_id'])
          .maybeSingle();

      if (!context.mounted) return;

      if (res != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(res['nama'] ?? 'inv_detail_produk'.tr(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow("inv_stok_saat_ini".tr(), "${res['stock'] ?? 0} PCS",
                    Colors.greenAccent),
                const Divider(color: Colors.white10, height: 20),
                _infoRow(
                    "inv_kategori".tr(), res['kategori'] ?? '-', Colors.white),
                if (res['kategori'] == 'Frame' && res['warna'] != null)
                  _infoRow("inv_warna_frame".tr(), res['warna'],
                      Colors.orangeAccent),
// ✅ FIX POSITIONAL ARGUMENTS: Sekarang sudah lengkap 3 data input + Warna aksennya
                if (res['kategori'] == 'Lensa') ...[
                  _infoRow("inv_jenis_lensa".tr(), res['jenis_lensa'] ?? '-',
                      Colors.orangeAccent),
                  _infoRow("SPH", _formatOpticLocal(res['sph_r']),
                      Colors.cyanAccent), // 🚀 FIX: Ditambahkan parameter warna
                  _infoRow("CYL", _formatOpticLocal(res['cyl_r']),
                      Colors.cyanAccent), // 🚀 FIX: Ditambahkan parameter warna
                  if (res['jenis_lensa'] == 'Progresif' ||
                      res['jenis_lensa'] == 'Kryptok')
                    _infoRow(
                        "ADD",
                        _formatOpticLocal(res['add_r']),
                        Colors
                            .purpleAccent), // 🚀 FIX: Ditambahkan parameter warna
                ],
                const SizedBox(height: 15),
                if (res['image_url'] != null && res['image_url'] != '-')
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(res['image_url'],
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Icon(
                            Icons.image_not_supported,
                            color: Colors.white10,
                            size: 50)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("inv_mengerti".tr(),
                      style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold)))
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("inv_not_found".tr()),
            backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      debugPrint("Gagal cek stok: $e");
    }
  }

  Widget _infoRow(String label, String val, Color valColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(val,
              style: TextStyle(
                  color: valColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _opTile(BuildContext context, String t, String s, IconData i, Color c,
      VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(top: 15),
      color: const Color(0xFF1E293B),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: Colors.white10)),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(i, color: c, size: 24)),
        title: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white)),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, height: 1.3))),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: Colors.white24),
      ),
    );
  }
}
