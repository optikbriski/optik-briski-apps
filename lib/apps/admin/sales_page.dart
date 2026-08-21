// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../shared/invoice/invoice_delivery_service.dart';
import '../../shared/invoice/invoice_detail_page.dart';
import '../../shared/invoice/invoice_hub_page.dart';
import '../../shared/invoice/invoice_layout.dart';
import '../../shared/invoice/invoice_lifecycle_service.dart';
import '../../shared/invoice/invoice_link.dart';
import '../../shared/invoice/invoice_settings_service.dart';
import '../../shared/invoice/invoice_status_footer.dart';

export '../../shared/invoice/invoice_detail_page.dart';
import '../../shared/qr/hid_scan_intake.dart';
import '../../shared/qr/obr_codes.dart';
import '../../shared/qr/product_code.dart';
import '../../shared/qr/qr_route.dart';
import '../../shared/qr/universal_qr_nav.dart';
import '../../shared/widgets/leave_page_guard.dart';
import '../../shared/training/training_approval_simulator.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/training/training_ops_sync.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/finance/gl_posting_service.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/logistics/stock_realtime.dart';
import 'absensi_toko_page.dart';
import 'garansi_page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/member/member_repository.dart';
import '../../shared/attendance/pos_duty_gate.dart';
import '../../shared/pos/pos_midtrans.dart';

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
                color: OptikAdminTokens.ice.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.9))),
            child:
                const Icon(Icons.remove, color: OptikAdminTokens.navy, size: 18),
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
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold, fontSize: 13),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 10, color: OptikAdminTokens.slate),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              filled: true,
              fillColor: OptikAdminTokens.card,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OptikAdminTokens.lineStrong)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OptikAdminTokens.lineStrong)),
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
                color: OptikAdminTokens.ice.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.9))),
            child: const Icon(Icons.add, color: OptikAdminTokens.navy, size: 18),
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
        color: OptikAdminTokens.navy,
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
  /// Debounce scan NIK di gerbang unlock (kamera sering fire berulang).
  bool _unlockScanBusy = false;
  String? _lastUnlockNik;
  DateTime? _lastUnlockScanAt;
  final MobileScannerController kameraLoginCtrl =
      MobileScannerController(facing: CameraFacing.front);

  // SESI TOKO & LACI KASIR (OPEN/CLOSE STORE)
  bool isStoreOpen = false;
  bool isLoading = false;
  /// Tanggal lokal terakhir RO EOD auto-send (yyyy-MM-dd) — sekali per hari.
  String? _roAutoSentLocalDay;
  int modalAwal = 0;
  final TextEditingController modalAwalCtrl = TextEditingController();
  final TextEditingController uangFisikCloseCtrl = TextEditingController();
  DateTime? storeOpenTime;

  static bool isPosUnlocked = false;
  static String namaKasir = "";
  static Map<String, dynamic>? activeCashier;
  /// Karyawan terlibat di transaksi aktif (tanpa peran). Kasir unlock selalu ikut.
  static List<Map<String, dynamic>> karyawanTerlibat = [];
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
  final TextEditingController voucherCtrl = TextEditingController();
  String? _appliedVoucherCode;
  int _appliedVoucherPointsCost = 0;
  /// Nominal diskon voucher terkunci (jangan parse ulang dari text field —
  /// "QA1PUSAT".replaceAll(non-digit) → "1" → total salah Rp 299999).
  int _appliedVoucherNominal = 0;
  bool _lookingUpVoucher = false;

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
  final TextEditingController _unlockNikManualCtrl = TextEditingController();
  bool _leavingPos = false;

  /// Hold stok mode bayar (POS_HOLD) — sync reserved_qty ke Master/Member/POS lain.
  String? _posHoldRefId;
  DateTime? _posHoldExpiresAt;
  Timer? _posHoldTick;
  bool _posHoldBusy = false;
  bool _posHoldExpiring = false;
  final ValueNotifier<Duration> _posHoldRemaining =
      ValueNotifier<Duration>(Duration.zero);
  VoidCallback? _posHoldExpireUi;
  StockRealtimeSubscription? _stockRt;
  Timer? _stockRtDebounce;

  String get _tokoId => widget.profile['toko_id']?.toString() ?? 'PUSAT';

  bool get _posHoldActive {
    final exp = _posHoldExpiresAt;
    return _posHoldRefId != null &&
        exp != null &&
        exp.isAfter(DateTime.now());
  }

  String get _posDraftPrefsKey => 'pos_draft_transaksi_$_tokoId';

  @override
  void initState() {
    super.initState();
    _fetchMerkLensa();
    _generateInvoice();
    _cekStatusOpenStore();
    _restorePosDraftIfNeeded();
    _startStockRealtime();
    unawaited(() async {
      try {
        await supabase.rpc('expire_all_stale_stock_holds');
      } catch (_) {
        try {
          await StockMutationService().expireStalePosHolds();
        } catch (_) {}
      }
    }());

    // NOTE (tinggi / RO): antrian hari ini + tombol KIRIM KE PUSAT manual.
    // Failsafe EOD: ≥ 23:59 lokal, sisa PENDING hari itu auto-kirim ke Pusat.
    // (Bukan "hilang" — status jadi SENT_TO_HQ, tetap bisa dilacak.)
    // Training: skip silent HQ send — trainee decides via simulator on explicit send.
    Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (TrainingMode.instance.isActive) return;
      final now = DateTime.now();
      final pastEod = now.hour > 23 || (now.hour == 23 && now.minute >= 59);
      if (!pastEod) return;
      final dayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (_roAutoSentLocalDay == dayKey) return;
      try {
        final tokoId = (widget.profile['toko_id'] ?? '').toString();
        if (tokoId.isEmpty || tokoId.toUpperCase() == 'PUSAT') {
          _roAutoSentLocalDay = dayKey;
          return;
        }
        final n = await RequestOrderService().autoSendTodayPendingToHq(tokoId);
        _roAutoSentLocalDay = dayKey;
        debugPrint(
            '--- RO EOD 23:59 auto-send: $n request → Pusat ($tokoId) ---');
      } catch (e) {
        debugPrint('--- RO EOD auto-send error: $e ---');
      }
    });
  }

  void _startStockRealtime() {
    unawaited(_stockRt?.dispose() ?? Future.value());
    _stockRt = StockRealtime.subscribeToko(
      tokoId: _tokoId,
      onEvent: (ev) {
        if (!mounted || ev.sku.isEmpty) return;
        // Patch available di keranjang bila SKU sama (tanpa full reload).
        var touched = false;
        for (final item in cartItems) {
          final sku = ProductIdentity.normalizeSku(item['sku']) ??
              ProductIdentity.normalizeBarcode(item['barcode']);
          if (sku == null || sku.toUpperCase() != ev.sku) continue;
          final stock = ev.stock ??
              (int.tryParse('${item['stock'] ?? 0}') ?? 0);
          final reserved = ev.reservedQty ??
              (int.tryParse('${item['reserved_qty'] ?? 0}') ?? 0);
          final avail = ev.availableQty ?? StockQty.available(stock, reserved);
          item['stock'] = stock;
          item['reserved_qty'] = reserved;
          item['available_qty'] = avail;
          touched = true;
        }
        if (touched) {
          _stockRtDebounce?.cancel();
          _stockRtDebounce = Timer(const Duration(milliseconds: 200), () {
            if (mounted) setState(() {});
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _posHoldTick?.cancel();
    _stockRtDebounce?.cancel();
    unawaited(_stockRt?.dispose() ?? Future.value());
    _posHoldRemaining.dispose();
    // Jangan lepas hold saat checkout sedang jalan (race dengan SALE).
    final ref = _posHoldRefId;
    if (ref != null && !isProcessing) {
      unawaited(StockMutationService().releasePosCartStock(
        ref,
        tokoId: _tokoId,
      ));
    }
    kameraLoginCtrl.dispose();
    modalAwalCtrl.dispose();
    uangFisikCloseCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    emailCtrl.dispose();
    skuScanCtrl.dispose();
    discountCtrl.dispose();
    voucherCtrl.dispose();
    paidCtrl.dispose();
    kasirCtrl.dispose();
    _unlockNikManualCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _posHoldItemsFromCart() {
    final agg = <String, int>{};
    for (final item in cartItems) {
      if (item['needs_fulfillment'] == true ||
          item['is_lensa_custom'] == true) {
        continue;
      }
      final sku = ProductIdentity.normalizeSku(item['sku']) ??
          ProductIdentity.normalizeBarcode(item['barcode']);
      if (sku == null) continue;
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;
      final k = sku.toUpperCase();
      agg[k] = (agg[k] ?? 0) + qty;
    }
    return [
      for (final e in agg.entries) {'sku': e.key, 'qty': e.value},
    ];
  }

  /// Bonus otomatis Frame (Kotak/Lap) ikut hold bila ada di master toko.
  Future<List<Map<String, dynamic>>> _posHoldItemsWithBonus() async {
    final base = _posHoldItemsFromCart();
    var frameQty = 0;
    for (final item in cartItems) {
      if (item['needs_fulfillment'] == true ||
          item['is_lensa_custom'] == true) {
        continue;
      }
      if ((item['kategori'] ?? '').toString() != 'Frame') continue;
      frameQty += (item['qty'] as num?)?.toInt() ?? 0;
    }
    if (frameQty <= 0) return base;

    final extras = <Map<String, dynamic>>[];
    for (final nama in ['Kotak Kacamata', 'Lap Kacamata']) {
      try {
        final row = await supabase
            .from('products')
            .select('sku, barcode')
            .eq('toko_id', _tokoId)
            .eq('nama', nama)
            .maybeSingle();
        final sku = ProductIdentity.normalizeSku(row?['sku']) ??
            ProductIdentity.normalizeBarcode(row?['barcode']);
        if (sku != null) {
          extras.add({'sku': sku, 'qty': frameQty});
        }
      } catch (_) {}
    }
    return [...base, ...extras];
  }

  int _cartReadyQtyForSku(String sku) {
    final want = sku.trim().toUpperCase();
    var sum = 0;
    for (final item in cartItems) {
      if (item['needs_fulfillment'] == true ||
          item['is_lensa_custom'] == true) {
        continue;
      }
      final s = ProductIdentity.normalizeSku(item['sku']) ??
          ProductIdentity.normalizeBarcode(item['barcode']);
      if (s == null || s.toUpperCase() != want) continue;
      sum += (item['qty'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  void _syncPosHoldRemaining() {
    final exp = _posHoldExpiresAt;
    final next =
        exp == null ? Duration.zero : exp.difference(DateTime.now());
    _posHoldRemaining.value = next.isNegative ? Duration.zero : next;
  }

  void _startPosHoldTick() {
    _posHoldTick?.cancel();
    _syncPosHoldRemaining();
    _posHoldTick = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncPosHoldRemaining();
      if (_posHoldRemaining.value <= Duration.zero &&
          _posHoldRefId != null) {
        unawaited(_onPosHoldExpired());
      }
    });
  }

  void _stopPosHoldTick() {
    _posHoldTick?.cancel();
    _posHoldTick = null;
  }

  Future<void> _onPosHoldExpired() async {
    // Jangan lepas hold di tengah finalize checkout.
    if (_posHoldExpiring || _posHoldRefId == null || isProcessing) return;
    _posHoldExpiring = true;
    _stopPosHoldTick();
    final ref = _posHoldRefId;
    _posHoldExpireUi?.call();
    _posHoldExpireUi = null;
    if (ref != null) {
      try {
        await StockMutationService().releasePosCartStock(
          ref,
          tokoId: _tokoId,
        );
      } catch (e) {
        debugPrint('expire POS hold: $e');
      }
    }
    _posHoldRefId = null;
    _posHoldExpiresAt = null;
    _posHoldRemaining.value = Duration.zero;
    _posHoldExpiring = false;
    if (mounted) {
      setState(() {});
      _showSnack(
        'Waktu bayar 15 menit habis — stok hold dilepas. '
        'Buka preview lagi untuk hold ulang.',
        OptikAdminTokens.warning,
      );
    }
  }

  Future<void> _releasePosHold({bool clearState = true}) async {
    _stopPosHoldTick();
    _posHoldExpireUi = null;
    final ref = _posHoldRefId;
    if (ref != null) {
      try {
        await StockMutationService().releasePosCartStock(
          ref,
          tokoId: _tokoId,
        );
      } catch (e) {
        debugPrint('release POS hold: $e');
      }
    }
    if (!clearState) return;
    _posHoldRefId = null;
    _posHoldExpiresAt = null;
    _posHoldRemaining.value = Duration.zero;
    if (mounted) setState(() {});
  }

  Future<bool> _ensurePosStockHold() async {
    if (_posHoldBusy) return false;
    _posHoldBusy = true;
    try {
      final items = await _posHoldItemsWithBonus();
      final ref = noInvoice.trim().isEmpty
          ? 'POS-${DateTime.now().millisecondsSinceEpoch}'
          : noInvoice.trim();

      if (items.isEmpty) {
        if (_posHoldRefId != null) {
          await StockMutationService().releasePosCartStock(
            _posHoldRefId!,
            tokoId: _tokoId,
          );
        }
        _posHoldRefId = null;
        _posHoldExpiresAt = null;
        _posHoldRemaining.value = Duration.zero;
        _stopPosHoldTick();
        if (mounted) setState(() {});
        return true;
      }

      final res = await StockMutationService().holdPosCartStock(
        tokoId: _tokoId,
        refId: ref,
        items: items,
      );
      if (res['ok'] != true) {
        _showSnack(
          (res['error'] ??
                  'Stok tidak cukup — sudah di-hold saluran lain / POS lain')
              .toString(),
          OptikAdminTokens.danger,
        );
        return false;
      }

      final exp = DateTime.tryParse('${res['expires_at'] ?? ''}')?.toLocal() ??
          DateTime.now().add(const Duration(minutes: 15));
      _posHoldRefId = ref;
      _posHoldExpiresAt = exp;
      _startPosHoldTick();
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      _showSnack('Gagal hold stok: $e', OptikAdminTokens.danger);
      return false;
    } finally {
      _posHoldBusy = false;
    }
  }

  Future<void> _syncPosHoldAfterCartChange() async {
    if (!_posHoldActive && _posHoldRefId == null) return;
    final ok = await _ensurePosStockHold();
    if (!ok && mounted) {
      // Hold gagal (stok kurang) — lepas sisa hold lama.
      await _releasePosHold();
    }
  }

  static String _formatHoldMmSs(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _posHoldCountdownBanner({bool compact = false}) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _posHoldRemaining,
      builder: (context, remaining, _) {
        if (_posHoldRefId == null && remaining <= Duration.zero) {
          return const SizedBox.shrink();
        }
        final expired = remaining <= Duration.zero;
        final warn = !expired && remaining.inMinutes < 3;
        final tone = expired
            ? OptikAdminTokens.danger
            : warn
                ? OptikAdminTokens.warning
                : OptikAdminTokens.navy;
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: compact ? 8 : 12),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: tone.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tone.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Icon(
                expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                color: tone,
                size: compact ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  expired
                      ? 'Hold stok habis — stok dikembalikan. Buka preview untuk hold ulang.'
                      : 'Selesaikan bayar dalam ${_formatHoldMmSs(remaining)} — stok di-hold.',
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 12 : 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _applyMemberVoucher() async {
    final code = voucherCtrl.text.trim();
    if (code.isEmpty) {
      _showSnack('Masukkan kode voucher', OptikAdminTokens.warning);
      return;
    }
    if (_subtotalBelanja <= 0) {
      _showSnack('Isi keranjang dulu sebelum pakai voucher', OptikAdminTokens.warning);
      return;
    }
    setState(() => _lookingUpVoucher = true);
    try {
      final repo = MemberRepository();
      final res = await repo.lookupPromo(code, channel: 'pos');
      if (!mounted) return;
      if (res['ok'] != true) {
        _showSnack(
          (res['error'] ?? 'Voucher tidak valid').toString(),
          OptikAdminTokens.danger,
        );
        return;
      }
      final type = (res['discount_type'] ?? 'nominal').toString();
      final value = int.tryParse('${res['discount_value'] ?? 0}') ?? 0;
      final pointsCost = int.tryParse('${res['points_cost'] ?? 0}') ?? 0;
      int nominal = 0;
      if (type == 'info') {
        _showSnack(
          'Voucher info saja — tidak ada potongan otomatis. '
          '${res['title'] ?? ''}',
          OptikAdminTokens.warning,
        );
        return;
      } else if (type == 'percent') {
        nominal = ((_subtotalBelanja * value) / 100).round();
      } else {
        nominal = value;
      }
      if (nominal <= 0) {
        _showSnack('Nilai diskon voucher 0', OptikAdminTokens.warning);
        return;
      }
      if (nominal > _subtotalBelanja) nominal = _subtotalBelanja;

      if (pointsCost > 0) {
        final phone = phoneCtrl.text.trim();
        if (phone.isEmpty) {
          _showSnack(
            'Voucher butuh $pointsCost poin — isi No. WA member dulu',
            OptikAdminTokens.warning,
          );
          return;
        }
      }

      setState(() {
        discountCtrl.text = '$nominal';
        _appliedVoucherCode = (res['voucher_code'] ?? code).toString();
        _appliedVoucherPointsCost = pointsCost;
        _appliedVoucherNominal = nominal;
        if (paymentStatus == 'Lunas') {
          paidCtrl.text = _totalAkhir.toString();
        }
      });
      final left = res['quantity_remaining'];
      final leftNote = left == null ? '' : ' · sisa kuota $left';
      final poinNote =
          pointsCost > 0 ? ' · −$pointsCost poin saat bayar' : '';
      _showSnack(
        'Voucher ${res['title'] ?? code} diterapkan (−Rp $nominal)'
        '$leftNote$poinNote',
        OptikAdminTokens.success,
      );
    } finally {
      if (mounted) setState(() => _lookingUpVoucher = false);
    }
  }

  void _clearAppliedVoucher() {
    voucherCtrl.clear();
    _appliedVoucherCode = null;
    _appliedVoucherPointsCost = 0;
    _appliedVoucherNominal = 0;
    discountCtrl.text = '0';
  }

  /// Parse diskon manual. Tolak campuran huruf (kode voucher terlanjur di field)
  /// supaya "QA1PUSAT" tidak jadi potongan Rp 1.
  int _parseDiskonRpText(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    if (RegExp(r'[A-Za-z]').hasMatch(t)) return 0;
    return int.tryParse(t.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static const _lensJenisOptions = ['Standar', 'Progresif', 'Kryptok'];
  static const _lensBahanOptions = [
    'Supersin',
    'Blueray',
    'Photochromic',
    'Bluechromic',
    'Night Driving',
    'Antifog',
  ];
  static const _paymentMethods = ['Tunai', 'Debit', 'Transfer', 'QRIS'];
  static const _paymentStatuses = ['Lunas', 'DP'];

  Future<void> _pickLensJenis() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pos_jenis_lensa'.tr(),
      selected:
          _lensJenisOptions.contains(lensJenis) ? lensJenis : 'Standar',
      searchable: false,
      options: _lensJenisOptions
          .map((e) => AdminPickerOption(value: e, label: e))
          .toList(),
    );
    if (sel == null || sel.isClear || !mounted) return;
    setState(() => lensJenis = sel.value!);
  }

  Future<void> _pickLensBahan() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pos_bahan_lensa'.tr(),
      selected: _lensBahanOptions.contains(lensBahan) ? lensBahan : 'Supersin',
      searchable: false,
      options: _lensBahanOptions
          .map((e) => AdminPickerOption(value: e, label: e))
          .toList(),
    );
    if (sel == null || sel.isClear || !mounted) return;
    setState(() => lensBahan = sel.value!);
  }

  Future<void> _pickLensJenisLama() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pos_jenis_lensa_lama'.tr(),
      selected: _lensJenisOptions.contains(lensJenisLama)
          ? lensJenisLama
          : 'Standar',
      searchable: false,
      options: _lensJenisOptions
          .map((e) => AdminPickerOption(value: e, label: e))
          .toList(),
    );
    if (sel == null || sel.isClear || !mounted) return;
    setState(() => lensJenisLama = sel.value!);
  }

  Future<void> _pickPaymentMethod() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pos_metode'.tr(),
      selected: paymentMethod,
      searchable: false,
      options: _paymentMethods
          .map((e) => AdminPickerOption(value: e, label: e))
          .toList(),
    );
    if (sel == null || sel.isClear || !mounted) return;
    setState(() => paymentMethod = sel.value!);
  }

  Future<void> _pickPaymentStatus() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pos_status'.tr(),
      selected: paymentStatus,
      searchable: false,
      options: _paymentStatuses
          .map((e) => AdminPickerOption(value: e, label: e))
          .toList(),
    );
    if (sel == null || sel.isClear || !mounted) return;
    setState(() {
      paymentStatus = sel.value!;
      if (paymentStatus == 'Lunas') {
        paidCtrl.text = _totalAkhir.toString();
      } else {
        paidCtrl.clear();
      }
    });
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
        // Store-open restore must NOT unlock POS — cashier NIK scan required.
        // (Previously always true, which skipped unlock after reload / training leak.)
        if (!storeOpen) {
          isPosUnlocked = false;
          activeCashier = null;
          namaKasir = '';
        }
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
          shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
          title: Text(
            "pos_tutup_shift_title".tr(),
            style: const TextStyle(
                color: OptikAdminTokens.navy, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${"pos_modal_awal_sesi".tr()}${formatRupiah(modalAwal)}",
                  style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12)),
              Text(
                  "${"pos_omzet_tunai_masuk".tr()}${formatRupiah(totalTunaiHariIni)}",
                  style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12)),
              const Divider(color: OptikAdminTokens.lineStrong, height: 20),
              Text(
                "${"pos_kas_seharusnya".tr()}${formatRupiah(uangSeharusnyaDiLaci)}",
                style: const TextStyle(
                    color: OptikAdminTokens.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: uangFisikCloseCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: OptikAdminTokens.navy, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "pos_hint_uang_fisik".tr(),
                  prefixText: "Rp ",
                  labelStyle: const TextStyle(color: OptikAdminTokens.slate, fontSize: 11),
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
                  style: const TextStyle(color: OptikAdminTokens.slate)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.danger,
                foregroundColor: OptikAdminTokens.snow,
              ),
              onPressed: () async {
                int uangFisikRiil = int.tryParse(uangFisikCloseCtrl.text
                        .replaceAll(RegExp(r'[^0-9]'), '')) ??
                    0;
                int selisih = uangFisikRiil - uangSeharusnyaDiLaci;

                final closeNow = DateTime.now();
                final closeDate = closeNow.toIso8601String().split('T')[0];
                // Unik per sesi (hindari tabrakan tutup toko 2x di hari sama).
                final closeRef =
                    'CLOSE-$tokoId-$closeDate-${closeNow.millisecondsSinceEpoch}';
                await supabase.from('finance_transactions').insert({
                  'toko_id': tokoId,
                  'tanggal_transaksi': closeDate,
                  'jenis_transaksi': selisih >= 0 ? 'PEMASUKAN' : 'PENGELUARAN',
                  'kategori': 'Penutupan Toko (Closing Shift)',
                  'deskripsi':
                      'Sesi Tutup Toko Selesai. Selisih Kas: Rp $selisih (Uang Fisik: Rp $uangFisikRiil | Sistem: Rp $uangSeharusnyaDiLaci)',
                  'nominal': selisih.abs(),
                  'status_pembayaran': 'LUNAS',
                  'metode_pembayaran': 'Tunai',
                  // APPROVED + CLOSE-*: masuk kas ledger, tidak ke antrean COA,
                  // dan tidak dihitung sebagai omzet POS (anti double-count).
                  'status_konfirmasi': 'APPROVED',
                  'referensi_id': closeRef,
                  'nama_kasir': activeCashier?['nama']?.toString() ??
                      widget.profile['nama']?.toString() ??
                      'Kasir',
                });

                try {
                  await GlPostingService().postClosingShift(
                    tokoId: tokoId.toString(),
                    referensiId: closeRef,
                    selisih: selisih,
                    createdBy: activeCashier?['nama']?.toString() ??
                        widget.profile['nama']?.toString(),
                    deskripsi:
                        'Sesi Tutup Toko. Selisih Kas: Rp $selisih',
                  );
                } catch (e) {
                  debugPrint('GL posting closing gagal: $e');
                }

                setState(() {
                  isStoreOpen = false;
                  modalAwal = 0;
                  storeOpenTime = null;
                });
                await _lockPosSession(restartScanner: false);

                modalAwalCtrl.clear();
                uangFisikCloseCtrl.clear();

                if (!mounted) return;
                Navigator.pop(ctx);

                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                    selisih == 0
                        ? "pos_tutup_balanced".tr()
                        : "${"pos_tutup_selisih".tr()}$selisih",
                    style: const TextStyle(
                      color: OptikAdminTokens.snow,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: selisih == 0
                      ? OptikAdminTokens.success
                      : OptikAdminTokens.warning,
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
        builder: (context) => PremiumScaffold(
          appBar: PremiumAppBar(
            title: 'Posisikan Barcode ID Karyawan',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: OptikAdminTokens.navy),
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

    // Mode latihan: no camera / physical NIK — open + unlock with TRAINING01.
    if (TrainingMode.instance.isActive) {
      try {
        await _openStoreTrainingFastPath();
      } catch (e) {
        _showSnack("❌ Error Open Store: $e", OptikAdminTokens.danger);
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
      return;
    }

    XFile? image;
    try {
      image = await _captureSilentOpenStorePhoto()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e) {
      debugPrint("Timeout auto-capture open store: $e");
    } catch (e) {
      debugPrint("Gagal inisialisasi hardware auto-capture: $e");
    }

    // Web often has no usable camera — continue with placeholder photo so the
    // unlock screen (HID / manual NIK) can still open the session.
    if (image == null && !kIsWeb) {
      if (mounted) setState(() => isLoading = false);
      _showSnack(
          "❌ Gagal menjepret foto otomatis. Pastikan izin kamera browser aktif!",
          OptikAdminTokens.danger);
      return;
    }

    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';

      String photoUrl = "";
      if (image != null) {
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
      } else {
        photoUrl = "https://placeholder.co/600x400?text=No+Photo+Absen";
      }

      // Web Chrome: skip in-flow camera NIK dialog — open store then unlock UI.
      if (kIsWeb) {
        try {
          await supabase.from('session_logs').insert({
            'toko_id': tokoId,
            'karyawan_id': 'PENDING_UNLOCK',
            'photo_url': photoUrl,
            'timestamp_open': DateTime.now().toIso8601String(),
            'status': 'OPEN',
          });
        } catch (e) {
          debugPrint('session_logs web open: $e');
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_store_open_$tokoId', true);
        await prefs.setString(
          'last_open_time_$tokoId',
          DateTime.now().toIso8601String(),
        );
        storeOpenTime = DateTime.now();
        if (mounted) {
          setState(() {
            isStoreOpen = true;
            isPosUnlocked = false;
            activeCashier = null;
            namaKasir = '';
            karyawanTerlibat = [];
          });
        }
        _showSnack(
          "Toko dibuka — ketik/scan NIK kasir untuk unlock.",
          OptikAdminTokens.success,
        );
        return;
      }

      // 🎯 SINKRONISASI TOTAL: Loncat ke scan barcode kamera depan untuk ID karyawan!
      final String? nikKaryawan =
          await _scanBarcode(facing: CameraFacing.front);

      if (nikKaryawan == null || nikKaryawan.isEmpty) {
        _showSnack("Sesi dibatalkan", OptikAdminTokens.danger);
        return;
      }

      final res = await _lookupKaryawanByNik(
        nikKaryawan,
        requireOnDuty: true,
      );
      if (res == null) {
        final errKey = _lastKaryawanLookupErrorKey;
        final any = await _lookupKaryawanByNik(
          nikKaryawan,
          requireAktif: false,
          requireOnDuty: false,
        );
        _showSnack(
          any == null
              ? '❌ Karyawan tidak terdaftar!'
              : (errKey ?? 'pos_terlibat_not_aktif').tr(),
          OptikAdminTokens.danger,
        );
        return;
      }

      await supabase.from('session_logs').insert({
        'toko_id': tokoId,
        // Kolom historis: text NIK (bukan uuid karyawan.id).
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
        // Terlibat final diisi ulang saat scan unlock POS (fleksibel).
        karyawanTerlibat = [];
      });
      _showSnack("✅ Toko Opened by: ${res['nama']}", OptikAdminTokens.success);
    } catch (e) {
      // 🎯 FIX: Ini pasangan catch utamanya yang tadi hilang kemakan
      _showSnack("❌ Error Open Store: $e", OptikAdminTokens.danger);
    } finally {
      // 🎯 FIX: Ini status loading diturunkan biar aplikasi ga nge-hang
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<XFile?> _captureSilentOpenStorePhoto() async {
    XFile? image;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;

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
    } finally {
      if (_silentCameraController != null) {
        await _silentCameraController!.dispose();
        _silentCameraController = null;
      }
    }
    return image;
  }

  /// Training Mode: open store + unlock POS without camera / physical NIK scan.
  Future<void> _openStoreTrainingFastPath() async {
    final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
    final res = await _lookupKaryawanByNik(
      'TRAINING01',
      requireAktif: false,
      requireOnDuty: false,
    );
    if (res == null) {
      _showSnack('pos_err_barcode'.tr(), OptikAdminTokens.danger);
      return;
    }

    try {
      await supabase.from('session_logs').insert({
        'toko_id': tokoId,
        'karyawan_id': 'TRAINING01',
        'photo_url': 'https://placeholder.co/600x400?text=Training+Session',
        'timestamp_open': DateTime.now().toIso8601String(),
        'status': 'OPEN',
      });
    } catch (e) {
      debugPrint('[Training] session_logs insert skipped/failed: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_store_open_$tokoId', true);
    await prefs.setString(
      'last_open_time_$tokoId',
      DateTime.now().toIso8601String(),
    );

    storeOpenTime = DateTime.now();
    setState(() {
      isStoreOpen = true;
      isPosUnlocked = true;
      activeCashier = res;
      namaKasir = res['nama']?.toString() ?? 'Kasir Latihan';
      kasirCtrl.text = namaKasir;
      karyawanTerlibat = [];
      _addKaryawanTerlibatSilent(res);
    });
    _showSnack("✅ Toko Opened by: $namaKasir", OptikAdminTokens.success);
  }

  /// Tambah karyawan ke daftar terlibat (dedupe). Return true jika baru ditambah.
  bool _addKaryawanTerlibatSilent(Map<String, dynamic> karyawan) {
    final id = karyawan['id']?.toString();
    if (id == null || id.isEmpty) return false;
    if (karyawanTerlibat.any((k) => k['id']?.toString() == id)) return false;
    karyawanTerlibat = [
      ...karyawanTerlibat,
      Map<String, dynamic>.from(karyawan),
    ];
    return true;
  }

  /// Error i18n terakhir dari lookup/duty gate (untuk snack yang spesifik).
  String? _lastKaryawanLookupErrorKey;

  Future<Map<String, dynamic>?> _lookupKaryawanByNik(
    String nik, {
    bool requireAktif = true,
    bool requireOnDuty = false,
  }) async {
    _lastKaryawanLookupErrorKey = null;
    final key = nik.trim();
    if (key.isEmpty) return null;
    try {
      final res = await supabase
          .from('karyawan')
          .select()
          .eq('nik', key)
          .maybeSingle();
      if (res == null) return null;
      final map = Map<String, dynamic>.from(res);
      if (requireAktif) {
        final status =
            (map['status_approval'] ?? '').toString().trim().toLowerCase();
        if (status.isNotEmpty && status != 'aktif') {
          _lastKaryawanLookupErrorKey = 'pos_terlibat_not_aktif';
          return null;
        }
      }
      if (requireOnDuty) {
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty) return null;
        final dutyBlock = await PosDutyGate.blockReason(
          karyawanId: id,
          nik: key,
        );
        if (dutyBlock != null) {
          _lastKaryawanLookupErrorKey = dutyBlock;
          return null;
        }
      }
      return map;
    } catch (e) {
      debugPrint('Lookup karyawan NIK gagal: $e');
      return null;
    }
  }

  bool _isLikelyKaryawanNik(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    // Jangan rebut payload produk/QR bertanda khusus.
    if (s.contains('|') || s.contains('{') || s.contains(':')) return false;
    if (ProductCode.looksLike(s)) return false;
    final routed = QrRouter.classify(s);
    if (routed.isKnown) return false;
    // NIK karyawan di sistem biasanya numerik / alfanumerik pendek.
    return RegExp(r'^[A-Za-z0-9_-]{4,32}$').hasMatch(s);
  }

  /// Scan pertama di gerbang POS: langsung masuk halaman kasir + daftar terlibat.
  Future<void> _restartUnlockScanner() async {
    try {
      await kameraLoginCtrl.start();
    } catch (e) {
      debugPrint('Restart kamera unlock POS: $e');
    }
  }

  Future<void> _lockPosSession({bool restartScanner = true}) async {
    if (!mounted) return;
    setState(() {
      isPosUnlocked = false;
      activeCashier = null;
      namaKasir = '';
      kasirCtrl.clear();
      karyawanTerlibat = [];
      isScanningLocal = true;
      _unlockScanBusy = false;
      _lastUnlockNik = null;
      _lastUnlockScanAt = null;
    });
    if (restartScanner && mounted) {
      await _restartUnlockScanner();
    }
  }

  Future<void> _onUnlockKaryawanBarcode(String rawNik) async {
    final nik = rawNik.trim();
    if (nik.isEmpty || _unlockScanBusy || isPosUnlocked) return;

    final now = DateTime.now();
    if (_lastUnlockNik == nik &&
        _lastUnlockScanAt != null &&
        now.difference(_lastUnlockScanAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastUnlockNik = nik;
    _lastUnlockScanAt = now;
    _unlockScanBusy = true;

    try {
      final isTrainingNik = nik.toUpperCase() == 'TRAINING01';
      final res = await _lookupKaryawanByNik(
        nik,
        requireAktif: !isTrainingNik,
        requireOnDuty: !isTrainingNik,
      );
      if (res == null) {
        final errKey = _lastKaryawanLookupErrorKey;
        final any = await _lookupKaryawanByNik(
          nik,
          requireAktif: false,
          requireOnDuty: false,
        );
        _showSnack(
          any == null
              ? 'pos_err_barcode'.tr()
              : (errKey ?? 'pos_terlibat_not_aktif').tr(),
          OptikAdminTokens.danger,
        );
        // Izinkan scan ulang NIK yang sama setelah gagal.
        _lastUnlockNik = null;
        _lastUnlockScanAt = null;
        return;
      }

      try {
        await kameraLoginCtrl.stop();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        karyawanTerlibat = [];
        _addKaryawanTerlibatSilent(res);
        activeCashier = res;
        namaKasir = res['nama']?.toString() ?? '';
        kasirCtrl.text = namaKasir;
        isPosUnlocked = true;
        isScanningLocal = false;
      });
      _showSnack(
        'pos_terlibat_scan_ok'
            .tr()
            .replaceAll('{}', res['nama']?.toString() ?? ''),
        OptikAdminTokens.success,
      );
    } finally {
      _unlockScanBusy = false;
    }
  }

  void _removeKaryawanTerlibat(String karyawanId) {
    final cashierId = activeCashier?['id']?.toString();
    // Kasir yang unlock POS wajib tetap di daftar.
    if (cashierId != null && cashierId == karyawanId) {
      _showSnack('pos_terlibat_keep_kasir'.tr(), OptikAdminTokens.warning);
      return;
    }
    setState(() {
      karyawanTerlibat = karyawanTerlibat
          .where((k) => k['id']?.toString() != karyawanId)
          .toList();
    });
  }

  Future<void> _pickTambahKaryawanTerlibat() async {
    final tokoId = _tokoId;
    List<Map<String, dynamic>> list;
    try {
      final rows = await supabase
          .from('karyawan')
          .select('id, nama, jabatan, toko_id, face_url, nik')
          .eq('toko_id', tokoId)
          .eq('status_approval', 'Aktif')
          .order('nama');
      list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final onDutyIds = await PosDutyGate.openShiftIdsForToko(tokoId);
      if (onDutyIds != null) {
        list = list
            .where((k) => onDutyIds.contains(k['id']?.toString()))
            .toList();
      }
    } catch (e) {
      _showSnack('${'pos_terlibat_load_err'.tr()}$e', OptikAdminTokens.danger);
      return;
    }
    if (!mounted) return;
    if (list.isEmpty) {
      _showSnack('pos_duty_picker_empty'.tr(), OptikAdminTokens.warning);
      return;
    }
    final existing = karyawanTerlibat
        .map((k) => k['id']?.toString())
        .whereType<String>()
        .toSet();
    final options = list
        .where((k) => !existing.contains(k['id']?.toString()))
        .map(
          (k) => AdminPickerOption<String>(
            value: k['id'].toString(),
            label: k['nama']?.toString() ?? '-',
            subtitle: k['jabatan']?.toString(),
            icon: Icons.person_add_alt_1_rounded,
          ),
        )
        .toList();
    if (options.isEmpty) {
      _showSnack('pos_terlibat_all_added'.tr(), OptikAdminTokens.ice);
      return;
    }
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pos_terlibat_pick'.tr(),
      options: options,
      searchable: options.length > 6,
    );
    if (sel == null || sel.value == null) return;
    final picked = list.firstWhere(
      (k) => k['id']?.toString() == sel.value,
      orElse: () => <String, dynamic>{},
    );
    if (picked.isEmpty) return;
    setState(() => _addKaryawanTerlibatSilent(picked));
    _showSnack(
      'pos_terlibat_added'
          .tr()
          .replaceAll('{}', picked['nama']?.toString() ?? ''),
      OptikAdminTokens.success,
    );
  }

  List<String> _terlibatIdsForCheckout() {
    final ids = <String>{};
    for (final k in karyawanTerlibat) {
      final id = k['id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    final cashierId = activeCashier?['id']?.toString();
    if (cashierId != null && cashierId.isNotEmpty) ids.add(cashierId);
    return ids.toList();
  }

  Future<void> _persistKaryawanTerlibat(
    String saleId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return;
    await supabase.from('sales_karyawan_terlibat').upsert(
          ids
              .map((id) => {
                    'sale_id': saleId,
                    'karyawan_id': id,
                  })
              .toList(),
          onConflict: 'sale_id,karyawan_id',
        );
  }

  Future<void> _awardPoinInvoiceTerlibat(
    String saleId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    for (final id in ids) {
      try {
        await supabase.from('poin_logs').insert({
          'karyawan_id': id,
          'tanggal': today,
          'poin': 5,
          'sumber': 'INVOICE',
          'ref_id': saleId,
        });
      } catch (e) {
        debugPrint('Poin INVOICE gagal untuk $id: $e');
      }
    }
  }

  Future<void> _rollbackPoinInvoiceTerlibat(String saleId) async {
    try {
      await supabase
          .from('poin_logs')
          .delete()
          .eq('sumber', 'INVOICE')
          .eq('ref_id', saleId);
    } catch (e) {
      debugPrint('Rollback poin INVOICE gagal: $e');
    }
  }

  Widget _buildKaryawanTerlibatBar() {
    final chips = karyawanTerlibat.map((k) {
      final id = k['id']?.toString() ?? '';
      final nama = (k['nama']?.toString() ?? 'Staff').trim();
      final short =
          nama.isEmpty ? 'Staff' : nama.split(' ').first.toUpperCase();
      final isCashier = activeCashier?['id']?.toString() == id;
      return InputChip(
        avatar: CircleAvatar(
          backgroundImage: k['face_url'] != null
              ? NetworkImage(k['face_url'].toString())
              : null,
          child: k['face_url'] == null
              ? const Icon(Icons.person, size: 14)
              : null,
        ),
        label: Text(
          short,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        onDeleted: (isCashier || isProcessing)
            ? null
            : () => _removeKaryawanTerlibat(id),
        deleteIconColor: OptikAdminTokens.danger,
        backgroundColor: OptikAdminTokens.bgMid,
        side: BorderSide(color: OptikAdminTokens.lineStrong),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: OptikAdminTokens.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.75)),
          boxShadow: OptikAdminTokens.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_rounded,
                    size: 18, color: OptikAdminTokens.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'pos_terlibat_title'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: OptikAdminTokens.navy,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      isProcessing ? null : _pickTambahKaryawanTerlibat,
                  style: TextButton.styleFrom(
                    foregroundColor: OptikAdminTokens.navy,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(
                    'pos_terlibat_tambah'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'pos_terlibat_hint'.tr(),
              style: TextStyle(
                fontSize: 10.5,
                color: OptikAdminTokens.navy.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...chips,
                if (chips.isEmpty)
                  Text(
                    'pos_terlibat_none'.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      color: OptikAdminTokens.navy.withOpacity(0.55),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _applyObrCustomer(QrRouteResult routed) {
    setState(() {
      if ((routed.customerNama ?? '').isNotEmpty) {
        nameCtrl.text = routed.customerNama!;
      }
      if ((routed.customerPhone ?? '').isNotEmpty) {
        phoneCtrl.text = routed.customerPhone!;
      }
      if ((routed.customerEmail ?? '').isNotEmpty) {
        emailCtrl.text = routed.customerEmail!;
      }
    });
    _showSnack('Data pelanggan terisi dari QR OBRCUS.', OptikAdminTokens.success);
  }

  void _showCustomerQrDialog() {
    final payload = ObrCustomer.encode(
      nama: nameCtrl.text,
      phone: phoneCtrl.text,
      email: emailCtrl.text,
    );
    if (payload.isEmpty) {
      _showSnack('Isi nama pelanggan dulu sebelum buat QR.', OptikAdminTokens.warning);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: const Text('QR Pelanggan (OBRCUS)',
            style: TextStyle(color: OptikAdminTokens.navy, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload,
                size: 180,
                version: QrVersions.auto,
                backgroundColor: OptikAdminTokens.snow,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              payload,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  /// Scan bebas urutan: apa yang di-scan → itu yang diterima (produk/karyawan/QR).
  Future<void> _onPosScanSubmitted(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) return;
    skuScanCtrl.clear();

    final routed = QrRouter.classify(raw);

    // 1) Payload yang sudah dikenali formatnya.
    if (routed.type == QrPayloadType.product || ProductCode.looksLike(raw)) {
      await _cariProdukBySKU(raw);
      return;
    }
    if (routed.type == QrPayloadType.customer) {
      _applyObrCustomer(routed);
      return;
    }
    if (routed.isKnown) {
      final proceed = await _guardPosLeaveForKnownQr(routed);
      if (!proceed || !mounted) return;
      await UniversalQrNav.dispatch(
        context,
        routed,
        profile: widget.profile,
        callerRole: UniversalQrCallerRole.admin,
        fromAdminHidScanner: routed.invoiceCustomerLifecycle,
      );
      return;
    }

    // 2) Deteksi isi: NIK karyawan aktif + sedang bertugas → terlibat.
    if (!isProcessing && _isLikelyKaryawanNik(raw)) {
      final asKaryawan = await _lookupKaryawanByNik(raw, requireOnDuty: true);
      if (asKaryawan != null) {
        final added = _addKaryawanTerlibatSilent(asKaryawan);
        if (mounted) setState(() {});
        _showSnack(
          added
              ? 'pos_terlibat_added'
                  .tr()
                  .replaceAll('{}', asKaryawan['nama']?.toString() ?? '')
              : 'pos_terlibat_already'
                  .tr()
                  .replaceAll('{}', asKaryawan['nama']?.toString() ?? ''),
          added ? OptikAdminTokens.success : OptikAdminTokens.ice,
        );
        return;
      }
      final errKey = _lastKaryawanLookupErrorKey;
      final any = await _lookupKaryawanByNik(
        raw,
        requireAktif: false,
        requireOnDuty: false,
      );
      if (any != null) {
        _showSnack(
          (errKey ?? 'pos_terlibat_not_aktif').tr(),
          OptikAdminTokens.danger,
        );
        return;
      }
    }

    // 3) Selain itu anggap SKU/barcode produk.
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
          await _releasePosHold();
          await _clearPosDraft();
          _resetForm();
          await _lockPosSession(restartScanner: false);
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
        'voucher_code': _appliedVoucherCode,
        'voucher_points_cost': _appliedVoucherPointsCost,
        'voucher_nominal': _appliedVoucherNominal,
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
        _showSnack('pos_draft_saved'.tr(), OptikAdminTokens.success);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('${'pos_draft_save_err'.tr()}$e', OptikAdminTokens.danger);
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
        final draftVoucher = (map['voucher_code'] ?? '').toString().trim();
        _appliedVoucherCode =
            draftVoucher.isEmpty ? null : draftVoucher;
        _appliedVoucherPointsCost =
            int.tryParse('${map['voucher_points_cost'] ?? 0}') ?? 0;
        _appliedVoucherNominal = _appliedVoucherCode == null
            ? 0
            : (int.tryParse('${map['voucher_nominal'] ?? ''}') ??
                _parseDiskonRpText(discountCtrl.text));
        // Diskon tanpa kode voucher di draft = diskon manual (bukan voucher).
        if (_appliedVoucherCode == null &&
            _parseDiskonRpText(discountCtrl.text) > 0) {
          // biarkan diskon manual
        }
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
        _showSnack('pos_draft_restored'.tr(), OptikAdminTokens.success);
      }
    } catch (e) {
      debugPrint('POS draft restore failed: $e');
    }
  }

  Future<void> _cariProdukBySKU(String rawScan) async {
    setState(() => isProcessing = true);
    try {
      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
      final parsed = ProductCode.parse(rawScan);
      final sku = (parsed?.sku ?? ProductCode.resolveSku(rawScan) ?? '').trim();
      final productId = parsed?.productId;

      if (sku.isEmpty && (productId == null || productId.isEmpty)) {
        _showSnack("pos_err_sku_tidak_terdaftar".tr(), OptikAdminTokens.warning);
        return;
      }

      // 1. Cari produk di toko login dulu (SKU/barcode), fallback master
      Map<String, dynamic>? res;
      if (productId != null && productId.isNotEmpty) {
        res = await supabase
            .from('products')
            .select()
            .eq('id', productId)
            .maybeSingle();
      }
      res ??= await ProductIdentity.findAtToko(
        tokoId: tokoId.toString(),
        sku: sku,
        barcode: sku,
        select: '*',
      );
      if (res == null && sku.isNotEmpty) {
        res = await supabase
            .from('products')
            .select()
            .eq('sku', sku)
            .eq('toko_id', 'PUSAT')
            .maybeSingle();
      }

      if (res != null) {
        final stockSku = (res['sku'] ?? res['barcode'] ?? sku).toString();
        // 2. Cek stok dari products.stock toko login (sumber kebenaran tunggal)
        Map<String, dynamic>? localProd;
        if ((res['toko_id'] ?? '').toString().toUpperCase() ==
            tokoId.toString().toUpperCase()) {
          localProd = Map<String, dynamic>.from(res);
        } else {
          // Produk pusat wajib terdaftar di toko (stok tidak disalin dari PUSAT).
          await ProductIdentity.ensureAtToko(
            tokoId: tokoId.toString(),
            sku: stockSku,
          );
          localProd = await supabase
              .from('products')
              .select('id, stock, reserved_qty, sku, barcode, toko_id')
              .eq('toko_id', tokoId)
              .eq('sku', stockSku)
              .maybeSingle();
          localProd ??= await supabase
              .from('products')
              .select('id, stock, reserved_qty, sku, barcode, toko_id')
              .eq('toko_id', tokoId)
              .eq('barcode', stockSku)
              .maybeSingle();
        }
        final stokAktif = StockQty.availableOf(
          localProd != null ? Map<String, dynamic>.from(localProd) : null,
        );

        // Pastikan item keranjang memakai id baris produk toko ini
        if (localProd != null && localProd['id'] != null) {
          res = {
            ...Map<String, dynamic>.from(res),
            'id': localProd['id'],
            'stock': StockQty.realOf(Map<String, dynamic>.from(localProd)),
            'reserved_qty':
                StockQty.pendingOf(Map<String, dynamic>.from(localProd)),
            'toko_id': tokoId,
            'sku': localProd['sku'] ?? stockSku,
          };
        }

        if (stokAktif <= 0) {
          // Stok 0: jangan blokir — lanjut RO / jual pending (bukan lensa scan R/L).
          if (res['kategori'] == 'Lensa') {
            _showSnack(
              'Stok lensa kosong — isi spek manual atau laporkan RO ke Pusat.',
              OptikAdminTokens.warning,
            );
            return;
          }
          _tambahKeRestockQueue(Map<String, dynamic>.from(res));
          return;
        }

        // 3. Pisahkan Logika Kategori Lensa vs Frame/Aksesoris
        if (res['kategori'] == 'Lensa') {
          if (lensScanSide == 'R') {
            setState(() {
              selectedLens = res;
              lensScanSide = 'L'; // Pindah minta scan lensa kiri
            });
            _showSnack("pos_lensa_r_sukses".tr(), OptikAdminTokens.success);
          } else {
            // Jika Lensa Kiri di-scan
            setState(() {
              _tambahKeKeranjangLensaLangsung(selectedLens, res);
              lensScanSide = 'R'; // Reset kembali ke kanan
              selectedLens = null;
            });
            _showSnack("pos_lensa_l_sukses".tr(), OptikAdminTokens.success);
          }
        } else {
          // Logika untuk Frame & Aksesoris
          _tambahItemKeKeranjang(res, stokAktif);
        }
      } else {
        _showSnack("pos_err_sku_tidak_terdaftar".tr(), OptikAdminTokens.warning);
      }
    } catch (e) {
      _showSnack("${"pos_err_search".tr()}$e", OptikAdminTokens.danger);
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
              OptikAdminTokens.warning);
        } else {
          cartItems[existingIndex]['qty']++;
          // Hitung subtotal menggunakan harga asli item itu sendiri yang sudah tersimpan
          int hargaItemTerbaca = cartItems[existingIndex]['harga'] ?? harga;
          cartItems[existingIndex]['subtotal'] =
              cartItems[existingIndex]['qty'] * hargaItemTerbaca;
          _showSnack("$nama berhasil ditambahkan", OptikAdminTokens.success);
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
        _showSnack("$nama berhasil ditambahkan", OptikAdminTokens.success);
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
    unawaited(_syncPosHoldAfterCartChange());
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        msg,
        style: const TextStyle(
          color: OptikAdminTokens.snow,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
    ));
  }

  Widget _posCategoryToggle({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor:
            active ? OptikAdminTokens.navy : OptikAdminTokens.card,
        foregroundColor:
            active ? OptikAdminTokens.snow : OptikAdminTokens.navy,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
          side: BorderSide(
            color: active
                ? OptikAdminTokens.navy
                : OptikAdminTokens.ice.withOpacity(0.85),
            width: active ? 1.2 : 1.4,
          ),
        ),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: active ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
      onPressed: onPressed,
    );
  }

  /// Panel POS — border + sheen agar tidak “pucet” di kanvas putih.
  Widget _posPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: OptikAdminTokens.cardSheen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: OptikAdminTokens.ice.withOpacity(0.7),
          width: 1.15,
        ),
        boxShadow: OptikAdminTokens.cardShadow,
      ),
      child: child,
    );
  }

  // ==========================================================================
  // WIDGET DIALOG: INPUT JUMLAH PENDING REQUEST / PRE-ORDER (LINT FIXED)
  // ==========================================================================
  void _showPendingRequestDialog(
      Map<String, dynamic> item, int sisaStokGudang) {
    // ✅ FIX 1: Singkirkan underscore (_) pada variabel lokal agar sesuai standar Dart rule
    final TextEditingController qtyPoCtrl = TextEditingController(
      text: sisaStokGudang <= 0 ? '1' : '',
    );
    final isRoEmpty = sisaStokGudang <= 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: Row(
          children: [
            Icon(
              isRoEmpty
                  ? Icons.local_shipping_rounded
                  : Icons.shopping_bag_outlined,
              color: OptikAdminTokens.navy,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isRoEmpty
                    ? 'Lanjut RO — isi qty'
                    : 'Stok terbatas (sisa: $sisaStokGudang)',
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Produk: ${item['nama_produk'] ?? item['nama']}",
                style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13)),
            const SizedBox(height: 8),
            Text(
              isRoEmpty
                  ? 'Pelanggan setuju RO. Masukkan qty → keranjang sebagai stok pending + RO ke Pusat.'
                  : 'Masukkan jumlah kekurangan (pre-order / RO):',
              style: const TextStyle(
                color: OptikAdminTokens.slate,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isRoEmpty ? 'Jumlah RO / qty jual:' : 'Jumlah kekurangan:',
              style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyPoCtrl, // ✅ Menggunakan nama variabel baru
              keyboardType: TextInputType.number,
              style: const TextStyle(color: OptikAdminTokens.navy),
              decoration: InputDecoration(
                hintText: "Contoh: 2",
                hintStyle: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
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
            child: const Text("Batal", style: TextStyle(color: OptikAdminTokens.slate)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            onPressed: () async {
              int qtyNeeded = int.tryParse(qtyPoCtrl.text) ??
                  0; // ✅ Menggunakan nama variabel baru
              if (qtyNeeded <= 0) {
                _showSnack("Jumlah harus lebih dari 0", OptikAdminTokens.danger);
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

                // Tandai item keranjang: stok belum ready → checkout bisa DP
                // atau LUNAS pending (admin konfirmasi nanti).
                setState(() {
                  final nama =
                      (item['nama_produk'] ?? item['nama'] ?? '').toString();
                  final sku = (item['sku'] ?? '').toString();
                  final idProduk = item['id'];
                  final idx = cartItems.indexWhere((c) {
                    if (idProduk != null && c['id'] == idProduk) return true;
                    return c['sku'] == sku &&
                        (c['nama_produk'] == nama || c['nama'] == nama);
                  });
                  if (idx >= 0) {
                    cartItems[idx]['needs_fulfillment'] = true;
                    cartItems[idx]['qty'] =
                        (cartItems[idx]['qty'] as int? ?? 1) + qtyNeeded;
                    final harga =
                        cartItems[idx]['harga'] as int? ?? 0;
                    cartItems[idx]['subtotal'] =
                        (cartItems[idx]['qty'] as int) * harga;
                  } else {
                    final harga = int.tryParse(item['harga']?.toString() ??
                            item['harga_jual']?.toString() ??
                            '0') ??
                        0;
                    cartItems.add({
                      'id': idProduk,
                      'nama_produk': nama,
                      'nama': nama,
                      'sku': sku.isEmpty ? 'No SKU' : sku,
                      'harga': harga,
                      'harga_jual': harga,
                      'qty': qtyNeeded,
                      'subtotal': harga * qtyNeeded,
                      'kategori': item['kategori'],
                      'is_lensa_custom': false,
                      'needs_fulfillment': true,
                    });
                  }
                });

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
                    OptikAdminTokens.training,
                  );
                } else {
                  _showSnack(
                    isRoEmpty
                        ? 'RO $qtyNeeded pcs + masuk keranjang (stok pending). '
                            'Bisa DP atau bayar lunas.'
                        : 'Pre-Order $qtyNeeded pcs + masuk keranjang (stok pending). '
                            'Bisa DP atau bayar lunas.',
                    OptikAdminTokens.success,
                  );
                }
              } catch (e) {
                _showSnack("Gagal menyimpan request: $e", OptikAdminTokens.danger);
              }
            },
            child: Text(
              isRoEmpty ? 'Simpan RO' : 'Simpan Request',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // POP-UP PENCARIAN & PEMILIHAN PRODUK MANUAL
  // ==========================================================================

  double _posPickDialogWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    // Lebar konten AlertDialog — jangan bungkus AlertDialog di ConstrainedBox
    // (itu yang bikin modal putih kosong di web).
    return (w * 0.88).clamp(320.0, 560.0);
  }

  double _posPickDialogHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.55).clamp(320.0, 520.0);
  }

  Widget _posPickProductTile({
    required Map<String, dynamic> item,
    required int stock,
    required int real,
    required int pending,
    required int totalReal,
    required String tokoLabel,
    required VoidCallback onTap,
  }) {
    final sku = item['sku']?.toString() ?? "pos_tanpa_sku".tr();
    final fotoUrl =
        (item['foto_url'] ?? item['image_url'] ?? '').toString();
    final nama = item['nama']?.toString() ?? "pos_tanpa_nama".tr();
    final harga = item['harga'] ?? 0;
    final stockColor = stock > 0 ? OptikAdminTokens.success : OptikAdminTokens.danger;

    return PremiumPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      borderRadius: 14,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: OptikAdminTokens.navy.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: fotoUrl.isNotEmpty
                    ? Image.network(
                        fotoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported,
                          color: OptikAdminTokens.slate,
                          size: 28,
                        ),
                      )
                    : const Icon(Icons.image, color: OptikAdminTokens.lineStrong, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nama,
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SKU: $sku',
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toko $tokoLabel — Tersedia: $stock · Real: $real · Pending: $pending',
                      style: TextStyle(
                        color: stockColor,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    Text(
                      'Total semua lokasi (Master): Real $totalReal',
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rp $harga',
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Icon(Icons.add_shopping_cart_rounded,
                    color: OptikAdminTokens.navy, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                // Katalog = semua Frame di PUSAT; stok = cabang login (0 jika belum ada).
                // Baris toko yang belum ada didaftarkan otomatis tanpa salin stok PUSAT.
                final res =
                    await ProductIdentity.listPusatCatalogWithTokoStock(
                  tokoId: (widget.profile['toko_id'] ?? 'PUSAT').toString(),
                  kategoriEq: 'Frame',
                  search: initLoad ? null : searchQuery,
                  limit: 80,
                  ensureMissingRows: true,
                );
                setStateDialog(() {
                  searchResults = res;
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

            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
                side: const BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              title: Text(
                "pos_pilih_produk_frame".tr(),
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: _posPickDialogWidth(context),
                height: _posPickDialogHeight(context),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: "pos_filter_nama_sku".tr(),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: OptikAdminTokens.navy, size: 22),
                        filled: true,
                        fillColor: OptikAdminTokens.bgMid,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.navy, width: 1.4),
                        ),
                      ),
                      onChanged: (val) {
                        searchQuery = val;
                        cariDataFrame();
                      },
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: OptikAdminTokens.ice))
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    "pos_produk_tidak_ditemukan".tr(),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.slate),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    var frame = searchResults[index];
                                    final frameMap =
                                        Map<String, dynamic>.from(frame as Map);
                                    final real = StockQty.realOf(frameMap);
                                    final pending =
                                        StockQty.pendingOf(frameMap);
                                    final stock =
                                        StockQty.availableOf(frameMap);
                                    final totalReal = int.tryParse(
                                            '${frameMap['total_stock'] ?? real}') ??
                                        real;
                                    final tokoLabel =
                                        (widget.profile['toko_id'] ?? 'PUSAT')
                                            .toString()
                                            .toUpperCase();

                                    return _posPickProductTile(
                                      item: frameMap,
                                      stock: stock,
                                      real: real,
                                      pending: pending,
                                      totalReal: totalReal,
                                      tokoLabel: tokoLabel,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        if (stock <= 0) {
                                          // Stok 0: tetap bisa jual → RO + keranjang pending.
                                          _tambahKeRestockQueue(frameMap);
                                          return;
                                        }
                                        setState(() {
                                          selectedFrame = frameMap;
                                          isFrameActive = true;
                                        });
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                      foregroundColor: OptikAdminTokens.slate),
                  child: Text("sop_batal".tr()),
                ),
              ],
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

            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
                side: const BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              title: Text(
                "pos_pilih_merk_lensa".tr(),
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 360,
                height: (MediaQuery.sizeOf(context).height * 0.45)
                    .clamp(260.0, 380.0),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(
                          color: OptikAdminTokens.navy, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Search brand...",
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: OptikAdminTokens.navy, size: 18),
                        filled: true,
                        fillColor: OptikAdminTokens.bgMid,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                      ),
                      onChanged: (val) =>
                          setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredMerk.isEmpty
                          ? const Center(
                              child: Text(
                                "Brand not registered",
                                style: TextStyle(color: OptikAdminTokens.slate),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredMerk.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  title: Text(
                                    filteredMerk[index],
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      color: OptikAdminTokens.slate,
                                      size: 12),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                      foregroundColor: OptikAdminTokens.slate),
                  child: Text("sop_batal".tr()),
                ),
              ],
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
                final res =
                    await ProductIdentity.listPusatCatalogWithTokoStock(
                  tokoId: (widget.profile['toko_id'] ?? 'PUSAT').toString(),
                  kategoriNeq: const ['Frame', 'Lensa'],
                  search: initLoad ? null : searchQuery,
                  limit: 80,
                  ensureMissingRows: true,
                );
                setStateDialog(() {
                  searchResults = res;
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

            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
                side: const BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              title: Text(
                "pos_pilih_aksesoris".tr(),
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: _posPickDialogWidth(context),
                height: _posPickDialogHeight(context),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: "pos_filter_nama_sku".tr(),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: OptikAdminTokens.navy, size: 22),
                        filled: true,
                        fillColor: OptikAdminTokens.bgMid,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.lineStrong),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                          borderSide: const BorderSide(
                              color: OptikAdminTokens.navy, width: 1.4),
                        ),
                      ),
                      onChanged: (val) {
                        searchQuery = val;
                        cariDataLainnya();
                      },
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: OptikAdminTokens.ice))
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    "pos_produk_tidak_ditemukan".tr(),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.slate),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    var item = searchResults[index];
                                    final itemMap =
                                        Map<String, dynamic>.from(item as Map);
                                    final real = StockQty.realOf(itemMap);
                                    final pending =
                                        StockQty.pendingOf(itemMap);
                                    final stock =
                                        StockQty.availableOf(itemMap);
                                    final totalReal = int.tryParse(
                                            '${itemMap['total_stock'] ?? real}') ??
                                        real;
                                    final tokoLabel =
                                        (widget.profile['toko_id'] ?? 'PUSAT')
                                            .toString()
                                            .toUpperCase();

                                    return _posPickProductTile(
                                      item: itemMap,
                                      stock: stock,
                                      real: real,
                                      pending: pending,
                                      totalReal: totalReal,
                                      tokoLabel: tokoLabel,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        if (stock <= 0) {
                                          // Stok 0: tetap bisa jual → RO + keranjang pending.
                                          _tambahKeRestockQueue(itemMap);
                                          return;
                                        }
                                        setState(() {
                                          selectedAksesoris = itemMap;
                                          isLainnyaActive = true;
                                        });
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                      foregroundColor: OptikAdminTokens.slate),
                  child: Text("sop_batal".tr()),
                ),
              ],
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
    // (skip untuk stok pending / lensa custom — sudah masuk skema DP / lunas pending)
    if (delta > 0 &&
        item['needs_fulfillment'] != true &&
        item['is_lensa_custom'] != true) {
      try {
        int stokGudangReal = 0;

        // Validasi menggunakan ID Master Produk (Jauh lebih aman daripada SKU "No SKU")
        if (item['id'] != null) {
          final prodRes = await supabase
              .from('products')
              .select('stock, reserved_qty')
              .eq('id', item['id'])
              .maybeSingle();

          stokGudangReal = StockQty.availableOf(
            prodRes != null ? Map<String, dynamic>.from(prodRes) : null,
          );
        }

        int qtyDiKeranjang = item['qty'] ?? 1;
        // Saat hold aktif, available sudah dikurangi hold sendiri — kembalikan kuota sendiri.
        final sku = ProductIdentity.normalizeSku(item['sku']) ??
            ProductIdentity.normalizeBarcode(item['barcode']);
        final ownHold = (_posHoldActive && sku != null)
            ? _cartReadyQtyForSku(sku)
            : 0;
        final room = stokGudangReal + ownHold;

        // Jika jumlah di keranjang sudah menyentuh atau melebihi stok tersedia
        if (qtyDiKeranjang >= room) {
          _showPendingRequestDialog(item, room);
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
    unawaited(_syncPosHoldAfterCartChange());
  }

  int get _subtotalBelanja {
    return cartItems.fold(
        0, (sum, item) => sum + ((item['subtotal'] ?? 0) as int));
  }

  int get _totalAkhir {
    final diskon = _appliedVoucherCode != null
        ? (_appliedVoucherNominal > 0
            ? _appliedVoucherNominal
            : _parseDiskonRpText(discountCtrl.text))
        : _parseDiskonRpText(discountCtrl.text);
    final total = _subtotalBelanja - diskon;
    return total < 0 ? 0 : total;
  }

// 🎯 FIXED FINAL CONFIG: DATA PELANGGAN KIRI, METADATA + KASIR KANAN, BADGE ATAS QR
  Future<void> _bukaLayarPreviewInvoice() async {
    if (cartItems.isEmpty) {
      _showSnack("pos_err_keranjang_kosong".tr(), OptikAdminTokens.danger);
      return;
    }
    if (nameCtrl.text.isEmpty) {
      _showSnack("pos_err_nama_pelanggan".tr(), OptikAdminTokens.danger);
      return;
    }
    if (paymentStatus == 'DP') {
      final um = int.tryParse(
              paidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      if (um <= 0) {
        _showSnack(
          'Uang muka DP harus lebih dari Rp 0',
          OptikAdminTokens.danger,
        );
        return;
      }
      if (um >= _totalAkhir) {
        _showSnack(
          'Uang muka DP harus kurang dari total. '
          'Pilih Lunas jika bayar penuh.',
          OptikAdminTokens.warning,
        );
        return;
      }
    }
    if (_appliedVoucherPointsCost > 0 && phoneCtrl.text.trim().isEmpty) {
      _showSnack(
        'Voucher butuh $_appliedVoucherPointsCost poin — isi No. WA member',
        OptikAdminTokens.warning,
      );
      return;
    }

    // Hold + countdown dimulai saat KONFIRMASI PEMBELIAN (bukan saat buka preview).
    String cabangLogin =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var confirming = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return FutureBuilder<InvoiceSettings>(
          future: InvoiceSettingsService().fetchForToko(cabangLogin),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: OptikAdminTokens.warning));
            }

            final invSettings =
                snapshot.data ?? InvoiceSettings.defaults(cabangLogin);

            final double fBody = invSettings.fontSizeBody;

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

            final docLines = <InvoiceDocLine>[];
            for (final item in cartItems) {
              String formattedItemLine = '';
              final rawName = item['nama_produk'] ?? '-';
              final kategori =
                  (item['kategori'] ?? '').toString().toLowerCase();

              if (kategori == 'frame' ||
                  (item['sku'] != 'CUSTOM_HQ' &&
                      !rawName.toUpperCase().contains('LENSA'))) {
                final colorAttr = item['warna'] ??
                    item['color'] ??
                    item['frame_color'] ??
                    'Hitam';
                final materialAttr =
                    item['material'] ?? item['bahan'] ?? 'Plastik';
                formattedItemLine =
                    'Frame: $rawName, $materialAttr, $colorAttr  ×${item['qty']}';
              } else if (kategori == 'lensa' ||
                  rawName.toUpperCase().contains('LENSA') ||
                  rawName.toUpperCase().contains('PROGRESIF')) {
                final side =
                    rawName.contains('(R)') ? 'Lensa (R)' : 'Lensa (L)';
                var cleanBrandName = rawName
                    .replaceAll(RegExp(r'Lensa\s*\([RL]\):'), '')
                    .trim();
                cleanBrandName = cleanBrandName
                    .replaceAll(
                        RegExp(
                            r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                        '')
                    .trim();
                var jenis = 'Standar';
                var merk = cleanBrandName;
                if (cleanBrandName.toLowerCase().contains('progresif')) {
                  merk = cleanBrandName
                      .replaceAll(
                          RegExp(r'progresif', caseSensitive: false), '')
                      .trim();
                  jenis = 'Progresif';
                } else if (cleanBrandName.toLowerCase().contains('kryptok')) {
                  merk = cleanBrandName
                      .replaceAll(
                          RegExp(r'kryptok', caseSensitive: false), '')
                      .trim();
                  jenis = 'Kryptok';
                }
                if (merk.isEmpty || merk == 'Lensa') merk = 'New Vision';
                final coating = item['sub_kategori'] ??
                    item['bahan'] ??
                    item['coating'] ??
                    lensBahan;
                formattedItemLine =
                    '$side: $merk, $jenis, $coating  ×${item['qty']}';
              } else {
                formattedItemLine = '$rawName  ×${item['qty']}';
              }
              docLines.add(InvoiceDocLine(
                label: formattedItemLine,
                amount: formatRupiah(item['subtotal'] ?? 0),
                group: InvoiceLayout.groupOfProduct(
                  tipe: item['tipe_produk']?.toString() ??
                      item['kategori']?.toString(),
                  nama: rawName.toString(),
                ),
              ));
            }

            Widget? lensExtra;
            if (hasLensa) {
              lensExtra = _posPreviewLensTable(
                odSph: odSph,
                odCyl: odCyl,
                odAdd: odAdd,
                osSph: osSph,
                osCyl: osCyl,
                osAdd: osAdd,
                liveAxisR: liveAxisR,
                liveAxisL: liveAxisL,
                livePdR: livePdR,
                livePdL: livePdL,
                fBody: fBody,
              );
            }

            final today =
                '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';
            final kasirNama = namaKasir.isNotEmpty
                ? namaKasir
                : (activeCashier?['nama'] ?? 'Staff');

            return AlertDialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
                side: const BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              title: const Text(
                "PRATINJAU NOTA PENJUALAN",
                style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 390,
                child: SingleChildScrollView(
                  child: InvoiceLayout.paper(
                    child: InvoiceLayout.documentBody(
                      settings: invSettings,
                      footerText: InvoiceStatusFooter.forCheckout(
                        isDp: sisaTagihan > 0,
                        footers: invSettings.statusFooters,
                      ),
                      meta: InvoiceDocMeta(
                        noInvoice: noInvoice,
                        customerName: nameCtrl.text,
                        whatsapp: phoneCtrl.text,
                        address: addressCtrl.text.isEmpty
                            ? null
                            : addressCtrl.text,
                        email: emailCtrl.text.isEmpty
                            ? null
                            : emailCtrl.text,
                        cashier: kasirNama.toString(),
                        dateLabel: 'Masuk: $today',
                        // Belum tersimpan — jam tampil setelah invoice jadi.
                        createdAtLabel: null,
                        status: sisaTagihan > 0 ? 'DP' : 'LUNAS',
                        boardStatus: InvoiceStatusFooter.statusOf({
                          'status_pembayaran':
                              sisaTagihan > 0 ? 'DP' : 'LUNAS',
                          'sisa_tagihan': sisaTagihan,
                          'tracking_status': sisaTagihan > 0
                              ? 'PENDING_PO'
                              : 'DIPROSES_DI_CABANG',
                        }),
                      ),
                      lines: docLines,
                      totalFormatted: formatRupiah(_totalAkhir),
                      paidLabel: sisaTagihan > 0
                          ? 'Uang muka (DP)'
                          : 'Dibayar',
                      paidFormatted: formatRupiah(uangMukaDP),
                      remainingFormatted: formatRupiah(sisaTagihan),
                      hasRemainingDebt: sisaTagihan > 0,
                      extras: lensExtra,
                      itemsTitle: 'Rincian item pesanan',
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: confirming ? null : () => Navigator.pop(ctx),
                  child: const Text("Edit Data Kembali",
                      style: TextStyle(color: OptikAdminTokens.slate)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikAdminTokens.navy,
                    foregroundColor: OptikAdminTokens.snow,
                  ),
                  onPressed: confirming
                      ? null
                      : () async {
                          setLocal(() => confirming = true);
                          // Hold stok + mulai countdown 15 menit saat konfirmasi.
                          final held = await _ensurePosStockHold();
                          if (!held || !ctx.mounted) {
                            setLocal(() => confirming = false);
                            return;
                          }
                          Navigator.pop(ctx);
                          await _prosesCheckout();
                        },
                  icon: confirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: OptikAdminTokens.snow,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(
                    confirming ? "MENAHAN STOK…" : "KONFIRMASI PEMBELIAN",
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
            );
          },
        );
      },
    );
  }

  Widget _posPreviewLensTable({
    required String odSph,
    required String odCyl,
    required String odAdd,
    required String osSph,
    required String osCyl,
    required String osAdd,
    required String liveAxisR,
    required String liveAxisL,
    required String livePdR,
    required String livePdL,
    required double fBody,
  }) {
    Widget cell(String txt, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            txt,
            style: TextStyle(
              fontSize: header ? 8 : 9,
              fontWeight: header ? FontWeight.bold : FontWeight.w500,
              color: OptikAdminTokens.navy,
            ),
            textAlign: TextAlign.center,
          ),
        );
    String ax(String v) => v.endsWith('°') ? v : '$v°';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: OptikAdminTokens.lineStrong),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            border: TableBorder.all(color: OptikAdminTokens.line),
            columnWidths: const {
              0: FlexColumnWidth(1.8),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: OptikAdminTokens.bgMid),
                children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                    .map((t) => cell(t, header: true))
                    .toList(),
              ),
              TableRow(
                children: [
                  'OD (Kanan)',
                  odSph,
                  odCyl,
                  ax(liveAxisR),
                  odAdd,
                ].map(cell).toList(),
              ),
              TableRow(
                children: [
                  'OS (Kiri)',
                  osSph,
                  osCyl,
                  ax(liveAxisL),
                  osAdd,
                ].map(cell).toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            'PD Pasien (R/L): $livePdR / $livePdL mm',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: (fBody - 3).clamp(8.0, 14.0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _prosesCheckout() async {
    if (cartItems.isEmpty) {
      _showSnack("pos_err_keranjang_kosong".tr(), OptikAdminTokens.danger);
      return;
    }
    if (nameCtrl.text.isEmpty) {
      _showSnack("pos_err_nama_pelanggan".tr(), OptikAdminTokens.danger);
      return;
    }
    // Kasir penanggung jawab harus masih bertugas (belom pulang / bukan libur).
    final cashierId = activeCashier?['id']?.toString();
    final cashierNik = activeCashier?['nik']?.toString();
    if (cashierId != null &&
        cashierId.isNotEmpty &&
        (cashierNik ?? '').toUpperCase() != 'TRAINING01') {
      final dutyBlock = await PosDutyGate.blockReason(
        karyawanId: cashierId,
        nik: cashierNik,
      );
      if (dutyBlock != null) {
        _showSnack(dutyBlock.tr(), OptikAdminTokens.danger);
        return;
      }
    }
    try {
      setState(() => isProcessing = true);

      // Pastikan hold aktif (biasanya sudah dari tombol KONFIRMASI).
      if (_posHoldItemsFromCart().isNotEmpty && !_posHoldActive) {
        final held = await _ensurePosStockHold();
        if (!held) {
          if (mounted) setState(() => isProcessing = false);
          return;
        }
      }

      final tokoId = widget.profile['toko_id'] ?? 'PUSAT';
      int total = _totalAkhir;
      final voucherCode = (_appliedVoucherCode ?? '').trim();
      final voucherDiscount = voucherCode.isEmpty
          ? 0
          : (_appliedVoucherNominal > 0
              ? _appliedVoucherNominal
              : _parseDiskonRpText(discountCtrl.text));

      // 🎯 SINKRONISASI FINANSIAL: Mengunci nilai nominal bayar sesuai status pilihan aktif di POS (Lunas/DP)
      int bayar = paymentStatus == "Lunas"
          ? total
          : (int.tryParse(paidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
              0);

      if (paymentStatus == 'DP') {
        if (bayar <= 0) {
          if (mounted) {
            setState(() => isProcessing = false);
            _showSnack(
              'Uang muka DP harus lebih dari Rp 0',
              OptikAdminTokens.danger,
            );
          }
          return;
        }
        if (bayar >= total) {
          if (mounted) {
            setState(() => isProcessing = false);
            _showSnack(
              'Uang muka DP harus kurang dari total. '
              'Pilih Lunas jika bayar penuh.',
              OptikAdminTokens.warning,
            );
          }
          return;
        }
      }

      if (_appliedVoucherPointsCost > 0 &&
          phoneCtrl.text.trim().isEmpty) {
        if (mounted) {
          setState(() => isProcessing = false);
          _showSnack(
            'Voucher butuh $_appliedVoucherPointsCost poin — isi No. WA member',
            OptikAdminTokens.warning,
          );
        }
        return;
      }

      int sisa = total - bayar;
      if (sisa < 0) sisa = 0;

      final isDpCheckout = paymentStatus == "DP" || sisa > 0;
      final statusNorm = isDpCheckout ? 'DP' : 'LUNAS';

      // Per-line: RO/custom = PENDING_RO; stok = READY (boleh ambil partial).
      final cartNeedsFulfillment = cartItems.any((i) =>
          i['is_lensa_custom'] == true || i['needs_fulfillment'] == true);
      final hasReadyStock = cartItems.any((i) =>
          i['is_lensa_custom'] != true && i['needs_fulfillment'] != true);
      final pendingForInvoice = await supabase
          .from('pending_requests')
          .select('id')
          .eq('no_invoice', noInvoice)
          .limit(1);
      final needsFulfillment = cartNeedsFulfillment ||
          pendingLensRequests.isNotEmpty ||
          (pendingForInvoice as List).isNotEmpty;

      // DP: PENDING_PO. LUNAS + ada READY → SIAP_DIAMBIL (partial OK walau ada RO).
      // LUNAS + hanya RO → PENDING_PO.
      final canPickupPartial = !isDpCheckout && hasReadyStock;
      final trackingStatus = isDpCheckout
          ? 'PENDING_PO'
          : (canPickupPartial
              ? 'SIAP_DIAMBIL'
              : (needsFulfillment ? 'PENDING_PO' : 'SIAP_DIAMBIL'));
      final qrLunasToken =
          canPickupPartial ? InvoiceLifecycleService.newToken() : null;
      // Tanpa QR hanya jika DP, atau LUNAS tanpa satu pun item READY.
      final paymentConfirmOnly = isDpCheckout || !canPickupPartial;

      String? posMidtransOrderId;
      if (PosMidtrans.usesGateway(paymentMethod)) {
        final charge = isDpCheckout ? bayar : total;
        if (charge <= 0) {
          if (mounted) {
            setState(() => isProcessing = false);
            _showSnack(
              'Nominal Midtrans tidak valid',
              OptikAdminTokens.warning,
            );
          }
          return;
        }
        final paid = await PosMidtrans.chargeAndWait(
          context: context,
          amountIdr: charge,
          purpose: 'sale',
          tokoId: tokoId.toString(),
          invoiceNo: noInvoice,
          customerName: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
        );
        if (!mounted) return;
        if (!paid.ok || !paid.settled) {
          setState(() => isProcessing = false);
          _showSnack(
            paid.error ?? 'Pembayaran Midtrans dibatalkan',
            OptikAdminTokens.warning,
          );
          return;
        }
        posMidtransOrderId = paid.midtransOrderId;
        if ((paid.paymentType ?? '').trim().isNotEmpty) {
          paymentMethod = PosMidtrans.labelForType(paid.paymentType!);
        }
      }

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
            'status_pembayaran': statusNorm,
            'metode_pembayaran': paymentMethod,
            'tracking_status': trackingStatus,
            if (voucherCode.isNotEmpty) 'voucher_code': voucherCode,
            if (voucherCode.isNotEmpty) 'voucher_discount': voucherDiscount,
            if (!isDpCheckout)
              'lunas_at': DateTime.now().toUtc().toIso8601String(),
            if (qrLunasToken != null) 'qr_lunas_token': qrLunasToken,
          })
          .select()
          .single();

      final saleId = saleRes['id'];
      if (posMidtransOrderId != null && posMidtransOrderId.isNotEmpty) {
        unawaited(PosMidtrans.linkSale(posMidtransOrderId, saleId.toString()));
      }
      // Snapshot sebelum proses lanjut — daftar tidak boleh berubah di tengah checkout.
      final terlibatIds = _terlibatIdsForCheckout();
      if (terlibatIds.isEmpty) {
        debugPrint('POS checkout tanpa karyawan terlibat — fallback kasir profil');
      }

      // Karyawan terlibat (tanpa peran) — cascade delete jika sale di-rollback.
      try {
        await _persistKaryawanTerlibat(saleId.toString(), terlibatIds);
      } catch (e) {
        debugPrint('Simpan karyawan terlibat gagal (retry 1x): $e');
        try {
          await Future.delayed(const Duration(milliseconds: 250));
          await _persistKaryawanTerlibat(saleId.toString(), terlibatIds);
        } catch (e2) {
          debugPrint('Simpan karyawan terlibat gagal permanen: $e2');
          // Jangan biarkan nota tanpa jejak terlibat bila ada ID.
          if (terlibatIds.isNotEmpty) {
            try {
              await supabase.from('sales').delete().eq('id', saleId);
            } catch (_) {}
            if (mounted) {
              setState(() => isProcessing = false);
              _showSnack(
                '${'pos_terlibat_save_err'.tr()}$e2',
                OptikAdminTokens.danger,
              );
            }
            return;
          }
        }
      }

      // Redeem voucher dulu (sebelum potong stok). Gagal → batalkan nota.
      if (voucherCode.isNotEmpty) {
        final redeem = await MemberRepository().redeemPromo(
          code: voucherCode,
          saleId: saleId.toString(),
          phone: phoneCtrl.text.trim(),
          discountApplied: voucherDiscount,
          channel: 'pos',
        );
        if (redeem['ok'] != true) {
          debugPrint('Redeem voucher gagal — rollback sale: $redeem');
          var rolledBack = false;
          try {
            // BEFORE DELETE trigger void POS/SETTLE; client backup jika trigger absen.
            final inv = saleRes['no_invoice']?.toString();
            if (inv != null && inv.isNotEmpty) {
              try {
                await GlPostingService().voidSaleJournals(
                  noInvoice: inv,
                  createdBy: widget.profile['nama']?.toString(),
                );
              } catch (_) {}
            }
            await supabase.from('sales').delete().eq('id', saleId);
            rolledBack = true;
          } catch (e) {
            debugPrint('Rollback delete sale gagal: $e');
            // Cadangan: netralisasi nota supaya diskon voucher tidak lolos.
            try {
              await supabase.from('sales').update({
                'voucher_code': null,
                'voucher_discount': 0,
                'total_harga': _subtotalBelanja,
                'dibayarkan': 0,
                'sisa_tagihan': _subtotalBelanja,
                'status_pembayaran': 'BATAL',
                'tracking_status': 'BATAL_VOUCHER',
              }).eq('id', saleId);
              rolledBack = true;
            } catch (e2) {
              debugPrint('Rollback netralisasi sale gagal: $e2');
            }
          }
          if (mounted) {
            setState(() => isProcessing = false);
            _showSnack(
              rolledBack
                  ? 'Checkout dibatalkan — voucher gagal di-redeem: '
                      '${redeem['error'] ?? 'unknown'}'
                  : 'KRITIS: voucher gagal redeem & nota gagal dibatalkan. '
                      'Cek manual sale $saleId / ${redeem['error']}',
              OptikAdminTokens.danger,
            );
          }
          return;
        }
      }

      // Consume POS_HOLD → SALE atomik (tanpa melepaskan hold dulu).
      final holdRef = _posHoldRefId;
      final readyHoldItems = await _posHoldItemsWithBonus();
      if (readyHoldItems.isNotEmpty) {
        if (holdRef == null || holdRef.isEmpty) {
          throw 'Hold stok POS hilang — batalkan & buka konfirmasi ulang.';
        }
        final consumed = await StockMutationService().consumePosCartIntoSale(
          tokoId: tokoId.toString(),
          refId: holdRef,
          items: readyHoldItems,
          invoiceNo: noInvoice.toString(),
          actorNama:
              (widget.profile['nama'] ?? widget.profile['email'] ?? '')
                  .toString(),
        );
        if (consumed['ok'] != true) {
          throw consumed['error'] ?? 'Gagal potong stok dari hold POS';
        }
        _posHoldRefId = null;
        _posHoldExpiresAt = null;
        _posHoldRemaining.value = Duration.zero;
        _stopPosHoldTick();
      } else if (holdRef != null) {
        await _releasePosHold(clearState: true);
      }

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

        final lineNeedsRo = item['is_lensa_custom'] == true ||
            item['needs_fulfillment'] == true;
        final insertedItem = await supabase.from('sales_items').insert({
          'sale_id': saleId,
          'product_id': item['id'],
          'tipe_produk': item['kategori'] ?? 'Lainnya',
          'nama_produk': item['nama_produk'],
          'harga_satuan': item['harga'],
          'qty': item['qty'],
          'subtotal': item['subtotal'],
          'detail_resep': item['is_lensa_custom'] == true
              ? 'Resep Kustom Terlampir'
              : resepKomplitFisik,
          'needs_fulfillment': lineNeedsRo,
          'fulfillment_status': lineNeedsRo ? 'PENDING_RO' : 'READY',
        }).select('id').single();

        // Hubungkan RO pending_requests → sale_item (partial fulfillment).
        if (lineNeedsRo) {
          try {
            final skuNorm = (item['sku'] ?? '').toString();
            final namaNorm =
                (item['nama_produk'] ?? item['nama'] ?? '').toString();
            var prQ = supabase
                .from('pending_requests')
                .select('id')
                .eq('no_invoice', noInvoice)
                .isFilter('sale_item_id', null);
            if (skuNorm.isNotEmpty && skuNorm != 'No SKU') {
              prQ = prQ.eq('sku', skuNorm);
            } else if (namaNorm.isNotEmpty) {
              prQ = prQ.eq('nama_produk', namaNorm);
            }
            final prRows = await prQ.limit(1);
            if ((prRows as List).isNotEmpty) {
              final prId = prRows.first['id'];
              await supabase.from('pending_requests').update({
                'sale_id': saleId,
                'sale_item_id': insertedItem['id'],
              }).eq('id', prId);
              await supabase.from('sales_items').update({
                'pending_request_id': prId,
              }).eq('id', insertedItem['id']);
            }
          } catch (e) {
            debugPrint('Link pending_requests → sale_item gagal: $e');
          }
        }

        // Stok ready (+ bonus Kotak/Lap) sudah dipotong atomik via
        // consume_pos_cart_into_sale di atas — jangan SALE ulang.
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
      // Harus APPROVED + referensi_id agar tidak masuk COA quarantine manual.
      final namaPasienForm = nameCtrl.text.trim();
      final namaKasirPost =
          (activeCashier?['nama'] ?? widget.profile['nama'] ?? '').toString();
      if (bayar > 0) {
        try {
          await supabase.from('finance_transactions').insert({
            'toko_id': tokoId,
            'tanggal_transaksi':
                DateTime.now().toIso8601String().split('T')[0],
            'jenis_transaksi': 'PEMASUKAN',
            'kategori': 'Penjualan Kasir',
            'deskripsi': 'Penjualan Kasir POS: $noInvoice ($namaPasienForm)',
            'nominal': bayar,
            'status_pembayaran': statusNorm,
            'metode_pembayaran': paymentMethod,
            'nama_kasir': namaKasirPost.isEmpty ? null : namaKasirPost,
            'status_konfirmasi': 'APPROVED',
            'referensi_id': noInvoice,
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint("Buku besar gagal mencatat pemasukan: $e");
          if (mounted) {
            _showSnack(
              'Nota OK, tapi Buku Besar gagal dicatat: $e. '
              'Cek ulang di Keuangan / COA.',
              OptikAdminTokens.danger,
            );
          }
        }
      }

      // 3b. Posting jurnal GL berimbang (enterprise)
      if (total > 0) {
        try {
          await GlPostingService().postPosSale(
            tokoId: tokoId.toString(),
            noInvoice: noInvoice.toString(),
            totalHarga: total,
            bayar: bayar,
            sisaTagihan: sisa,
            metode: paymentMethod,
            createdBy: namaKasirPost.isEmpty ? null : namaKasirPost,
            namaPelanggan: namaPasienForm,
          );
        } catch (e) {
          debugPrint('GL posting POS gagal: $e');
        }
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

      // 4. Kirim nota (+ QR hanya bila stok ready / bukan DP·pending)
      try {
        final terlibatNames = karyawanTerlibat
            .map((k) => (k['nama'] ?? '').toString().trim())
            .where((n) => n.isNotEmpty)
            .toList();
        final saleForPdf = Map<String, dynamic>.from(saleRes);
        if (terlibatNames.isNotEmpty) {
          saleForPdf['nama_kasir'] = terlibatNames.join(', ');
        }
        await _generateAndSharePDF(
          saleForPdf,
          cartItems,
          paymentConfirmOnly: paymentConfirmOnly,
        );
      } catch (emailErr) {
        debugPrint("Sistem background kirim nota tertunda: $emailErr");
      }

      if (!mounted) return;

      // Poin +5 per karyawan unik yang terlibat (uncapped KPI transaksi).
      final saleIdStr = saleId.toString();
      await _awardPoinInvoiceTerlibat(saleIdStr, terlibatIds);

      // 5. Lempar ke Halaman Struk Nota Akhir (nota sudah aman di DB).
      try {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => InvoiceDetailPage(saleId: saleIdStr),
          ),
        );
      } catch (navErr) {
        debugPrint('Navigasi nota gagal setelah checkout: $navErr');
        if (mounted) {
          _showSnack(
            'pos_terlibat_nota_ok_nav_fail'.tr(),
            OptikAdminTokens.warning,
          );
        }
      }
      await _clearPosDraft();
      _resetForm();
      await _lockPosSession();
    } catch (e) {
      debugPrint("Checkout Engine Error: $e");
      // Jika nota sempat tersimpan tapi stok/consume gagal — batalkan nota.
      final inv = noInvoice.trim();
      if (inv.isNotEmpty) {
        try {
          final orphan = await supabase
              .from('sales')
              .select('id')
              .eq('no_invoice', inv)
              .maybeSingle();
          final orphanId = orphan?['id']?.toString();
          if (orphanId != null && orphanId.isNotEmpty) {
            await _rollbackPoinInvoiceTerlibat(orphanId);
          }
          await supabase.from('sales').delete().eq('no_invoice', inv);
        } catch (delErr) {
          debugPrint('Rollback sale setelah gagal checkout: $delErr');
        }
      }
      _showSnack("${"pos_err_simpan_transaksi".tr()}$e", OptikAdminTokens.danger);
      // Best-effort: hold ulang keranjang siap bayar.
      if (cartItems.isNotEmpty) {
        unawaited(_ensurePosStockHold());
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

// MESIN PDF 1: OTOMATIS SAAT KASIR CHECKOUT (JIPLAK MURNI 100% DARI MODAL PRATINJAU)
  Future<void> _generateAndSharePDF(
    Map<String, dynamic> sale,
    List<dynamic> items, {
    bool paymentConfirmOnly = false,
  }) async {
    try {
      // Jangan terbitkan QR di DP / lunas pending — hanya setelah admin ready.
      if (!paymentConfirmOnly) {
        try {
          final sid = sale['id']?.toString();
          if (sid != null && sid.isNotEmpty) {
            sale = await InvoiceLifecycleService().ensureTokens(sid);
          }
        } catch (e) {
          debugPrint('ensureTokens QR invoice: $e');
        }
      }

      final pdf = pw.Document();

      final bool hasLensa = items.any((item) =>
          item['nama_produk'].toString().toLowerCase().contains('lensa') ||
          item['nama_produk'].toString().toLowerCase().contains('progresif'));

      int totalHarga = sale['total_harga'] ?? 0;
      int uangMukaDP = sale['dibayarkan'] ?? 0;
      int sisaTagihan = sale['sisa_tagihan'] ?? 0;

      final cabangNota = sale['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      final invSettings =
          await InvoiceSettingsService().fetchForToko(cabangNota);
      final config = invSettings.toLegacyConfigMap();

      pw.ImageProvider? logoImage;
      if (invSettings.hasLogo) {
        try {
          logoImage = await networkImage(invSettings.logoUrl);
        } catch (_) {}
      }

      final statusFooter = InvoiceStatusFooter.forSale(
        Map<String, dynamic>.from(sale),
        footers: invSettings.statusFooters,
        forPdf: true,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            final pdfLines = <InvoiceDocLine>[];
            for (final item in items) {
              var rawName = item['nama_produk'] ?? '-';
              if (rawName.toString().toUpperCase().contains('LENSA') ||
                  rawName.toString().toUpperCase().contains('PROGRESIF')) {
                rawName = rawName
                    .toString()
                    .replaceAll(
                        RegExp(
                            r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                        '')
                    .trim();
              }
              pdfLines.add(InvoiceDocLine(
                label: '$rawName  ×${item['qty'] ?? 1}',
                amount: formatRupiah((item['subtotal'] ?? 0) as int),
                group: InvoiceLayout.groupOfProduct(
                  tipe: item['tipe_produk']?.toString() ??
                      item['kategori']?.toString(),
                  nama: item['nama_produk']?.toString(),
                ),
              ));
            }

            pw.Widget? lensPdf;
            if (hasLensa) {
              pw.Widget pCell(String txt, {bool header = false}) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Text(
                      txt,
                      style: pw.TextStyle(
                        fontSize: header ? 8 : 9,
                        fontWeight: header
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                        color: header
                            ? const PdfColor.fromInt(0xFF6D8196)
                            : const PdfColor.fromInt(0xFF000080),
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  );
              String ax(String v) => v.endsWith('°') ? v : '$v°';
              lensPdf = pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                          color: const PdfColor.fromInt(0x4D6D8196)),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Table(
                      border: pw.TableBorder.all(
                          color: const PdfColor.fromInt(0x336D8196)),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.8),
                        1: pw.FlexColumnWidth(2),
                        2: pw.FlexColumnWidth(2),
                        3: pw.FlexColumnWidth(2),
                        4: pw.FlexColumnWidth(2),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                              color: PdfColor.fromInt(0xFFF7FBFC)),
                          children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                              .map((t) => pCell(t, header: true))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OD (Kanan)',
                            sphRCtrl.text,
                            cylRCtrl.text,
                            ax(axisRCtrl.text),
                            addRCtrl.text,
                          ].map(pCell).toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OS (Kiri)',
                            sphLCtrl.text,
                            cylLCtrl.text,
                            ax(axisLCtrl.text),
                            addLCtrl.text,
                          ].map(pCell).toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'PD Pasien (R/L): ${pdRCtrl.text.isEmpty ? '0' : pdRCtrl.text} / ${pdLCtrl.text.isEmpty ? '0' : pdLCtrl.text} mm',
                    style: pw.TextStyle(
                      color: const PdfColor.fromInt(0xFF000080),
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              );
            }

            pw.Widget? qrPdf;
            if (config['show_qr_invoice'] == true &&
                !paymentConfirmOnly &&
                InvoiceLink.isCustomerLifecycleQr(
                    InvoiceLink.encodeFromSale(
                        Map<String, dynamic>.from(sale)))) {
              qrPdf = pw.Container(
                height: 44,
                width: 44,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: InvoiceLink.encodeFromSale(
                      Map<String, dynamic>.from(sale)),
                  padding: pw.EdgeInsets.zero,
                ),
              );
            }

            final today =
                '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';

            return InvoiceLayout.documentBodyPdf(
              settings: invSettings,
              footerText: statusFooter,
              logoImage: logoImage,
              meta: InvoiceDocMeta(
                noInvoice: sale['no_invoice']?.toString() ?? '-',
                customerName: (sale['nama_pelanggan'] ?? '-').toString(),
                whatsapp: sale['no_wa']?.toString(),
                address: sale['alamat']?.toString(),
                email: sale['email_pelanggan']?.toString(),
                cashier: sale['nama_kasir']?.toString() ?? 'Staff',
                dateLabel: 'Masuk: $today',
                createdAtLabel: InvoiceLayout.formatInvoiceCreatedAt(
                  sale['created_at'],
                ),
                status: sisaTagihan > 0 ? 'DP' : 'LUNAS',
                boardStatus: InvoiceStatusFooter.statusOf(
                  Map<String, dynamic>.from(sale),
                ),
              ),
              lines: pdfLines,
              totalFormatted: formatRupiah(totalHarga),
              paidLabel: sisaTagihan > 0 ? 'Uang muka (DP)' : 'Dibayar',
              paidFormatted: formatRupiah(uangMukaDP),
              remainingFormatted: formatRupiah(sisaTagihan),
              hasRemainingDebt: sisaTagihan > 0,
              extras: lensPdf,
              qrChild: qrPdf,
              itemsTitle: 'RINCIAN ITEM PESANAN',
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      final pdfBase64 = base64Encode(pdfBytes);

      final delivered = await InvoiceDeliveryService().deliver(
        sale: Map<String, dynamic>.from(sale),
        pdfBase64: pdfBase64,
        mode: paymentConfirmOnly
            ? InvoiceDeliveryMode.paymentConfirm
            : InvoiceDeliveryMode.withQr,
      );
      debugPrint(
        'Kirim nota ${sale['no_invoice']}: ${delivered.summary} '
        'confirmOnly=$paymentConfirmOnly',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              delivered.summary,
              style: const TextStyle(
                color: OptikAdminTokens.snow,
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: delivered.anyOk || delivered.allRequestedOk
                ? OptikAdminTokens.success
                : OptikAdminTokens.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint("Gagal orkestrasi pencetakan PDF: $e");
    }
  }

  void _resetForm() {
    unawaited(_releasePosHold(clearState: true));
    setState(() {
      cartItems.clear();
      nameCtrl.clear();
      phoneCtrl.clear();
      addressCtrl.clear();
      emailCtrl.clear();
      _clearAppliedVoucher();
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
        tryHandleKnown: (result) async {
          if (result.type == QrPayloadType.product) {
            await _cariProdukBySKU(result.raw);
            return true;
          }
          if (result.type == QrPayloadType.customer) {
            _applyObrCustomer(result);
            return true;
          }
          return false;
        },
        // Unknown bisa NIK karyawan ATAU SKU biasa — satu jalur dengan kolom scan.
        onUnknown: (raw) async {
          await _onPosScanSubmitted(raw);
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
    return PremiumScaffold(
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
                        color: OptikAdminTokens.navy.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront_rounded,
                          color: OptikAdminTokens.warning, size: 80),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      "TOKO SAAT INI TUTUP",
                      style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Sistem siap untuk dioperasikan",
                      style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 14,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: 280,
                      height: 60,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: OptikAdminTokens.navy,
                          foregroundColor: OptikAdminTokens.snow,
                          elevation: 4,
                          shadowColor: OptikAdminTokens.navy.withOpacity(0.25),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                OptikAdminTokens.radiusLg),
                          ),
                        ),
                        icon: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: OptikAdminTokens.snow,
                                    strokeWidth: 2))
                            : const Icon(Icons.lock_open_rounded),
                        label: Text(
                          isLoading
                              ? "MENGINISIALISASI..."
                              : "MULAI SESI KASIR",
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
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
                          TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
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

    // HID wedge / keyboard barcode must hit HidScanIntake — camera-only unlock
    // left Chrome/desktop unable to type NIK.
    return HidScanIntake(
      onUnknown: (raw) async {
        await _onUnlockKaryawanBarcode(raw);
        return true;
      },
      child: PremiumScaffold(
        appBar: PremiumAppBar(
          title: "pos_otorisasi_kasir".tr(),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: "Kembali ke Dashboard",
            onPressed: () async {
              await kameraLoginCtrl.stop();
              await _requestLeavePos();
            },
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: PremiumPanel(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                borderRadius: 24,
                borderColor: OptikAdminTokens.ice.withOpacity(0.4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PremiumIconBadge(
                      icon: Icons.qr_code_scanner_rounded,
                      color: OptikAdminTokens.navy,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "pos_otorisasi_kasir".tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "pos_msg_scan_kasir_multi".tr(),
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 280,
                      height: 280,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: MobileScanner(
                          fit: BoxFit.cover,
                          controller: kameraLoginCtrl,
                          onDetect: (capture) async {
                            if (!isScanningLocal || isPosUnlocked) return;
                            final barcodes = capture.barcodes;
                            if (barcodes.isEmpty ||
                                barcodes.first.rawValue == null) {
                              return;
                            }
                            await _onUnlockKaryawanBarcode(
                                barcodes.first.rawValue!);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _unlockNikManualCtrl,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'NIK karyawan (ketik / HID)',
                        hintText: 'Scan wedge atau ketik lalu Enter',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Unlock',
                          icon: const Icon(Icons.login_rounded),
                          onPressed: () {
                            final nik = _unlockNikManualCtrl.text.trim();
                            if (nik.isNotEmpty) {
                              _onUnlockKaryawanBarcode(nik);
                            }
                          },
                        ),
                      ),
                      onSubmitted: (v) {
                        final nik = v.trim();
                        if (nik.isNotEmpty) _onUnlockKaryawanBarcode(nik);
                      },
                    ),
                    if (TrainingMode.instance.isActive) ...[
                      const SizedBox(height: 16),
                      PremiumPrimaryButton(
                        label: 'training_pos_unlock_cashier'.tr(),
                        icon: Icons.school_rounded,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            OptikAdminTokens.trainingSoft,
                            OptikAdminTokens.training,
                          ],
                        ),
                        onPressed: () =>
                            _onUnlockKaryawanBarcode('TRAINING01'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tambahKeRestockQueue(Map<String, dynamic> item) {
    // Popup HANYA saat produk dipilih & stok habis — tanya pelanggan dulu.
    unawaited(_confirmRoWhenOutOfStock(Map<String, dynamic>.from(item)));
  }

  /// Stok habis saat pilih produk → tanya pelanggan: lanjut RO atau tidak.
  Future<void> _confirmRoWhenOutOfStock(Map<String, dynamic> item) async {
    final nama = (item['nama_produk'] ?? item['nama'] ?? 'Produk').toString();
    final sku = (item['sku'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: const Text(
          'Stok habis',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '“$nama”${sku.isEmpty || sku == 'No SKU' ? '' : ' ($sku)'} '
          'stok tersedia 0.\n\n'
          'Tanyakan ke pelanggan:\n'
          '• Lanjutkan Request Order (RO) ke Pusat, atau\n'
          '• Pilih produk lain?',
          style: const TextStyle(
            color: OptikAdminTokens.slate,
            height: 1.4,
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Tidak — produk lain',
              style: TextStyle(color: OptikAdminTokens.slate),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjutkan ke RO'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() {
      if (!restockQueue.any((element) => element['id'] == item['id'])) {
        restockQueue.add(item);
      }
    });
    _showPendingRequestDialog(item, 0);
  }

  // ==========================================================================
  // UI TERMINAL UTAMA KASIR POS
  // ==========================================================================
  void _openAbsensiFromPos() {
    if (TrainingMode.instance.isActive) {
      _showSnack('training_pos_absensi_blocked'.tr(), OptikAdminTokens.training);
      return;
    }
    // Push (bukan replace) agar keranjang/transaksi POS tetap utuh saat kembali.
    // Face match di perangkat Admin toko — bukan AbsensiPage HP karyawan.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AbsensiTokoPage(profile: widget.profile),
      ),
    );
  }

  Widget _buildSalesMainUI() {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "pos_title".tr(),
        subtitle: namaKasir.isNotEmpty
            ? namaKasir.split(' ').first.toUpperCase()
            : null,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: OptikAdminTokens.navy),
          tooltip: 'leave_title_pos'.tr(),
          onPressed: _requestLeavePos,
        ),
        actions: [
          if (R.isNarrow(context)) ...[
            IconButton(
              icon: const Icon(Icons.face_retouching_natural_rounded,
                  color: OptikAdminTokens.navy),
              tooltip: "pos_ttip_absen".tr(),
              onPressed: _openAbsensiFromPos,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: OptikAdminTokens.slate),
              tooltip: 'Menu POS',
              onPressed: () async {
                final sel = await showAdminPicker<String>(
                  context: context,
                  title: 'Menu POS',
                  searchable: false,
                  headerIcon: Icons.more_horiz_rounded,
                  options: [
                    AdminPickerOption(
                      value: 'close',
                      label: "pos_trip_close".tr(),
                      icon: Icons.power_settings_new_rounded,
                    ),
                    const AdminPickerOption(
                      value: 'lock',
                      label: 'Lock & Switch Cashier',
                      icon: Icons.lock_outline_rounded,
                    ),
                    const AdminPickerOption(
                      value: 'clear',
                      label: 'Kosongkan Keranjang',
                      icon: Icons.delete_sweep,
                    ),
                  ],
                );
                if (sel == null || sel.isClear) return;
                switch (sel.value) {
                  case 'close':
                    _prosesCloseStore();
                    break;
                  case 'lock':
                    _resetForm();
                    await _lockPosSession();
                    _showSnack("Sesi dikunci. Silakan scan ID Karyawan baru.",
                        OptikAdminTokens.warning);
                    break;
                  case 'clear':
                    _resetForm();
                    _showSnack(
                        "Keranjang transaksi berhasil dikosongkan", OptikAdminTokens.danger);
                    break;
                }
              },
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
                        color: OptikAdminTokens.navy, size: 20),
                    label: Text(
                      "pos_btn_absen".tr(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: OptikAdminTokens.navy),
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
                      color: OptikAdminTokens.danger),
                  tooltip: "pos_trip_close".tr(),
                  onPressed: () => _prosesCloseStore(),
                ),
                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.lock_outline_rounded,
                      color: OptikAdminTokens.warning),
                  tooltip: "Lock & Switch Cashier",
                  onPressed: () async {
                    _resetForm();
                    await _lockPosSession();
                    _showSnack("Sesi dikunci. Silakan scan ID Karyawan baru.",
                        OptikAdminTokens.warning);
                  },
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 14,
                  backgroundImage: activeCashier?['face_url'] != null
                      ? NetworkImage(activeCashier!['face_url'])
                      : null,
                  child: activeCashier?['face_url'] == null
                      ? const Icon(Icons.person,
                          size: 16, color: OptikAdminTokens.navy)
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
                      color: OptikAdminTokens.success),
                ),

                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: OptikAdminTokens.danger),
                  tooltip: "pos_ttip_batal".tr(),
                  onPressed: () {
                    _resetForm();
                    _showSnack(
                        "Keranjang transaksi berhasil dikosongkan", OptikAdminTokens.danger);
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
    return ColoredBox(
      color: OptikAdminTokens.bgMid,
      child: SafeArea(
        child: Column(
          children: [
            // Header Widget: Invoice & Live Clock
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: OptikAdminTokens.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: OptikAdminTokens.ice.withOpacity(0.75),
                    width: 1.15,
                  ),
                  boxShadow: OptikAdminTokens.cardShadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: OptikAdminTokens.success.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color:
                                    OptikAdminTokens.success.withOpacity(0.45),
                              ),
                            ),
                            child: Text(
                              "pos_status_aktif".tr(),
                              style: const TextStyle(
                                color: OptikAdminTokens.success,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            noInvoice.isNotEmpty
                                ? noInvoice
                                : "pos_memuat".tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.bgMid,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: OptikAdminTokens.lineStrong),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              color: OptikAdminTokens.navy, size: 16),
                          SizedBox(width: 8),
                          LiveClock(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _buildKaryawanTerlibatBar(),

            // Area Scrollable Utama
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                child: Column(
                  children: [
                    // --- BAGIAN 1: DATA PELANGGAN ---
                    _posPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildCardTitle(
                                    "pos_data_pelanggan".tr(),
                                    Icons.person_pin_rounded),
                              ),
                              TextButton.icon(
                                onPressed: _showCustomerQrDialog,
                                style: TextButton.styleFrom(
                                  foregroundColor: OptikAdminTokens.navy,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                ),
                                icon: const Icon(Icons.qr_code_2_rounded,
                                    size: 18),
                                label: const Text(
                                  'QR pelanggan',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            controller: nameCtrl,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: "pos_nama_pasien".tr(),
                              prefixIcon: const Icon(Icons.badge_rounded,
                                  size: 20),
                            ),
                          ),
                          const SizedBox(height: 14),
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
                                  style: const TextStyle(
                                    color: OptikAdminTokens.navy,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: "pos_wa".tr(),
                                    prefixIcon: const Icon(
                                        Icons.phone_rounded,
                                        size: 20),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                fit: FlexFit.loose,
                                child: TextField(
                                  controller: addressCtrl,
                                  maxLines: 2,
                                  textCapitalization:
                                      TextCapitalization.words,
                                  style: const TextStyle(
                                    color: OptikAdminTokens.navy,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: "pos_alamat".tr(),
                                    prefixIcon: const Icon(
                                        Icons.location_on_rounded,
                                        size: 20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: "pos_email".tr(),
                              prefixIcon: const Icon(Icons.email_rounded,
                                  size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // --- BAGIAN 2: INPUT TRANSAKSI BARANG ---
                    _posPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCardTitle(
                              "pos_input_barang".tr(), Icons.inventory_2_rounded),

                          // 1. KOLOM SCANNER GLOBAL (HID → field jika fokusokus; else HardwareBarcodeListener)
                          TextField(
                            controller: skuScanCtrl,
                            style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: "pos_scan_global".tr(),
                              prefixIcon: const Icon(Icons.search_rounded,
                                  size: 20, color: OptikAdminTokens.navy),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner_rounded,
                                    color: OptikAdminTokens.navy),
                                onPressed: () async {
                                  final code = await _scanBarcode();
                                  if (code == null || code.isEmpty) return;
                                  await _onPosScanSubmitted(code);
                                },
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
                              child: _posCategoryToggle(
                                active: isFrameActive,
                                icon: Icons.filter_frames_rounded,
                                label: "pos_btn_frame".tr(),
                                onPressed: () => setState(
                                    () => isFrameActive = !isFrameActive),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              fit: FlexFit.loose,
                              child: _posCategoryToggle(
                                active: isLensaActive,
                                icon: Icons.visibility_rounded,
                                label: "pos_btn_lensa".tr(),
                                onPressed: () => setState(
                                    () => isLensaActive = !isLensaActive),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              fit: FlexFit.loose,
                              child: _posCategoryToggle(
                                active: isLainnyaActive,
                                icon: Icons.more_horiz_rounded,
                                label: "pos_btn_lainnya".tr(),
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
                              final fm = Map<String, dynamic>.from(
                                  selectedFrame! as Map);
                              final stock = StockQty.availableOf(fm);
                              final real = StockQty.realOf(fm);
                              final pending = StockQty.pendingOf(fm);
                              bool stokHabis = stock <= 0;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(selectedFrame!['nama'] ?? 'Frame',
                                    style:
                                        const TextStyle(color: OptikAdminTokens.navy)),
                                subtitle: Text(
                                  stokHabis
                                      ? "pos_stok_habis".tr()
                                      : "${"pos_stok_tersedia".tr()} $stock  ·  Real $real  ·  Pending $pending | Rp ${selectedFrame!['harga']}",
                                  style: TextStyle(
                                      color: stokHabis
                                          ? OptikAdminTokens.danger
                                          : OptikAdminTokens.success),
                                ),
                                trailing: SizedBox(
                                  width:
                                      145, // 👈 KUNCI UTAMA: Mengunci lebar tombol kasir agar tidak melar
                                  child: stokHabis
                                      ? FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                OptikAdminTokens.warning,
                                            foregroundColor:
                                                OptikAdminTokens.snow,
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
                                      : FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                OptikAdminTokens.success,
                                            foregroundColor:
                                                OptikAdminTokens.snow,
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
                                color: OptikAdminTokens.bgMid,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: OptikAdminTokens.ice.withOpacity(0.75),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("pos_cari_frame".tr(),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.navy,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 10),
                                  TextField(
                                    readOnly: true,
                                    onTap: () =>
                                        _munculkanDialogPilihFrame(context),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: "pos_hint_cari_frame".tr(),
                                      labelStyle: const TextStyle(
                                          color: OptikAdminTokens.slate, fontSize: 11),
                                      suffixIcon: const Icon(
                                          Icons.touch_app_rounded,
                                          color: OptikAdminTokens.navy,
                                          size: 20),
                                      filled: true,
                                      fillColor: OptikAdminTokens.card,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: OptikAdminTokens.lineStrong),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: OptikAdminTokens.lineStrong),
                                      ),
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
                          const Divider(color: OptikAdminTokens.line, height: 30),
                          Text("pos_id_lensa".tr(),
                              style: const TextStyle(
                                  color: OptikAdminTokens.navy,
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
                                      color: OptikAdminTokens.navy,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    labelText: "pos_merk_lensa".tr(),
                                    labelStyle: const TextStyle(
                                        fontSize: 11, color: OptikAdminTokens.slate),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 12),
                                    filled: true,
                                    fillColor: OptikAdminTokens.bgMid,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: OptikAdminTokens.lineStrong)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: OptikAdminTokens.lineStrong)),
                                    suffixIcon: const Icon(Icons.search_rounded,
                                        color: OptikAdminTokens.navy, size: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                fit: FlexFit.tight,
                                child: AdminPickerField(
                                  label: 'pos_jenis_lensa'.tr(),
                                  valueText: _lensJenisOptions.contains(lensJenis)
                                      ? lensJenis
                                      : 'Standar',
                                  icon: Icons.lens_outlined,
                                  onTap: _pickLensJenis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                fit: FlexFit.tight,
                                child: AdminPickerField(
                                  label: 'pos_bahan_lensa'.tr(),
                                  valueText: _lensBahanOptions.contains(lensBahan)
                                      ? lensBahan
                                      : 'Supersin',
                                  icon: Icons.layers_outlined,
                                  onTap: _pickLensBahan,
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
                                      color: OptikAdminTokens.bgMid,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.7))),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("pos_mata_kanan".tr(),
                                          style: const TextStyle(
                                              color: OptikAdminTokens.navy,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800)),
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
                                                          color: OptikAdminTokens.navy,
                                                          fontSize: 13),
                                                      decoration: InputDecoration(
                                                          labelText: "pos_axis_kanan"
                                                              .tr(),
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: OptikAdminTokens.slate),
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
                                            color: OptikAdminTokens.line, height: 1),
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
                                                          color: OptikAdminTokens.navy,
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
                                                          fillColor: OptikAdminTokens.ice.withOpacity(0.1),
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
                                      color: OptikAdminTokens.bgMid,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.7))),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("pos_mata_kiri".tr(),
                                          style: const TextStyle(
                                              color: OptikAdminTokens.navy,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800)),
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
                                                          color: OptikAdminTokens.navy,
                                                          fontSize: 13),
                                                      decoration: InputDecoration(
                                                          labelText:
                                                              "pos_axis_kiri"
                                                                  .tr(),
                                                          labelStyle:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: OptikAdminTokens.slate),
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
                                            color: OptikAdminTokens.line, height: 1),
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
                                                          color: OptikAdminTokens.navy,
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
                                                          fillColor: OptikAdminTokens.ice.withOpacity(0.1),
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
                          const Divider(color: OptikAdminTokens.line, height: 25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("pos_tanya_kacamata_lama".tr(),
                                  style: const TextStyle(
                                      color: OptikAdminTokens.slate, fontSize: 11)),
                              Switch(
                                  value: isInputKacamataLamaActive,
                                  activeColor: OptikAdminTokens.navy,
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
                                          OptikAdminTokens.ice.withOpacity(0.75)),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("pos_resep_lama".tr(),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.navy,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  AdminPickerField(
                                    label: 'pos_jenis_lensa_lama'.tr(),
                                    valueText: lensJenisLama,
                                    icon: Icons.lens_outlined,
                                    onTap: _pickLensJenisLama,
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
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: OptikAdminTokens.navy,
                                foregroundColor: OptikAdminTokens.snow,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: const Text(
                                "CHECK STOCK & ADD TO CART",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onPressed: () {
                                String inputMerk = lensBrandCtrl.text.trim();
                                if (inputMerk.isEmpty) {
                                  _showSnack(
                                      "pos_err_merk_lensa".tr(), OptikAdminTokens.danger);
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
                                      OptikAdminTokens.danger);
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
                                        OptikAdminTokens.success);
                                  } else {
                                    _showSnack(
                                        "🛑 Gagal! Stok lensa kembar kurang (Sisa: $stockR Pcs). Silakan klik Lapor Pusat!",
                                        OptikAdminTokens.danger);
                                  }
                                } else {
                                  if (stockR >= 1 && stockL >= 1) {
                                    _tambahKeKeranjangLensaLangsung(
                                        lensaKanan, lensaKiri);
                                    _showSnack("pos_lensa_masuk_keranjang".tr(),
                                        OptikAdminTokens.success);
                                  } else {
                                    List<String> lowStock = [];
                                    if (stockR < 1)
                                      lowStock.add("Kanan (Stok: $stockR)");
                                    if (stockL < 1)
                                      lowStock.add("Kiri (Stok: $stockL)");
                                    _showSnack(
                                        "🛑 Gagal! Stok habis pada mata: ${lowStock.join(' & ')}. Silakan klik Lapor Pusat!",
                                        OptikAdminTokens.danger);
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
                                foregroundColor: OptikAdminTokens.navy,
                                side: const BorderSide(
                                    color: OptikAdminTokens.navy, width: 1.2),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.send_to_mobile_rounded,
                                  size: 18),
                              label: Text(
                                "pos_btn_lapor_pusat".tr(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              onPressed: () async {
                                String inputMerk = lensBrandCtrl.text.trim();
                                if (inputMerk.isEmpty) {
                                  _showSnack(
                                      "pos_err_merk_lensa".tr(), OptikAdminTokens.danger);
                                  return;
                                }
                                if (nameCtrl.text.trim().isEmpty) {
                                  _showSnack(
                                      "Nama pelanggan wajib diisi sebelum melaporkan pesanan khusus!",
                                      OptikAdminTokens.danger);
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
                                      OptikAdminTokens.training,
                                    );
                                  } else {
                                    _showSnack(
                                        "✓ Real-time: Laporan ukuran khusus berhasil dikirim ke database pusat!",
                                        OptikAdminTokens.success);
                                  }
                                } catch (e) {
                                  _showSnack(
                                      "🛑 Gagal mengirim laporan ke pusat: $e",
                                      OptikAdminTokens.danger);
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
                                  style: const TextStyle(color: OptikAdminTokens.navy)),
                              subtitle: Text(
                                  "Rp ${selectedAksesoris!['harga'] ?? 0}",
                                  style: const TextStyle(
                                      color: OptikAdminTokens.success)),
                              trailing: SizedBox(
                                width:
                                    120, // 👈 KUNCI SAKTI: Membatasi lebar tombol Tambah Aksesoris
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: OptikAdminTokens.success,
                                    foregroundColor: OptikAdminTokens.snow,
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
                                color: OptikAdminTokens.bgMid,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: OptikAdminTokens.ice.withOpacity(0.75),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("pos_cari_aksesoris".tr(),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.navy,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 10),
                                  TextField(
                                    readOnly: true, // DIKUNCI
                                    onTap: () => _munculkanDialogPilihLainnya(
                                        context), // MUNCULKAN POP-UP saat diklik
                                    style: const TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: "pos_hint_cari_aksesoris".tr(),
                                      labelStyle: const TextStyle(
                                          color: OptikAdminTokens.slate, fontSize: 11),
                                      suffixIcon: const Icon(
                                          Icons.touch_app_rounded,
                                          color: OptikAdminTokens.navy,
                                          size: 20),
                                      filled: true,
                                      fillColor: OptikAdminTokens.card,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: OptikAdminTokens.lineStrong),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: OptikAdminTokens.lineStrong),
                                      ),
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
                    _posPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCardTitle(
                              "${"pos_daftar_pesanan".tr()} (${cartItems.length})",
                              Icons.shopping_cart_rounded),
                          const SizedBox(height: 10),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cartItems.length,
                            itemBuilder: (c, i) {
                              final item = cartItems[i];
                              return PremiumPanel(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                borderRadius: 12,
                                child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(item['nama_produk'] ?? '-',
                                                style: const TextStyle(
                                                    color: OptikAdminTokens.navy,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text("Rp ${item['harga']} / pcs",
                                                style: const TextStyle(
                                                    color: OptikAdminTokens.slate,
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
                                                            OptikAdminTokens.warning,
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
                                                  color: OptikAdminTokens.warning,
                                                  size: 20),
                                              onPressed: () =>
                                                  _ubahQtyCartItem(i, -1)),
                                          Text("${item['qty']}",
                                              style: const TextStyle(
                                                  color: OptikAdminTokens.navy,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline,
                                                  color: OptikAdminTokens.success,
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
                                                  color: OptikAdminTokens.success,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12)),
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: OptikAdminTokens.danger,
                                                  size: 18),
                                              onPressed: () =>
                                                  _hapusDariKeranjang(i)),
                                        ],
                                      ),
                                    ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // --- BAGIAN 4: PEMBAYARAN ---
                  _posPanel(
                    child: Column(
                      children: [
                        _buildCardTitle(
                            "pos_pembayaran".tr(), Icons.payments_rounded),
                        if (_posHoldRefId != null)
                          _posHoldCountdownBanner(compact: true),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("pos_subtotal".tr(),
                                style: const TextStyle(
                                  color: OptikAdminTokens.slate,
                                  fontWeight: FontWeight.w600,
                                )),
                            Text("Rp $_subtotalBelanja",
                                style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                )),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: voucherCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Kode voucher Member',
                                  hintText: 'Contoh: PROMO50',
                                  suffixIcon: _appliedVoucherCode == null
                                      ? null
                                      : IconButton(
                                          tooltip: 'Hapus voucher',
                                          onPressed: () => setState(() {
                                            _clearAppliedVoucher();
                                            if (paymentStatus == 'Lunas') {
                                              paidCtrl.text =
                                                  _totalAkhir.toString();
                                            }
                                          }),
                                          icon: const Icon(Icons.close,
                                              color: OptikAdminTokens.slate),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: OptikAdminTokens.navy,
                                  foregroundColor: OptikAdminTokens.snow,
                                ),
                                onPressed: _lookingUpVoucher
                                    ? null
                                    : _applyMemberVoucher,
                                child: _lookingUpVoucher
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: OptikAdminTokens.snow,
                                        ),
                                      )
                                    : const Text(
                                        'Cek',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        if (_appliedVoucherCode != null) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Voucher: $_appliedVoucherCode',
                              style: const TextStyle(
                                color: OptikAdminTokens.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: discountCtrl,
                          // Voucher aktif: kunci diskon — cegah lepas kode tapi
                          // tetap pakai potongan (kebocoran kuota).
                          readOnly: _appliedVoucherCode != null,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.bold),
                          onChanged: (v) => setState(() {
                            if (_appliedVoucherCode != null) {
                              // Seharusnya tidak terpanggil (readOnly), jaga ketat.
                              return;
                            }
                            if (paymentStatus == "Lunas") {
                              paidCtrl.text = _totalAkhir.toString();
                            }
                          }),
                          decoration: InputDecoration(
                              labelText: _appliedVoucherCode != null
                                  ? 'Diskon voucher (hapus voucher untuk edit)'
                                  : "pos_diskon".tr(),
                              prefixText: "- Rp ",
                              filled: true,
                              fillColor: OptikAdminTokens.bgMid),
                        ),
                        const Divider(height: 30, color: OptikAdminTokens.line),
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                              color: OptikAdminTokens.bgMid,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: OptikAdminTokens.lineStrong)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("pos_total_nett".tr(),
                                  style: const TextStyle(
                                      color: OptikAdminTokens.slate,
                                      fontWeight: FontWeight.bold)),
                              Text("Rp $_totalAkhir",
                                  style: const TextStyle(
                                      color: OptikAdminTokens.navy,
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
                              child: AdminPickerField(
                                label: 'pos_metode'.tr(),
                                valueText: paymentMethod,
                                icon: Icons.payments_outlined,
                                onTap: _pickPaymentMethod,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              fit: FlexFit.loose,
                              child: AdminPickerField(
                                label: 'pos_status'.tr(),
                                valueText: paymentStatus,
                                icon: Icons.check_circle_outline,
                                onTap: _pickPaymentStatus,
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
                              color: OptikAdminTokens.success,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: paymentStatus == "Lunas"
                                ? "pos_dibayar_full".tr()
                                : "pos_dp".tr(),
                            prefixText: "Rp ",
                            filled: paymentStatus == "Lunas",
                            fillColor: paymentStatus == "Lunas"
                                ? OptikAdminTokens.bgMid
                                : OptikAdminTokens.bgMid,
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
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikAdminTokens.navy,
                        foregroundColor: OptikAdminTokens.snow,
                        disabledBackgroundColor:
                            OptikAdminTokens.navy.withOpacity(0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              OptikAdminTokens.radiusSm),
                        ),
                      ),
                      // 🎯 FIX: Dialihkan ke fungsi Pratinjau terlebih dahulu sebelum eksekusi final!
                      onPressed: isProcessing
                          ? null
                          : () => _bukaLayarPreviewInvoice(),
                      child: isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: OptikAdminTokens.snow,
                              ),
                            )
                          : const Text(
                              "PRATINJAU INVOICE", // <-- Ganti text agar kasir tahu ini step preview
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
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
    ),
    );
  }

  Widget _buildCardTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: OptikAdminTokens.navy,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: OptikAdminTokens.navy, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    OptikAdminTokens.ice.withOpacity(0.9),
                    OptikAdminTokens.ice.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
