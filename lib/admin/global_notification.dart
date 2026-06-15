import 'dart:async'; // ✅ WAJIB: Menghilangkan error merah pada objek Timer periodic
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verifikasi_terima.dart'; // ✅ SEFOLDER: Otomatis tersambung ke sistem verifikasi terima barang Bos

// ============================================================================
// MODUL 12: GLOBAL NOTIFICATION ICON (LONCENG PINTAR)
// ============================================================================
class GlobalNotificationIcon extends StatefulWidget {
  final Map<String, dynamic> profile;
  const GlobalNotificationIcon({super.key, required this.profile});

  @override
  State<GlobalNotificationIcon> createState() => _GlobalNotificationIconState();
}

class _GlobalNotificationIconState extends State<GlobalNotificationIcon> {
  int pendingCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cekNotifikasi();
    // Sistem auto-refresh background secara berkala setiap 30 detik
    _timer =
        Timer.periodic(const Duration(seconds: 30), (t) => _cekNotifikasi());
  }

  @override
  void dispose() {
    _timer
        ?.cancel(); // Mencegah kebocoran memori (memory leak) saat ganti halaman
    super.dispose();
  }

  // LOGIKA UTAMA: HITUNG BARANG TRANSIT / PENDING YG AKAN MASUK KE TOKO INI
  Future<void> _cekNotifikasi() async {
    try {
      final tokoSaya = widget.profile['toko_id']?.toString() ?? '';
      if (tokoSaya.isEmpty) return;

      // Tarik ID mutasi barang yang tujuan pengirimannya menuju cabang/pusat aktif saat ini
      final res = await Supabase.instance.client
          .from('stock_move_history')
          .select('id')
          .eq('ke_lokasi', tokoSaya)
          .inFilter('status', ['PENDING', 'TRANSIT']);

      if (mounted) {
        setState(() {
          pendingCount = (res as List).length;
        });
      }
    } catch (e) {
      debugPrint("Gagal cek status notifikasi masuk: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_active_rounded,
              color: Colors.orangeAccent, size: 22),
          onPressed: () {
            // ✅ NAVIGASI AKTIF: Langsung diarahkan menuju screen verifikasi terima paket
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (c) =>
                      IncomingVerification(profile: widget.profile)),
            ).then((_) =>
                _cekNotifikasi()); // Tarik ulang data notif saat user kembali ke dashboard
          },
        ),

        // BADGE BADGE NOTIFIKASI MERAH (Hanya muncul jika ada barang di perjalanan)
        if (pendingCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle),
              child: Text(
                pendingCount > 9 ? '9+' : pendingCount.toString(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          )
      ],
    );
  }
}
