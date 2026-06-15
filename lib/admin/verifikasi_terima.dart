import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';

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

  Future<void> _prosesVerifikasi(dynamic task) async {
    // 1. WAJIB BUKA KAMERA & AMBIL FOTO
    final photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("inc_err_foto".tr()), backgroundColor: Colors.orange));
      return;
    }

    setState(() => isLoading = true);
    try {
      // 2. UPDATE STATUS HISTORY JADI SUCCESS
      await supabase
          .from('stock_move_history')
          .update({'status': 'SUCCESS'}).eq('id', task['id']);

      // 3. TAMBAH STOK FISIK DI CABANG
      final existingProd = await supabase
          .from('products')
          .select('id, stock')
          .eq('nama', task['product_name'])
          .eq('toko_id', widget.profile['toko_id'])
          .maybeSingle();

      if (existingProd != null) {
        await supabase.from('products').update({
          'stock': (existingProd['stock'] ?? 0) + (task['jumlah'] ?? 0)
        }).eq('id', existingProd['id']);
      } else {
        await supabase.from('products').insert({
          'nama': task['product_name'],
          'stock': task['jumlah'],
          'toko_id': widget.profile['toko_id'],
          'harga': 0, // Nol dulu, biar Kasir cabang yang set harga
          'kategori': 'Frame',
          'sub_kategori': 'Lainnya',
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("smr_sukses_terima".tr()),
          backgroundColor: Colors.green));

      _load(); // Refresh daftar yang masih pending
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
    return Scaffold(
      backgroundColor:
          const Color(0xFF0F172A), // Menjaga keselarasan tema gelap Bos Natan
      appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          elevation: 0,
          centerTitle: true,
          title: Text("inc_title".tr(),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
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
                              backgroundColor: Colors.green,
                              minimumSize: const Size(110,
                                  40), // Ukuran tombol dibuat lebih proporsional
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
                          onPressed: () => _prosesVerifikasi(task),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
