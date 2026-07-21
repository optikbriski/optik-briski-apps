// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart'; // Pastikan import ini ada
import '../../shared/pos_print_service.dart';
import '../../shared/responsive.dart';
import '../../shared/garansi/garansi_service.dart';
import '../../shared/invoice/invoice_link.dart';
import '../../shared/qr/hid_scan_intake.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/widgets/leave_page_guard.dart';
import '../../shared/training/training_approval_simulator.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/training/training_ops_sync.dart';
import '../../shared/logistics/request_order_service.dart';
import '../karyawan/absensi_page.dart';
import 'garansi_page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

// ============================================================================
// MODUL 4: SALES / TERMINAL KASIR & STRUK NOTA DIGITAL (FULL SYSTEM)
// ============================================================================

final supabase = Supabase.instance.client;

String formatRupiah(int nominal) {
  return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
      .format(nominal);
}

// ============================================================================
// WIDGET BANTUAN: INPUT RESEP KUSTOM DENGAN TOMBOL -/+ (STEP 0.25)
// ============================================================================
class ResepInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Function(double) onChanged;

  const ResepInput({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  void _updateValue(double step) {
    double val = double.tryParse(
            controller.text.replaceAll(',', '.').replaceAll('+', '')) ??
        0.0;

    if (val == 0.0 && step > 0) {
      val = 0.25;
    } else if (val == 0.0 && step < 0) {
      val = -0.25;
    } else {
      val += step;
    }

    controller.text = (val > 0 ? "+" : "") + val.toStringAsFixed(2);
    onChanged(val);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _updateValue(-0.25),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8)),
            child:
                const Icon(Icons.remove, color: Colors.orangeAccent, size: 18),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 10, color: Colors.grey),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => onChanged(
                double.tryParse(v.replaceAll(',', '.').replaceAll('+', '')) ??
                    0.0),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => _updateValue(0.25),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.add, color: Colors.greenAccent, size: 18),
          ),
        ),
      ],
    );
  }
}

// --- KOMPONEN JAM TERPISAH (ANTI-CRASH) ---
class LiveClock extends StatefulWidget {
  const LiveClock({super.key});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      "${_currentTime.day.toString().padLeft(2, '0')}-${_currentTime.month.toString().padLeft(2, '0')}-${_currentTime.year} | ${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}",
      style: const TextStyle(
        color: Colors.blueAccent,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }
}

class SalesPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const SalesPage({super.key, required this.profile});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  // Letakkan di bawah variabel isLoading lo
  CameraController? _silentCameraController;
  bool isScanningLocal = true;
  final MobileScannerController kameraLoginCtrl =
      MobileScannerController(facing: CameraFacing.front);

  // SESI TOKO & LACI KASIR (OPEN/CLOSE STORE)
  bool isStoreOpen = false;
  bool isLoading = false;
  int modalAwal = 0;
  final TextEditingController modalAwalCtrl = TextEditingController();
  final TextEditingController uangFisikCloseCtrl = TextEditingController();
  DateTime? storeOpenTime;

  static bool isPosUnlocked = false;
  static String namaKasir = "";
  static Map<String, dynamic>? activeCashier;
  static List<Map<String, dynamic>> cartItems = [];
  bool isScanning = true;

  // DATA PELANGGAN (CRM-SYSTEM)
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  /// Kolom scan SKU global (juga menerima HID saat field fokusokus).
  final TextEditingController skuScanCtrl = TextEditingController();

  // KERANJANG BELANJA & DISKON GLOBAL
  List<Map<String, dynamic>> restockQueue = [];
  final TextEditingController discountCtrl = TextEditingController(text: "0");

  // TOOGLE SELEKSI LAYOUT BARANG
  bool isFrameActive = false;
  bool isLensaActive = false;
  bool isLainnyaActive = false;

  String lensScanSide = 'R';
  String lensJenis = 'Standar';
  String lensBahan = 'Supersin';
  String lensJenisLama = 'Standar';
  List<Map<String, dynamic>> pendingLensRequests = [];

  // SEKSI FRAME
  Map<String, dynamic>? selectedFrame;

  // SEKSI LENSA & PARAMETER DIAGNOSA KLINIS LENGKAP
  List<String> listMerkLensa = [];
  List<Map<String, dynamic>> masterLensaProducts = [];
  String? selectedMerkLensa;
  Map<String, dynamic>? selectedLens;

  final TextEditingController lensBrandCtrl = TextEditingController();
  final TextEditingController namaManualCtrl = TextEditingController();

  // Parameter Resep Baru Pasien
  final TextEditingController sphRCtrl = TextEditingController(text: "0.00");
  final TextEditingController sphLCtrl = TextEditingController(text: "0.00");
  final TextEditingController cylRCtrl = TextEditingController(text: "0.00");
  final TextEditingController cylLCtrl = TextEditingController(text: "0.00");
  final TextEditingController addRCtrl = TextEditingController(text: "0.00");
  final TextEditingController addLCtrl = TextEditingController(text: "0.00");
  final TextEditingController axisRCtrl = TextEditingController(text: "0");
  final TextEditingController axisLCtrl = TextEditingController(text: "0");
  final TextEditingController pdRCtrl = TextEditingController();
  final TextEditingController pdLCtrl = TextEditingController();

  // Parameter Kacamata Lama Pasien (CRM Comparison)
  bool isInputKacamataLamaActive = false;
  final TextEditingController sphOldRCtrl = TextEditingController(text: "0.00");
  final TextEditingController cylOldRCtrl = TextEditingController(text: "0.00");
  final TextEditingController axisOldRCtrl = TextEditingController(text: "0");
  final TextEditingController sphOldLCtrl = TextEditingController(text: "0.00");
  final TextEditingController cylOldLCtrl = TextEditingController(text: "0.00");
  final TextEditingController axisOldLCtrl = TextEditingController(text: "0");

  // SEKSI AKSESORIS / LAINNYA
  String lainnyaMode = 'Paket';
  Map<String, dynamic>? selectedAksesoris;
  final TextEditingController aksesorisQtyCtrl =
      TextEditingController(text: "1");

  // BILLING SYSTEM & METODE PEMBAYARAN
  String paymentMethod = "Tunai";
  String paymentStatus = "Lunas";
  final TextEditingController paidCtrl = TextEditingController();

  // SISTEM KONTROL POS
  bool isProcessing = false;
  String noInvoice = "";
  final TextEditingController kasirCtrl = TextEditingController();
  bool _leavingPos = false;

  String get _tokoId => widget.profile['toko_id']?.toString() ?? 'PUSAT';

  String get _posDraftPrefsKey => 'pos_draft_transaksi_$_tokoId';

  @override
  void initState() {
    super.initState();
    _fetchMerkLensa();
    _generateInvoice();
    _cekStatusOpenStore();
    _restorePosDraftIfNeeded();

    // ⏰ SEKURITI PENGIRIMAN OTOMATIS: Jaga-jaga auto-send ke pusat setiap Jam 21.00 Malam
    // Training: skip silent HQ send — trainee decides via simulator on explicit send.
    Timer.periodic(const Duration(minutes: 15), (timer) async {
      if (TrainingMode.instance.isActive) return;
      final now = DateTime.now();
      // Deteksi jika waktu lokal laptop sudah menyentuh jam 9 malam (pukul 21)
      if (now.hour == 21) {
        try {
          final todayStr = now.toIso8601String().split('T')[0];
          final tokoId = widget.profile['toko_id'] ?? 'PUSAT';

          // Sapu bersih semua sisa status PENDING di hari tersebut, paksa kirim ke pusat
          await supabase
              .from('pending_requests')
              .update({
                'status': 'SENT_TO_HQ',
                'tracking_status': 'DIKIRIM_KE_PUSAT',
              })
              .eq('toko_id', tokoId)
              .eq('status', 'PENDING')
              .gte('created_at', '${todayStr}T00:00:00');

          debugPrint(
              "--- ⏰ LOG OPTIK CRON: TRIGGER AUTO-SEND JAM 9 MALAM BERHASIL DIKIRIM ---");
        } catch (e) {
          debugPrint(
              "--- ⏰ LOG OPTIK CRON ERROR: Auto-send gagal dipicu: $e ---");
        }
      }
    });
  }

  @override
  void dispose() {
    kameraLoginCtrl.dispose();
    modalAwalCtrl.dispose();
    uangFisikCloseCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    emailCtrl.dispose();
    skuScanCtrl.dispose();
    discountCtrl.dispose();
    paidCtrl.dispose();
    kasirCtrl.dispose();
    super.dispose();
  }

  void _generateInvoice() {
    final now = DateTime.now();
    final dateStr =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    final unixStr = now.millisecondsSinceEpoch.toString().substring(9);
    setState(() {
      noInvoice = "INV-$dateStr-$unixStr";
    });
  }

  Future<void> _cekStatusOpenStore() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
    String? lastOpenStr = prefs.getString('last_open_time_$tokoId');
    bool storeOpen = prefs.getBool('is_store_open_$tokoId') ?? false;

    if (storeOpen && lastOpenStr != null) {
      DateTime lastOpen = DateTime.parse(lastOpenStr);
      DateTime now = DateTime.now();
      DateTime hariIniJam6 = DateTime(now.year, now.month, now.day, 6, 0);
      DateTime resetTime = now.isBefore(hariIniJam6)
          ? hariIniJam6.subtract(const Duration(days: 1))
          : hariIniJam6;

      if (lastOpen.isBefore(resetTime)) {
        storeOpen = false;
        await prefs.setBool('is_store_open_$tokoId', false);
      } else {
        // 🎯 FIX: Pastikan variabel waktu terisi saat aplikasi diload ulang
        storeOpenTime = lastOpen;
      }
    }

    if (mounted) {
      setState(() {
        isStoreOpen = storeOpen;
        isPosUnlocked = true;
      });
    }
  }

  Future<void> _prosesCloseStore() async {
    setState(() => isProcessing = true);
    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';

      // 🎯 FIX SAKTI: Jika storeOpenTime null, fallback ke jam 00:00:00 hari ini
      final startTime = storeOpenTime ??
          DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day);

      final res = await Supabase.instance.client
          .from('finance_transactions')
          .select('nominal')
          .eq('toko_id', tokoId)
          .eq('jenis_transaksi', 'PEMASUKAN')
          .neq('kategori',
              'Modal Awal Sesi') // 🎯 REVISI KUNCI: Kecualikan modal awal dari hitungan omzet harian agar tidak double-count!
          .eq('metode_pembayaran', 'Tunai')
          .gte('created_at', startTime.toIso8601String());

      int totalTunaiHariIni = 0;
      for (var item in res) {
        totalTunaiHariIni += (item['nominal'] ?? 0) as int;
      }

      int uangSeharusnyaDiLaci = modalAwal + totalTunaiHariIni;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            "pos_tutup_shift_title".tr(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${"pos_modal_awal_sesi".tr()}${formatRupiah(modalAwal)}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                  "${"pos_omzet_tunai_masuk".tr()}${formatRupiah(totalTunaiHariIni)}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(color: Colors.white24, height: 20),
              Text(
                "${"pos_kas_seharusnya".tr()}${formatRupiah(uangSeharusnyaDiLaci)}",
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: uangFisikCloseCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "pos_hint_uang_fisik".tr(),
                  prefixText: "Rp ",
                  labelStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                uangFisikCloseCtrl.clear();
                Navigator.pop(ctx);
              },
              child: Text("sop_batal".tr(),
                  style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                int uangFisikRiil = int.tryParse(uangFisikCloseCtrl.text
                        .replaceAll(RegExp(r'[^0-9]'), '')) ??
                    0;
                int selisih = uangFisikRiil - uangSeharusnyaDiLaci;

                await supabase.from('finance_transactions').insert({
                  'toko_id': tokoId,
                  'tanggal_transaksi':
                      DateTime.now().toIso8601String().split('T')[0],
                  'jenis_transaksi': selisih >= 0 ? 'PEMASUKAN' : 'PENGELUARAN',
                  'kategori': 'Penutupan Toko (Closing Shift)',
                  'deskripsi':
                      'Sesi Tutup Toko Selesai. Selisih Kas: Rp $selisih (Uang Fisik: Rp $uangFisikRiil | Sistem: Rp $uangSeharusnyaDiLaci)',
                  'nominal': selisih.abs(),
                  'status_pembayaran': 'LUNAS',
                  'metode_pembayaran': 'Tunai',
                });

                setState(() {
                  isStoreOpen = false;
                  isPosUnlocked = false;
                  activeCashier = null;
                  modalAwal = 0;
                  storeOpenTime = null;
                });

                modalAwalCtrl.clear();
                uangFisikCloseCtrl.clear();

                if (!mounted) return;
                Navigator.pop(ctx);

                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(selisih == 0
                      ? "pos_tutup_balanced".tr()
                      : "${"pos_tutup_selisih".tr()}$selisih"),
                  backgroundColor: selisih == 0 ? Colors.green : Colors.orange,
                ));
              },
              child: Text("pos_konfirmasi".tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint("${"pos_err_closing".tr()}$e");
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<void> _fetchMerkLensa() async {
    try {
      final res = await Supabase.instance.client
          .from('products')
          .select()
          .eq('kategori', 'Lensa');

      final List<Map<String, dynamic>> data =
          List<Map<String, dynamic>>.from(res);

      final unikMerk = data
          .map((e) =>
              e['nama']?.toString() ?? "") // 🎯 FIX: 'merk' ganti ke 'nama'
          .where((m) => m.isNotEmpty)
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          listMerkLensa = unikMerk;
          masterLensaProducts = data;
        });
      }
    } catch (e) {
      debugPrint("${"pos_err_load_lensa".tr()}$e");
    }
  }

// 1. Scanner Generik (Bisa dipakai produk maupun ID Karyawan) - FIX AUTO CLOSE
  Future<String?> _scanBarcode(
      {CameraFacing facing = CameraFacing.back}) async {
    final MobileScannerController ctrl =
        MobileScannerController(facing: facing);
    bool hasPopped = false; // Kunci barikade agar tidak double pop

    final String? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: OptikAdminTokens.card,
            title: const Text("Posisikan Barcode ID Karyawan",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (!hasPopped) {
                  hasPopped = true;
                  Navigator.pop(context, null);
                }
              },
            ),
          ),
          body: MobileScanner(
            controller: ctrl,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                if (!hasPopped) {
                  hasPopped = true;
                  // Begitu barcode ke-detect, langsung tendang keluar dan kirim datanya
                  Navigator.pop(context, barcodes.first.rawValue);
                }
              }
            },
          ),
        ),
      ),
    );

    await ctrl.stop();
    ctrl.dispose();
    return result;
  }

// 2. Silent Open Store (Triggered by Enter) - AUTO PHOTO -> AUTO OPEN SCANNER NIK
  Future<void> _startSilentOpenStore() async {
    setState(() => isLoading = true);
    XFile? image;

    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCam = cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        _silentCameraController = CameraController(
          frontCam,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await _silentCameraController!.initialize();
        if (mounted) setState(() {});
        await Future.delayed(const Duration(milliseconds: 500));
        image = await _silentCameraController!.takePicture();
      }
    } catch (e) {
      debugPrint("Gagal inisialisasi hardware auto-capture: $e");
    } finally {
      if (_silentCameraController != null) {
        await _silentCameraController!.dispose();
        _silentCameraController = null;
      }
    }

    if (image == null) {
      setState(() => isLoading = false);
      _showSnack(
          "❌ Gagal menjepret foto otomatis. Pastikan izin kamera browser aktif!",
          Colors.red);
      return;
    }

    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';

      String photoUrl = "";
      try {
        final bytes = await image.readAsBytes();
        final path =
            "$tokoId/session_${DateTime.now().millisecondsSinceEpoch}.jpg";
        await supabase.storage.from('session_photos').uploadBinary(path, bytes);
        photoUrl = supabase.storage.from('session_photos').getPublicUrl(path);
      } catch (storageError) {
        debugPrint("Storage tertunda, gunakan fallback: $storageError");
        photoUrl = "https://placeholder.co/600x400?text=No+Photo+Absen";
      }

      // 🎯 SINKRONISASI TOTAL: Langsung loncat ke scan barcode kamera depan untuk ID karyawan!
      final String? nikKaryawan =
          await _scanBarcode(facing: CameraFacing.front);

      if (nikKaryawan == null || nikKaryawan.isEmpty) {
        _showSnack("Sesi dibatalkan", Colors.red);
        return;
      }

      final res = await supabase
          .from('karyawan')
          .select()
          .eq('nik', nikKaryawan)
          .maybeSingle();
      if (res == null) {
        _showSnack("❌ Karyawan tidak terdaftar!", Colors.red);
        return;
      }

      await supabase.from('session_logs').insert({
        'toko_id': tokoId,
        'karyawan_id': nikKaryawan,
        'photo_url': photoUrl,
        'timestamp_open': DateTime.now().toIso8601String(),
        'status': 'OPEN'
      });

      // 🎯 KUNCI SESI: Biar aman pas di-back browser (Dari langkah sebelumnya)
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_store_open_$tokoId', true);
      await prefs.setString(
          'last_open_time_$tokoId', DateTime.now().toIso8601String());

      setState(() {
        isStoreOpen = true;
        activeCashier = res;
        namaKasir = res['nama'];
      });
      _showSnack("✅ Toko Opened by: ${res['nama']}", Colors.green);
    } catch (e) {
      // 🎯 FIX: Ini pasangan catch utamanya yang tadi hilang kemakan
      _showSnack("❌ Error Open Store: $e", Colors.red);
    } finally {
      // 🎯 FIX: Ini status loading diturunkan biar aplikasi ga nge-hang
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Scan dari kolom SKU (kamera / HID / Enter): routing QR dulu, lalu SKU.
  Future<void> _onPosScanSubmitted(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) return;
    skuScanCtrl.clear();

    final routed = QrRouter.classify(raw);
    if (routed.isKnown) {
      final proceed = await _guardPosLeaveForKnownQr(routed);
      if (!proceed || !mounted) return;
      await UniversalQrNav.dispatch(
        context,
        routed,
        profile: widget.profile,
        callerRole: UniversalQrCallerRole.admin,
      );
      return;
    }
    await _cariProdukBySKU(raw);
  }

  /// QR non-produk yang akan membuka halaman lain → dialog 3 opsi dulu.
  Future<bool> _guardPosLeaveForKnownQr(QrRouteResult result) async {
    if (!UniversalQrNav.wouldNavigate(
      result,
      callerRole: UniversalQrCallerRole.admin,
    )) {
      return true;
    }
    return _confirmPosLeave(prepareLeave: true);
  }

  /// Dialog keluar POS: Batalkan / buang draft / simpan draft.
  Future<bool> _confirmPosLeave({required bool prepareLeave}) async {
    final action = await LeavePageGuard.confirmPos(context);
    switch (action) {
      case null:
      case LeavePageAction.cancel:
        return false;
      case LeavePageAction.leaveDiscard:
        if (prepareLeave) {
          // Buang draft + ulang dari awal prosedur (scan kasir lagi).
          await _clearPosDraft();
          _resetForm();
          setState(() {
            isPosUnlocked = false;
            activeCashier = null;
            namaKasir = '';
            kasirCtrl.clear();
            isScanningLocal = true;
          });
        }
        return true;
      case LeavePageAction.leaveSave:
        if (prepareLeave) {
          await _savePosDraft();
          _resetForm();
        }
        return true;
    }
  }

  Future<void> _requestLeavePos() async {
    if (_leavingPos) return;
    _leavingPos = true;
    try {
      final ok = await _confirmPosLeave(prepareLeave: true);
      if (ok && mounted) Navigator.of(context).pop();
    } finally {
      _leavingPos = false;
    }
  }

  Future<void> _savePosDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'saved_at': DateTime.now().toIso8601String(),
        'no_invoice': noInvoice,
        'cart': cartItems,
        'customer': {
          'name': nameCtrl.text,
          'phone': phoneCtrl.text,
          'address': addressCtrl.text,
          'email': emailCtrl.text,
        },
        'discount': discountCtrl.text,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus,
        'paid': paidCtrl.text,
        'lens': {
          'sph_r': sphRCtrl.text,
          'sph_l': sphLCtrl.text,
          'cyl_r': cylRCtrl.text,
          'cyl_l': cylLCtrl.text,
          'add_r': addRCtrl.text,
          'add_l': addLCtrl.text,
          'axis_r': axisRCtrl.text,
          'axis_l': axisLCtrl.text,
          'pd_r': pdRCtrl.text,
          'pd_l': pdLCtrl.text,
          'old_active': isInputKacamataLamaActive,
          'sph_old_r': sphOldRCtrl.text,
          'cyl_old_r': cylOldRCtrl.text,
          'axis_old_r': axisOldRCtrl.text,
          'sph_old_l': sphOldLCtrl.text,
          'cyl_old_l': cylOldLCtrl.text,
          'axis_old_l': axisOldLCtrl.text,
        },
      };
      await prefs.setString(_posDraftPrefsKey, jsonEncode(payload));
      if (mounted) {
        _showSnack('pos_draft_saved'.tr(), Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('${'pos_draft_save_err'.tr()}$e', Colors.redAccent);
      }
    }
  }

  Future<void> _clearPosDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_posDraftPrefsKey);
    } catch (_) {}
  }

  Future<void> _restorePosDraftIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_posDraftPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);

      final cartRaw = map['cart'];
      final List<Map<String, dynamic>> restoredCart = [];
      if (cartRaw is List) {
        for (final item in cartRaw) {
          if (item is Map) {
            restoredCart.add(Map<String, dynamic>.from(item));
          }
        }
      }

      // Jangan timpa sesi keranjang yang masih hidup di memori.
      if (cartItems.isNotEmpty) return;

      final customer = map['customer'] is Map
          ? Map<String, dynamic>.from(map['customer'] as Map)
          : <String, dynamic>{};
      final lens = map['lens'] is Map
          ? Map<String, dynamic>.from(map['lens'] as Map)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        cartItems
          ..clear()
          ..addAll(restoredCart);
        final inv = (map['no_invoice'] ?? '').toString();
        if (inv.isNotEmpty) noInvoice = inv;
        nameCtrl.text = (customer['name'] ?? '').toString();
        phoneCtrl.text = (customer['phone'] ?? '').toString();
        addressCtrl.text = (customer['address'] ?? '').toString();
        emailCtrl.text = (customer['email'] ?? '').toString();
        discountCtrl.text = (map['discount'] ?? '0').toString();
        paymentMethod = (map['payment_method'] ?? paymentMethod).toString();
        paymentStatus = (map['payment_status'] ?? paymentStatus).toString();
        paidCtrl.text = (map['paid'] ?? '').toString();
        sphRCtrl.text = (lens['sph_r'] ?? sphRCtrl.text).toString();
        sphLCtrl.text = (lens['sph_l'] ?? sphLCtrl.text).toString();
        cylRCtrl.text = (lens['cyl_r'] ?? cylRCtrl.text).toString();
        cylLCtrl.text = (lens['cyl_l'] ?? cylLCtrl.text).toString();
        addRCtrl.text = (lens['add_r'] ?? addRCtrl.text).toString();
        addLCtrl.text = (lens['add_l'] ?? addLCtrl.text).toString();
        axisRCtrl.text = (lens['axis_r'] ?? axisRCtrl.text).toString();
        axisLCtrl.text = (lens['axis_l'] ?? axisLCtrl.text).toString();
        pdRCtrl.text = (lens['pd_r'] ?? pdRCtrl.text).toString();
        pdLCtrl.text = (lens['pd_l'] ?? pdLCtrl.text).toString();
        isInputKacamataLamaActive = lens['old_active'] == true;
        sphOldRCtrl.text = (lens['sph_old_r'] ?? sphOldRCtrl.text).toString();
        cylOldRCtrl.text = (lens['cyl_old_r'] ?? cylOldRCtrl.text).toString();
        axisOldRCtrl.text = (lens['axis_old_r'] ?? axisOldRCtrl.text).toString();
        sphOldLCtrl.text = (lens['sph_old_l'] ?? sphOldLCtrl.text).toString();
        cylOldLCtrl.text = (lens['cyl_old_l'] ?? cylOldLCtrl.text).toString();
        axisOldLCtrl.text = (lens['axis_old_l'] ?? axisOldLCtrl.text).toString();
      });

      if (restoredCart.isNotEmpty ||
          nameCtrl.text.trim().isNotEmpty ||
          phoneCtrl.text.trim().isNotEmpty) {
        _showSnack('pos_draft_restored'.tr(), Colors.blueAccent);
      }
    } catch (e) {
      debugPrint('POS draft restore failed: $e');
    }
  }

  Future<void> _cariProdukBySKU(String sku) async {
    setState(() => isProcessing = true);
    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';

      // 1. Cari Master Produk
      final res =
          await supabase.from('products').select().eq('sku', sku).maybeSingle();

      if (res != null) {
        // 2. Cek Stok di Cabang Tersebut
        final stockRes = await supabase
            .from('inventory_stocks')
            .select('stok')
            .eq('toko_id', tokoId)
            .eq('sku', sku)
            .maybeSingle();

        int stokAktif = stockRes != null ? (stockRes['stok'] ?? 0) : 0;

        if (stokAktif <= 0) {
          _showSnack("${"pos_stok_kosong".tr()} SKU: $sku", Colors.redAccent);
          return;
        }

        // 3. Pisahkan Logika Kategori Lensa vs Frame/Aksesoris
        if (res['kategori'] == 'Lensa') {
          if (lensScanSide == 'R') {
            setState(() {
              selectedLens = res;
              lensScanSide = 'L'; // Pindah minta scan lensa kiri
            });
            _showSnack("pos_lensa_r_sukses".tr(), Colors.green);
          } else {
            // Jika Lensa Kiri di-scan
            setState(() {
              _tambahKeKeranjangLensaLangsung(selectedLens, res);
              lensScanSide = 'R'; // Reset kembali ke kanan
              selectedLens = null;
            });
            _showSnack("pos_lensa_l_sukses".tr(), Colors.green);
          }
        } else {
          // Logika untuk Frame & Aksesoris
          _tambahItemKeKeranjang(res, stokAktif);
        }
      } else {
        _showSnack("pos_err_sku_tidak_terdaftar".tr(), Colors.orange);
      }
    } catch (e) {
      _showSnack("${"pos_err_search".tr()}$e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // ==========================================================================
  // MANAJEMEN KERANJANG BELANJA (CART)
  // ==========================================================================
  void _tambahItemKeKeranjang(Map<String, dynamic> produk, int stokGudang) {
    String nama = produk['nama'] ?? produk['nama_produk'] ?? "Unnamed";
    int harga = int.tryParse(produk['harga']?.toString() ??
            produk['harga_jual']?.toString() ??
            '0') ??
        0;
    String sku = produk['sku'] ?? "";
    dynamic idProduk =
        produk['id']; // 💡 Ambil ID Primary Key asli dari Supabase

    // 💡 REVISI UTAMA: Cari duplikat berdasarkan ID (paling aman), atau gabungan SKU + Nama jika ID kosong
    int existingIndex = cartItems.indexWhere((item) {
      if (idProduk != null && item['id'] == idProduk) return true;
      return item['sku'] == sku && item['nama'] == nama;
    });

    setState(() {
      if (existingIndex >= 0) {
        // Jika beneran item yang SAMA PERSIS di-add lagi, baru naikkan Qty
        int stokDiKeranjang = cartItems[existingIndex]['qty'];
        if (stokDiKeranjang + 1 > stokGudang) {
          _showSnack("Stok di keranjang melebihi batas gudang: $stokGudang",
              Colors.orange);
        } else {
          cartItems[existingIndex]['qty']++;
          // Hitung subtotal menggunakan harga asli item itu sendiri yang sudah tersimpan
          int hargaItemTerbaca = cartItems[existingIndex]['harga'] ?? harga;
          cartItems[existingIndex]['subtotal'] =
              cartItems[existingIndex]['qty'] * hargaItemTerbaca;
          _showSnack("$nama berhasil ditambahkan", Colors.greenAccent);
        }
      } else {
        // Jika barang berbeda (walau sama-sama tanpa SKU), buat baris BARU di Order List
        cartItems.add({
          'id': idProduk, // Simpan ID untuk validasi unik pencarian ulang
          'nama_produk': nama,
          'nama': nama,
          'sku': sku.isEmpty ? "No SKU" : sku,
          'harga': harga,
          'harga_jual': harga,
          'qty': 1,
          'subtotal': harga,
          'kategori': produk['kategori'],
          'is_lensa_custom': false,
        });
        _showSnack("$nama berhasil ditambahkan", Colors.greenAccent);
      }
    });
  }

// 🎯 REVISI FINAL: SPLIT LENSA KANAN & KIRI JADI 2 ITEM MANDIRI (AKURAT POTONG STOK & HARGA)
  void _tambahKeKeranjangLensaLangsung(
      Map<String, dynamic>? lensaR, Map<String, dynamic>? lensaL) {
    if (lensaR == null || lensaL == null) return;

    setState(() {
      // 🟢 1. MASUKKAN LENSA MATA KANAN (R)
      int hargaR = int.tryParse(lensaR['harga']?.toString() ?? '0') ?? 0;

      // Racik info ukuran kanan: Otomatis tambah ADD jika Progresif/Kryptok
      String infoR = "${sphRCtrl.text}/${cylRCtrl.text}";
      if (lensaR['jenis_lensa'] == 'Progresif' ||
          lensaR['jenis_lensa'] == 'Kryptok') {
        infoR += " ADD ${addRCtrl.text}";
      }

      String namaR =
          "Lensa (R): ${lensaR['nama'] ?? 'Lensa'} ${lensaR['jenis_lensa'] ?? ''} ($infoR)";
      dynamic idR = lensaR['id'];
      String skuR = lensaR['sku'] ?? "";

      int idxR = cartItems.indexWhere((item) =>
          idR != null &&
          item['id'] == idR &&
          item['nama_produk'].contains('(R)'));
      if (idxR >= 0) {
        cartItems[idxR]['qty']++;
        cartItems[idxR]['subtotal'] =
            cartItems[idxR]['qty'] * (cartItems[idxR]['harga'] as int);
      } else {
        cartItems.add({
          'id': idR,
          'nama_produk': namaR,
          'nama': namaR,
          'sku': skuR.isEmpty ? "No SKU" : skuR,
          'harga': hargaR,
          'harga_jual': hargaR,
          'qty': 1,
          'subtotal': hargaR,
          'kategori': 'Lensa',
          'is_lensa_custom': false,
        });
      }

      // 🔵 2. MASUKKAN LENSA MATA KIRI (L)
      int hargaL = int.tryParse(lensaL['harga']?.toString() ?? '0') ?? 0;

      // Racik info ukuran kiri: Otomatis tambah ADD jika Progresif/Kryptok
      String infoL = "${sphLCtrl.text}/${cylLCtrl.text}";
      if (lensaL['jenis_lensa'] == 'Progresif' ||
          lensaL['jenis_lensa'] == 'Kryptok') {
        infoL += " ADD ${addLCtrl.text}";
      }

      String namaL =
          "Lensa (L): ${lensaL['nama'] ?? 'Lensa'} ${lensaL['jenis_lensa'] ?? ''} ($infoL)";
      dynamic idL = lensaL['id'];
      String skuL = lensaL['sku'] ?? "";

      int idxL = cartItems.indexWhere((item) =>
          idL != null &&
          item['id'] == idL &&
          item['nama_produk'].contains('(L)'));
      if (idxL >= 0) {
        cartItems[idxL]['qty']++;
        cartItems[idxL]['subtotal'] =
            cartItems[idxL]['qty'] * (cartItems[idxL]['harga'] as int);
      } else {
        cartItems.add({
          'id': idL,
          'nama_produk': namaL,
          'nama': namaL,
          'sku': skuL.isEmpty ? "No SKU" : skuL,
          'harga': hargaL,
          'harga_jual': hargaL,
          'qty': 1,
          'subtotal': hargaL,
          'kategori': 'Lensa',
          'is_lensa_custom': false,
        });
      }
    });
  }

  void _hapusDariKeranjang(int index) {
    setState(() {
      cartItems.removeAt(index);
    });
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
    ));
  }

  // ==========================================================================
  // WIDGET DIALOG: INPUT JUMLAH PENDING REQUEST / PRE-ORDER (LINT FIXED)
  // ==========================================================================
  void _showPendingRequestDialog(
      Map<String, dynamic> item, int sisaStokGudang) {
    // ✅ FIX 1: Singkirkan underscore (_) pada variabel lokal agar sesuai standar Dart rule
    final TextEditingController qtyPoCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            const Icon(Icons.shopping_bag_outlined, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Text(
              "Stok Terbatas! (Sisa: $sisaStokGudang)",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Produk: ${item['nama_produk'] ?? item['nama']}",
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 15),
            const Text("Masukkan Jumlah Kekurangan (Pre-Order):",
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: qtyPoCtrl, // ✅ Menggunakan nama variabel baru
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Contoh: 2",
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                filled: true,
                fillColor: OptikAdminTokens.bgMid,
                // ✅ FIX 2: Bersihkan kata 'const' tidak perlu agar compiler adem
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              int qtyNeeded = int.tryParse(qtyPoCtrl.text) ??
                  0; // ✅ Menggunakan nama variabel baru
              if (qtyNeeded <= 0) {
                _showSnack("Jumlah harus lebih dari 0", Colors.red);
                return;
              }

              try {
                final tokoId = widget.profile['toko_id'] ?? 'PUSAT';

                final inserted =
                    await supabase.from('pending_requests').insert({
                  'toko_id': tokoId,
                  'no_invoice':
                      noInvoice, // 👈 HUBUNGKAN KE INVOICE AKTIF UNTUK TRACKING
                  'nama_pelanggan':
                      nameCtrl.text, // 👈 NAMA PELANGGAN UNTUK PENCARIAN CRM
                  'sku': item['sku'] == "No SKU" ? null : item['sku'],
                  'nama_produk': item['nama_produk'] ?? item['nama'],
                  'kategori': item['kategori'],
                  'qty_request': qtyNeeded,
                  'tipe_request':
                      sisaStokGudang <= 0 ? 'RESTOCK_LIMIT' : 'PRE_ORDER',
                  'status': 'PENDING',
                  'tracking_status': 'DIPROSES_DI_CABANG'
                }).select('id').single();

                Navigator.pop(context);
                if (TrainingMode.instance.isActive && mounted) {
                  final outcome = await TrainingApprovalSimulator
                      .simulatePendingRequestIfTraining(
                    context,
                    id: inserted['id'],
                    body: 'training_approval_sim_body_request_order'.tr(),
                    trackingFor: RequestOrderService.trackingFor,
                  );
                  _showSnack(
                    'training_ro_outcome_${outcome?.name ?? 'pending'}'.tr(),
                    const Color(0xFFB45309),
                  );
                } else {
                  _showSnack(
                      "✓ Berhasil mencatat $qtyNeeded pcs Pre-Order ke data pusat",
                      Colors.green);
                }
              } catch (e) {
                _showSnack("Gagal menyimpan request: $e", Colors.red);
              }
            },
            child: const Text("Simpan Request",
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // POP-UP PENCARIAN & PEMILIHAN PRODUK MANUAL
  // ==========================================================================
  void _munculkanDialogPilihFrame(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        String searchQuery = "";
        List<dynamic> searchResults = [];
        bool isLoading = false;
        bool hasFetchedInit = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void cariDataFrame({bool initLoad = false}) async {
              setStateDialog(() => isLoading = true);
              try {
                var query = supabase
                    .from('products')
                    .select()
                    .eq('kategori', 'Frame')
                    .eq('toko_id', widget.profile['toko_id']);

                if (!initLoad && searchQuery.trim().isNotEmpty) {
                  query = query
                      .or('sku.ilike.%$searchQuery%,nama.ilike.%$searchQuery%');
                }

                final res = await query.limit(20);
                setStateDialog(() {
                  searchResults = res as List<dynamic>;
                  isLoading = false;
                });
              } catch (e) {
                setStateDialog(() => isLoading = false);
              }
            }

            if (!hasFetchedInit) {
              hasFetchedInit = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                cariDataFrame(initLoad: true);
              });
            }

            return R.constrainedDialog(
              context: context,
              preferWidth: 360,
              child: AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              title: Text("pos_pilih_produk_frame".tr(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.infinity,
                height: (MediaQuery.sizeOf(context).height * 0.55).clamp(320.0, 450.0),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "pos_filter_nama_sku".tr(),
                        suffixIcon: const Icon(Icons.search,
                            color: Colors.orangeAccent, size: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        searchQuery = val;
                        cariDataFrame();
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.orangeAccent))
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text("pos_produk_tidak_ditemukan".tr(),
                                      style:
                                          const TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    var frame = searchResults[index];
                                    int stock = frame['stock'] ?? 0;
                                    String sku =
                                        frame['sku'] ?? "pos_tanpa_sku".tr();
                                    String fotoUrl = frame['foto_url'] ??
                                        frame['image_url'] ??
                                        "";

                                    return Card(
                                      color: Colors.white.withOpacity(0.03),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      child: ListTile(
                                        leading: Container(
                                          width: 45,
                                          height: 45,
                                          decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withOpacity(0.05),
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: fotoUrl.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: Image.network(fotoUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                              error,
                                                              stackTrace) =>
                                                          const Icon(
                                                              Icons
                                                                  .image_not_supported,
                                                              color:
                                                                  Colors.grey,
                                                              size: 18)))
                                              : const Icon(Icons.image,
                                                  color: Colors.white24,
                                                  size: 18),
                                        ),
                                        title: Text(
                                            frame['nama'] ??
                                                "pos_tanpa_nama".tr(),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold)),
                                        subtitle: Text(
                                            "SKU: $sku\nStok: $stock | Rp ${frame['harga'] ?? 0}",
                                            style: TextStyle(
                                                color: stock > 0
                                                    ? Colors.greenAccent
                                                    : Colors.redAccent,
                                                fontSize: 11)),
                                        isThreeLine: true,
                                        trailing: const Icon(
                                            Icons.add_shopping_cart,
                                            color: Colors.orangeAccent),
                                        onTap: () {
                                          if (stock <= 0) {
                                            _showSnack("pos_stok_kosong".tr(),
                                                Colors.red);
                                            return;
                                          }
                                          setState(() {
                                            selectedFrame = frame;
                                            isFrameActive = true;
                                          });
                                          Navigator.pop(ctx);
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }

  void _munculkanDialogPilihMerk(BuildContext context) {
    // 🎯 FIX SAKTI: Izinkan data master dari Cabang Aktif, PUSAT, atau yang bernilai NULL (Katalog Global)
    List<String> daftarMerkUnik = masterLensaProducts
        .where((e) =>
            e['toko_id'] == widget.profile['toko_id'] ||
            e['toko_id'] == 'PUSAT' ||
            e['toko_id'] == null)
        .map((e) =>
            (e['nama'] ?? "").toString()) // Dipastikan menembak kolom 'nama'
        .where((merk) => merk.trim().isNotEmpty)
        .toSet()
        .toList();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            List<String> filteredMerk = daftarMerkUnik
                .where(
                    (m) => m.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return R.constrainedDialog(
              context: context,
              preferWidth: 300,
              child: AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              title: const Text(
                  "pos_pilih_merk_lensa", // Menampilkan title konstan agar aman dari i18n crash
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.infinity,
                height: (MediaQuery.sizeOf(context).height * 0.5).clamp(280.0, 400.0),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Search brand...",
                        prefixIcon: const Icon(Icons.search,
                            color: Colors.orangeAccent, size: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (val) =>
                          setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredMerk.isEmpty
                          ? const Center(
                              child: Text("Brand not registered",
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: filteredMerk.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  title: Text(filteredMerk[index],
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13)),
                                  trailing: const Icon(Icons.arrow_forward_ios,
                                      color: Colors.grey, size: 12),
                                  onTap: () {
                                    setState(() => lensBrandCtrl.text =
                                        filteredMerk[index]);
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }

  void _munculkanDialogPilihLainnya(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        String searchQuery = "";
        List<dynamic> searchResults = [];
        bool isLoading = false;
        bool hasFetchedInit = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void cariDataLainnya({bool initLoad = false}) async {
              setStateDialog(() => isLoading = true);
              try {
                var query = supabase
                    .from('products')
                    .select()
                    .neq('kategori', 'Frame')
                    .neq('kategori', 'Lensa')
                    .eq('toko_id', widget.profile['toko_id']);
                if (!initLoad && searchQuery.trim().isNotEmpty) {
                  query = query
                      .or('sku.ilike.%$searchQuery%,nama.ilike.%$searchQuery%');
                }
                final res = await query.limit(20);
                setStateDialog(() {
                  searchResults = res as List<dynamic>;
                  isLoading = false;
                });
              } catch (e) {
                setStateDialog(() => isLoading = false);
              }
            }

            if (!hasFetchedInit) {
              hasFetchedInit = true;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => cariDataLainnya(initLoad: true));
            }

            return R.constrainedDialog(
              context: context,
              preferWidth: 360,
              child: AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              title: Text("pos_pilih_aksesoris".tr(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.infinity,
                height: (MediaQuery.sizeOf(context).height * 0.55).clamp(320.0, 450.0),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "pos_filter_nama_sku".tr(),
                        suffixIcon: const Icon(Icons.search,
                            color: Colors.orangeAccent, size: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        searchQuery = val;
                        cariDataLainnya();
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.orangeAccent))
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text("pos_produk_tidak_ditemukan".tr(),
                                      style:
                                          const TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    var item = searchResults[index];
                                    int stock = item['stock'] ?? 0;
                                    String sku =
                                        item['sku'] ?? "pos_tanpa_sku".tr();
                                    String fotoUrl = item['foto_url'] ??
                                        item['image_url'] ??
                                        "";

                                    return Card(
                                      color: Colors.white.withOpacity(0.03),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      child: ListTile(
                                        leading: Container(
                                          width: 45,
                                          height: 45,
                                          decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withOpacity(0.05),
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: fotoUrl.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: Image.network(fotoUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (c, e, s) =>
                                                          const Icon(
                                                              Icons
                                                                  .image_not_supported,
                                                              color:
                                                                  Colors.grey,
                                                              size: 18)))
                                              : const Icon(Icons.image,
                                                  color: Colors.white24,
                                                  size: 18),
                                        ),
                                        title: Text(
                                            item['nama'] ??
                                                "pos_tanpa_nama".tr(),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold)),
                                        subtitle: Text(
                                            "SKU: $sku\nStok: $stock | Rp ${item['harga'] ?? 0}",
                                            style: TextStyle(
                                                color: stock > 0
                                                    ? Colors.greenAccent
                                                    : Colors.redAccent,
                                                fontSize: 11)),
                                        isThreeLine: true,
                                        trailing: const Icon(
                                            Icons.add_shopping_cart,
                                            color: Colors.orangeAccent),
                                        onTap: () {
                                          setState(() {
                                            selectedAksesoris = item;
                                            isLainnyaActive = true;
                                          });
                                          Navigator.pop(ctx);
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }

// ==========================================================================
  // KALKULASI & CHECKOUT SISTEM (BULLETPROOF ID-BASED STOCK CONTROL)
  // ==========================================================================
  Future<void> _ubahQtyCartItem(int index, int delta) async {
    final item = cartItems[index];

    // 💡 GATES 1: Jika kasir menekan tombol PLUS (+), kunci dengan stok asli dari table products
    if (delta > 0) {
      try {
        int stokGudangReal = 0;

        // Validasi menggunakan ID Master Produk (Jauh lebih aman daripada SKU "No SKU")
        if (item['id'] != null) {
          final prodRes = await supabase
              .from('products')
              .select('stock')
              .eq('id', item['id'])
              .maybeSingle();

          stokGudangReal = prodRes != null ? (prodRes['stock'] ?? 0) : 0;
        }

        int qtyDiKeranjang = item['qty'] ?? 1;

        // Jika jumlah di keranjang sudah menyentuh atau melebihi stok asli (15), rem total & tawarkan PO!
        if (qtyDiKeranjang >= stokGudangReal) {
          _showPendingRequestDialog(item, stokGudangReal);
          return; // Menghentikan fungsi di sini agar angka tidak naik ke 16, 17, dst
        }
      } catch (e) {
        debugPrint("Gagal mengunci kontrol stok fisik: $e");
      }
    }

    // GATES 2: Jika tombol MINUS (-) diklik atau stok laci toko masih tersedia
    setState(() {
      int currentQty = (cartItems[index]['qty'] ?? 1) as int;
      int newQty = currentQty + delta;

      if (newQty <= 0) {
        cartItems.removeAt(index);
      } else {
        cartItems[index]['qty'] = newQty;
        int hargaSatuan = (cartItems[index]['harga'] ?? 0) as int;
        cartItems[index]['subtotal'] = hargaSatuan * newQty;
      }
    });
  }

  int get _subtotalBelanja {
    return cartItems.fold(
        0, (sum, item) => sum + ((item['subtotal'] ?? 0) as int));
  }

  int get _totalAkhir {
    int diskon =
        int.tryParse(discountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    int total = _subtotalBelanja - diskon;
    return total < 0 ? 0 : total;
  }

// 🎯 FIXED FINAL CONFIG: DATA PELANGGAN KIRI, METADATA + KASIR KANAN, BADGE ATAS QR
  Future<void> _bukaLayarPreviewInvoice() async {
    if (cartItems.isEmpty) {
      _showSnack("pos_err_keranjang_kosong".tr(), Colors.red);
      return;
    }
    if (nameCtrl.text.isEmpty) {
      _showSnack("pos_err_nama_pelanggan".tr(), Colors.red);
      return;
    }

    String cabangLogin =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: () async {
            var res = await Supabase.instance.client
                .from('invoice_settings')
                .select()
                .eq('toko_id', cabangLogin)
                .maybeSingle();
            res ??= await Supabase.instance.client
                .from('invoice_settings')
                .select()
                .eq('toko_id', 'PUSAT')
                .maybeSingle();
            return res;
          }(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Colors.orangeAccent));
            }

            final config = snapshot.data ??
                {
                  'shop_name': 'OPTIK B. RISKI',
                  'address': 'Alamat Toko Cabang $cabangLogin',
                  'phone': '-',
                  'header_alignment': 'CENTER',
                  'font_size_header': 16,
                  'font_size_body': 12,
                  'show_qr_invoice': true,
                  'footer_text': 'Terima kasih atas kepercayaan Anda.'
                };

            final isCenter = config['header_alignment'] == 'CENTER';
            final double fHeader =
                (config['font_size_header'] ?? 16).toDouble();
            final double fBody = (config['font_size_body'] ?? 12).toDouble();

            // 🎯 MESIN PARSER MANDIRI: Ekstraksi resep murni langsung dari item keranjang belanja
            String ambilResepDariCart(String mata, String parameter) {
              try {
                final itemLensa = cartItems.firstWhere((e) =>
                    e['kategori'] == 'Lensa' &&
                    e['nama_produk'].toString().contains('($mata)'));

                String namaLengkap = itemLensa['nama_produk'].toString();
                final matchKurung =
                    RegExp(r'\(([^)]+)\)$').firstMatch(namaLengkap);
                if (matchKurung != null) {
                  String stringResep = matchKurung.group(1)!;
                  List<String> belahanSlash = stringResep.split('/');

                  if (parameter == 'SPH') return belahanSlash[0].trim();

                  if (belahanSlash.length > 1) {
                    String sisaTeks = belahanSlash[1];
                    if (sisaTeks.contains('ADD')) {
                      List<String> belahanAdd = sisaTeks.split('ADD');
                      if (parameter == 'CYL') return belahanAdd[0].trim();
                      if (parameter == 'ADD')
                        return "+${belahanAdd[1].trim().replaceAll('+', '')}";
                    } else {
                      if (parameter == 'CYL') return sisaTeks.trim();
                      if (parameter == 'ADD') return '0.00';
                    }
                  }
                }
              } catch (_) {}

              if (mata == 'R') {
                if (parameter == 'SPH') return sphRCtrl.text;
                if (parameter == 'CYL') return cylRCtrl.text;
                if (parameter == 'ADD') return addRCtrl.text;
              } else {
                if (parameter == 'SPH') return sphLCtrl.text;
                if (parameter == 'CYL') return cylLCtrl.text;
                if (parameter == 'ADD') return addLCtrl.text;
              }
              return '0.00';
            }

            String odSph = ambilResepDariCart('R', 'SPH');
            String odCyl = ambilResepDariCart('R', 'CYL');
            String odAdd = ambilResepDariCart('R', 'ADD');

            String osSph = ambilResepDariCart('L', 'SPH');
            String osCyl = ambilResepDariCart('L', 'CYL');
            String osAdd = ambilResepDariCart('L', 'ADD');

            String liveAxisR = axisRCtrl.text.isEmpty ? '0' : axisRCtrl.text;
            String liveAxisL = axisLCtrl.text.isEmpty ? '0' : axisLCtrl.text;
            String livePdR = pdRCtrl.text.isEmpty ? '-' : pdRCtrl.text;
            String livePdL = pdLCtrl.text.isEmpty ? '-' : pdLCtrl.text;

            final bool hasLensa = cartItems.any((item) =>
                item['nama_produk']
                    .toString()
                    .toLowerCase()
                    .contains('lensa') ||
                item['nama_produk']
                    .toString()
                    .toLowerCase()
                    .contains('progresif'));

            int uangMukaDP = paymentStatus == "DP"
                ? (int.tryParse(
                        paidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                    0)
                : _totalAkhir;
            int sisaTagihan =
                paymentStatus == "DP" ? (_totalAkhir - uangMukaDP) : 0;

            return R.constrainedDialog(
              context: context,
              preferWidth: 390,
              child: AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text("🔍 PRATINJAU NOTA PENJUALAN",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 15),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 🏢 1. SECTION HEADER
                            isCenter
                                ? SizedBox(
                                    width: double.infinity,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        if (config['logo_url'] != null &&
                                            config['logo_url']
                                                .toString()
                                                .isNotEmpty)
                                          Positioned(
                                            left: 0,
                                            top: -2.0,
                                            child: Image.network(
                                                config['logo_url'],
                                                height: 24,
                                                fit: BoxFit.contain),
                                          ),
                                        SizedBox(
                                          width: double.infinity,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                (config['shop_name'] ??
                                                        'OPTIK B. RISKI')
                                                    .toString()
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                    color:
                                                        OptikAdminTokens.bgMid,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: fHeader - 1,
                                                    letterSpacing: 0.5,
                                                    height: 1.0),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 45.0),
                                                child: Text(
                                                    config['address'] ?? '',
                                                    style: const TextStyle(
                                                        color: Colors.black54,
                                                        fontSize: 8.5,
                                                        height: 1.35),
                                                    textAlign:
                                                        TextAlign.center),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                  "Telp: ${config['phone'] ?? '-'}",
                                                  style: const TextStyle(
                                                      color: Colors.black87,
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                  textAlign: TextAlign.center),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (config['logo_url'] != null &&
                                          config['logo_url']
                                              .toString()
                                              .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 12.0),
                                          child: Image.network(
                                              config['logo_url'],
                                              height: 24,
                                              fit: BoxFit.contain),
                                        ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                (config['shop_name'] ??
                                                        'OPTIK B. RISKI')
                                                    .toString()
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                    color:
                                                        OptikAdminTokens.bgMid,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: fHeader - 1,
                                                    letterSpacing: 0.5)),
                                            const SizedBox(height: 4),
                                            Text(config['address'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.black54,
                                                    fontSize: 8.5,
                                                    height: 1.35),
                                                textAlign: TextAlign.end),
                                            const SizedBox(height: 1),
                                            Text(
                                                "Telp: ${config['phone'] ?? '-'}",
                                                style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 8.5,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 8),
                            const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Divider(
                                    color: Colors.black87,
                                    thickness: 1.5,
                                    height: 1),
                                SizedBox(height: 1.5),
                                Divider(
                                    color: Colors.black12,
                                    thickness: 0.5,
                                    height: 1),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // 📋 2. METADATA & DATA PELANGGAN (OVERHAULED FLIPPED POSITIONS)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 🌟 SISI KIRI: Sekarang memuat full Data Pelanggan (Rata Kiri)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("PELANGGAN",
                                          style: TextStyle(
                                              color: Colors.black38,
                                              fontSize: fBody - 4,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.8)),
                                      Text(nameCtrl.text.toUpperCase(),
                                          style: TextStyle(
                                              color: OptikAdminTokens.card,
                                              fontSize: fBody - 2,
                                              fontWeight: FontWeight.bold)),
                                      Text("WhatsApp: ${phoneCtrl.text}",
                                          style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 9.5)),
                                      Text(
                                          "Alamat: ${addressCtrl.text.isEmpty ? '-' : addressCtrl.text}",
                                          style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 9.5),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                          "Email: ${emailCtrl.text.isEmpty ? '-' : emailCtrl.text}",
                                          style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 9.5)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 15),
                                // 🌟 SISI KANAN: Sekarang memuat urusan administratif internal (Rata Kanan) + Nama Kasir Aktif
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(noInvoice,
                                        style: TextStyle(
                                            color: OptikAdminTokens.bgMid,
                                            fontWeight: FontWeight.bold,
                                            fontSize: fBody - 1,
                                            letterSpacing: 0.2)),
                                    const SizedBox(height: 4),
                                    Text(
                                        "Masuk: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}",
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 9.5)),
                                    const SizedBox(height: 2),
                                    Text(
                                        "Kasir: ${namaKasir.isNotEmpty ? namaKasir : (activeCashier?['nama'] ?? 'Staff')}",
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Divider(color: Colors.black12, height: 1),
                            const SizedBox(height: 6),

                            // 👓 3. SECTION RINCIAN BELANJA ITEM KASIR
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("RINCIAN ITEM PESANAN",
                                    style: TextStyle(
                                        color: Colors.black38,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8)),
                                const SizedBox(height: 4),
                                ...cartItems.map((item) {
                                  String formattedItemLine = "";
                                  String rawName = item['nama_produk'] ?? '-';
                                  String kategori = (item['kategori'] ?? '')
                                      .toString()
                                      .toLowerCase();

                                  if (kategori == 'frame' ||
                                      (item['sku'] != 'CUSTOM_HQ' &&
                                          !rawName
                                              .toUpperCase()
                                              .contains('LENSA'))) {
                                    String colorAttr = item['warna'] ??
                                        item['color'] ??
                                        item['frame_color'] ??
                                        'Hitam';
                                    String materialAttr = item['material'] ??
                                        item['bahan'] ??
                                        'Plastik';
                                    formattedItemLine =
                                        "Frame: $rawName, $materialAttr, $colorAttr (x${item['qty']})";
                                  } else if (kategori == 'lensa' ||
                                      rawName.toUpperCase().contains('LENSA') ||
                                      rawName
                                          .toUpperCase()
                                          .contains('PROGRESIF')) {
                                    String side = rawName.contains('(R)')
                                        ? 'Lensa (R)'
                                        : 'Lensa (L)';
                                    String cleanBrandName = rawName
                                        .replaceAll(
                                            RegExp(r'Lensa\s*\([RL]\):'), '')
                                        .trim();
                                    cleanBrandName = cleanBrandName
                                        .replaceAll(
                                            RegExp(
                                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                                            '')
                                        .trim();

                                    String jenis = "Standar";
                                    String merk = cleanBrandName;

                                    if (cleanBrandName
                                        .toLowerCase()
                                        .contains('progresif')) {
                                      merk = cleanBrandName
                                          .replaceAll(
                                              RegExp(r'progresif',
                                                  caseSensitive: false),
                                              '')
                                          .trim();
                                      jenis = "Progresif";
                                    } else if (cleanBrandName
                                        .toLowerCase()
                                        .contains('kryptok')) {
                                      merk = cleanBrandName
                                          .replaceAll(
                                              RegExp(r'kryptok',
                                                  caseSensitive: false),
                                              '')
                                          .trim();
                                      jenis = "Kryptok";
                                    }

                                    if (merk.isEmpty || merk == "Lensa")
                                      merk = "New Vision";

                                    String coating = item['sub_kategori'] ??
                                        item['bahan'] ??
                                        item['coating'] ??
                                        lensBahan;
                                    formattedItemLine =
                                        "$side: $merk, $jenis, $coating (x${item['qty']})";
                                  } else {
                                    formattedItemLine =
                                        "$rawName (x${item['qty']})";
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 2.0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(formattedItemLine,
                                              style: const TextStyle(
                                                  color: OptikAdminTokens.bgMid,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.2)),
                                        ),
                                        const SizedBox(width: 15),
                                        Text(
                                            formatRupiah(item['subtotal'] ?? 0),
                                            style: const TextStyle(
                                                color: OptikAdminTokens.bgMid,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),

                            // 👁️ 4. SECTION HASIL REFRAKSI MEDIS SINKRON TOTAL
                            if (hasLensa) ...[
                              const SizedBox(height: 4),
                              const Divider(color: Colors.black12, height: 1),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                    border: Border.all(color: Colors.black26),
                                    borderRadius: BorderRadius.circular(4)),
                                child: HScroll(
                                  minWidth: 480,
                                  child: Table(
                                  border:
                                      TableBorder.all(color: Colors.black12),
                                  columnWidths: const {
                                    0: FlexColumnWidth(1.8),
                                    1: FlexColumnWidth(2),
                                    2: FlexColumnWidth(2),
                                    3: FlexColumnWidth(2),
                                    4: FlexColumnWidth(2),
                                  },
                                  children: [
                                    TableRow(
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFF8FAFC)),
                                      children: [
                                        'OD/OS',
                                        'SPH',
                                        'CYL',
                                        'AXIS',
                                        'ADD'
                                      ]
                                          .map((txt) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 3),
                                                child: Text(txt,
                                                    style: const TextStyle(
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black45),
                                                    textAlign:
                                                        TextAlign.center),
                                              ))
                                          .toList(),
                                    ),
                                    TableRow(
                                      children: [
                                        'OD (Kanan)',
                                        odSph,
                                        odCyl,
                                        liveAxisR.endsWith('°')
                                            ? liveAxisR
                                            : "$liveAxisR°",
                                        odAdd
                                      ]
                                          .map((txt) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3),
                                              child: Text(txt,
                                                  style: const TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.w500),
                                                  textAlign: TextAlign.center)))
                                          .toList(),
                                    ),
                                    TableRow(
                                      children: [
                                        'OS (Kiri)',
                                        osSph,
                                        osCyl,
                                        liveAxisL.endsWith('°')
                                            ? liveAxisL
                                            : "$liveAxisL°",
                                        osAdd
                                      ]
                                          .map((txt) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3),
                                              child: Text(txt,
                                                  style: const TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.w500),
                                                  textAlign: TextAlign.center)))
                                          .toList(),
                                    ),
                                  ],
                                ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "PD Pasien (R/L): $livePdR / $livePdL mm",
                                    style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: (fBody - 3).clamp(8.0, 14.0),
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.1),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 4),
                            const Divider(color: Colors.black87, thickness: 1),
                            const SizedBox(height: 6),

                            // 💰 5. SECTION FINANSIAL & QR BLOCK
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: sisaTagihan > 0
                                              ? Colors.orange.shade50
                                              : Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: sisaTagihan > 0
                                                  ? Colors.orange.shade300
                                                  : Colors.green.shade300)),
                                      child: Text(
                                          sisaTagihan > 0 ? "DP" : "LUNAS",
                                          style: TextStyle(
                                              color: sisaTagihan > 0
                                                  ? Colors.orange.shade900
                                                  : Colors.green.shade900,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 8)),
                                    ),
                                    const SizedBox(height: 6),
                                    config['show_qr_invoice'] == true
                                        ? const Icon(Icons.qr_code_2,
                                            color: Colors.black87, size: 46)
                                        : const SizedBox(height: 46, width: 46),
                                  ],
                                ),
                                SizedBox(
                                  width: 210,
                                  child: Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(1.4),
                                      1: FlexColumnWidth(1.2)
                                    },
                                    children: [
                                      TableRow(
                                        children: [
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 1.5),
                                              child: Text("TOTAL BELANJA",
                                                  style: TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: fBody - 2,
                                                      fontWeight:
                                                          FontWeight.w500))),
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 1.5),
                                              child: Text(
                                                  formatRupiah(_totalAkhir),
                                                  style: TextStyle(
                                                      color: Colors.black,
                                                      fontSize: fBody - 2,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  textAlign: TextAlign.end)),
                                        ],
                                      ),
                                      TableRow(
                                        children: [
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 1.5),
                                              child: Text("UANG MUKA (DP)",
                                                  style: TextStyle(
                                                      color: Colors.black38,
                                                      fontSize: fBody - 3))),
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 1.5),
                                              child: Text(
                                                  formatRupiah(uangMukaDP),
                                                  style: TextStyle(
                                                      color: Colors.black45,
                                                      fontSize: fBody - 3),
                                                  textAlign: TextAlign.end)),
                                        ],
                                      ),
                                      TableRow(
                                        children: [
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3.0),
                                              child: Text(
                                                  "Sisa Piutang", // <-- Diubah jadi Sisa Piutang
                                                  style: TextStyle(
                                                      color: const Color(
                                                          0xFF0F172A),
                                                      fontSize: fBody - 1,
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3.0),
                                              child: Text(
                                                  formatRupiah(sisaTagihan),
                                                  style: TextStyle(
                                                      color: sisaTagihan > 0
                                                          ? Colors.red.shade700
                                                          : Colors
                                                              .green.shade700,
                                                      fontSize: fBody - 1,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  textAlign: TextAlign.end)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.black26),
                            const SizedBox(height: 4),

                            // 🎯 6. FOOTER NOTICE
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(config['footer_text'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 8.5,
                                      height: 1.35)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Edit Data Kembali",
                      style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _prosesCheckout();
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text("KONFIRMASI PEMBELIAN",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
            );
          },
        );
      },
    );
  }

  Future<void> _prosesCheckout() async {
    if (cartItems.isEmpty) {
      _showSnack("pos_err_keranjang_kosong".tr(), Colors.red);
      return;
    }
    if (nameCtrl.text.isEmpty) {
      _showSnack("pos_err_nama_pelanggan".tr(), Colors.red);
      return;
    }

    try {
      setState(() => isProcessing = true);

      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
      int total = _totalAkhir;

      // 🎯 SINKRONISASI FINANSIAL: Mengunci nilai nominal bayar sesuai status pilihan aktif di POS (Lunas/DP)
      int bayar = paymentStatus == "Lunas"
          ? total
          : (int.tryParse(paidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
              0);

      int sisa = total - bayar;
      if (sisa < 0) sisa = 0;

      debugPrint(
          "DEBUG KASIR ID: ${activeCashier?['id'] ?? widget.profile['id']}");

      // 1. Simpan Transaksi Utama ke Tabel 'sales' (Data Diri Mengalir Murni dari POS)
      final saleRes = await supabase
          .from('sales')
          .insert({
            'no_invoice': noInvoice,
            'toko_id': tokoId,
            'kasir_id': supabase.auth.currentUser!.id,
            // Karyawan yang unlock POS (untuk rating QR) — fallback auth admin
            'kasir_karyawan_id': activeCashier?['id'],
            'nama_kasir': activeCashier?['nama'] ?? widget.profile['nama'],
            'nama_pelanggan': nameCtrl.text.trim(),
            'no_wa': phoneCtrl.text.trim(),
            'alamat': addressCtrl.text.trim(),
            'email_pelanggan': emailCtrl.text.trim(),
            'total_harga': total,
            'dibayarkan': bayar,
            'sisa_tagihan': sisa,
            'kembalian': (paymentStatus == "Lunas" &&
                    (int.tryParse(paidCtrl.text
                                .replaceAll(RegExp(r'[^0-9]'), '')) ??
                            total) >
                        total)
                ? (int.tryParse(
                            paidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                        total) -
                    total
                : 0,
            'status_pembayaran':
                paymentStatus, // "Lunas" atau "DP" murni dari input tombol kasir
            'metode_pembayaran': paymentMethod,
            // Lunas = siap diambil; garansi baru jalan setelah scan ambil + foto hasil
            'tracking_status':
                paymentStatus == "Lunas" ? 'SIAP_DIAMBIL' : 'PENDING_PO',
          })
          .select()
          .single();

      final saleId = saleRes['id'];

      // 2. Simpan Item & Tembakkan Data Resep Riil POS ke Database (Anti-Isi Manual)
      for (var item in cartItems) {
        String resepKomplitFisik = "Normal";

        // 🎯 LOGIKA JIPLAKAN KLINIK: Jika item berkategori Lensa, sedot semua controller input tanpa terkecuali
        if (item['kategori'] == 'Lensa' ||
            item['nama_produk'].toString().toLowerCase().contains('lensa') ||
            item['nama_produk']
                .toString()
                .toLowerCase()
                .contains('progresif')) {
          resepKomplitFisik =
              "R: SPH ${sphRCtrl.text}/CYL ${cylRCtrl.text}/AXIS ${axisRCtrl.text}/ADD ${addRCtrl.text} | "
              "L: SPH ${sphLCtrl.text}/CYL ${cylLCtrl.text}/AXIS ${axisLCtrl.text}/ADD ${addLCtrl.text} | "
              "PD Pasien: ${pdRCtrl.text.isEmpty ? '-' : pdRCtrl.text}/${pdLCtrl.text.isEmpty ? '-' : pdLCtrl.text} mm";
        }

        await supabase.from('sales_items').insert({
          'sale_id': saleId,
          'product_id': item['id'],
          'tipe_produk': item['kategori'] ?? 'Lainnya',
          'nama_produk': item['nama_produk'],
          'harga_satuan': item['harga'],
          'qty': item['qty'],
          'subtotal': item['subtotal'],
          'detail_resep': item['is_lensa_custom'] == true
              ? 'Resep Kustom Terlampir'
              : resepKomplitFisik, // 🎯 DATA MASUK UTUH: Apa yang diketik di POS masuk ke detail invoice database harian
        });

        // Pengurangan Stok Utama Mengunci ID Unik
        if (item['id'] != null && item['is_lensa_custom'] == false) {
          try {
            final prodData = await supabase
                .from('products')
                .select('stock, id')
                .eq('id', item['id'])
                .eq('toko_id', tokoId)
                .single();

            int stokSekarang = (prodData['stock'] ?? 0) as int;
            int stokBaru = stokSekarang - (item['qty'] as int);

            await supabase
                .from('products')
                .update({'stock': stokBaru < 0 ? 0 : stokBaru}).eq(
                    'id', prodData['id']);
          } catch (e) {
            debugPrint("Gagal potong stok produk ID ${item['id']}: $e");
          }
        }

        // OTOMASI POTONG STOK PAKET BONUS FRAME
        if (item['kategori'] == 'Frame') {
          final List<String> bonusItems = ['Kotak Kacamata', 'Lap Kacamata'];
          for (String namaBonus in bonusItems) {
            try {
              final bonusData = await supabase
                  .from('products')
                  .select('id, stock')
                  .eq('nama', namaBonus)
                  .eq('toko_id', tokoId)
                  .maybeSingle();

              if (bonusData != null) {
                int stokBonusSekarang = (bonusData['stock'] ?? 0) as int;
                int stokBonusBaru = stokBonusSekarang - (item['qty'] as int);
                await supabase.from('products').update({
                  'stock': stokBonusBaru < 0 ? 0 : stokBonusBaru
                }).eq('id', bonusData['id']);
              }
            } catch (e) {
              debugPrint("Gagal potong otomatis item bonus: $e");
            }
          }
        }
      }

      // 2b. Kartu garansi otomatis untuk item Frame / Lensa
      try {
        final nKartu =
            await GaransiService().createKartuFromSale(saleId.toString());
        debugPrint('Garansi: $nKartu kartu dibuat untuk sale $saleId');
      } catch (e) {
        debugPrint('Garansi kartu gagal (sale tetap OK): $e');
      }

      // 3. Masukkan ke Buku Besar Keuangan (Finance Jurnal Otomatis)
      try {
        String namaPasienForm = nameCtrl.text.trim();
        await supabase.from('finance_transactions').insert({
          'toko_id': tokoId,
          'tanggal_transaksi': DateTime.now().toIso8601String().split('T')[0],
          'jenis_transaksi': 'PEMASUKAN',
          'kategori': 'Penjualan Kasir',
          'deskripsi': 'Penjualan Kasir POS: $noInvoice ($namaPasienForm)',
          'nominal': bayar,
          'status_pembayaran': paymentStatus == "Lunas" ? 'LUNAS' : 'DP',
          'metode_pembayaran': paymentMethod,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint("Buku besar gagal mencatat pemasukan: $e");
      }

      // Training: harden cross-module sync (History / Finance / Garansi / stok).
      if (TrainingMode.instance.isActive) {
        try {
          final sync = await TrainingOpsSync.ensureAfterPosCheckout(
            saleId: saleId.toString(),
            tokoId: tokoId.toString(),
            noInvoice: noInvoice,
            namaPelanggan: nameCtrl.text.trim(),
            bayar: bayar,
            paymentStatus: paymentStatus,
            paymentMethod: paymentMethod,
            cartSnapshot: List<Map<String, dynamic>>.from(cartItems),
          );
          debugPrint(
            '[Training] POS sync ok=${sync.allOk} '
            'warranty=${sync.warrantyCards} errors=${sync.errors}',
          );
        } catch (e) {
          debugPrint('[Training] POS sync ensure failed: $e');
        }
      }

      // 4. Kirim Nota Sultan Beserta PDF Terintegrasi ke Email Customer
      try {
        await _generateAndSharePDF(saleRes, cartItems);
      } catch (emailErr) {
        debugPrint("Sistem background email tertunda: $emailErr");
      }

      if (!mounted) return;

      // 5. Lempar ke Halaman Struk Nota Akhir
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InvoiceDetailPage(saleId: saleId.toString()),
        ),
      ).then((_) async {
        await _clearPosDraft();
        _resetForm();
        setState(() {
          isPosUnlocked = false;
          activeCashier = null;
          namaKasir = "";
          kasirCtrl.clear();
          isScanningLocal = true;
        });
      });
    } catch (e) {
      debugPrint("Checkout Engine Error: $e");
      _showSnack("${"pos_err_simpan_transaksi".tr()}$e", Colors.red);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

// MESIN PDF 1: OTOMATIS SAAT KASIR CHECKOUT (JIPLAK MURNI 100% DARI MODAL PRATINJAU)
  Future<void> _generateAndSharePDF(
      Map<String, dynamic> sale, List<dynamic> items) async {
    try {
      final pdf = pw.Document();

      final bool hasLensa = items.any((item) =>
          item['nama_produk'].toString().toLowerCase().contains('lensa') ||
          item['nama_produk'].toString().toLowerCase().contains('progresif'));

      int totalHarga = sale['total_harga'] ?? 0;
      int uangMukaDP = sale['dibayarkan'] ?? 0;
      int sisaTagihan = sale['sisa_tagihan'] ?? 0;

      String cabangNota = sale['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      var resConfig = await supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', cabangNota)
          .maybeSingle();
      resConfig ??= await supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', 'PUSAT')
          .maybeSingle();

      final config = resConfig ??
          {
            'shop_name': 'OPTIK B. RISKI CIMAHI',
            'address':
                'Jl. Jend. H. Amir Machmud No.280a, Sukaraja, Kec. Cicendo, Kota Bandung, Jawa Barat 40522',
            'phone': '082223417848',
            'header_alignment': 'CENTER',
            'font_size_header': 16,
            'font_size_body': 12,
            'show_qr_invoice': true,
            'footer_text': 'Terima kasih atas kepercayaan Anda.'
          };

      final double fHeader = (config['font_size_header'] ?? 16).toDouble();
      final double fBody = (config['font_size_body'] ?? 12).toDouble();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 🏢 1. SECTION HEADER (SINKRON REVISI CENTERED)
                pw.SizedBox(
                  width: double.infinity,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        (config['shop_name'] ?? 'OPTIK B. RISKI')
                            .toString()
                            .toUpperCase(),
                        style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF0F172A),
                            fontWeight: pw.FontWeight.bold,
                            fontSize: fHeader - 2),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        config['address'] ?? '',
                        style:
                            pw.TextStyle(color: PdfColors.grey700, fontSize: 8),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        "Telp: ${config['phone'] ?? '-'}",
                        style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF263238),
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Divider(
                        color: PdfColor.fromInt(0xFF000000),
                        thickness: 1.5,
                        height: 1),
                    pw.SizedBox(height: 1.5),
                    pw.Divider(
                        color: PdfColor.fromInt(0xFFB0BEC5),
                        thickness: 0.5,
                        height: 1),
                  ],
                ),
                pw.SizedBox(height: 8),

                // 📋 2. METADATA & DATA PELANGGAN
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("PELANGGAN",
                            style: pw.TextStyle(
                                color: PdfColors.grey500,
                                fontSize: fBody - 4,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text(
                            (sale['nama_pelanggan'] ?? '-')
                                .toString()
                                .toUpperCase(),
                            style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF1E293B),
                                fontSize: fBody - 2,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text("WhatsApp: ${sale['no_wa'] ?? '-'}",
                            style: pw.TextStyle(
                                color: PdfColors.grey700, fontSize: 9.5)),
                        pw.Text("Alamat: ${sale['alamat'] ?? '-'}",
                            style: pw.TextStyle(
                                color: PdfColors.grey700, fontSize: 9.5)),
                        pw.Text("Email: ${sale['email_pelanggan'] ?? '-'}",
                            style: pw.TextStyle(
                                color: PdfColors.grey700, fontSize: 9.5)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(sale['no_invoice'] ?? '-',
                            style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF0F172A),
                                fontWeight: pw.FontWeight.bold,
                                fontSize: fBody - 1)),
                        pw.SizedBox(height: 4),
                        pw.Text(
                            "Masuk: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}",
                            style: pw.TextStyle(
                                color: PdfColors.grey700, fontSize: 9.5)),
                        pw.SizedBox(height: 2),
                        pw.Text("Kasir: ${sale['nama_kasir'] ?? 'Staff'}",
                            style: pw.TextStyle(
                                color: PdfColors.grey700,
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(color: PdfColors.grey300, height: 1),
                pw.SizedBox(height: 6),

                // 👓 3. SECTION RINCIAN BELANJA ITEM KASIR
                pw.Text("RINCIAN ITEM PESANAN",
                    style: pw.TextStyle(
                        color: PdfColors.grey500,
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                ...items.map((item) {
                  String rawName = item['nama_produk'] ?? '-';
                  if (rawName.toUpperCase().contains('LENSA') ||
                      rawName.toUpperCase().contains('PROGRESIF')) {
                    rawName = rawName
                        .replaceAll(
                            RegExp(
                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                            '')
                        .trim();
                  }
                  return pw.Padding(
                    padding: pw.EdgeInsets.symmetric(vertical: 4.0),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Text("• $rawName (x${item['qty'] ?? 1})",
                              style: pw.TextStyle(
                                  color: PdfColor.fromInt(0xFF0F172A),
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.SizedBox(width: 15),
                        pw.Text(formatRupiah((item['subtotal'] ?? 0) as int),
                            style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF0F172A),
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  );
                }),

                // 📊 4. SECTION REFRAKSI KLINIS LENSA
                if (hasLensa) ...[
                  pw.SizedBox(height: 4),
                  pw.Divider(color: PdfColors.grey300, height: 1),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.8),
                        1: pw.FlexColumnWidth(2),
                        2: pw.FlexColumnWidth(2),
                        3: pw.FlexColumnWidth(2),
                        4: pw.FlexColumnWidth(2)
                      },
                      children: [
                        pw.TableRow(
                          decoration:
                              pw.BoxDecoration(color: PdfColors.grey100),
                          children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.grey600),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OD (Kanan)',
                            sphRCtrl.text,
                            cylRCtrl.text,
                            axisRCtrl.text.endsWith('°')
                                ? axisRCtrl.text
                                : "${axisRCtrl.text}°",
                            addRCtrl.text
                          ]
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 9, color: PdfColors.black),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OS (Kiri)',
                            sphLCtrl.text,
                            cylLCtrl.text,
                            axisLCtrl.text.endsWith('°')
                                ? axisLCtrl.text
                                : "${axisLCtrl.text}°",
                            addLCtrl.text
                          ]
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 9, color: PdfColors.black),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.only(top: 6, left: 4),
                    child: pw.Text(
                        "PD Pasien (R/L): ${pdRCtrl.text.isEmpty ? '0' : pdRCtrl.text} / ${pdLCtrl.text.isEmpty ? '0' : pdLCtrl.text} mm",
                        style: pw.TextStyle(
                            color: PdfColors.black,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                ],

                pw.SizedBox(height: 4),
                pw.Divider(color: PdfColors.black, thickness: 1),
                pw.SizedBox(height: 6),

                // 💰 5. SECTION FINANSIAL SUMMARY
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Container(
                          padding: pw.EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                              color: sisaTagihan > 0
                                  ? PdfColor.fromInt(0xFFFFF3E0)
                                  : PdfColor.fromInt(0xFFE6F4EA),
                              borderRadius: pw.BorderRadius.circular(4),
                              border: pw.Border.all(
                                  color: sisaTagihan > 0
                                      ? PdfColors.orange300
                                      : PdfColor.fromInt(0xFF34A853))),
                          child: pw.Text(sisaTagihan > 0 ? "DP" : "LUNAS",
                              style: pw.TextStyle(
                                  color: sisaTagihan > 0
                                      ? PdfColors.orange900
                                      : PdfColor.fromInt(0xFF137333),
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 8)),
                        ),
                        pw.SizedBox(height: 6),
                        if (config['show_qr_invoice'] == true)
                          pw.Container(
                              height: 44,
                              width: 44,
                              child: pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: InvoiceLink.encode(
                                      sale['no_invoice']?.toString() ??
                                          'EMPTY'),
                                  padding: pw.EdgeInsets.zero)),
                      ],
                    ),
                    pw.SizedBox(
                      width: 210,
                      child: pw.Table(
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.4),
                          1: pw.FlexColumnWidth(1.2)
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                  padding:
                                      pw.EdgeInsets.symmetric(vertical: 1.5),
                                  child: pw.Text("TOTAL BELANJA",
                                      style: pw.TextStyle(
                                          color: PdfColors.grey700,
                                          fontSize: fBody - 2,
                                          fontWeight: pw.FontWeight.bold))),
                              pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(
                                      vertical: 1.5),
                                  child: pw.Text(formatRupiah(totalHarga),
                                      style: pw.TextStyle(
                                          color: PdfColors.black,
                                          fontSize: fBody - 2,
                                          fontWeight: pw.FontWeight.bold),
                                      textAlign: pw.TextAlign.end)),
                            ],
                          ),
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                  padding:
                                      pw.EdgeInsets.symmetric(vertical: 1.5),
                                  child: pw.Text("UANG MUKA (DP)",
                                      style: pw.TextStyle(
                                          color: PdfColors.grey500,
                                          fontSize: fBody - 3))),
                              pw.Padding(
                                  padding:
                                      pw.EdgeInsets.symmetric(vertical: 1.5),
                                  child: pw.Text(formatRupiah(uangMukaDP),
                                      style: pw.TextStyle(
                                          color: PdfColors.grey600,
                                          fontSize: fBody - 3),
                                      textAlign: pw.TextAlign.end)),
                            ],
                          ),
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                  padding:
                                      pw.EdgeInsets.symmetric(vertical: 3.0),
                                  child: pw.Text("SISA TAGIHAN",
                                      style: pw.TextStyle(
                                          color: PdfColor.fromInt(0xFF0F172A),
                                          fontSize: fBody - 1,
                                          fontWeight: pw.FontWeight.bold))),
                              pw.Padding(
                                  padding:
                                      pw.EdgeInsets.symmetric(vertical: 3.0),
                                  child: pw.Text(formatRupiah(sisaTagihan),
                                      style: pw.TextStyle(
                                          color: sisaTagihan > 0
                                              ? PdfColors.red700
                                              : PdfColor.fromInt(0xFF34A853),
                                          fontSize: fBody - 1,
                                          fontWeight: pw.FontWeight.bold),
                                      textAlign: pw.TextAlign.end)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 4),

                // 📝 6. FOOTER NOTICE
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(config['footer_text'] ?? '',
                      style: pw.TextStyle(
                          color: PdfColors.grey600, fontSize: 8.5)),
                ),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      String pdfBase64 = base64Encode(pdfBytes);

      await supabase.functions.invoke(
        'send-invoice-email',
        body: {
          'invoice': sale['no_invoice'] ?? 'INV-UNKNOWN',
          'email': sale['email_pelanggan'] ?? '',
          'customerName': sale['nama_pelanggan'] ?? 'Pelanggan Setia',
          'netTotal': totalHarga.toString(),
          'pdfBase64': pdfBase64,
        },
      );
    } catch (e) {
      debugPrint("Gagal orkestrasi pencetakan PDF: $e");
    }
  }

  void _resetForm() {
    setState(() {
      cartItems.clear();
      nameCtrl.clear();
      phoneCtrl.clear();
      addressCtrl.clear();
      emailCtrl.clear();
      discountCtrl.text = "0";
      paidCtrl.clear();
      _resetFormResepLensa();
      isInputKacamataLamaActive = false;
      _generateInvoice();
    });
  }

  void _resetFormResepLensa() {
    sphRCtrl.text = "0.00";
    sphLCtrl.text = "0.00";
    cylRCtrl.text = "0.00";
    cylLCtrl.text = "0.00";
    addRCtrl.text = "0.00";
    addLCtrl.text = "0.00";
    axisRCtrl.text = "0";
    axisLCtrl.text = "0";
    pdLCtrl.text = "0";
    pdRCtrl.text = "0";

    sphOldRCtrl.text = "0.00";
    cylOldRCtrl.text = "0.00";
    axisOldRCtrl.text = "0";
    sphOldLCtrl.text = "0.00";
    cylOldLCtrl.text = "0.00";
    axisOldLCtrl.text = "0";
  }

  @override
  Widget build(BuildContext context) {
    // Tampung widget UI ke dalam variable penampung sementara
    Widget currentUI;

    if (!isStoreOpen) {
      currentUI = _buildClosedStoreUI();
    } else if (isPosUnlocked && activeCashier != null) {
      // HID global di shell; intake lokal: SKU → cart, invoice → dialog draft POS.
      currentUI = HidScanIntake(
        onUnknown: (raw) async {
          await _cariProdukBySKU(raw);
          return true;
        },
        onBeforeNavigate: _guardPosLeaveForKnownQr,
        child: _buildSalesMainUI(),
      );
    } else {
      currentUI = _buildBarcodeScannerLayar();
    }

    // Back / swipe: dialog 3 opsi draft saat sesi toko buka.
    return PopScope(
      canPop: !isStoreOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestLeavePos();
      },
      child: currentUI,
    );
  }

  Widget _buildClosedStoreUI() {
    return Scaffold(
      body: Stack(
        children: [
          // Konten Utama Layar Penutupan Toko
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [OptikAdminTokens.bgMid, OptikAdminTokens.card],
              ),
            ),
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  _startSilentOpenStore();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront_rounded,
                          color: Colors.orangeAccent, size: 80),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      "TOKO SAAT INI TUTUP",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Sistem siap untuk dioperasikan",
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: 280,
                      height: 60,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          elevation: 8,
                          shadowColor: Colors.blueAccent.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.lock_open, color: Colors.white),
                        label: Text(
                          isLoading
                              ? "MENGINISIALISASI..."
                              : "MULAI SESI KASIR",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1),
                        ),
                        onPressed: isLoading ? null : _startSilentOpenStore,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Tekan ENTER untuk cepat",
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🎯 TRIK AMAN: Render kamera secara invisible di koordinat minus luar layar (Off-Screen)
          // Ini trik wajib di Chrome agar browser mau memproses takePicture() tanpa mendisplay video overlay ke user.
          if (isLoading &&
              _silentCameraController != null &&
              _silentCameraController!.value.isInitialized)
            Positioned(
              left: -1000,
              top: -1000,
              child: SizedBox(
                width: 10,
                height: 10,
                child: CameraPreview(_silentCameraController!),
              ),
            ),
        ],
      ),
    );
  }

// GERBANG 2: Layar Scan Barcode Kasir Penanggung Jawab (STERIL & AUTO-CLOSE CAMERA)
  Widget _buildBarcodeScannerLayar() {
    // ❌ BARIS "bool isScanningLocal = true;" SUDAH DIHAPUS DARI SINI AGAR TIDAK LOOPING REBUILD!

    return PremiumScaffold(
      // 🎯 SUNTIKAN SAKTI: Mengadakan AppBar transparan khusus untuk tombol kembali ke Dashboard Admin
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          tooltip: "Kembali ke Dashboard",
          onPressed: () async {
            await kameraLoginCtrl.stop();
            await _requestLeavePos();
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.blueAccent, size: 80),
              const SizedBox(height: 20),
              Text(
                "pos_otorisasi_kasir".tr(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                "pos_msg_scan_kasir".tr(),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 280,
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: MobileScanner(
                    fit: BoxFit.cover,
                    controller:
                        kameraLoginCtrl, // ✅ Gunakan controller kelas agar beneran bisa dimatikan
                    onDetect: (capture) async {
                      if (!isScanningLocal) return;

                      final barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty &&
                          barcodes.first.rawValue != null) {
                        final String scannedNik = barcodes.first.rawValue!;

                        setState(() {
                          isScanningLocal = false; // Kunci kamera instan
                        });

                        debugPrint(
                            "--- 🚨 LOG OPTIK: MENGECEK NIK DI SUPABASE = $scannedNik ---");

                        try {
                          final res = await supabase
                              .from('karyawan')
                              .select()
                              .eq('nik', scannedNik)
                              .maybeSingle();

                          if (res != null) {
                            debugPrint(
                                "--- ✅ LOG OPTIK: KARYAWAN DITEMUKAN = ${res['nama']} ---");

                            // ✅ KUNCI UTAMA: Matikan aliran video kamera laptop Bos biar gak melotot terus!
                            await kameraLoginCtrl.stop();

                            setState(() {
                              activeCashier = res;
                              namaKasir = res['nama'] ?? "";
                              kasirCtrl.text = namaKasir;
                              isPosUnlocked = true; // Gerbang POS Kasir terbuka
                            });
                          } else {
                            debugPrint(
                                "--- ❌ LOG OPTIK: NIK TIDAK TERDAFTAR ---");
                            _showSnack("Gagal Otorisasi: NIK tidak ditemukan!",
                                Colors.red);

                            // Beri jeda 3 detik sebelum kasir bisa nyecan ulang (biar gak spam loop)
                            await Future.delayed(const Duration(seconds: 3));
                            setState(() {
                              isScanningLocal = true; // Buka kunci kembali
                            });
                          }
                        } catch (e) {
                          debugPrint(
                              "--- 💥 LOG OPTIK: DATABASE EXCEPTION = $e ---");
                          _showSnack("Error Koneksi Database", Colors.red);

                          // Beri jeda 3 detik jika database error
                          await Future.delayed(const Duration(seconds: 3));
                          setState(() {
                            isScanningLocal = true; // Buka kunci kembali
                          });
                        }
                      }
                    },
                  ),
                ), // Penutup ClipRRect
              ), // Penutup SizedBox
              if (TrainingMode.instance.isActive) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB45309),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.school_rounded),
                    label: Text('training_pos_unlock_cashier'.tr()),
                    onPressed: () async {
                      try {
                        final res = await supabase
                            .from('karyawan')
                            .select()
                            .eq('nik', 'TRAINING01')
                            .maybeSingle();
                        if (res == null) {
                          _showSnack(
                            'training_pos_unlock_missing'.tr(),
                            Colors.red,
                          );
                          return;
                        }
                        await kameraLoginCtrl.stop();
                        setState(() {
                          activeCashier = res;
                          namaKasir = res['nama']?.toString() ?? 'Kasir Latihan';
                          kasirCtrl.text = namaKasir;
                          isPosUnlocked = true;
                          isScanningLocal = false;
                        });
                      } catch (e) {
                        _showSnack(
                          'training_msg_error'.tr().replaceAll('{}', '$e'),
                          Colors.red,
                        );
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _tambahKeRestockQueue(Map<String, dynamic> item) {
    setState(() {
      if (!restockQueue.any((element) => element['id'] == item['id'])) {
        restockQueue.add(item);
      }
    });
    _showSnack(
        "${item['nama']} ${"pos_msg_restock".tr()}", Colors.orangeAccent);
  }

  // ==========================================================================
  // UI TERMINAL UTAMA KASIR POS
  // ==========================================================================
  void _openAbsensiFromPos() {
    if (TrainingMode.instance.isActive) {
      _showSnack('training_pos_absensi_blocked'.tr(), const Color(0xFFB45309));
      return;
    }
    // Push (bukan replace) agar keranjang/transaksi POS tetap utuh saat kembali.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AbsensiPage()),
    );
  }

  Widget _buildSalesMainUI() {
    return PremiumScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'leave_title_pos'.tr(),
          onPressed: _requestLeavePos,
        ),
        title: Text(
          "pos_title".tr(),
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        actions: [
          if (R.isNarrow(context)) ...[
            IconButton(
              icon: const Icon(Icons.face_retouching_natural_rounded,
                  color: Colors.cyanAccent),
              tooltip: "pos_ttip_absen".tr(),
              onPressed: _openAbsensiFromPos,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              color: OptikAdminTokens.card,
              onSelected: (action) {
                switch (action) {
                  case 'close':
                    _prosesCloseStore();
                    break;
                  case 'lock':
                    _resetForm();
                    setState(() {
                      isPosUnlocked = false;
                      activeCashier = null;
                      namaKasir = "";
                      kasirCtrl.clear();
                      isScanningLocal = true;
                    });
                    _showSnack("Sesi dikunci. Silakan scan ID Karyawan baru.",
                        Colors.orange);
                    break;
                  case 'clear':
                    _resetForm();
                    _showSnack(
                        "Keranjang transaksi berhasil dikosongkan", Colors.red);
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'close',
                  child: Row(
                    children: [
                      const Icon(Icons.power_settings_new_rounded,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Text("pos_trip_close".tr()),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'lock',
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          color: Colors.orangeAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Lock & Switch Cashier'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep,
                          color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Kosongkan Keranjang'),
                    ],
                  ),
                ),
              ],
            ),
          ] else
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: "pos_ttip_absen".tr(),
                  child: TextButton.icon(
                    onPressed: _openAbsensiFromPos,
                    icon: const Icon(Icons.face_retouching_natural_rounded,
                        color: Colors.cyanAccent, size: 20),
                    label: Text(
                      "pos_btn_absen".tr(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded,
                      color: Colors.redAccent),
                  tooltip: "pos_trip_close".tr(),
                  onPressed: () => _prosesCloseStore(),
                ),
                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.lock_outline_rounded,
                      color: Colors.orangeAccent),
                  tooltip: "Lock & Switch Cashier",
                  onPressed: () {
                    _resetForm();
                    setState(() {
                      isPosUnlocked = false;
                      activeCashier = null;
                      namaKasir = "";
                      kasirCtrl.clear();
                      isScanningLocal = true;
                    });
                    _showSnack("Sesi dikunci. Silakan scan ID Karyawan baru.",
                        Colors.orange);
                  },
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.blueAccent.withOpacity(0.2),
                  backgroundImage: activeCashier?['face_url'] != null
                      ? NetworkImage(activeCashier!['face_url'])
                      : null,
                  child: activeCashier?['face_url'] == null
                      ? const Icon(Icons.person,
                          size: 16, color: Colors.blueAccent)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  namaKasir.isNotEmpty
                      ? namaKasir.split(' ')[0].toUpperCase()
                      : "STAFF",
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent),
                ),

                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                  tooltip: "pos_ttip_batal".tr(),
                  onPressed: () {
                    _resetForm();
                    _showSnack(
                        "Keranjang transaksi berhasil dikosongkan", Colors.red);
                  },
                )
              ],
            ),
          ),
        ],
      ),
      body: _buildBodyContent(),
    );
  }

  Widget _buildBodyContent() {
    return SafeArea(
      child: Column(
        children: [
          // Header Widget: Invoice & Live Clock
          Padding(
            padding: const EdgeInsets.all(20.0).copyWith(bottom: 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "pos_status_aktif".tr(),
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        noInvoice.isNotEmpty ? noInvoice : "pos_memuat".tr(),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                  const Row(
                    children: [
                      Icon(Icons.calendar_month,
                          color: Colors.blueAccent, size: 16),
                      SizedBox(width: 8),
                      LiveClock(),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Area Scrollable Utama
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // --- BAGIAN 1: DATA PELANGGAN ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: OptikAdminTokens.card,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCardTitle(
                            "pos_data_pelanggan".tr(), Icons.person_pin),
                        TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "pos_nama_pasien".tr(),
                            prefixIcon: const Icon(Icons.badge, size: 20),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Flexible(
                              fit: FlexFit.loose,
                              child: TextField(
                                controller: phoneCtrl,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: "pos_wa".tr(),
                                  prefixIcon: const Icon(Icons.phone, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              fit: FlexFit.loose,
                              child: TextField(
                                controller: addressCtrl,
                                maxLines: 2,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: "pos_alamat".tr(),
                                  prefixIcon:
                                      const Icon(Icons.location_on, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "pos_email".tr(),
                            prefixIcon: const Icon(Icons.email, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- BAGIAN 2: INPUT TRANSAKSI BARANG ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: OptikAdminTokens.card,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                            color: Colors.blueAccent.withOpacity(0.3))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCardTitle(
                            "pos_input_barang".tr(), Icons.inventory),
                        const SizedBox(height: 15),

                        // 1. KOLOM SCANNER GLOBAL (HID → field jika fokusokus; else HardwareBarcodeListener)
                        TextField(
                          controller: skuScanCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "pos_scan_global".tr(),
                            labelStyle: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                            prefixIcon: const Icon(Icons.search,
                                size: 18, color: Colors.blueAccent),
                            suffixIcon: Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: IconButton(
                                icon: const Icon(Icons.qr_code_scanner,
                                    color: Colors.blueAccent),
                                onPressed: () async {
                                  final code = await _scanBarcode();
                                  if (code == null || code.isEmpty) return;
                                  await _onPosScanSubmitted(code);
                                },
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: _onPosScanSubmitted,
                        ),
                        const SizedBox(height: 20),

                        // 2. TOMBOL KATEGORI MANUAL (BISA AKTIF BARENGAN)
                        Row(
                          children: [
                            Flexible(
                              fit: FlexFit.loose,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isFrameActive
                                      ? Colors.blueAccent
                                      : Colors.black26,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: Icon(Icons.filter_frames,
                                    color: isFrameActive
                                        ? Colors.white
                                        : Colors.grey,
                                    size: 16),
                                label: Text("pos_btn_frame".tr(),
                                    style: TextStyle(
                                        color: isFrameActive
                                            ? Colors.white
                                            : Colors.grey,
                                        fontSize: 11)),
                                onPressed: () => setState(
                                    () => isFrameActive = !isFrameActive),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              fit: FlexFit.loose,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isLensaActive
                                      ? Colors.blueAccent
                                      : Colors.black26,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: Icon(Icons.visibility,
                                    color: isLensaActive
                                        ? Colors.white
                                        : Colors.grey,
                                    size: 16),
                                label: Text("pos_btn_lensa".tr(),
                                    style: TextStyle(
                                        color: isLensaActive
                                            ? Colors.white
                                            : Colors.grey,
                                        fontSize: 11)),
                                onPressed: () => setState(
                                    () => isLensaActive = !isLensaActive),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              fit: FlexFit.loose,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isLainnyaActive
                                      ? Colors.blueAccent
                                      : Colors.black26,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: Icon(Icons.more_horiz,
                                    color: isLainnyaActive
                                        ? Colors.white
                                        : Colors.grey,
                                    size: 16),
                                label: Text("pos_btn_lainnya".tr(),
                                    style: TextStyle(
                                        color: isLainnyaActive
                                            ? Colors.white
                                            : Colors.grey,
                                        fontSize: 11)),
                                onPressed: () => setState(
                                    () => isLainnyaActive = !isLainnyaActive),
                              ),
                            ),
                          ],
                        ),

                        // ==========================================================
                        // --- SUB: BINGKAI (FRAME) ---
                        // ==========================================================
                        if (isFrameActive) ...[
                          const SizedBox(height: 15),
                          if (selectedFrame != null) ...[
                            Builder(builder: (context) {
                              int stock = selectedFrame!['stock'] ?? 0;
                              bool stokHabis = stock <= 0;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(selectedFrame!['nama'] ?? 'Frame',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  stokHabis
                                      ? "pos_stok_habis".tr()
                                      : "${"pos_stok_tersedia".tr()} $stock | Rp ${selectedFrame!['harga']}",
                                  style: TextStyle(
                                      color: stokHabis
                                          ? Colors.redAccent
                                          : Colors.greenAccent),
                                ),
                                trailing: SizedBox(
                                  width:
                                      145, // 👈 KUNCI UTAMA: Mengunci lebar tombol kasir agar tidak melar
                                  child: stokHabis
                                      ? ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal:
                                                    6), // Biar text muat
                                          ),
                                          icon: const Icon(Icons.local_shipping,
                                              size: 14),
                                          label: Text(
                                            "pos_btn_restock".tr(),
                                            style: const TextStyle(
                                                fontSize:
                                                    11), // Perkecil sedikit font-nya
                                          ),
                                          onPressed: () =>
                                              _tambahKeRestockQueue(
                                                  selectedFrame!),
                                        )
                                      : ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6),
                                          ),
                                          onPressed: () {
                                            _tambahItemKeKeranjang(
                                                selectedFrame!, stock);
                                            setState(
                                                () => selectedFrame = null);
                                          },
                                          child: Text(
                                            "pos_btn_tambah".tr(),
                                            style:
                                                const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                ), // Penutup SizedBox
                              );
                            }),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        Colors.orangeAccent.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("pos_cari_frame".tr(),
                                      style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  TextField(
                                    readOnly: true,
                                    onTap: () =>
                                        _munculkanDialogPilihFrame(context),
                                    style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: "pos_hint_cari_frame".tr(),
                                      labelStyle: const TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      suffixIcon: const Icon(Icons.touch_app,
                                          color: Colors.orangeAccent, size: 20),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.05),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide.none),
                                    ),
                                  )
                                ],
                              ),
                            )
                          ]
                        ],

                        // ==========================================================
                        // --- SUB: LENSA MANUAL (BACK TO BASIC) ---
                        // ==========================================================
                        if (isLensaActive) ...[
                          const Divider(color: Colors.white10, height: 30),
                          Text("pos_id_lensa".tr(),
                              style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),

                          // 1. MERK, JENIS, COATING
                          Row(
                            children: [
                              Flexible(
                                fit: FlexFit.tight,
                                child: TextField(
                                  controller: lensBrandCtrl,
                                  readOnly:
                                      true, // Kunci agar memilih dari master
                                  onTap: () =>
                                      _munculkanDialogPilihMerk(context),
                                  style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    labelText: "pos_merk_lensa".tr(),
                                    labelStyle: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 12),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none),
                                    suffixIcon: const Icon(Icons.search,
                                        color: Colors.orangeAccent, size: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                fit: FlexFit.tight,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  dropdownColor: OptikAdminTokens.card,
                                  value: ["Standar", "Progresif", "Kryptok"]
                                          .contains(lensJenis)
                                      ? lensJenis
                                      : "Standar",
                                  decoration: InputDecoration(
                                      labelText: "pos_jenis_lensa".tr()),
                                  items: ["Standar", "Progresif", "Kryptok"]
                                      .map((e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e,
                                              style: const TextStyle(
                                                  fontSize: 12))))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => lensJenis = v!),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                fit: FlexFit.tight,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  dropdownColor: OptikAdminTokens.card,
                                  value: [
                                    'Supersin',
                                    'Blueray',
                                    'Photochromic',
                                    'Bluechromic',
                                    'Night Driving',
                                    'Antifog'
                                  ].contains(lensBahan)
                                      ? lensBahan
                                      : 'Supersin',
                                  decoration: InputDecoration(
                                      labelText: "pos_bahan_lensa".tr()),
                                  items: [
                                    'Supersin',
                                    'Blueray',
                                    'Photochromic',
                                    'Bluechromic',
                                    'Night Driving',
                                    'Antifog'
                                  ]
                                      .map((e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e,
                                              style: const TextStyle(
                                                  fontSize: 12))))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => lensBahan = v!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),

                          // 2. MATRIKS UKURAN & MULTIFOKAL (KANAN)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                fit: FlexFit.tight,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("pos_mata_kanan".tr(),
                                          style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 12),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Align(
                                                alignment: Alignment.center,
                                                child: ResepInput(
                                                    label: "SPH (R)",
                                                    controller: sphRCtrl,
                                                    onChanged: (v) =>
                                                        setState(() {}))),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                ResepInput(
                                                    label: "CYL (R)",
                                                    controller: cylRCtrl,
                                                    onChanged: (v) =>
                                                        setState(() {})),
                                                if ((double.tryParse(cylRCtrl
                                                            .text
                                                            .replaceAll(
                                                                ',', '.')
                                                            .replaceAll(
                                                                '+', '')) ??
                                                        0.0) !=
                                                    0.0) ...[
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    width: 140,
                                                    child: TextField(
                                                      controller: axisRCtrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13),
                                                      decoration: InputDecoration(
                                                          labelText: "pos_axis_kanan"
                                                              .tr(),
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .grey),
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 10,
                                                                  horizontal:
                                                                      10),
                                                          filled: true,
                                                          fillColor: Colors
                                                              .white
                                                              .withOpacity(
                                                                  0.05),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              borderSide:
                                                                  BorderSide
                                                                      .none)),
                                                    ),
                                                  ),
                                                ]
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (lensJenis == 'Progresif' ||
                                          lensJenis == 'Kryptok') ...[
                                        const SizedBox(height: 12),
                                        const Divider(
                                            color: Colors.white10, height: 1),
                                        const SizedBox(height: 12),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Align(
                                                  alignment: Alignment.center,
                                                  child: ResepInput(
                                                      label: "ADD (R)",
                                                      controller: addRCtrl,
                                                      onChanged: (v) =>
                                                          setState(() {}))),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: 140,
                                                    child: TextField(
                                                      controller: pdRCtrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13),
                                                      decoration: InputDecoration(
                                                          labelText: "pos_pd_kanan"
                                                              .tr(),
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .tealAccent),
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 10,
                                                                  horizontal:
                                                                      10),
                                                          filled: true,
                                                          fillColor: Colors.teal
                                                              .withOpacity(0.1),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              borderSide:
                                                                  BorderSide
                                                                      .none)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // 3. MATRIKS UKURAN & MULTIFOKAL (KIRI)
                              Flexible(
                                fit: FlexFit.tight,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("pos_mata_kiri".tr(),
                                          style: const TextStyle(
                                              color: Colors.blueAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 12),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Align(
                                                alignment: Alignment.center,
                                                child: ResepInput(
                                                    label: "SPH (L)",
                                                    controller: sphLCtrl,
                                                    onChanged: (v) =>
                                                        setState(() {}))),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                ResepInput(
                                                    label: "CYL (L)",
                                                    controller: cylLCtrl,
                                                    onChanged: (v) =>
                                                        setState(() {})),
                                                if ((double.tryParse(cylLCtrl
                                                            .text
                                                            .replaceAll(
                                                                ',', '.')
                                                            .replaceAll(
                                                                '+', '')) ??
                                                        0.0) !=
                                                    0.0) ...[
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    width: 140,
                                                    child: TextField(
                                                      controller: axisLCtrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13),
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              "pos_axis_kiri"
                                                                  .tr(),
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .grey),
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 10,
                                                                  horizontal:
                                                                      10),
                                                          filled: true,
                                                          fillColor:
                                                              Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.05),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              borderSide:
                                                                  BorderSide
                                                                      .none)),
                                                    ),
                                                  ),
                                                ]
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (lensJenis == 'Progresif' ||
                                          lensJenis == 'Kryptok') ...[
                                        const SizedBox(height: 12),
                                        const Divider(
                                            color: Colors.white10, height: 1),
                                        const SizedBox(height: 12),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Align(
                                                  alignment: Alignment.center,
                                                  child: ResepInput(
                                                      label: "ADD (L)",
                                                      controller: addLCtrl,
                                                      onChanged: (v) =>
                                                          setState(() {}))),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: 140,
                                                    child: TextField(
                                                      controller: pdLCtrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13),
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              "pos_pd_kiri"
                                                                  .tr(),
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .tealAccent),
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 10,
                                                                  horizontal:
                                                                      10),
                                                          filled: true,
                                                          fillColor: Colors.teal
                                                              .withOpacity(0.1),
                                                          border: OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              borderSide:
                                                                  BorderSide
                                                                      .none)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // 4. RIWAYAT KACAMATA LAMA
                          const Divider(color: Colors.white10, height: 25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("pos_tanya_kacamata_lama".tr(),
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              Switch(
                                  value: isInputKacamataLamaActive,
                                  activeColor: Colors.orangeAccent,
                                  onChanged: (val) => setState(
                                      () => isInputKacamataLamaActive = val)),
                            ],
                          ),
                          if (isInputKacamataLamaActive) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color:
                                          Colors.orangeAccent.withOpacity(0.5)),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("pos_resep_lama".tr(),
                                      style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    dropdownColor: OptikAdminTokens.card,
                                    value: lensJenisLama,
                                    decoration: InputDecoration(
                                        labelText: "pos_jenis_lensa_lama".tr()),
                                    items: ["Standar", "Progresif", "Kryptok"]
                                        .map((e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e,
                                                style: const TextStyle(
                                                    fontSize: 12))))
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => lensJenisLama = v!),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Flexible(
                                          fit: FlexFit.tight,
                                          child: TextField(
                                              controller: sphOldRCtrl,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      "pos_sph_r_lama".tr()))),
                                      const SizedBox(width: 5),
                                      Flexible(
                                          fit: FlexFit.tight,
                                          child: TextField(
                                              controller: cylOldRCtrl,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      "pos_cyl_r_lama".tr()))),
                                      if ((double.tryParse(cylOldRCtrl.text
                                                  .replaceAll(',', '.')) ??
                                              0.0) !=
                                          0.0) ...[
                                        const SizedBox(width: 5),
                                        Flexible(
                                            fit: FlexFit.tight,
                                            child: TextField(
                                                controller: axisOldRCtrl,
                                                decoration: InputDecoration(
                                                    labelText: "pos_axis_r_lama"
                                                        .tr()))),
                                      ]
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Flexible(
                                          fit: FlexFit.tight,
                                          child: TextField(
                                              controller: sphOldLCtrl,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      "pos_sph_l_lama".tr()))),
                                      const SizedBox(width: 5),
                                      Flexible(
                                          fit: FlexFit.tight,
                                          child: TextField(
                                              controller: cylOldLCtrl,
                                              decoration: InputDecoration(
                                                  labelText:
                                                      "pos_cyl_l_lama".tr()))),
                                      if ((double.tryParse(cylOldLCtrl.text
                                                  .replaceAll(',', '.')) ??
                                              0.0) !=
                                          0.0) ...[
                                        const SizedBox(width: 5),
                                        Flexible(
                                            fit: FlexFit.tight,
                                            child: TextField(
                                                controller: axisOldLCtrl,
                                                decoration: InputDecoration(
                                                    labelText: "pos_axis_l_lama"
                                                        .tr()))),
                                      ]
                                    ],
                                  ),
                                  if (lensJenisLama == 'Progresif' ||
                                      lensJenisLama == 'Kryptok') ...[
                                    const SizedBox(height: 8),
                                    TextField(
                                        controller: TextEditingController(),
                                        decoration: InputDecoration(
                                            labelText: "pos_add_lama".tr())),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 15),

// ==========================================================
                          // 5. TOMBOL SINKRON MASTER & LAPORAN KE PUSAT (KEDUANYA LENGKAP)
                          // ==========================================================
                          const SizedBox(height: 15),
                          SizedBox(
                            width: MediaQuery.of(context).size.width,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: const Text("CHECK STOCK & ADD TO CART",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                              onPressed: () {
                                String inputMerk = lensBrandCtrl.text.trim();
                                if (inputMerk.isEmpty) {
                                  _showSnack(
                                      "pos_err_merk_lensa".tr(), Colors.red);
                                  return;
                                }

                                double parseAngka(String teks) {
                                  return double.tryParse(teks
                                          .replaceAll(',', '.')
                                          .replaceAll('+', '')) ??
                                      0.0;
                                }

                                double sphR = parseAngka(sphRCtrl.text);
                                double cylR = parseAngka(cylRCtrl.text);
                                double addR = parseAngka(addRCtrl.text);

                                double sphL = parseAngka(sphLCtrl.text);
                                double cylL = parseAngka(cylLCtrl.text);
                                double addL = parseAngka(addLCtrl.text);

                                // 🎯 KUNCI ABSOLUT: BRAND, JENIS, COATING, SPH, CYL, DAN ADD WAJIB COCOK 100%
                                Map<String, dynamic>? cariLensa(
                                    double targetSph,
                                    double targetCyl,
                                    double targetAdd) {
                                  for (var item in masterLensaProducts) {
                                    double itemSph = parseAngka(
                                        (item['sph_r'] ?? item['sph'] ?? '0')
                                            .toString());
                                    double itemCyl = parseAngka(
                                        (item['cyl_r'] ?? item['cyl'] ?? '0')
                                            .toString());
                                    double itemAdd = parseAngka(
                                        (item['add_r'] ?? item['add'] ?? '0')
                                            .toString());

                                    bool matchMerk = item['nama']
                                            ?.toString()
                                            .toLowerCase() ==
                                        inputMerk.toLowerCase();
                                    bool matchJenis =
                                        item['jenis_lensa'] == lensJenis;
                                    bool matchBahan = (item['sub_kategori'] ??
                                            item['bahan'] ??
                                            item['coating']) ==
                                        lensBahan;
                                    bool matchSph = itemSph == targetSph;
                                    bool matchCyl = itemCyl == targetCyl;

                                    bool matchAdd = true;
                                    if (lensJenis == 'Progresif' ||
                                        lensJenis == 'Kryptok') {
                                      matchAdd = itemAdd == targetAdd;
                                    }

                                    if (matchMerk &&
                                        matchJenis &&
                                        matchBahan &&
                                        matchSph &&
                                        matchCyl &&
                                        matchAdd) {
                                      return item;
                                    }
                                  }
                                  return null;
                                }

                                var lensaKanan = cariLensa(sphR, cylR, addR);
                                var lensaKiri = cariLensa(sphL, cylL, addL);

                                // 🛑 BARIKADE 1: JIKA UKURAN TIDAK COCOK SAMA MASTER DATA -> BLOKIR INSTAN
                                if (lensaKanan == null || lensaKiri == null) {
                                  List<String> missingItems = [];
                                  if (lensaKanan == null)
                                    missingItems.add(
                                        "Kanan (SPH ${sphRCtrl.text} CYL ${cylRCtrl.text} ADD ${addRCtrl.text})");
                                  if (lensaKiri == null)
                                    missingItems.add(
                                        "Kiri (SPH ${sphLCtrl.text} CYL ${cylLCtrl.text} ADD ${addLCtrl.text})");

                                  _showSnack(
                                      "🛑 Gagal! Ukuran ${missingItems.join(' & ')} tidak tersedia di katalog cabang. Silakan klik Lapor Pusat!",
                                      Colors.red);
                                  return;
                                }

                                // 🛑 BARIKADE 2: CEK KETERSEDIAAN FISIK STOK DI CABANG
                                int stockR = lensaKanan['stock'] ?? 0;
                                int stockL = lensaKiri['stock'] ?? 0;
                                bool isSamaPersis =
                                    (lensaKanan['id'] == lensaKiri['id']);

                                if (isSamaPersis) {
                                  if (stockR >= 2) {
                                    _tambahKeKeranjangLensaLangsung(
                                        lensaKanan, lensaKiri);
                                    _showSnack("pos_lensa_masuk_keranjang".tr(),
                                        Colors.green);
                                  } else {
                                    _showSnack(
                                        "🛑 Gagal! Stok lensa kembar kurang (Sisa: $stockR Pcs). Silakan klik Lapor Pusat!",
                                        Colors.red);
                                  }
                                } else {
                                  if (stockR >= 1 && stockL >= 1) {
                                    _tambahKeKeranjangLensaLangsung(
                                        lensaKanan, lensaKiri);
                                    _showSnack("pos_lensa_masuk_keranjang".tr(),
                                        Colors.green);
                                  } else {
                                    List<String> lowStock = [];
                                    if (stockR < 1)
                                      lowStock.add("Kanan (Stok: $stockR)");
                                    if (stockL < 1)
                                      lowStock.add("Kiri (Stok: $stockL)");
                                    _showSnack(
                                        "🛑 Gagal! Stok habis pada mata: ${lowStock.join(' & ')}. Silakan klik Lapor Pusat!",
                                        Colors.red);
                                  }
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: MediaQuery.of(context).size.width,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Colors.orangeAccent)),
                              icon: const Icon(Icons.send_to_mobile,
                                  color: Colors.orangeAccent, size: 18),
                              label: Text("pos_btn_lapor_pusat".tr(),
                                  style: const TextStyle(
                                      color: Colors.orangeAccent)),
                              onPressed: () async {
                                String inputMerk = lensBrandCtrl.text.trim();
                                if (inputMerk.isEmpty) {
                                  _showSnack(
                                      "pos_err_merk_lensa".tr(), Colors.red);
                                  return;
                                }
                                if (nameCtrl.text.trim().isEmpty) {
                                  _showSnack(
                                      "Nama pelanggan wajib diisi sebelum melaporkan pesanan khusus!",
                                      Colors.red);
                                  return;
                                }

                                try {
                                  final tokoId =
                                      widget.profile['toko_id'] ?? 'PUSAT';

                                  final inserted = await supabase
                                      .from('pending_requests')
                                      .insert({
                                    'toko_id': tokoId,
                                    'no_invoice': noInvoice,
                                    'nama_pelanggan': nameCtrl.text.trim(),
                                    'sku': "CUSTOM_HQ",
                                    'nama_produk':
                                        "Special Order: Lensa $inputMerk $lensJenis ($lensBahan)",
                                    'kategori': 'Lensa',
                                    'qty_request': 2,
                                    'tipe_request': 'PRE_ORDER',
                                    'status': 'PENDING',
                                    'tracking_status': 'DIPROSES_DI_CABANG',
                                    'detail_resep':
                                        "R: SPH ${sphRCtrl.text}/CYL ${cylRCtrl.text}/AXIS ${axisRCtrl.text}/ADD ${addRCtrl.text} | "
                                            "L: SPH ${sphLCtrl.text}/CYL ${cylLCtrl.text}/AXIS ${axisLCtrl.text}/ADD ${addLCtrl.text} | "
                                            "PD: ${pdRCtrl.text.isEmpty ? '-' : pdRCtrl.text}/${pdLCtrl.text.isEmpty ? '-' : pdLCtrl.text} mm"
                                  }).select('id').single();

                                  setState(() {
                                    pendingLensRequests.add({
                                      'merk': inputMerk,
                                      'jenis': lensJenis,
                                      'bahan': lensBahan,
                                      'resep_r':
                                          "SPH: ${sphRCtrl.text}, CYL: ${cylRCtrl.text}, AXIS: ${axisRCtrl.text}",
                                      'resep_l':
                                          "SPH: ${sphLCtrl.text}, CYL: ${cylLCtrl.text}, AXIS: ${axisLCtrl.text}",
                                      'add_pd':
                                          "ADD R: ${addRCtrl.text}, ADD L: ${addLCtrl.text}, PD R: ${pdRCtrl.text}, PD L: ${pdLCtrl.text}",
                                      'waktu': DateTime.now().toIso8601String()
                                    });

                                    cartItems.add({
                                      'nama_produk':
                                          "Special Order: $inputMerk $lensJenis (R: ${sphRCtrl.text}/${cylRCtrl.text} L: ${sphLCtrl.text}/${cylLCtrl.text})",
                                      'sku': "CUSTOM_HQ",
                                      'harga': 0,
                                      'qty': 1,
                                      'subtotal': 0,
                                      'kategori': 'Lensa',
                                      'is_lensa_custom': true,
                                      'detail': "pos_menunggu_pusat".tr()
                                    });
                                  });

                                  if (TrainingMode.instance.isActive &&
                                      mounted) {
                                    final outcome =
                                        await TrainingApprovalSimulator
                                            .simulatePendingRequestIfTraining(
                                      context,
                                      id: inserted['id'],
                                      body:
                                          'training_approval_sim_body_request_order'
                                              .tr(),
                                      trackingFor:
                                          RequestOrderService.trackingFor,
                                    );
                                    _showSnack(
                                      'training_ro_outcome_${outcome?.name ?? 'pending'}'
                                          .tr(),
                                      const Color(0xFFB45309),
                                    );
                                  } else {
                                    _showSnack(
                                        "✓ Real-time: Laporan ukuran khusus berhasil dikirim ke database pusat!",
                                        Colors.green);
                                  }
                                } catch (e) {
                                  _showSnack(
                                      "🛑 Gagal mengirim laporan ke pusat: $e",
                                      Colors.red);
                                }
                              },
                            ),
                          ),
                        ],

                        // ==========================================================
                        // --- SUB: AKSESORIS / LAINNYA (PENCARIAN MASTER PRODUK) ---
                        // ==========================================================
                        if (isLainnyaActive) ...[
                          const SizedBox(height: 15),
                          if (selectedAksesoris != null) ...[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  selectedAksesoris!['nama'] ?? 'Aksesoris',
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                  "Rp ${selectedAksesoris!['harga'] ?? 0}",
                                  style: const TextStyle(
                                      color: Colors.greenAccent)),
                              trailing: SizedBox(
                                width:
                                    120, // 👈 KUNCI SAKTI: Membatasi lebar tombol Tambah Aksesoris
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4), // Biar text muat
                                  ),
                                  onPressed: () {
                                    _tambahItemKeKeranjang(selectedAksesoris!,
                                        selectedAksesoris!['stock'] ?? 0);
                                    setState(() => selectedAksesoris = null);
                                  },
                                  child: Text(
                                    "pos_btn_tambah".tr(),
                                    style: const TextStyle(
                                        fontSize: 12), // Kunci ukuran font
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            //--- LAYOUT BARU: KLIK UNTUK POP-UP AKSESORIS/LAINNYA ---
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.orangeAccent
                                          .withOpacity(0.3))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("pos_cari_aksesoris".tr(),
                                      style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  TextField(
                                    readOnly: true, // DIKUNCI
                                    onTap: () => _munculkanDialogPilihLainnya(
                                        context), // MUNCULKAN POP-UP saat diklik
                                    style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: "pos_hint_cari_aksesoris".tr(),
                                      labelStyle: const TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      suffixIcon: const Icon(Icons.touch_app,
                                          color: Colors.orangeAccent, size: 20),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.05),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide.none),
                                    ),
                                  )
                                ],
                              ),
                            )
                          ]
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- BAGIAN 3: DAFTAR KERANJANG BELANJA ---
                  if (cartItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: OptikAdminTokens.card,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                              color: Colors.blueAccent.withOpacity(0.5))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCardTitle(
                              "${"pos_daftar_pesanan".tr()} (${cartItems.length})",
                              Icons.shopping_cart),
                          const SizedBox(height: 10),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cartItems.length,
                            itemBuilder: (c, i) {
                              final item = cartItems[i];
                              return Card(
                                color: Colors.black26,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(item['nama_produk'] ?? '-',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text("Rp ${item['harga']} / pcs",
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11)),
                                            if (item['detail_r'] != null ||
                                                item['detail_l'] != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4),
                                                child: Text(
                                                    "pos_pesanan_khusus".tr(),
                                                    style: const TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontSize: 10,
                                                        fontStyle:
                                                            FontStyle.italic)),
                                              )
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  color: Colors.orangeAccent,
                                                  size: 20),
                                              onPressed: () =>
                                                  _ubahQtyCartItem(i, -1)),
                                          Text("${item['qty']}",
                                              style: const TextStyle(
                                                  color: Colors.blueAccent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline,
                                                  color: Colors.greenAccent,
                                                  size: 20),
                                              onPressed: () =>
                                                  _ubahQtyCartItem(i, 1)),
                                        ],
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text("Rp ${item['subtotal']}",
                                              style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12)),
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent,
                                                  size: 18),
                                              onPressed: () =>
                                                  _hapusDariKeranjang(i)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // --- BAGIAN 4: PEMBAYARAN ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: OptikAdminTokens.card,
                        borderRadius: BorderRadius.circular(15)),
                    child: Column(
                      children: [
                        _buildCardTitle("pos_pembayaran".tr(), Icons.payments),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("pos_subtotal".tr(),
                                style: const TextStyle(color: Colors.grey)),
                            Text("Rp $_subtotalBelanja",
                                style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: discountCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold),
                          onChanged: (v) => setState(() {
                            if (paymentStatus == "Lunas") {
                              paidCtrl.text = _totalAkhir.toString();
                            }
                          }),
                          decoration: InputDecoration(
                              labelText: "pos_diskon".tr(),
                              prefixText: "- Rp ",
                              filled: true,
                              fillColor: Colors.orangeAccent.withOpacity(0.1)),
                        ),
                        const Divider(height: 30, color: Colors.white10),
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("pos_total_nett".tr(),
                                  style: const TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold)),
                              Text("Rp $_totalAkhir",
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Flexible(
                              fit: FlexFit.loose,
                              child: DropdownButtonFormField<String>(
                                dropdownColor: OptikAdminTokens.card,
                                value: paymentMethod,
                                items: ["Tunai", "Debit", "Transfer", "QRIS"]
                                    .map((e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e,
                                            style:
                                                const TextStyle(fontSize: 12))))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => paymentMethod = v!),
                                decoration: InputDecoration(
                                    labelText: "pos_metode".tr()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              fit: FlexFit.loose,
                              child: DropdownButtonFormField<String>(
                                dropdownColor: OptikAdminTokens.card,
                                value: paymentStatus,
                                items: ["Lunas", "DP"]
                                    .map((e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e,
                                            style:
                                                const TextStyle(fontSize: 12))))
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  paymentStatus = v!;
                                  if (v == "Lunas") {
                                    paidCtrl.text = _totalAkhir.toString();
                                  } else {
                                    paidCtrl.clear();
                                  }
                                }),
                                decoration: InputDecoration(
                                    labelText: "pos_status".tr()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: paidCtrl,
                          keyboardType: TextInputType.number,
                          readOnly: paymentStatus == "Lunas",
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: paymentStatus == "Lunas"
                                ? "pos_dibayar_full".tr()
                                : "pos_dp".tr(),
                            prefixText: "Rp ",
                            filled: paymentStatus == "Lunas",
                            fillColor: paymentStatus == "Lunas"
                                ? Colors.white.withOpacity(0.05)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

// SUBMIT BUTTON (PROSES PENJUALAN - REVISI INTEGRATED PREVIEW)
                  SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      // 🎯 FIX: Dialihkan ke fungsi Pratinjau terlebih dahulu sebelum eksekusi final!
                      onPressed: isProcessing
                          ? null
                          : () => _bukaLayarPreviewInvoice(),
                      child: isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "PRATINJAU INVOICE", // <-- Ganti text agar kasir tahu ini step preview
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1))
        ],
      ),
    );
  }
}

// ============================================================================
// KELAS NOTA DIGITAL & MESIN CETAK PDF (INVOICE DETAIL PAGE - FULL SYNCED)
// ============================================================================
class InvoiceDetailPage extends StatefulWidget {
  final String saleId;
  const InvoiceDetailPage({super.key, required this.saleId});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool isLoading = true;
  Map<String, dynamic>? saleData;
  List<dynamic>? saleItems;
  Map<String, dynamic>?
      configData; // Menampung konfigurasi layout dinamis dari database cabang
  bool isPrinting = false;
  String currentTrackingStatus = "DIPROSES_DI_CABANG";

  @override
  void initState() {
    super.initState();
    _fetchNota();
  }

  Future<void> _fetchNota() async {
    try {
      final resSale = await supabase
          .from('sales')
          .select()
          .eq('id', widget.saleId)
          .single();
      final resItems = await supabase
          .from('sales_items')
          .select()
          .eq('sale_id', widget.saleId);

      // Sinkronisasi Konfigurasi Cabang: Mengunci banner alamat & footer notice riil dari database
      String cabangNota =
          resSale['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      var resConfig = await supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', cabangNota)
          .maybeSingle();
      resConfig ??= await supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', 'PUSAT')
          .maybeSingle();

      if (mounted) {
        setState(() {
          saleData = resSale;
          saleItems = resItems;
          configData = resConfig ??
              {
                'shop_name': 'OPTIK B. RISKI',
                'address': 'Alamat Toko Cabang $cabangNota',
                'phone': '-',
                'header_alignment': 'CENTER',
                'font_size_header': 16,
                'font_size_body': 12,
                'show_qr_invoice': true,
                'footer_text': 'Terima kasih atas kepercayaan Anda.'
              };
          currentTrackingStatus =
              resSale['tracking_status'] ?? "DIPROSES_DI_CABANG";
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal muat data detail nota: $e");
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("${"pos_err_muat_nota".tr()} $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _updateTrackingStatus(String status, String snackMsg) async {
    setState(() => isPrinting = true);
    try {
      await supabase
          .from('sales')
          .update({'tracking_status': status}).eq('id', widget.saleId);
      setState(() => currentTrackingStatus = status);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(snackMsg,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal memperbarui status: $e"),
          backgroundColor: Colors.red));
    } finally {
      setState(() => isPrinting = false);
    }
  }

  Future<void> _showFlexiblePrint(
      Map<String, dynamic> sale, List<dynamic> items) async {
    setState(() => isPrinting = true);
    try {
      await PosPrintService.showPrintOptions(
        context,
        sale: sale,
        items: items,
        formatRupiah: (n) => formatRupiah(n.round()),
      );
    } finally {
      if (mounted) setState(() => isPrinting = false);
    }
  }

  // 🎯 MESIN PARSER PINTAR: Membongkar string database menjadi matriks tabel medis riil hulu ke hilir
  String _parseResepDinamis(String rawResep, String mata, String parameter) {
    if (rawResep.isEmpty || rawResep == 'Normal') {
      return parameter == 'PD' ? '-' : '0.00';
    }

    try {
      List<String> parts = rawResep.split('|').map((e) => e.trim()).toList();

      if (parameter == 'PD') {
        for (var part in parts) {
          if (part.toUpperCase().contains('PD PASIEN:')) {
            return part.split(RegExp(r'PD Pasien:\s*'))[1].trim();
          }
        }
        return '-';
      }

      String barisMata = mata == 'OD'
          ? parts.firstWhere((e) => e.startsWith('R:'), orElse: () => '')
          : parts.firstWhere((e) => e.startsWith('L:'), orElse: () => '');

      if (barisMata.isEmpty) return '0.00';

      final regExp = RegExp('$parameter\\s+([^/|\\s°]+)');
      final match = regExp.firstMatch(barisMata);
      return match?.group(1) ?? '0.00';
    } catch (e) {
      return parameter == 'PD' ? '-' : '0.00';
    }
  }

// MESIN SHARE PDF STRUK INVOICE (JIPLAK MURNI 100% SAMA DENGAN PRATINJAU NOTA DAN DATABASE)
  Future<void> _generateDetailPagePDF(
      Map<String, dynamic> sale, List<dynamic> items) async {
    try {
      final pdf = pw.Document();
      final config = configData ?? {};

      final bool hasLensa = items.any((item) =>
          item['tipe_produk'].toString().toLowerCase().contains('lensa') ||
          item['nama_produk'].toString().toLowerCase().contains('lensa'));

      String detailResepDb = items.firstWhere(
              (e) => e['tipe_produk'] == 'Lensa',
              orElse: () => {'detail_resep': ''})['detail_resep'] ??
          '';

      int totalHarga = sale['total_harga'] ?? 0;
      int uangMukaDP = sale['dibayarkan'] ?? 0;
      int sisaTagihan = sale['sisa_tagihan'] ?? 0;

      final double fHeader = (config['font_size_header'] ?? 16).toDouble();
      final double fBody = (config['font_size_body'] ?? 12).toDouble();
      final isCenter = config['header_alignment'] == 'CENTER';

      // 🏢 FIX LOGO: Menggunakan networkImage bawaan package printing
      pw.ImageProvider? logoImage;
      if (config['logo_url'] != null &&
          config['logo_url'].toString().isNotEmpty) {
        logoImage = await networkImage(config['logo_url'].toString());
      }

      // 🎯 SANITASI KARAKTER ILLEGAL (Pencegah kotak tofu silang rusak di PDF)
      String cleanFooter = (config['footer_text'] ?? '')
          .toString()
          .replaceAll('•', '-')
          .replaceAll('–', '-')
          .replaceAll('—', '-');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 🏢 HEADER PERUSAHAAN (CENTERED)
                isCenter
                    ? pw.SizedBox(
                        width: double.infinity,
                        child: pw.Stack(
                          children: [
                            if (logoImage != null)
                              pw.Positioned(
                                left: 0,
                                top: 0,
                                child: pw.Container(
                                    height: 24,
                                    child: pw.Image(logoImage,
                                        fit: pw.BoxFit.contain)),
                              ),
                            pw.SizedBox(
                              width: double.infinity,
                              child: pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    (config['shop_name'] ?? 'OPTIK B. RISKI')
                                        .toString()
                                        .toUpperCase(),
                                    style: pw.TextStyle(
                                        fontSize: fHeader - 2,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColor.fromInt(0xFF0F172A)),
                                  ),
                                  pw.SizedBox(height: 4),
                                  pw.Text(
                                    config['address'] ?? '',
                                    style: pw.TextStyle(
                                        fontSize: 8, color: PdfColors.grey700),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    "Telp: ${config['phone'] ?? '-'}",
                                    style: pw.TextStyle(
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.black),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (logoImage != null)
                            pw.Padding(
                              padding: pw.EdgeInsets.only(right: 12.0),
                              child: pw.Container(
                                  height: 24,
                                  child: pw.Image(logoImage,
                                      fit: pw.BoxFit.contain)),
                            ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(
                                    (config['shop_name'] ?? 'OPTIK B. RISKI')
                                        .toString()
                                        .toUpperCase(),
                                    style: pw.TextStyle(
                                        fontSize: fHeader - 2,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColor.fromInt(0xFF0F172A))),
                                pw.SizedBox(height: 4),
                                pw.Text(config['address'] ?? '',
                                    style: pw.TextStyle(
                                        fontSize: 8, color: PdfColors.grey700),
                                    textAlign: pw.TextAlign.end),
                                pw.SizedBox(height: 1),
                                pw.Text("Telp: ${config['phone'] ?? '-'}",
                                    style: pw.TextStyle(
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.black)),
                              ],
                            ),
                          ),
                        ],
                      ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1.5, color: PdfColors.black),
                pw.SizedBox(height: 8),

                // 👥 DATA PELANGGAN & INVOICE META
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("PELANGGAN",
                            style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey600)),
                        pw.Text(
                            (sale['nama_pelanggan'] ?? '-')
                                .toString()
                                .toUpperCase(),
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: fBody - 2,
                                color: PdfColor.fromInt(0xFF1E293B))),
                        pw.Text("WhatsApp: ${sale['no_wa'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                        pw.Text("Alamat: ${sale['alamat'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                        pw.Text("Email: ${sale['email_pelanggan'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(sale['no_invoice'] ?? '-',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: fBody - 1,
                                color: PdfColor.fromInt(0xFF0F172A))),
                        pw.Text(
                            "Masuk: ${sale['created_at'].toString().split('T')[0]}",
                            style: pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey700)),
                        pw.Text("Kasir: ${sale['nama_kasir'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(color: PdfColors.grey300, height: 1),
                pw.SizedBox(height: 6),

                // 📦 RINCIAN ITEM PESANAN
                pw.Text("RINCIAN ITEM PESANAN",
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600)),
                pw.SizedBox(height: 6),
                ...items.map((item) {
                  String cleanName = item['nama_produk'] ?? '-';
                  if (cleanName.toUpperCase().contains('LENSA') ||
                      cleanName.toUpperCase().contains('PROGRESIF')) {
                    cleanName = cleanName
                        .replaceAll(
                            RegExp(
                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                            '')
                        .trim();
                  }
                  return pw.Padding(
                    padding: pw.EdgeInsets.symmetric(vertical: 4.0),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                            child: pw.Text(
                                "- $cleanName (x${item['qty'] ?? 1})",
                                style: pw.TextStyle(
                                    color: PdfColor.fromInt(0xFF0F172A),
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold))),
                        pw.Text(formatRupiah((item['subtotal'] ?? 0) as int),
                            style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF0F172A),
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  );
                }),

                // 📊 TABEL REFRAKSI LENSA (SINKRON DATABASE)
                if (hasLensa) ...[
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.grey300, height: 1),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                            color: PdfColors.grey400, width: 0.5)),
                    child: pw.Table(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey300, width: 0.5),
                      children: [
                        pw.TableRow(
                          decoration:
                              pw.BoxDecoration(color: PdfColors.grey200),
                          children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.grey700),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OD (Kanan)',
                            _parseResepDinamis(detailResepDb, 'OD', 'SPH'),
                            _parseResepDinamis(detailResepDb, 'OD', 'CYL'),
                            _parseResepDinamis(detailResepDb, 'OD', 'AXIS')
                                    .endsWith('°')
                                ? _parseResepDinamis(
                                    detailResepDb, 'OD', 'AXIS')
                                : "${_parseResepDinamis(detailResepDb, 'OD', 'AXIS')}°",
                            _parseResepDinamis(detailResepDb, 'OD', 'ADD')
                          ]
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.all(3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8, color: PdfColors.black),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OS (Kiri)',
                            _parseResepDinamis(detailResepDb, 'OS', 'SPH'),
                            _parseResepDinamis(detailResepDb, 'OS', 'CYL'),
                            _parseResepDinamis(detailResepDb, 'OS', 'AXIS')
                                    .endsWith('°')
                                ? _parseResepDinamis(
                                    detailResepDb, 'OS', 'AXIS')
                                : "${_parseResepDinamis(detailResepDb, 'OS', 'AXIS')}°",
                            _parseResepDinamis(detailResepDb, 'OS', 'ADD')
                          ]
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.all(3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8, color: PdfColors.black),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                      padding: pw.EdgeInsets.only(top: 6, left: 4),
                      child: pw.Text(
                          "PD Pasien (R/L): ${_parseResepDinamis(detailResepDb, '', 'PD')} mm",
                          style: pw.TextStyle(
                              color: PdfColors.black,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold))),
                ],
                pw.SizedBox(height: 4),
                pw.Divider(color: PdfColors.black, thickness: 1),
                pw.SizedBox(height: 6),

                // 💰 BADGE LUNAS & RANGKUMAN FINANSIAL
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          padding: pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                              color: sisaTagihan > 0
                                  ? PdfColor.fromInt(0xFFFFF3E0)
                                  : PdfColor.fromInt(0xFFE6F4EA),
                              borderRadius: pw.BorderRadius.circular(4),
                              border: pw.Border.all(
                                  color: sisaTagihan > 0
                                      ? PdfColors.orange300
                                      : PdfColor.fromInt(0xFF34A853))),
                          child: pw.Text(sisaTagihan > 0 ? "DP" : "LUNAS",
                              style: pw.TextStyle(
                                  color: sisaTagihan > 0
                                      ? PdfColors.orange900
                                      : PdfColor.fromInt(0xFF137333),
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 8)),
                        ),
                        pw.SizedBox(height: 6),
                        if (config['show_qr_invoice'] == true)
                          pw.Container(
                              height: 55,
                              width: 55,
                              child: pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: InvoiceLink.encode(
                                      sale['no_invoice']?.toString() ?? ''),
                                  padding: pw.EdgeInsets.zero)),
                      ],
                    ),
                    pw.SizedBox(
                      width: 210,
                      child: pw.Table(
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.4),
                          1: pw.FlexColumnWidth(1.2)
                        },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text("TOTAL BELANJA",
                                    style: pw.TextStyle(
                                        color: PdfColors.grey700,
                                        fontSize: fBody - 2,
                                        fontWeight: pw.FontWeight.bold))),
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text(formatRupiah(totalHarga),
                                    style: pw.TextStyle(
                                        color: const PdfColor(0, 0, 0),
                                        fontSize: fBody - 2,
                                        fontWeight: pw.FontWeight.bold),
                                    textAlign: pw.TextAlign.end)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text("UANG MUKA (DP)",
                                    style: pw.TextStyle(
                                        color: PdfColors.grey600,
                                        fontSize: fBody - 3))),
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text(formatRupiah(uangMukaDP),
                                    style: pw.TextStyle(
                                        color: PdfColors.grey700,
                                        fontSize: fBody - 3),
                                    textAlign: pw.TextAlign.end)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 3.0),
                                child: pw.Text("SISA TAGIHAN",
                                    style: pw.TextStyle(
                                        color: const PdfColor(0, 0, 0),
                                        fontSize: fBody - 1,
                                        fontWeight: pw.FontWeight.bold))),
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 3.0),
                                child: pw.Text(formatRupiah(sisaTagihan),
                                    style: pw.TextStyle(
                                        color: sisaTagihan > 0
                                            ? PdfColors.red700
                                            : PdfColor.fromInt(0xFF34A853),
                                        fontSize: fBody - 1,
                                        fontWeight: pw.FontWeight.bold),
                                    textAlign: pw.TextAlign.end)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 4),

                // 📝 FOOTER T&C NOTICE
                pw.Text("TERIMA KASIH ATAS KEPERCAYAAN ANDA",
                    style: pw.TextStyle(
                        color: PdfColors.grey600,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(cleanFooter,
                    style:
                        pw.TextStyle(color: PdfColors.grey700, fontSize: 8.5)),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      String pdfBase64 = base64Encode(pdfBytes);

      await supabase.functions.invoke(
        'send-invoice-email',
        body: {
          'invoice': sale['no_invoice'] ?? 'INV-UNKNOWN',
          'email': sale['email_pelanggan'] ?? '',
          'customerName': sale['nama_pelanggan'] ?? 'Pelanggan Setia',
          'netTotal': (sale['total_harga'] ?? 0).toString(),
          'pdfBase64': pdfBase64,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✓ Resend Nota PDF Berhasil Terkirim!",
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Gagal share PDF: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const PremiumScaffold(
        body:
            Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    if (saleData == null || configData == null) {
      return PremiumScaffold(
        appBar: PremiumAppBar(title: "pos_nota_title".tr()),
        body: Center(
            child: Text("pos_data_tidak_ditemukan".tr(),
                style: const TextStyle(color: Colors.white))),
      );
    }

    final sale = saleData!;
    final items = saleItems ?? [];
    final config = configData!;

    final isCenter = config['header_alignment'] == 'CENTER';
    final double fHeader = (config['font_size_header'] ?? 16).toDouble();
    final double fBody = (config['font_size_body'] ?? 12).toDouble();

    // 🎯 FIX MANDATORI: Inisialisasi variabel finansial laci untuk konsumsi UI Widget Tree screen utama
    int totalHarga = sale['total_harga'] ?? 0;
    int uangMukaDP = sale['dibayarkan'] ?? 0;
    int sisaTagihan = sale['sisa_tagihan'] ?? 0;

    final bool hasLensa = items.any((item) =>
        item['tipe_produk'].toString().toLowerCase().contains('lensa') ||
        item['nama_produk'].toString().toLowerCase().contains('lensa'));

    String detailResepDb = items.firstWhere((e) => e['tipe_produk'] == 'Lensa',
            orElse: () => {'detail_resep': ''})['detail_resep'] ??
        '';

    return PremiumScaffold(
      appBar: const PremiumAppBar(
        title: '📄 INVOICE STRUK DIGITAL REAL',
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 📦 KARTU PUTIH UTAMA (JEPLAK 100% PERSIS SINKRON SAMA LAYAR PREVIEW)
              Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]),
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🏢 1. SECTION HEADER (SINKRON DATA INVOICE SETTINGS AKTIF)
                    isCenter
                        ? SizedBox(
                            width: double.infinity,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (config['logo_url'] != null &&
                                    config['logo_url'].toString().isNotEmpty)
                                  Positioned(
                                    left: 0,
                                    top: -2.0,
                                    child: Image.network(config['logo_url'],
                                        height: 24, fit: BoxFit.contain),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        (config['shop_name'] ??
                                                'OPTIK B. RISKI')
                                            .toString()
                                            .toUpperCase(),
                                        style: TextStyle(
                                            color: OptikAdminTokens.bgMid,
                                            fontWeight: FontWeight.w800,
                                            fontSize: fHeader - 1,
                                            letterSpacing: 0.5,
                                            height: 1.0),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 45.0),
                                        child: Text(config['address'] ?? '',
                                            style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 8.5,
                                                height: 1.35),
                                            textAlign: TextAlign.center),
                                      ),
                                      const SizedBox(height: 3),
                                      Text("Telp: ${config['phone'] ?? '-'}",
                                          style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (config['logo_url'] != null &&
                                  config['logo_url'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Image.network(config['logo_url'],
                                      height: 24, fit: BoxFit.contain),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        (config['shop_name'] ??
                                                'OPTIK B. RISKI')
                                            .toString()
                                            .toUpperCase(),
                                        style: TextStyle(
                                            color: OptikAdminTokens.bgMid,
                                            fontWeight: FontWeight.w800,
                                            fontSize: fHeader - 1,
                                            letterSpacing: 0.5)),
                                    const SizedBox(height: 4),
                                    Text(config['address'] ?? '',
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 8.5,
                                            height: 1.35),
                                        textAlign: TextAlign.end),
                                    const SizedBox(height: 1),
                                    Text("Telp: ${config['phone'] ?? '-'}",
                                        style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 8),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(
                            color: Colors.black87, thickness: 1.5, height: 1),
                        SizedBox(height: 1.5),
                        Divider(
                            color: Colors.black12, thickness: 0.5, height: 1),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 📋 2. DATA PELANGGAN & INTERNAL META ADMINISTRATIF (SISI KIRI PELANGGAN, SISI KANAN NOTA)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sale['no_invoice'] ?? '-',
                                  style: TextStyle(
                                      color: OptikAdminTokens.bgMid,
                                      fontWeight: FontWeight.bold,
                                      fontSize: fBody - 1,
                                      letterSpacing: 0.2)),
                              const SizedBox(height: 6),
                              const Text("PELANGGAN",
                                  style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8)),
                              const SizedBox(height: 1),
                              Text(
                                  (sale['nama_pelanggan'] ?? '-')
                                      .toString()
                                      .toUpperCase(),
                                  style: TextStyle(
                                      color: OptikAdminTokens.card,
                                      fontSize: fBody - 2,
                                      fontWeight: FontWeight.bold)),
                              Text("WhatsApp: ${sale['no_wa'] ?? '-'}",
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: fBody - 3)),
                              if (sale['alamat'] != null &&
                                  sale['alamat'].toString().isNotEmpty)
                                Text("Alamat: ${sale['alamat']}",
                                    style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: fBody - 3)),
                              Text("Email: ${sale['email_pelanggan'] ?? '-'}",
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: fBody - 3)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: sisaTagihan > 0
                                      ? Colors.orange.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: sisaTagihan > 0
                                          ? Colors.orange.shade300
                                          : Colors.green.shade300)),
                              child: Text(
                                  sisaTagihan > 0
                                      ? "DP (SISA TAGIHAN)"
                                      : "LUNAS",
                                  style: TextStyle(
                                      color: sisaTagihan > 0
                                          ? Colors.orange.shade900
                                          : Colors.green.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 8)),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text("Masuk: ",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 8.5)),
                                Text(
                                    sale['created_at'].toString().split('T')[0],
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("Kasir: ",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 8.5)),
                                Text(sale['nama_kasir'] ?? 'Staff',
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("Metode: ",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 8.5)),
                                Text(sale['metode_pembayaran'] ?? 'Tunai',
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(color: Colors.black12, height: 1),
                    const SizedBox(height: 6),

                    // 👓 3. SECTION RINCIAN BELANJA ITEM KASIR (DICLEAN DENGAN REGEX PREVIEW)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("RINCIAN ITEM PESANAN",
                            style: TextStyle(
                                color: Colors.black38,
                                fontSize: fBody - 4,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 6),
                        ...items.map((item) {
                          String rawName = item['nama_produk'] ?? '-';

                          if (rawName.toUpperCase().contains('LENSA') ||
                              rawName.toUpperCase().contains('PROGRESIF')) {
                            final rxPrescription = RegExp(
                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)');
                            rawName =
                                rawName.replaceAll(rxPrescription, '').trim();
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                      "- $rawName (x${item['qty'] ?? 1})",
                                      style: const TextStyle(
                                          color: OptikAdminTokens.bgMid,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          height: 1.2)),
                                ),
                                const SizedBox(width: 15),
                                Text(formatRupiah(item['subtotal'] ?? 0),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.bgMid,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 👁️ 4. SECTION HASIL REFRAKSI MEDIS SINKRON TOTAL (TABLE KEMBAR IDENTIK SAMA PREVIEW)
                    if (hasLensa) ...[
                      const Divider(color: Colors.black12, height: 1),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(4)),
                        child: HScroll(
                          minWidth: 480,
                          child: Table(
                          border: TableBorder.all(color: Colors.black12),
                          columnWidths: const {
                            0: FlexColumnWidth(1.8),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FlexColumnWidth(2),
                            4: FlexColumnWidth(2),
                          },
                          children: [
                            TableRow(
                              decoration:
                                  const BoxDecoration(color: Color(0xFFF8FAFC)),
                              children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                                  .map((txt) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Text(txt,
                                            style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black45),
                                            textAlign: TextAlign.center),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: [
                                'OD (Kanan)',
                                _parseResepDinamis(detailResepDb, 'OD', 'SPH'),
                                _parseResepDinamis(detailResepDb, 'OD', 'CYL'),
                                _parseResepDinamis(detailResepDb, 'OD', 'AXIS')
                                        .endsWith('°')
                                    ? _parseResepDinamis(
                                        detailResepDb, 'OD', 'AXIS')
                                    : "${_parseResepDinamis(detailResepDb, 'OD', 'AXIS')}°",
                                _parseResepDinamis(detailResepDb, 'OD', 'ADD')
                              ]
                                  .map((txt) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Text(txt,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w500),
                                            textAlign: TextAlign.center),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: [
                                'OS (Kiri)',
                                _parseResepDinamis(detailResepDb, 'OS', 'SPH'),
                                _parseResepDinamis(detailResepDb, 'OS', 'CYL'),
                                _parseResepDinamis(detailResepDb, 'OS', 'AXIS')
                                        .endsWith('°')
                                    ? _parseResepDinamis(
                                        detailResepDb, 'OS', 'AXIS')
                                    : "${_parseResepDinamis(detailResepDb, 'OS', 'AXIS')}°",
                                _parseResepDinamis(detailResepDb, 'OS', 'ADD')
                              ]
                                  .map((txt) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Text(txt,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w500),
                                            textAlign: TextAlign.center),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "PD Pasien (R/L): ${_parseResepDinamis(detailResepDb, '', 'PD')} mm",
                            style: TextStyle(
                                color: Colors.black87,
                                fontSize: (fBody - 3).clamp(8.0, 14.0),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.1),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),
                    const Divider(color: Colors.black87, thickness: 1),
                    const SizedBox(height: 6),

                    // 💰 5. SECTION FINANSIAL & QR EXPANDED (SINKRON PREVIEW RATAN KANAN)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        config['show_qr_invoice'] == true
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      border: Border.all(color: Colors.black12),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: SizedBox(
                                    height: 55,
                                    width: 55,
                                    child: QrImageView(
                                        data: InvoiceLink.encode(
                                            sale['no_invoice']?.toString() ??
                                                ''),
                                        version: QrVersions.auto,
                                        padding: EdgeInsets.zero),
                                  ),
                                ),
                              )
                            : const SizedBox(),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total Belanja",
                                      style: TextStyle(
                                          color: Colors.black54, fontSize: 11)),
                                  Text(formatRupiah(totalHarga),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.bgMid,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold))
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total Dibayar",
                                      style: TextStyle(
                                          color: Colors.black38, fontSize: 11)),
                                  Text(formatRupiah(uangMukaDP),
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600))
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.0),
                                child: Divider(
                                    color: Colors.black12,
                                    height: 1,
                                    thickness: 1),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("SISA TAGIHAN",
                                      style: TextStyle(
                                          color: OptikAdminTokens.bgMid,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold)),
                                  Text(formatRupiah(sisaTagihan),
                                      style: TextStyle(
                                          color: sisaTagihan > 0
                                              ? Colors.red.shade700
                                              : Colors.green.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900))
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.black26),
                    const SizedBox(height: 4),

                    // 🎯 6. FOOTER NOTICE
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(config['footer_text'] ?? '',
                          style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 8.5,
                              height: 1.35)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Lunas: SIAP_DIAMBIL → scan barcode + foto di Garansi untuk DIAMBIL (mulai 7 hari)
              if (sale['status_pembayaran'] == 'Lunas') ...[
                Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: OptikAdminTokens.card,
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Status: $currentTrackingStatus'
                        '${sale['diambil_at'] != null ? ' · sudah diambil' : ''}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    currentTrackingStatus == 'DIAMBIL' ||
                                            sale['diambil_at'] != null
                                        ? Colors.green
                                        : const Color(0xFFE8C872),
                                foregroundColor: OptikAdminTokens.bgMid,
                              ),
                              onPressed: isPrinting ||
                                      sale['diambil_at'] != null ||
                                      currentTrackingStatus == 'DIAMBIL'
                                  ? null
                                  : () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              GaransiKonfirmasiAmbilPage(
                                            profile: {
                                              'toko_id': sale['toko_id'],
                                              'role': 'admin_toko',
                                            },
                                            prefillInvoice:
                                                sale['no_invoice']?.toString(),
                                          ),
                                        ),
                                      );
                                      await _fetchNota();
                                    },
                              icon: const Icon(Icons.qr_code_scanner, size: 16),
                              label: Text(
                                sale['diambil_at'] != null
                                    ? 'SUDAH DIAMBIL'
                                    : 'SCAN AMBIL + FOTO',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      currentTrackingStatus == 'PENDING_PO'
                                          ? Colors.orange
                                          : Colors.grey.shade800),
                              onPressed: isPrinting
                                  ? null
                                  : () => _updateTrackingStatus('PENDING_PO',
                                      "✓ Sukses! Pesanan dinyatakan Tertunda (PENDING PO)."),
                              icon:
                                  const Icon(Icons.hourglass_empty, size: 16),
                              label: const Text("PENDING PO",
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              Container(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal),
                        onPressed: isPrinting
                            ? null
                            : () => _showFlexiblePrint(sale, items),
                        icon: const Icon(Icons.print, size: 16),
                        label: Text("nota_btn_cetak".tr(),
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        onPressed: isPrinting
                            ? null
                            : () => _generateDetailPagePDF(sale, items),
                        icon: const Icon(Icons.picture_as_pdf, size: 16),
                        label: Text("nota_btn_share".tr(),
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: R.dialogMaxWidth(context, 420),
                height: 45,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24)),
                  onPressed: () => Navigator.pop(context),
                  child: Text("nota_btn_baru".tr(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
