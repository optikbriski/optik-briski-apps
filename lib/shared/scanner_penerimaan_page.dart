import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'qr/hid_scan_intake.dart';
import 'qr/qr_route.dart';
import 'responsive.dart';
import 'logistics/receive_scan_service.dart';
import 'safe_image_picker.dart';
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
  final _picker = ImagePicker();

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
        warna: OptikAdminTokens.warning,
      );
      return;
    }

    try {
      var result = await _service.receiveFromQr(
        qrRaw: dataDariQR,
        cabangKaryawan: widget.cabangKaryawan,
        verifiedById: id,
        verifiedByName: nama,
      );
      if (result.needsPhoto) {
        if (!mounted) return;
        final photo = await pickImageSafe(
          picker: _picker,
          context: context,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 50,
        );
        if (photo == null) {
          _tampilkanDialogHasil(
            sukses: false,
            judul: "scan_salah_alamat".tr(),
            pesan: 'Foto terima wajib sebelum stok masuk.',
            icon: Icons.photo_camera_rounded,
            warna: OptikAdminTokens.warning,
          );
          return;
        }
        final bytes = await photo.readAsBytes();
        final moveId = (result.moveId ?? 'scan').toString();
        final path =
            'konfirmasi/${moveId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final db = Supabase.instance.client;
        await db.storage.from('attendance_photos').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        final imgUrl = db.storage.from('attendance_photos').getPublicUrl(path);
        result = await _service.receiveFromQr(
          qrRaw: dataDariQR,
          cabangKaryawan: widget.cabangKaryawan,
          verifiedById: id,
          verifiedByName: nama,
          buktiFotoPenerima: imgUrl,
        );
      }

      if (result.ok) {
        _tampilkanDialogHasil(
          sukses: true,
          judul: result.becameTransit
              ? 'Berangkat (TRANSIT)'
              : "scan_terima_sukses".tr(),
          pesan: result.message,
          icon: result.becameTransit
              ? Icons.local_shipping_rounded
              : Icons.check_circle_rounded,
          warna: result.becameTransit ? OptikAdminTokens.warning : OptikAdminTokens.success,
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
          warna: result.alreadyDone ? OptikAdminTokens.navy : OptikAdminTokens.danger,
        );
      }
    } catch (e) {
      _tampilkanDialogHasil(
        sukses: false,
        judul: 'Gagal Proses',
        pesan: 'Tidak bisa memproses scan: $e',
        icon: Icons.error_rounded,
        warna: OptikAdminTokens.danger,
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
                        color: OptikAdminTokens.slate, fontSize: 14, height: 1.5)),
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
                          color: OptikAdminTokens.snow, fontWeight: FontWeight.bold),
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
              ? const CircularProgressIndicator(color: OptikAdminTokens.navy)
              : Text(
                  '${widget.cabangKaryawan} · ${widget.karyawanNama ?? '-'}',
                  style: const TextStyle(color: OptikAdminTokens.slate),
                ),
        ),
      );
    }

    return PremiumScaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: OptikAdminTokens.snow),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('scan_qr'.tr(),
            style: const TextStyle(
                color: OptikAdminTokens.snow, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_rounded, color: OptikAdminTokens.ice),
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
                        color: OptikAdminTokens.danger, size: 50),
                    SizedBox(height: 16),
                    Text(
                      "Gagal mengakses kamera.\nPastikan izin kamera telah diberikan di pengaturan HP.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: OptikAdminTokens.slate, fontSize: 13),
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
              color: OptikAdminTokens.navy.withOpacity(0.54),
              child: const Center(
                child: CircularProgressIndicator(color: OptikAdminTokens.navy),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: OptikAdminTokens.navy.withOpacity(0.8), width: 3),
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
                        color: OptikAdminTokens.navy.withOpacity(0.87),
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "scan_instruksi".tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: OptikAdminTokens.snow, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.cabangKaryawan} · ${widget.karyawanNama ?? '-'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: OptikAdminTokens.slate, fontSize: 12),
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
