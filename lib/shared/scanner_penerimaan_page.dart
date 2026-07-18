import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'responsive.dart';

class ScannerPenerimaanPage extends StatefulWidget {
  final String cabangKaryawan;
  const ScannerPenerimaanPage({super.key, required this.cabangKaryawan});

  @override
  State<ScannerPenerimaanPage> createState() => _ScannerPenerimaanPageState();
}

class _ScannerPenerimaanPageState extends State<ScannerPenerimaanPage> {
  bool _isScanning = true;

  // Controller scanner kamera
  final MobileScannerController cameraController = MobileScannerController();

  // Bagian pembersihan memori (Anti-Lemot & HP Kasir ga panas)
  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _validasiBarangMasuk(String dataDariQR) {
    if (!_isScanning) return;
    setState(() => _isScanning = false);

    // Hentikan deteksi kamera sementara saat dialog muncul agar tidak double scan
    cameraController.stop();

    if (dataDariQR.contains(widget.cabangKaryawan)) {
      _tampilkanDialogHasil(
        sukses: true,
        judul: "scan_terima_sukses".tr(),
        pesan:
            "${"scan_data_terbaca".tr()} $dataDariQR\n\n${"scan_barang_dari_pusat".tr()} ${widget.cabangKaryawan} ${"scan berhasil dicatat".tr()}",
        icon: Icons.check_circle_rounded,
        warna: Colors.green,
        rawQRData: dataDariQR,
      );
    } else {
      _tampilkanDialogHasil(
        sukses: false,
        judul: "scan_salah_alamat".tr(),
        pesan:
            "${"scan_data_terbaca".tr()} $dataDariQR\n\n${"scan_akses_ditolak".tr()} ${widget.cabangKaryawan}!",
        icon: Icons.error_rounded,
        warna: Colors.redAccent,
        rawQRData: dataDariQR,
      );
    }
  }

  void _tampilkanDialogHasil({
    required bool sukses,
    required String judul,
    required String pesan,
    required IconData icon,
    required Color warna,
    required String rawQRData,
  }) {
    // Pelindung tambahan sebelum memunculkan dialog
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => R.constrainedDialog(
        context: dialogContext,
        preferWidth: 380,
        child: AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: warna, size: 80),
            const SizedBox(height: 20),
            Text(judul,
                style: TextStyle(
                    color: warna, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Text(pesan,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.5)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: warna,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (sukses) {
                    if (!mounted) return;
                    Navigator.pop(context, rawQRData.trim());
                  } else {
                    setState(() => _isScanning = true);
                    cameraController.start();
                  }
                },
                child: Text(
                  sukses ? "scan_btn_tutup".tr() : "scan_btn_coba_lagi".tr(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            )
          ],
        ),
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("scan_title".tr(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_rounded, color: Colors.yellow),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: cameraController,
            errorBuilder: (context, error) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.redAccent, size: 50),
                    const SizedBox(height: 16),
                    const Text(
                      "Gagal mengakses kamera.\nPastikan izin kamera telah diberikan di pengaturan HP.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              );
            },
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _validasiBarangMasuk(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          // Kotak Target Scanner
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.blueAccent.withOpacity(0.8), width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
            width: 250,
            height: 250,
          ),
          // Teks Instruksi di Bawah
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: R.widthOf(context) - 48),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      "scan instruksi".tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
