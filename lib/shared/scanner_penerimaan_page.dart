import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'qr/hid_scan_intake.dart';
import 'qr/qr_route.dart';
import 'responsive.dart';
import 'logistics/receive_scan_service.dart';
import 'theme.dart';
import 'widgets/admin/admin_premium.dart';

class ScannerPenerimaanPage extends StatefulWidget {
  final String cabangKaryawan;
  final String? karyawanId;
  final String? karyawanNama;

  /// Jika diisi (dari scanner universal), proses langsung tanpa scan ulang.
  final String? initialQr;

  const ScannerPenerimaanPage({
    super.key,
    required this.cabangKaryawan,
    this.karyawanId,
    this.karyawanNama,
    this.initialQr,
  });

  @override
  State<ScannerPenerimaanPage> createState() => _ScannerPenerimaanPageState();
}

class _ScannerPenerimaanPageState extends State<ScannerPenerimaanPage> {
  bool _isScanning = true;
  bool _isProcessing = false;
  /// true = sudah di-scan lewat UniversalQrScanPage; halaman ini hanya proses hasil.
  late final bool _fromUniversalScan;
  final MobileScannerController cameraController = MobileScannerController();
  final _service = ReceiveScanService();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQr?.trim();
    _fromUniversalScan = initial != null && initial.isNotEmpty;
    if (_fromUniversalScan) {
      _isScanning = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _validasiBarangMasuk(initial!);
      });
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _validasiBarangMasuk(String dataDariQR) async {
    if (_isProcessing) return;
    if (!_fromUniversalScan && !_isScanning) return;
    setState(() {
      _isScanning = false;
      _isProcessing = true;
    });
    if (!_fromUniversalScan) {
      await cameraController.stop();
    }

    final id = (widget.karyawanId ?? '').trim();
    final nama = (widget.karyawanNama ?? '').trim();
    if (id.isEmpty || nama.isEmpty) {
      _tampilkanDialogHasil(
        sukses: false,
        judul: "scan_salah_alamat".tr(),
        pesan:
            'Profil karyawan belum lengkap. Login ulang lalu coba scan lagi.',
        icon: Icons.person_off_rounded,
        warna: Colors.orangeAccent,
      );
      return;
    }

    try {
      final result = await _service.receiveFromQr(
        qrRaw: dataDariQR,
        cabangKaryawan: widget.cabangKaryawan,
        verifiedById: id,
        verifiedByName: nama,
      );

      if (result.ok) {
        _tampilkanDialogHasil(
          sukses: true,
          judul: "scan_terima_sukses".tr(),
          pesan: result.message,
          icon: Icons.check_circle_rounded,
          warna: Colors.green,
          popWithResult: result.resi ?? dataDariQR.trim(),
        );
      } else {
        _tampilkanDialogHasil(
          sukses: false,
          judul: result.alreadyDone
              ? 'Sudah Diterima'
              : "scan_salah_alamat".tr(),
          pesan: result.message,
          icon: result.alreadyDone
              ? Icons.info_rounded
              : Icons.error_rounded,
          warna: result.alreadyDone ? Colors.blueAccent : Colors.redAccent,
        );
      }
    } catch (e) {
      _tampilkanDialogHasil(
        sukses: false,
        judul: 'Gagal Proses',
        pesan: 'Tidak bisa memproses scan: $e',
        icon: Icons.error_rounded,
        warna: Colors.redAccent,
      );
    }
  }

  void _tampilkanDialogHasil({
    required bool sukses,
    required String judul,
    required String pesan,
    required IconData icon,
    required Color warna,
    String? popWithResult,
  }) {
    if (!mounted) return;
    setState(() => _isProcessing = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => R.constrainedDialog(
        context: dialogContext,
        preferWidth: 380,
        child: AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: warna, size: 80),
                const SizedBox(height: 20),
                Text(judul,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: warna,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
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
                        Navigator.pop(context, popWithResult);
                      } else if (_fromUniversalScan) {
                        // Kembali ke caller; scan ulang lewat Scan QR universal.
                        if (!mounted) return;
                        Navigator.pop(context);
                      } else {
                        setState(() => _isScanning = true);
                        cameraController.start();
                      }
                    },
                    child: Text(
                      sukses
                          ? "scan_btn_tutup".tr()
                          : "scan_btn_coba_lagi".tr(),
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

  Future<bool> _tryHandleReceiveQr(QrRouteResult result) async {
    if (result.type != QrPayloadType.receiveStock) return false;
    await _validasiBarangMasuk(result.raw);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return HidScanIntake(
      tryHandleKnown: _tryHandleReceiveQr,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Hasil routing dari Scan QR universal — tanpa kamera kedua.
    if (_fromUniversalScan) {
      return PremiumScaffold(
        appBar: PremiumAppBar(
          title: 'scan_qr'.tr(),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: _isProcessing
              ? const CircularProgressIndicator(color: Colors.blueAccent)
              : Text(
                  '${widget.cabangKaryawan} · ${widget.karyawanNama ?? '-'}',
                  style: const TextStyle(color: Colors.white54),
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('scan_qr'.tr(),
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
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_off_rounded,
                        color: Colors.redAccent, size: 50),
                    SizedBox(height: 16),
                    Text(
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
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.blueAccent.withOpacity(0.8), width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
            width: 250,
            height: 250,
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: R.widthOf(context) - 48),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "scan_instruksi".tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.cabangKaryawan} · ${widget.karyawanNama ?? '-'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
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
