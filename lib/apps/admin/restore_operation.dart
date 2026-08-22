import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../shared/logistics/do_lifecycle_service.dart';
import '../../shared/logistics/kurir_pick_dialog.dart';
import '../../shared/logistics/logistics_tracking_service.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/training/training_approval_simulator.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

// Shortcut client Supabase khusus file ini
final supabase = Supabase.instance.client;

// ============================================================================
// MODUL 11: RESTORE OPERATION (RETUR BARANG CABANG -> PUSAT) - PART 1 OF 2
// ============================================================================
class RestoreOperation extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RestoreOperation({super.key, required this.profile});

  @override
  State<RestoreOperation> createState() => _RestoreOperationState();
}

class _RestoreOperationState extends State<RestoreOperation> {
  List<dynamic> myProducts = [];
  bool isLoading = true;
  bool isProcessing = false;
  Map<String, int> returnItems = {};
  Map<String, TextEditingController> qtyControllers = {};
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMyStock();
  }

  @override
  void dispose() {
    searchController.dispose();
    for (var ctrl in qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // 1. AMBIL DATA STOK YANG TERSEDIA DI CABANG INI
  Future<void> _fetchMyStock() async {
    if (mounted) setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('products')
          .select()
          .eq('toko_id', widget.profile['toko_id'])
          .gt('stock', 0); // Hanya tampilkan yang stok fisik > 0

      if (mounted) {
        setState(() {
          myProducts = res;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error load retur stok: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. FUNGSI HITUNG DAN KUNCI JUMLAH RETUR BARANG
  void _updateReturnQty(String id, int delta, int maxStok) {
    setState(() {
      int current = returnItems[id] ?? 0;
      int next = current + delta;

      if (next <= 0) {
        returnItems.remove(id);
      } else if (next > maxStok) {
        returnItems[id] = maxStok;
        qtyControllers[id]?.text = maxStok.toString();

        // ✅ FIX TOKEN: Diubah dari '()' menjadi '{}' agar sinkron dengan JSON
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "retur_maksimal".tr().replaceFirst('{}', maxStok.toString())),
            backgroundColor: OptikAdminTokens.warning));
      } else {
        returnItems[id] = next;
        qtyControllers[id]?.text = next.toString();
      }
    });
  }

// ============================================================================
  // MODUL 11: RESTORE OPERATION (RETUR BARANG CABANG -> PUSAT) - PART 2 OF 2 (FINISH)
  // ============================================================================

  // 3. FUNGSI UTAMA EKSEKUSI MUTASI DAN POTONG STOK KE SUPABASE
  Future<void> _processReturn() async {
    if (returnItems.isEmpty) return;
    setState(() => isProcessing = true);

    try {
      List<Map<String, dynamic>> detailReturn = [];

      final fromToko =
          (widget.profile['toko_id'] ?? '').toString().toUpperCase();

      for (var entry in returnItems.entries) {
        final prod =
            myProducts.firstWhere((p) => p['id'].toString() == entry.key);
        int returQty = entry.value;
        final sku = ProductIdentity.skuOf(Map<String, dynamic>.from(prod));
        if (sku == null) {
          throw 'Produk ${prod['nama']} belum punya SKU. Tidak bisa retur.';
        }

        detailReturn.add({
          'id_produk': prod['id'],
          'nama': prod['nama'],
          'barcode': prod['barcode'] ?? sku,
          'sku': sku,
          'harga_jual': prod['harga_jual'] ?? prod['harga'] ?? 0,
          'harga_modal': prod['harga_modal'] ?? 0,
          'kategori': prod['kategori'] ?? 'Lainnya',
          'warna': prod['warna'] ?? '-',
          'qty': returQty
        });
      }

      if (!mounted) return;
      final kurirPick = await showKurirPickDialog(
        context,
        service: LogisticsTrackingService(),
        tokoId: widget.profile['toko_id']?.toString(),
        title: 'Pilih kurir retur (opsional)',
      );
      if (kurirPickCancelled(kurirPick)) {
        setState(() => isProcessing = false);
        return;
      }

      final created = await DoLifecycleService().createReturn(
        dari: fromToko,
        items: detailReturn,
        kurirId: kurirPickSkipped(kurirPick)
            ? null
            : kurirPick?['id']?.toString(),
        kurirNama: kurirPickSkipped(kurirPick)
            ? null
            : kurirPick?['nama']?.toString(),
      );
      final inserted = {
        'id': created['id'],
      };

      if (mounted) {
        setState(() {
          returnItems.clear();
          qtyControllers.clear();
        });
        if (TrainingMode.instance.isActive) {
          TrainingApprovalOutcome? outcome;
          try {
            outcome =
                await TrainingApprovalSimulator.simulateStockMoveIfTraining(
              context,
              id: inserted['id'],
            );
          } catch (_) {
            outcome = null;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                outcome == null
                    ? 'retur_sukses_dikirim'.tr()
                    : 'training_stock_move_outcome_${outcome.name}'.tr(),
              ),
              backgroundColor: outcome == TrainingApprovalOutcome.rejected
                  ? OptikAdminTokens.warning
                  : OptikAdminTokens.training,
            ));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("retur_sukses_dikirim".tr()),
              backgroundColor: OptikAdminTokens.success));
        }
        _fetchMyStock(); // Tarik ulang data stok terbaru cabang
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal memproses retur: $e"),
            backgroundColor: OptikAdminTokens.danger));
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Jalur filter pencarian produk lokal cabang
    List<dynamic> displayList = myProducts.where((p) {
      String q = searchController.text.toLowerCase();
      String nama = (p['nama'] ?? '').toString().toLowerCase();
      return nama.contains(q);
    }).toList();

    return PremiumScaffold(
      appBar: PremiumAppBar(title: "retur_title".tr()),
      body: Column(
        children: [
          // BAR INPUT PENCARIAN PRODUK
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: searchController,
              onChanged: (v) => setState(() {}),
              style: const TextStyle(color: OptikAdminTokens.navy),
              decoration: InputDecoration(
                  hintText: "retur_cari_produk".tr(),
                  prefixIcon: const Icon(Icons.search, color: OptikAdminTokens.textMuted),
                  filled: true,
                  fillColor: OptikAdminTokens.snow.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none)),
            ),
          ),

          // AREA UTAMA LIST DAFTAR PRODUK CABANG
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: OptikAdminTokens.ice))
                : displayList.isEmpty
                    ? Center(
                        child: Text("retur_stok_kosong".tr(),
                            style: const TextStyle(color: OptikAdminTokens.textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: displayList.length,
                        itemBuilder: (ctx, i) {
                          final item = displayList[i];
                          String id = item['id'].toString();
                          int maxStok =
                              int.tryParse(item['stock']?.toString() ?? '0') ??
                                  0;
                          bool isSelected = returnItems.containsKey(id);

                          return Card(
                            color: isSelected
                                ? OptikAdminTokens.danger.withOpacity(0.1)
                                : OptikAdminTokens.card,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: isSelected
                                        ? OptikAdminTokens.danger
                                        : OptikAdminTokens.ice.withOpacity(0.45))),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              title: Text(item['nama'] ?? '-',
                                  style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: Text("Stok di Cabang: $maxStok PCS",
                                  style: const TextStyle(
                                      color: OptikAdminTokens.textMuted, fontSize: 11)),
                              trailing: isSelected
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Tombol Kurangi Angka Retur
                                        IconButton(
                                            icon: const Icon(
                                                Icons.remove_circle,
                                                color: OptikAdminTokens.warning,
                                                size: 22),
                                            onPressed: () => _updateReturnQty(
                                                id, -1, maxStok)),
                                        Text("${returnItems[id]}",
                                            style: const TextStyle(
                                                color: OptikAdminTokens.navy,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        // Tombol Tambah Angka Retur
                                        IconButton(
                                            icon: const Icon(Icons.add_circle,
                                                color: OptikAdminTokens.success,
                                                size: 22),
                                            onPressed: () => _updateReturnQty(
                                                id, 1, maxStok)),
                                      ],
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.keyboard_return,
                                          color: OptikAdminTokens.danger, size: 22),
                                      onPressed: () {
                                        setState(() {
                                          returnItems[id] = 1;
                                          qtyControllers[id] =
                                              TextEditingController(text: '1');
                                        });
                                      }),
                            ),
                          );
                        },
                      ),
          ),

          // TOMBOL EKSEKUSI DI BAGIAN BAWAH HALAMAN
          Container(
            padding: const EdgeInsets.all(20),
            color: OptikAdminTokens.bgMid,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed:
                  (isProcessing || returnItems.isEmpty) ? null : _processReturn,
              icon: isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: OptikAdminTokens.navy, strokeWidth: 2))
                  : const Icon(Icons.local_shipping, color: OptikAdminTokens.navy),
              label: Text("retur_btn_kirim".tr(),
                  style: const TextStyle(
                      color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
} // 👈 Selesai Sempurna! Ini kurung kurawal penutup akhir untuk kelas State
