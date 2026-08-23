import 'dart:async'; // ✅ WAJIB: Menghilangkan error merah pada objek Timer periodic
import 'package:flutter/material.dart';
import 'verifikasi_terima.dart';
import '../../shared/logistics/receive_queue_service.dart';
import '../../shared/logistics/receive_verification_rules.dart';
import '../../shared/theme.dart';

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
      if (!ReceiveVerificationRules.canOpenIncomingQueue(widget.profile)) {
        if (mounted) setState(() => pendingCount = 0);
        return;
      }
      final tokoSaya = widget.profile['toko_id']?.toString() ?? '';
      if (tokoSaya.isEmpty) return;

      final n = await ReceiveQueueService().countIncoming(tokoId: tokoSaya);

      if (mounted) {
        setState(() {
          pendingCount = n;
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
              color: OptikAdminTokens.warning, size: 22),
          onPressed: () {
            if (!ReceiveVerificationRules.canOpenIncomingQueue(
                widget.profile)) {
              return;
            }
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
                  color: OptikAdminTokens.danger, shape: BoxShape.circle),
              child: Text(
                pendingCount > 9 ? '9+' : pendingCount.toString(),
                style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          )
      ],
    );
  }
}
