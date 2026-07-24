import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

// ✅ MANTRA PENGAMAN: Definisikan ulang shortcut client Supabase di file ini
final supabase = Supabase.instance.client;

// ============================================================================
// VERIFIKASI TERIMA BARANG (FIX ALUR KAMERA & STOK)
// ============================================================================
class IncomingVerification extends StatefulWidget {
  final Map<String, dynamic> profile;
  const IncomingVerification({super.key, required this.profile});

  @override
  State<IncomingVerification> createState() => _IncomingVerificationState();
}

class _IncomingVerificationState extends State<IncomingVerification> {
  List<dynamic> pendingTasks = [];
  bool isLoading = true;
  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final res = await supabase
          .from('stock_move_history')
          .select()
          .eq('ke_lokasi', widget.profile['toko_id'] ?? '')
          .eq('status', 'PENDING');

      if (mounted) {
        setState(() {
          pendingTasks = res;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load pending error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

// ✅ PERBAIKAN: Amankan fungsi dari spam click di awal method
  Future<void> _prosesVerifikasi(dynamic task) async {
    if (isLoading) return;

    // 1. Ambil Foto Bukti (desktop/web: fall back ke galeri)
    final photo = await pickImageSafe(picker: picker, context: context);
    if (photo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("inc_err_foto".tr()), backgroundColor: Colors.orange));
      return;
    }

    setState(() => isLoading = true);
    try {
      // 2. OPSI UTAMA: Upload foto bukti ke Supabase Storage agar tidak hilang
      final bytes = await photo.readAsBytes();
      final String fileName =
          'bukti_${task['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('verification-proofs')
          .uploadBinary(fileName, bytes);

      // 3. Stok via ledger SKU-first (bukan nama/resi)
      final tipe = (task['tipe'] ?? '').toString().toUpperCase();
      final resiName = (task['product_name'] ?? '').toString();
      final isReturn =
          tipe == 'RETUR' || resiName.toUpperCase().startsWith('RET-');
      await StockMutationService().receiveItemsFromMoveKeterangan(
        tokoId: (widget.profile['toko_id'] ?? '').toString(),
        keterangan: task['keterangan']?.toString() ?? '',
        jumlahFlat: int.tryParse(task['jumlah']?.toString() ?? '0') ?? 0,
        reason: StockReason.transferIn,
        refType: 'stock_move',
        refId: task['id'].toString(),
        actorNama: (widget.profile['nama'] ?? '').toString(),
        isReturn: isReturn,
      );

      // 4. UPDATE STATUS HISTORY JADI SUCCESS
      await supabase.from('stock_move_history').update({
        'status': 'SUCCESS',
        'bukti_foto_penerim': fileName,
      }).eq('id', task['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("smr_sukses_terima".tr()),
          backgroundColor: Colors.green));

      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal verifikasi: $e"),
          backgroundColor: Colors.redAccent));
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(title: "inc_title".tr()),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : pendingTasks.isEmpty
              ? Center(
                  child: Text("inc_kosong".tr(),
                      style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: pendingTasks.length,
                  itemBuilder: (c, i) {
                    final task = pendingTasks[i];
                    return Card(
                      color: const Color(
                          0xFF1E293B), // Mengikuti standard warna card admin/karyawan
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(15),
                        title: Text(task['product_name'] ?? 'Produk Tanpa Nama',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            // ✅ FIX: Diubah ke '{}' agar cocok dengan isi kamus JSON lokal Bos
                            "inc_jumlah_dikirim".tr().replaceFirst(
                                '{}', task['jumlah']?.toString() ?? '0'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70),
                          ),
                        ),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isLoading
                                  ? Colors.grey
                                  : Colors.green, // Ubah warna jika loading
                              minimumSize: const Size(110, 40),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          icon: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 14),
                          label: Text("smr_btn_foto_terima".tr(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          // ✅ PERBAIKAN: Jika isLoading true, onPressed jadi null (tombol beku)
                          onPressed:
                              isLoading ? null : () => _prosesVerifikasi(task),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
