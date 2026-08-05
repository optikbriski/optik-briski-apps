// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'coa_approval_page.dart';
import 'enterprise_gl_page.dart';
import '../../shared/responsive.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/training/training_approval_simulator.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/premium_date_range_picker.dart';
import '../../shared/export/daily_ledger_pdf_service.dart';
import '../../shared/finance/gl_posting_service.dart';

// ============================================================================
// MODUL 16: FULL CORPORATE GENERAL LEDGER & FISCAL FINANCIAL CONSOLIDATION
// ============================================================================
class BukuBesarPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const BukuBesarPage({super.key, required this.profile});

  @override
  State<BukuBesarPage> createState() => _BukuBesarPageState();
}

class _BukuBesarPageState extends State<BukuBesarPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  bool isLoading = false;

  /// GL hanya owner / superadmin / toko PUSAT. Cabang biasa: Keuangan & Kas saja.
  bool get _canAccessGl {
    final role = widget.profile['role']?.toString().toLowerCase() ?? '';
    if (role == 'owner' || role == 'superadmin') return true;
    final toko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? '';
    return toko == 'PUSAT';
  }

  // --- CONTROL OVERVIEW DRILL-DOWN NAVIGATION ---
  String? selectedTokoId; // Stage 1 -> Stage 2 (Kunci ID Cabang)
  String? selectedDateStr; // Stage 2 -> Stage 3 (Kunci Kalender YYYY-MM-DD)

  // --- PENAMPUNG ARSIP DATA KORPORAT GLOBAL ---
  List<String> listCabangUnik = [];

  // --- MATRIX OVERVIEW CARDS (5-TIER TOP MATRIX DISPLAY CORPORATE) ---
  int totalPemasukanPOS = 0; // 1101 - Arus Kas Masuk Tunai/Transfer Terkumpul
  int totalPengeluaran = 0; // 5100 - Total Beban Pengeluaran Operasional (OPEX)
  int totalPenjualanRiilCabang =
      0; // 4100 - Omzet Bruto Seluruh Nota Invoice POS
  int totalSisaTagihanCabang = 0; // 1103 - Piutang Usaha Berjalan Pasien
  int saldoTokoAkhir = 0; // Net Cash Balance Riil di Dalam Laci Kasir

  // --- FISCAL TAXATION & NET REVENUE STATEMENT RUNNING ---
  int globalDppNetto = 0; // Dasar Pengenaan Pajak (Omzet Bersih Bisnis)
  int globalPpnKeluaran = 0; // PPN 11% Titipan Konsumen untuk Negara

// --- UNIFIED CALENDAR HARIAN SINKRON (ANTI-DISCONNECT DATA) ---
  List<String> listTanggalJurnal = [];
  Map<String, List<Map<String, dynamic>>> jurnalGroupedByDay = {};
  Map<String, int> dailyPosCashIn = {};
  Map<String, int> dailyPosDebt = {};
  Map<String, int> dailyPosOmzet = {};

  // --- NEW EXTENSION SYSTEM: DRILL-DOWN DATA AUDIT HARIAN (STAGE 3 ACTIVE) ---
  List<Map<String, dynamic>> dailyItemsSold = [];
  int dailyOmzetPemasukan = 0;
  int dailyTotalHppModal = 0;
  int dailyBiayaPengeluaran = 0;

  // --- DETAILED FISCAL TAXATION HARIAN (STAGE 3 BREAKDOWN) ---
  int dailyDppNetto = 0;
  int dailyPpnKeluaran = 0;

  String lastSyncTime = 'Belum Sinkron';

  /// Filter jurnal — sama UX Request Order (PremiumDateRangePicker).
  bool _useDateFilter = false;
  DateTime _filterStart =
      DateTime.now().subtract(const Duration(days: 6));
  DateTime _filterEnd = DateTime.now();
  String _filterPresetId = 'last7';
  final _dayFmt = DateFormat('d MMM yyyy', 'id_ID');

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Auto-posting omzet POS/online (referensi = no_invoice / sale id).
  /// CLOSE-* / SETTLE-* / FT-* bukan omzet POS — boleh masuk kas harian.
  bool _isPosSaleRef(Map<String, dynamic> row) {
    final ref = (row['referensi_id'] ?? '').toString().trim();
    if (ref.isEmpty) return false;
    final u = ref.toUpperCase();
    if (u.startsWith('CLOSE-') ||
        u.startsWith('SETTLE-') ||
        u.startsWith('FT-') ||
        u.startsWith('VOID-')) {
      return false;
    }
    return true;
  }

  bool _isClosingShift(Map<String, dynamic> row) {
    final ref = (row['referensi_id'] ?? '').toString().toUpperCase();
    if (ref.startsWith('CLOSE-')) return true;
    final k = (row['kategori'] ?? '').toString().toUpperCase();
    return k.contains('PENUTUPAN') || k.contains('CLOSING');
  }

  bool _isApprovedOrPos(Map<String, dynamic> row) {
    final st = (row['status_konfirmasi'] ?? '').toString().toUpperCase();
    if (st == 'APPROVED') return true;
    if (_isPosSaleRef(row)) return true;
    // Legacy tutup toko: sering tanpa status / PENDING — tetap masuk kas.
    if (_isClosingShift(row)) return true;
    return false;
  }

  /// Kas masuk jurnal (bukan omzet POS) untuk satu hari.
  int _manualCashInForDay(List<Map<String, dynamic>> listTx) {
    var sum = 0;
    for (final e in listTx) {
      if (!_isIncome(e) || !_isApprovedOrPos(e)) continue;
      if (_isPosSaleRef(e)) continue;
      if (_isModalNoise(e['kategori']?.toString())) continue;
      sum += int.tryParse(e['nominal']?.toString() ?? '0') ?? 0;
    }
    return sum;
  }

  /// Kas keluar jurnal untuk satu hari.
  int _cashOutForDay(List<Map<String, dynamic>> listTx) {
    var sum = 0;
    for (final e in listTx) {
      if (!_isExpense(e) || !_isApprovedOrPos(e)) continue;
      if (_isModalNoise(e['kategori']?.toString())) continue;
      sum += int.tryParse(e['nominal']?.toString() ?? '0') ?? 0;
    }
    return sum;
  }

  /// Pemasukan non-produk untuk laba (exclude closing & POS).
  int _manualIncomeForPl(List<Map<String, dynamic>> listTx) {
    var sum = 0;
    for (final e in listTx) {
      if (!_isIncome(e) || !_isApprovedOrPos(e)) continue;
      if (_isPosSaleRef(e) || _isClosingShift(e)) continue;
      if (_isModalNoise(e['kategori']?.toString())) continue;
      sum += int.tryParse(e['nominal']?.toString() ?? '0') ?? 0;
    }
    return sum;
  }

  /// OPEX untuk laba (exclude closing selisih).
  int _opexForPl(List<Map<String, dynamic>> listTx) {
    var sum = 0;
    for (final e in listTx) {
      if (!_isExpense(e) || !_isApprovedOrPos(e)) continue;
      if (_isClosingShift(e)) continue;
      if (_isModalNoise(e['kategori']?.toString())) continue;
      sum += int.tryParse(e['nominal']?.toString() ?? '0') ?? 0;
    }
    return sum;
  }

  List<String> _datesInFilter(List<String> all) {
    if (!_useDateFilter) return all;
    final startBound = _dateOnly(_filterStart);
    final endBound = _dateOnly(_filterEnd);
    return all.where((tgl) {
      try {
        final itemDate = DateTime.parse(tgl);
        final day = DateTime(itemDate.year, itemDate.month, itemDate.day);
        return !day.isBefore(startBound) && !day.isAfter(endBound);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  /// Modal / noise noise — jangan masuk KPI kas masuk.
  /// Hindari false positive "PENJUALAN KASIR" via contains('KAS').
  bool _isModalNoise(String? kategori) {
    final k = (kategori ?? '').toUpperCase();
    if (k.contains('MODAL') ||
        k.contains('KEMBALIAN') ||
        k.contains('SALDO AWAL')) {
      return true;
    }
    if (k.contains('PENUTUPAN') || k.contains('CLOSING')) return false;
    if (k.contains('KASIR')) return false;
    return RegExp(r'(^|[^A-Z])KAS([^A-Z]|$)').hasMatch(k);
  }

  bool _isIncome(Map<String, dynamic> row) {
    final j = (row['jenis_transaksi'] ?? '').toString().toUpperCase();
    return j == 'PEMASUKAN' || j == 'PIUTANG';
  }

  bool _isExpense(Map<String, dynamic> row) {
    final j = (row['jenis_transaksi'] ?? '').toString().toUpperCase();
    return j == 'PENGELUARAN' || j == 'HUTANG';
  }

  String _tokoLabel(String? id) {
    final t = (id ?? '').trim().toUpperCase();
    if (t.isEmpty) return '-';
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  String get _filterTriggerLabel {
    if (!_useDateFilter) return 'Semua tanggal';
    final range = '${_dayFmt.format(_filterStart)} – ${_dayFmt.format(_filterEnd)}';
    switch (_filterPresetId) {
      case 'last7':
        return '7 hari terakhir: $range';
      case 'last30':
        return '30 hari terakhir: $range';
      case 'last60':
        return '60 hari terakhir: $range';
      case 'last90':
        return '90 hari terakhir: $range';
      case 'thisMonth':
        return 'Bulan ini: $range';
      case 'lastMonth':
        return 'Bulan lalu: $range';
      case 'lastYear':
        return 'Tahun lalu: $range';
      default:
        return range;
    }
  }

  Future<void> _openPeriodPicker() async {
    final result = await showPremiumDateRangePicker(
      context: context,
      initialStart: _dateOnly(_filterStart),
      initialEnd: _dateOnly(_filterEnd),
      initialPresetId: _useDateFilter ? _filterPresetId : 'custom',
    );
    if (result == null) return;
    setState(() {
      _useDateFilter = true;
      _filterStart = _dateOnly(result.start);
      _filterEnd = _dateOnly(result.end);
      _filterPresetId = result.presetId;
    });
  }

  // --- REKONSILIASI KANAL LIKUIDITAS INSTRUMEN HARIAN ---
  Map<String, int> dailyPaymentBreakdown = {
    'CASH': 0,
    'BCA': 0,
    'MANDIRI': 0,
    'QRIS': 0,
    'LAINNYA': 0,
  };

  @override
  void initState() {
    super.initState();
    _inisialisasiFilterHakAkses();
  }

  // Mengubah data int nominal menjadi teks string format Rupiah Lokal Indonesia
  String _formatRupiah(dynamic angka) {
    if (angka == null) return 'Rp0';
    int value = int.tryParse(angka.toString()) ?? 0;
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String hasil =
        value.toString().replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return "Rp$hasil";
  }

  // Mengubah kode penanggalan mentah ISO (YYYY-MM-DD) menjadi format formal nasional
  String _formatTanggalIndonesia(String dateStr) {
    try {
      DateTime parsed = DateTime.parse(dateStr);
      return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(parsed);
    } catch (e) {
      return dateStr;
    }
  }

  // --- SINKRONISASI SECURITY AUTORISASI LEVEL AKSES AWAL ---
  void _inisialisasiFilterHakAkses() {
    String role = widget.profile['role']?.toString().toLowerCase() ?? 'kasir';
    String userTokoId =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

    if (role == 'owner' || userTokoId == 'PUSAT') {
      selectedTokoId = null;
      _fetchTransaksiGlobalOwner();
    } else {
      selectedTokoId = userTokoId;
      _fetchTransaksiPerCabang(userTokoId);
    }
  }

  // 🌍 ENGINE 1 FIX: Menyatukan Pencarian Cabang Lintas Tabel (Anti-Kecolongan Data)
  Future<void> _fetchTransaksiGlobalOwner() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final resFinance =
          await supabase.from('finance_transactions').select('toko_id');
      final resSales = await supabase.from('sales').select('toko_id');

      final List<Map<String, dynamic>> dataFinance =
          List<Map<String, dynamic>>.from(resFinance);
      final List<Map<String, dynamic>> dataSales =
          List<Map<String, dynamic>>.from(resSales);

      final Set<String> cabangSet = {};
      for (var e in dataFinance) {
        cabangSet.add(e['toko_id']?.toString().toUpperCase() ?? 'PUSAT');
      }
      for (var e in dataSales) {
        cabangSet.add(e['toko_id']?.toString().toUpperCase() ?? 'PUSAT');
      }

      setState(() {
        listCabangUnik = cabangSet.toList();
        isLoading = false;
      });
    } catch (e) {
      _showSnackEror("Gagal memuat daftar cabang: $e");
    }
  }

  void _showSnackEror(String msg) {
    setState(() => isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: OptikAdminTokens.danger),
      );
    }
  }

  /// Self-heal legacy tutup toko (PENDING / tanpa CLOSE-*) agar sinkron COA + ledger.
  Future<void> _normalizeLegacyClosing(
      List<Map<String, dynamic>> rows) async {
    for (final item in rows) {
      if (!_isClosingShift(item)) continue;
      final id = item['id'];
      if (id == null) continue;
      final ref = (item['referensi_id'] ?? '').toString().trim();
      final st = (item['status_konfirmasi'] ?? '').toString().toUpperCase();
      final needsStatus = st != 'APPROVED';
      final needsRef = ref.isEmpty || !ref.toUpperCase().startsWith('CLOSE-');
      if (!needsStatus && !needsRef) continue;

      final toko = (item['toko_id'] ?? 'PUSAT').toString();
      final tgl = (item['tanggal_transaksi'] ??
              item['created_at']?.toString().split('T').first ??
              DateTime.now().toIso8601String().split('T').first)
          .toString();
      final patch = <String, dynamic>{
        if (needsStatus) 'status_konfirmasi': 'APPROVED',
        if (needsRef) 'referensi_id': 'CLOSE-$toko-$tgl-$id',
        'updated_at': DateTime.now().toIso8601String(),
      };
      try {
        await supabase
            .from('finance_transactions')
            .update(patch)
            .eq('id', id);
        item.addAll(patch);
      } catch (_) {
        // Biarkan fallback kategori di helper tetap bekerja jika update gagal.
      }
    }
  }

  Future<void> _exportDailyLedgerPdf() async {
    final dateStr = selectedDateStr;
    final tokoId = selectedTokoId;
    if (dateStr == null || tokoId == null) return;

    final txKasManual = jurnalGroupedByDay[dateStr] ?? [];
    final pemasukanManual = _manualIncomeForPl(txKasManual);
    final opex = _opexForPl(txKasManual);
    final laba =
        (dailyOmzetPemasukan - dailyTotalHppModal) + pemasukanManual - opex;

    try {
      await DailyLedgerPdfService.sharePdf(
        DailyLedgerPdfData(
          tokoLabel: _tokoLabel(tokoId),
          tokoId: tokoId,
          dateStr: dateStr,
          omzet: dailyOmzetPemasukan,
          hpp: dailyTotalHppModal,
          dpp: dailyDppNetto,
          ppn: dailyPpnKeluaran,
          pemasukanManual: pemasukanManual,
          opex: opex,
          labaBersih: laba,
          paymentBreakdown: Map<String, int>.from(dailyPaymentBreakdown),
          itemsSold: List<Map<String, dynamic>>.from(dailyItemsSold),
          mutasi: List<Map<String, dynamic>>.from(txKasManual),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengekspor PDF: $e'),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    }
  }

  // 🏢 ENGINE 2: CONSOLIDATED ENTERPRISE ENGINE DUAL-QUERY (SINKRONISASI FISKAL MULTI-TABEL)
  Future<void> _fetchTransaksiPerCabang(String tokoId) async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final resFinance = await supabase
          .from('finance_transactions')
          .select()
          .eq('toko_id', tokoId)
          .order('tanggal_transaksi', ascending: false);

      final resSales = await supabase
          .from('sales')
          .select('total_harga, sisa_tagihan, created_at')
          .eq('toko_id', tokoId);

      final List<Map<String, dynamic>> dataFinance =
          List<Map<String, dynamic>>.from(resFinance);
      final List<Map<String, dynamic>> dataSales =
          List<Map<String, dynamic>>.from(resSales);

      int hitungPengeluaran = 0;
      int hitungPenjualanRiil = 0;
      int hitungSisaTagihan = 0;
      int hitungUangMasukDariPos = 0;
      int hitungDpp = 0;
      int hitungPpn = 0;

      final Map<String, int> tempDailyPosCash = {};
      final Map<String, int> tempDailyPosDebt = {};
      final Map<String, int> tempDailyOmzet = {};
      final Map<String, List<Map<String, dynamic>>> temporaryGroup = {};

      for (var sale in dataSales) {
        int total = int.tryParse(sale['total_harga']?.toString() ?? '0') ?? 0;
        int sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
        int cashCollected = total - sisa;

        hitungPenjualanRiil += total;
        hitungSisaTagihan += sisa;
        hitungUangMasukDariPos += cashCollected;

        int dppItem = (total / 1.11).round();
        int ppnItem = total - dppItem;
        hitungDpp += dppItem;
        hitungPpn += ppnItem;

        String dateKey = sale['created_at']?.toString().split('T')[0] ?? '';
        if (dateKey.isNotEmpty) {
          tempDailyPosCash[dateKey] =
              (tempDailyPosCash[dateKey] ?? 0) + cashCollected;
          tempDailyPosDebt[dateKey] = (tempDailyPosDebt[dateKey] ?? 0) + sisa;
          tempDailyOmzet[dateKey] = (tempDailyOmzet[dateKey] ?? 0) + total;
        }
      }

      for (var item in dataFinance) {
        final nominal = int.tryParse(item['nominal']?.toString() ?? '0') ?? 0;
        final kategori = item['kategori']?.toString() ?? '';

        if (_isIncome(item) && _isApprovedOrPos(item)) {
          // Omzet POS sudah dari tabel sales — tambah hanya manual / closing.
          if (!_isPosSaleRef(item) && !_isModalNoise(kategori)) {
            hitungUangMasukDariPos += nominal;
          }
        } else if (_isExpense(item) && _isApprovedOrPos(item)) {
          if (!_isModalNoise(kategori)) {
            hitungPengeluaran += nominal;
          }
        }

        final tanggalKey = (item['tanggal_transaksi'] ??
                item['created_at']?.toString().split('T').first ??
                '')
            .toString();
        if (tanggalKey.isNotEmpty) {
          temporaryGroup.putIfAbsent(tanggalKey, () => []).add(item);
        }
      }

      await _normalizeLegacyClosing(dataFinance);

      final Set<String> setTanggalMaster = {};
      setTanggalMaster.addAll(tempDailyPosCash.keys);
      setTanggalMaster.addAll(temporaryGroup.keys);

      setState(() {
        jurnalGroupedByDay = temporaryGroup;
        dailyPosCashIn = tempDailyPosCash;
        dailyPosDebt = tempDailyPosDebt;
        dailyPosOmzet = tempDailyOmzet;
        listTanggalJurnal = setTanggalMaster.toList()
          ..sort((a, b) => b.compareTo(a));

        totalPemasukanPOS = hitungUangMasukDariPos;
        totalPengeluaran = hitungPengeluaran;
        totalPenjualanRiilCabang = hitungPenjualanRiil;
        totalSisaTagihanCabang = hitungSisaTagihan;
        globalDppNetto = hitungDpp;
        globalPpnKeluaran = hitungPpn;

        saldoTokoAkhir = totalPemasukanPOS - totalPengeluaran;
        // Mengunci waktu sinkronisasi data mutasi secara riil
        lastSyncTime = DateFormat('HH:mm').format(DateTime.now());
        isLoading = false;
      });
    } catch (e) {
      _showSnackEror("Gagal memuat data keuangan: $e");
    }
  }

  // 📊 ENGINE 3: AUDIT DRILL-DOWN INTEGRATED (SINKRON DOKUMEN TRAIL, FISKAL HARIAN & REKONSILIASI REKENING BANK)
  Future<void> _loadAuditDetailHariIni(String dateStr) async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      String tokoId = selectedTokoId ?? widget.profile['toko_id'] ?? 'PUSAT';

      final resSales = await supabase
          .from('sales')
          .select('*, sales_items(*)')
          .eq('toko_id', tokoId)
          .gte('created_at', '${dateStr}T00:00:00')
          .lte('created_at', '${dateStr}T23:59:59');

      List<Map<String, dynamic>> salesData =
          List<Map<String, dynamic>>.from(resSales);
      List<Map<String, dynamic>> temporaryItems = [];

      int akumulasiOmzet = 0;
      int akumulasiHpp = 0;

      final Map<String, int> targetInstruments = {
        'CASH': 0,
        'BCA': 0,
        'MANDIRI': 0,
        'QRIS': 0,
        'MIDTRANS': 0,
        'LAINNYA': 0
      };

      for (var sale in salesData) {
        String currentInvoice = sale['no_invoice'] ?? 'INV-UNKNOWN';
        String currentPatient = sale['nama_pelanggan'] ?? 'Pasien Anonim';
        String currentMetode =
            sale['metode_pembayaran']?.toString().trim().toUpperCase() ??
                'CASH';
        if (currentMetode == 'TUNAI') currentMetode = 'CASH';
        // Online Member / gateway → bucket Midtrans (bukan hilang di LAINNYA).
        if (currentMetode.contains('MIDTRANS') ||
            currentMetode.contains('GOPAY') ||
            currentMetode.contains('SHOPEEPAY') ||
            currentMetode.contains('OVO') ||
            currentMetode.contains('DANA') ||
            currentMetode == 'CREDIT_CARD' ||
            currentMetode == 'BANK_TRANSFER' ||
            (sale['channel']?.toString().toLowerCase() == 'member_online' &&
                currentMetode != 'CASH')) {
          currentMetode = 'MIDTRANS';
        }

        int saleTotal =
            int.tryParse(sale['total_harga']?.toString() ?? '0') ?? 0;
        int saleSisa =
            int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
        int riilCollected = saleTotal - saleSisa;

        // Akumulasi Alokasi Mutasi Bank Setoran Harian
        if (targetInstruments.containsKey(currentMetode)) {
          targetInstruments[currentMetode] =
              targetInstruments[currentMetode]! + riilCollected;
        } else {
          targetInstruments['LAINNYA'] =
              targetInstruments['LAINNYA']! + riilCollected;
        }

        var items = sale['sales_items'] as List<dynamic>? ?? [];
        for (var item in items) {
          int qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          int subtotal = int.tryParse(item['subtotal']?.toString() ?? '0') ?? 0;

          int hargaModalSatuan =
              int.tryParse(item['harga_modal']?.toString() ?? '') ??
                  ((subtotal / qty) * 0.4).round();
          int totalHppItem = hargaModalSatuan * qty;

          akumulasiOmzet += subtotal;
          akumulasiHpp += totalHppItem;

          // SUNTIK DATA: Jejak Dokumen (Trail Dokumen Invoice & Nama Pasien) Terikat ke Baris Item
          temporaryItems.add({
            'no_invoice': currentInvoice,
            'nama_pelanggan': currentPatient,
            'nama_produk': item['nama_produk'] ?? '-',
            'qty': qty,
            'harga_jual': (subtotal / qty).round(),
            'subtotal': subtotal,
            'harga_modal': hargaModalSatuan,
            'total_hpp': totalHppItem,
            'margin': subtotal - totalHppItem,
          });
        }
      }

      int calcDpp = (akumulasiOmzet / 1.11).round();
      int calcPpn = akumulasiOmzet - calcDpp;

      List<Map<String, dynamic>> txHariIni = jurnalGroupedByDay[dateStr] ?? [];
      int pengeluaranHariIni = _opexForPl(txHariIni);

      setState(() {
        dailyItemsSold = temporaryItems;
        dailyOmzetPemasukan = akumulasiOmzet;
        dailyTotalHppModal = akumulasiHpp;
        dailyBiayaPengeluaran = pengeluaranHariIni;
        dailyDppNetto = calcDpp;
        dailyPpnKeluaran = calcPpn;
        dailyPaymentBreakdown = targetInstruments;
        isLoading = false;
      });
    } catch (e) {
      _showSnackEror("Gagal memuat rincian harian: $e");
    }
  }

  // --- DIALOG ENTRI JURNAL MANUAL BERBASIS CHART OF ACCOUNTS (COA) STANDARD ---
  static const _coaJenisOptions = [
    AdminPickerOption(
      value: 'PEMASUKAN',
      label: 'Pemasukan kas',
      icon: Icons.arrow_downward_rounded,
    ),
    AdminPickerOption(
      value: 'PENGELUARAN',
      label: 'Beban operasional',
      icon: Icons.arrow_upward_rounded,
    ),
    AdminPickerOption(
      value: 'PIUTANG',
      label: 'Piutang usaha',
      icon: Icons.account_balance_wallet_outlined,
    ),
    AdminPickerOption(
      value: 'HUTANG',
      label: 'Hutang supplier',
      icon: Icons.receipt_long_outlined,
    ),
  ];

  static const _coaMetodeOptions = [
    AdminPickerOption(value: 'CASH', label: 'Tunai', icon: Icons.payments_outlined),
    AdminPickerOption(value: 'BCA', label: 'BCA', icon: Icons.account_balance_outlined),
    AdminPickerOption(value: 'MANDIRI', label: 'Mandiri', icon: Icons.account_balance_outlined),
    AdminPickerOption(value: 'QRIS', label: 'QRIS', icon: Icons.qr_code_rounded),
    AdminPickerOption(value: 'LAINNYA', label: 'Lainnya', icon: Icons.more_horiz_rounded),
  ];

  static const _coaStatusOptions = [
    AdminPickerOption(value: 'LUNAS', label: 'Lunas', icon: Icons.check_circle_outline),
    AdminPickerOption(value: 'BELUM LUNAS', label: 'Belum lunas', icon: Icons.pending_outlined),
  ];

  String _coaJenisLabel(String value) =>
      _coaJenisOptions
          .firstWhere((o) => o.value == value, orElse: () => _coaJenisOptions.first)
          .label;

  String _coaMetodeLabel(String value) =>
      _coaMetodeOptions
          .firstWhere((o) => o.value == value,
              orElse: () => _coaMetodeOptions.first)
          .label;

  String _coaStatusLabel(String value) =>
      _coaStatusOptions
          .firstWhere((o) => o.value == value,
              orElse: () => _coaStatusOptions.first)
          .label;

  void _showAddTransactionDialog() {
    TextEditingController nominalCtrl = TextEditingController();
    TextEditingController dibayarCtrl = TextEditingController();
    TextEditingController kategoriCtrl = TextEditingController();
    TextEditingController deskripsiCtrl = TextEditingController();
    XFile? fileBuktiFoto;
    String selectedJenis = 'PEMASUKAN';
    String selectedMetode = 'CASH';
    String selectedStatus = 'LUNAS';
    DateTime selectedDate = DateTime.now();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setInnerState) {
          return R.constrainedDialog(
            context: context,
            preferWidth: 420,
            child: AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Catat keuangan manual",
                style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: isSaving
                  ? const SizedBox(
                      height: 100,
                      child: Center(
                          child: CircularProgressIndicator(color: OptikAdminTokens.ice)))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () async {
                            DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100));
                            if (picked != null)
                              setInnerState(() => selectedDate = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 10),
                            decoration: BoxDecoration(
                                color: OptikAdminTokens.navy.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              const Icon(Icons.calendar_today,
                                  color: OptikAdminTokens.navy, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                  "Tanggal Buku: ${selectedDate.toString().split(' ')[0]}",
                                  style: const TextStyle(
                                      color: OptikAdminTokens.navy, fontSize: 13)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AdminPickerField(
                          label: 'Jenis transaksi',
                          valueText: _coaJenisLabel(selectedJenis),
                          icon: Icons.account_balance_outlined,
                          onTap: () async {
                            final sel = await showAdminPicker<String>(
                              context: context,
                              title: 'Klasifikasi Akun Akuntansi',
                              selected: selectedJenis,
                              searchable: false,
                              options: _coaJenisOptions,
                            );
                            if (sel == null || sel.isClear) return;
                            setInnerState(() => selectedJenis = sel.value!);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: kategoriCtrl,
                          style: const TextStyle(
                              color: OptikAdminTokens.navy, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: "Kategori",
                              hintText: "e.g. Listrik, Sewa Ruko, Modal Awal",
                              hintStyle: const TextStyle(color: OptikAdminTokens.lineStrong),
                              filled: true,
                              fillColor: OptikAdminTokens.snow.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 12),

                        // 🎯 RE-SUNTIK UTAMA: Kolom Total Tagihan yang Wajib Selalu Muncul Lintas Status
                        TextField(
                          controller: nominalCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: TextStyle(
                              color: (selectedJenis == 'PENGELUARAN' ||
                                      selectedJenis == 'HUTANG')
                                  ? OptikAdminTokens.danger
                                  : OptikAdminTokens.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                          decoration: InputDecoration(
                              labelText: "Nominal (Rp)",
                              prefixText: "Rp ",
                              filled: true,
                              fillColor: OptikAdminTokens.snow.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 12),

                        // 🎯 KOLOM CICILAN: Muncul di bawahnya secara otomatis hanya saat status BELUM LUNAS
                        if (selectedStatus == 'BELUM LUNAS') ...[
                          TextField(
                            controller: dibayarCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            style: TextStyle(
                                color: (selectedJenis == 'PENGELUARAN' ||
                                        selectedJenis == 'HUTANG')
                                    ? OptikAdminTokens.danger
                                    : OptikAdminTokens.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                            decoration: InputDecoration(
                                labelText:
                                    "Jumlah dibayar sekarang (Rp)",
                                prefixText: "Rp ",
                                filled: true,
                                fillColor: OptikAdminTokens.snow.withOpacity(0.05),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none)),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: deskripsiCtrl,
                          maxLines: 2,
                          style: const TextStyle(
                              color: OptikAdminTokens.navy, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: "Catatan / keterangan",
                              filled: true,
                              fillColor: OptikAdminTokens.snow.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 12),

                        InkWell(
                          onTap: () async {
                            // Desktop/web: fall back ke galeri (image_picker butuh cameraDelegate).
                            final XFile? image = await pickImageSafe(
                              context: context,
                              imageQuality: 70,
                            );
                            if (image != null) {
                              setInnerState(() => fileBuktiFoto = image);
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 10),
                            decoration: BoxDecoration(
                                color: fileBuktiFoto != null
                                    ? OptikAdminTokens.accentSoft.withOpacity(0.15)
                                    : OptikAdminTokens.snow.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: fileBuktiFoto != null
                                        ? OptikAdminTokens.navy
                                        : OptikAdminTokens.line,
                                    width: 1)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  fileBuktiFoto != null
                                      ? Icons.check_circle_rounded
                                      : Icons.camera_alt_rounded,
                                  color: fileBuktiFoto != null
                                      ? OptikAdminTokens.navy
                                      : OptikAdminTokens.ice,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  fileBuktiFoto != null
                                      ? "Foto struk terlampir"
                                      : "Ambil foto struk / bukti",
                                  style: TextStyle(
                                      color: fileBuktiFoto != null
                                          ? OptikAdminTokens.navy
                                          : OptikAdminTokens.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(children: [
                          Expanded(
                            child: AdminPickerField(
                              label: 'Metode bayar',
                              valueText: _coaMetodeLabel(selectedMetode),
                              icon: Icons.payments_outlined,
                              onTap: () async {
                                final sel = await showAdminPicker<String>(
                                  context: context,
                                  title: 'Kanal Likuiditas',
                                  selected: selectedMetode,
                                  searchable: false,
                                  options: _coaMetodeOptions,
                                );
                                if (sel == null || sel.isClear) return;
                                setInnerState(() => selectedMetode = sel.value!);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AdminPickerField(
                              label: 'Status bayar',
                              valueText: _coaStatusLabel(selectedStatus),
                              icon: Icons.flag_outlined,
                              onTap: () async {
                                final sel = await showAdminPicker<String>(
                                  context: context,
                                  title: 'Klarifikasi Status',
                                  selected: selectedStatus,
                                  searchable: false,
                                  options: _coaStatusOptions,
                                );
                                if (sel == null || sel.isClear) return;
                                setInnerState(() => selectedStatus = sel.value!);
                              },
                            ),
                          ),
                        ]),
                      ],
                    ),
            ),
            actions: isSaving
                ? []
                : [
                    // Memberikan jarak napas yang pas antara tombol batal dan simpan
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("Batal",
                              style: TextStyle(color: OptikAdminTokens.textMuted))),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: OptikAdminTokens.accent),
                      onPressed: () async {
                        // 1. Validasi dasar akun & nominal total
                        if (nominalCtrl.text.isEmpty ||
                            kategoriCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      "⚠️ Data administrasi belum lengkap!")));
                          return;
                        }

                        // 2. Validasi nominal cicilan jika status BELUM LUNAS
                        if (selectedStatus == 'BELUM LUNAS' &&
                            dibayarCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  "⚠️ Masukkan nominal biaya yang dibayarkan sekarang!")));
                          return;
                        }

                        setInnerState(() => isSaving = true);

                        // 3. Engine parsing angka nominal mentah
                        int totalNominal = int.tryParse(nominalCtrl.text
                                .replaceAll(RegExp(r'[^0-9]'), '')) ??
                            0;
                        int yangDibayar = selectedStatus == 'BELUM LUNAS'
                            ? (int.tryParse(dibayarCtrl.text
                                    .replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0)
                            : totalNominal;

                        try {
                          String urlBuktiPublic = "Tidak Ada Lampiran Foto";

                          // 🚀 PROSES UPLOAD BINARY KE SUPABASE STORAGE
                          if (fileBuktiFoto != null) {
                            final bytesImage =
                                await fileBuktiFoto!.readAsBytes();
                            final String ext =
                                fileBuktiFoto!.name.split('.').last;
                            final String nameFile =
                                "bukti_${DateTime.now().millisecondsSinceEpoch}.$ext";
                            final String fullPathStorage =
                                "${selectedTokoId ?? 'PUSAT'}/$nameFile";

                            // Upload aman dalam format Bytes (Aman dari pembatasan path Chrome Web)
                            await supabase.storage
                                .from('bukti_transaksi')
                                .uploadBinary(fullPathStorage, bytesImage,
                                    fileOptions: const FileOptions(
                                        cacheControl: '3600', upsert: false));

                            // Ambil link publik file gambarnya
                            urlBuktiPublic = supabase.storage
                                .from('bukti_transaksi')
                                .getPublicUrl(fullPathStorage);
                          }

                          // 📝 STRUKTURISASI MEMO AUDIT TRAIL
                          String catatanAkuntansi = deskripsiCtrl.text.trim();
                          if (selectedStatus == 'BELUM LUNAS') {
                            catatanAkuntansi +=
                                " (Total Tagihan: ${_formatRupiah(totalNominal)} | Dibayar: ${_formatRupiah(yangDibayar)} | Sisa Utang: ${_formatRupiah(totalNominal - yangDibayar)})";
                          }
                          // Gabungkan URL gambar di paling akhir deskripsi biar mempermudah audit owner
                          catatanAkuntansi += " | URL Bukti: $urlBuktiPublic";

                          // Deteksi otomatis hak akses approval bertingkat
                          String rolePenginput = widget.profile['role']
                                  ?.toString()
                                  .toLowerCase() ??
                              'kasir';
                          String statusAwalKonfirmasi =
                              (rolePenginput == 'owner')
                                  ? 'APPROVED'
                                  : 'PENDING';

                          // 🗄️ KIRIM ENTRI FINAL KE SUPABASE
                          final inserted = await supabase
                              .from('finance_transactions')
                              .insert({
                            'toko_id': selectedTokoId ?? 'PUSAT',
                            'tanggal_transaksi':
                                selectedDate.toIso8601String().split('T')[0],
                            'jenis_transaksi': selectedJenis,
                            'kategori': kategoriCtrl.text.trim(),
                            'deskripsi': catatanAkuntansi,
                            'nominal': yangDibayar,
                            'status_pembayaran': selectedStatus,
                            'metode_pembayaran': selectedMetode,
                            'nama_kasir': widget.profile['nama'] ??
                                widget.profile['nama_kasir'] ??
                                'Staff Optik',
                            'status_konfirmasi': statusAwalKonfirmasi,
                            'updated_at': DateTime.now().toIso8601String(),
                          }).select().single();

                          if (statusAwalKonfirmasi == 'APPROVED') {
                            try {
                              await GlPostingService().postManualFinance(
                                ft: Map<String, dynamic>.from(inserted),
                                createdBy: widget.profile['nama']?.toString(),
                              );
                            } catch (_) {}
                          }

                          Navigator.pop(ctx);

                          if (statusAwalKonfirmasi == 'PENDING' &&
                              TrainingMode.instance.isActive &&
                              mounted) {
                            final outcome = await TrainingApprovalSimulator
                                .simulateCoaIfTraining(
                              context,
                              id: inserted['id'],
                            );
                            if (mounted && outcome != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'training_coa_outcome_${outcome.name}'.tr(),
                                  ),
                                  backgroundColor: outcome ==
                                          TrainingApprovalOutcome.rejected
                                      ? OptikAdminTokens.warning
                                      : OptikAdminTokens.training,
                                ),
                              );
                            }
                          }

                          _fetchTransaksiPerCabang(selectedTokoId ?? 'PUSAT');
                        } catch (e) {
                          setInnerState(() => isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text("Gagal menyimpan entri: $e"),
                              backgroundColor: OptikAdminTokens.danger));
                        }
                      },
                      child: const Text("Simpan jurnal"),
                    )
                  ],
          ),
          );
        });
      },
    );
  }

// --- POP-UP REKONSILIASI: OTORISASI APPROVAL & DELETE RECORD CONTROL ---
  Future<void> _showOptionDialog(Map<String, dynamic> item) async {
    final role = widget.profile['role']?.toString().toLowerCase() ?? 'kasir';
    final isPending =
        item['status_konfirmasi']?.toString().toUpperCase() == 'PENDING';
    final isPosAuto = _isPosSaleRef(item);
    final isClosing = _isClosingShift(item);

    final options = <AdminPickerOption<String>>[];
    if (role == 'owner' && isPending && !isPosAuto) {
      options.add(const AdminPickerOption(
        value: 'approve',
        label: 'Setujui transaksi',
        icon: Icons.check_circle_rounded,
      ));
    }
    // Hapus hanya owner; transaksi POS auto tidak boleh dihapus dari sini.
    if (role == 'owner' && !isPosAuto) {
      options.add(AdminPickerOption(
        value: 'delete',
        label: isClosing
            ? 'Hapus penutupan toko'
            : 'Hapus rekaman transaksi',
        icon: Icons.delete_outline_rounded,
      ));
    }

    if (options.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada tindakan yang tersedia untuk transaksi ini.'),
        backgroundColor: OptikAdminTokens.textMuted,
      ));
      return;
    }

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih tindakan',
      searchable: false,
      headerIcon: Icons.gavel_rounded,
      options: options,
    );
    if (sel == null || sel.isClear) return;

    if (sel.value == 'approve') {
      setState(() => isLoading = true);
      try {
        await supabase
            .from('finance_transactions')
            .update({'status_konfirmasi': 'APPROVED'}).eq('id', item['id']);
        final approved = Map<String, dynamic>.from(item);
        approved['status_konfirmasi'] = 'APPROVED';
        try {
          await GlPostingService().postManualFinance(
            ft: approved,
            createdBy: widget.profile['nama']?.toString(),
          );
        } catch (_) {}
        _fetchTransaksiPerCabang(selectedTokoId ?? 'PUSAT');
      } catch (e) {
        _showSnackEror("Gagal menyetujui mutasi kas: $e");
      }
      return;
    }

    if (sel.value == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          title: const Text('Hapus transaksi?',
              style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          content: Text(
            'Rekaman "${item['kategori'] ?? '-'}" akan dihapus permanen.',
            style: const TextStyle(
                color: OptikAdminTokens.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal',
                  style: TextStyle(color: OptikAdminTokens.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.danger,
                foregroundColor: OptikAdminTokens.snow,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        // Void GL terkait (DB trigger BEFORE DELETE juga menutup CLOSE/SETTLE/MANUAL).
        try {
          final gl = GlPostingService();
          final by = widget.profile['nama']?.toString();
          final ref = (item['referensi_id'] ?? '').toString();
          final refU = ref.toUpperCase();
          final kat = (item['kategori'] ?? '').toString().toUpperCase();
          if (refU.startsWith('CLOSE-') ||
              kat.contains('PENUTUPAN') ||
              kat.contains('CLOSING')) {
            await gl.voidBySumberRef(
              sumber: 'CLOSING',
              referensiId: ref.isNotEmpty ? ref : 'CLOSE-FT-${item['id']}',
              createdBy: by,
            );
          } else if (refU.startsWith('SETTLE-') || kat.contains('PELUNASAN')) {
            await gl.voidBySumberRef(
              sumber: 'SETTLE',
              referensiId: ref,
              createdBy: by,
            );
          } else {
            await gl.voidBySumberRef(
              sumber: 'MANUAL',
              referensiId: 'FT-${item['id']}',
              createdBy: by,
            );
          }
        } catch (_) {}
        await supabase
            .from('finance_transactions')
            .delete()
            .eq('id', item['id']);
        _fetchTransaksiPerCabang(selectedTokoId ?? 'PUSAT');
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal menghapus rekaman: $e"),
            backgroundColor: OptikAdminTokens.danger));
      }
    }
  }

  // ==========================================================================
  // CORE DRILL-DOWN ROUTER ENGINE (MANAJEMEN ALUR PERPINDAHAN LAPISAN SCREEN)
  // ==========================================================================
  Widget _orchestrateBukuBesarFlowLayout() {
    if (selectedTokoId == null) return _buildStage1ListCabang(); // Lapis 1
    if (selectedDateStr == null) return _buildStage2JurnalHarian(); // Lapis 2
    return _buildStage3RincianItemPerHari(); // Lapis 3
  }

  // ==========================================================================
  // STAGE 1: MENU UTAMA SELEKSI CABANG WILAYAH (MONITORING PORTFOLIO GLOBAL OWNER)
  // ==========================================================================
  Widget _buildStage1ListCabang() {
    if (listCabangUnik.isEmpty) {
      return const PremiumEmptyState(
        message: 'Belum ada perputaran dana di cabang mana pun.',
        icon: Icons.account_balance_wallet_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: listCabangUnik.length,
      itemBuilder: (context, index) {
        final tokoId = listCabangUnik[index];
        return PremiumListTile(
          title: 'Optik B. Riski · ${_tokoLabel(tokoId)}',
          subtitle: 'Buka jurnal keuangan cabang',
          icon: Icons.store_rounded,
          iconColor: OptikAdminTokens.navy,
          onTap: () {
            setState(() => selectedTokoId = tokoId);
            _fetchTransaksiPerCabang(tokoId);
          },
        );
      },
    );
  }

  // ==========================================================================
  // STAGE 2: DASBOR JURNAL KALENDER HARIAN (5 KARTU SINKRON & STRUKTUR FISKAL)
  // ==========================================================================
  Widget _buildStage2JurnalHarian() {
    final kpiDates = _datesInFilter(listTanggalJurnal);
    var kpiCashIn = 0;
    var kpiOut = 0;
    var kpiOmzet = 0;
    var kpiDebt = 0;
    for (final tgl in kpiDates) {
      final listTx = jurnalGroupedByDay[tgl] ?? [];
      kpiCashIn += (dailyPosCashIn[tgl] ?? 0) + _manualCashInForDay(listTx);
      kpiOut += _cashOutForDay(listTx);
      kpiOmzet += dailyPosOmzet[tgl] ?? 0;
      kpiDebt += dailyPosDebt[tgl] ?? 0;
    }
    final kpiSaldo = kpiCashIn - kpiOut;
    final kpiDpp = (kpiOmzet / 1.11).round();
    final kpiPpn = kpiOmzet - kpiDpp;

    return Column(
      children: [
        PremiumStatGrid(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          items: [
            PremiumStatItem(
              label: 'Kas masuk',
              value: _formatRupiah(kpiCashIn),
              color: OptikAdminTokens.success,
            ),
            PremiumStatItem(
              label: 'Pengeluaran',
              value: _formatRupiah(kpiOut),
              color: OptikAdminTokens.danger,
            ),
            PremiumStatItem(
              label: 'Omzet riil',
              value: _formatRupiah(kpiOmzet),
              color: OptikAdminTokens.navy,
            ),
            PremiumStatItem(
              label: 'Belum bayar',
              value: _formatRupiah(kpiDebt),
              color: OptikAdminTokens.warning,
            ),
            PremiumStatItem(
              label: 'Saldo toko',
              value: _formatRupiah(kpiSaldo),
              color: OptikAdminTokens.navy,
            ),
          ],
        ),

        // 🏛️ EXTENSION PANEL: DEKLARASI FISKAL PAJAK & REVENUE EFFICIENCY
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: PremiumPanel(
            padding: const EdgeInsets.all(14),
            borderRadius: 16,
            borderColor: OptikAdminTokens.warning.withOpacity(0.28),
            child: Column(
              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("DPP (omzet netto):",
                      style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 10.5)),
                  Text(_formatRupiah(kpiDpp),
                      style: const TextStyle(
                          color: OptikAdminTokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("PPN keluaran (11%):",
                      style: TextStyle(color: OptikAdminTokens.textMuted, fontSize: 10.5)),
                  Text(_formatRupiah(kpiPpn),
                      style: const TextStyle(
                          color: OptikAdminTokens.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Jurnal Keuangan Harian",
                style: TextStyle(
                    color: OptikAdminTokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: OptikAdminTokens.spaceMd),
              PremiumDateRangeTrigger(
                label: _filterTriggerLabel,
                onTap: _openPeriodPicker,
              ),
              const SizedBox(height: OptikAdminTokens.spaceMd),
              AdminPickerField(
                label: 'Rentang tanggal',
                valueText:
                    _useDateFilter ? 'Pakai tanggal' : 'Semua tanggal',
                icon: Icons.date_range_rounded,
                onTap: () async {
                  final sel = await showAdminPicker<bool>(
                    context: context,
                    title: 'Filter tanggal jurnal',
                    searchable: false,
                    selected: _useDateFilter,
                    headerIcon: Icons.date_range_rounded,
                    options: const [
                      AdminPickerOption(
                        value: true,
                        label: 'Pakai tanggal',
                        subtitle: 'Tampilkan hanya rentang terpilih',
                        icon: Icons.event_available_rounded,
                      ),
                      AdminPickerOption(
                        value: false,
                        label: 'Semua tanggal',
                        subtitle: 'Tampilkan seluruh jurnal',
                        icon: Icons.event_busy_rounded,
                      ),
                    ],
                  );
                  if (sel == null || sel.isClear) return;
                  setState(() => _useDateFilter = sel.value!);
                },
              ),
              const SizedBox(height: OptikAdminTokens.spaceMd),
            ],
          ),
        ),

// 🎯 KALENDER HARIAN SINKRONISASI TOTAL DENGAN PEWARNAAN CONDITION RESPONSIVE
        Expanded(
          child: Builder(
            builder: (context) {
              final todayStr = DateTime.now().toIso8601String().split('T')[0];
              final displayedDates = _datesInFilter(listTanggalJurnal);

              if (displayedDates.isEmpty) {
                return const PremiumEmptyState(
                  message: 'Tidak ada arsip pembukuan untuk periode terpilih.',
                  icon: Icons.event_busy_rounded,
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(15, 5, 15, 88),
                itemCount: displayedDates.length,
                itemBuilder: (context, index) {
                  final tglKey = displayedDates[index];
                  final listTxHariIni = jurnalGroupedByDay[tglKey] ?? [];

                  // POS cash + jurnal manual/closing saja (anti double-count POS).
                  final dayIn = (dailyPosCashIn[tglKey] ?? 0) +
                      _manualCashInForDay(listTxHariIni);
                  final dayOut = _cashOutForDay(listTxHariIni);
                  final dayNet = dayIn - dayOut;
                  final dayDebt = dailyPosDebt[tglKey] ?? 0;

                  Color netColor;
                  if (dayDebt > 0) {
                    netColor = OptikAdminTokens.textMuted;
                  } else if (dayNet < 0) {
                    netColor = OptikAdminTokens.danger;
                  } else {
                    netColor = OptikAdminTokens.ice;
                  }

                  return PremiumPanel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    borderRadius: 16,
                    margin: const EdgeInsets.only(bottom: 10),
                    onTap: () async {
                      setState(() {
                        selectedDateStr = tglKey;
                      });
                      await _loadAuditDetailHariIni(tglKey);
                    },
                    child: Row(
                      children: [
                        PremiumIconBadge(
                          icon: Icons.calendar_today_rounded,
                          color: OptikAdminTokens.navy,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatTanggalIndonesia(tglKey),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.navy,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: tglKey == todayStr
                                          ? OptikAdminTokens.warning.withOpacity(0.15)
                                          : OptikAdminTokens.line,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tglKey == todayStr
                                          ? "Sesi terbuka"
                                          : "Ditutup",
                                      style: TextStyle(
                                        color: tglKey == todayStr
                                            ? OptikAdminTokens.warning
                                            : OptikAdminTokens.textMuted,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text("Masuk: ${_formatRupiah(dayIn)}",
                                      style: const TextStyle(
                                          color: OptikAdminTokens.success,
                                          fontSize: 11)),
                                  const SizedBox(width: 10),
                                  Text("Keluar: ${_formatRupiah(dayOut)}",
                                      style: const TextStyle(
                                          color: OptikAdminTokens.danger, fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text("Netto: ${_formatRupiah(dayNet)}",
                            style: TextStyle(
                                color: netColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded,
                            color: OptikAdminTokens.textMuted, size: 18),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // STAGE 3: LAPORAN ENTERPRISE AUDIT JEROAN LABA-RUGI & DETAILED AUDIT TRAIL
  // ==========================================================================
  Widget _buildStage3RincianItemPerHari() {
    final txKasManual = jurnalGroupedByDay[selectedDateStr] ?? [];

    // Jangan campur omzet POS (sudah di dailyOmzet) / closing ke laba produk.
    final totalPemasukanKasManual = _manualIncomeForPl(txKasManual);
    final biayaOpex = _opexForPl(txKasManual);

    final untungKotorProduk = dailyOmzetPemasukan - dailyTotalHppModal;
    final labaBersihReal =
        untungKotorProduk + totalPemasukanKasManual - biayaOpex;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 📊 PANEL A: RINGKASAN EKSEKUTIF FINANSIAL HARIAN DENGAN INTEGRATED TAXATION BREAKDOWN
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: OptikAdminTokens.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OptikAdminTokens.line, width: 0.5)),
            child: Column(
              children: [
                _buildRowFinansialCorporate("Omzet bruto POS",
                    _formatRupiah(dailyOmzetPemasukan), OptikAdminTokens.navy),
                // 🎯 SUNTIK DATA 3: Konsistensi Deklarasi Pajak Mikro Di Jeroan Laba Rugi
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("↳ DPP (omzet netto):",
                          style:
                              TextStyle(color: OptikAdminTokens.lineStrong, fontSize: 10)),
                      Text(_formatRupiah(dailyDppNetto),
                          style: const TextStyle(
                              color: OptikAdminTokens.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("↳ PPN keluaran (11%):",
                          style:
                              TextStyle(color: OptikAdminTokens.lineStrong, fontSize: 10)),
                      Text(_formatRupiah(dailyPpnKeluaran),
                          style: TextStyle(
                              color: OptikAdminTokens.warning.withOpacity(0.4),
                              fontSize: 10)),
                    ],
                  ),
                ),
                _buildRowFinansialCorporate("Total HPP / modal pokok",
                    "- ${_formatRupiah(dailyTotalHppModal)}", OptikAdminTokens.textSecondary),
                const Divider(color: OptikAdminTokens.line, height: 16),
                _buildRowFinansialCorporate(
                    "Pemasukan kas manual",
                    "+ ${_formatRupiah(totalPemasukanKasManual)}",
                    OptikAdminTokens.success),
                _buildRowFinansialCorporate(
                    "Beban operasional",
                    "- ${_formatRupiah(biayaOpex)}",
                    OptikAdminTokens.danger),
                const Divider(color: OptikAdminTokens.lineStrong, thickness: 1, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Laba bersih harian",
                        style: TextStyle(
                            color: OptikAdminTokens.navy,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    Text(_formatRupiah(labaBersihReal),
                        style: TextStyle(
                            color: labaBersihReal >= 0
                                ? OptikAdminTokens.navy
                                : OptikAdminTokens.warning,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),

          // 💳 PANEL B: REKONSILIASI KANAL LIKUIDITAS INSTRUMEN HARIAN (SETORAN CASH VS DIGITAL MUTASI BANK)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: OptikAdminTokens.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OptikAdminTokens.line, width: 0.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    "Rekonsiliasi kanal setoran harian",
                    style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2)),
                const SizedBox(height: 8),
                PremiumChipWrap(
                  children: dailyPaymentBreakdown.entries.map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 5, horizontal: 8),
                      decoration: BoxDecoration(
                          color: OptikAdminTokens.line,
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: OptikAdminTokens.line, width: 0.5)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("${e.key}: ",
                              style: const TextStyle(
                                  color: OptikAdminTokens.textMuted, fontSize: 10)),
                          Text(_formatRupiah(e.value),
                              style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }).toList(),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 📦 PANEL C: TABEL DETAIL MUTASI BARANG KELUAR DENGAN JEJAK DOKUMEN AUDIT TRAIL KORPORAT
          const Text("Barang keluar & margin",
              style: TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          dailyItemsSold.isEmpty
              ? const PremiumEmptyState(
                  message: 'Tidak ada sirkulasi produk keluar pada hari ini.',
                  icon: Icons.inventory_2_outlined,
                )
              : Container(
                  decoration: BoxDecoration(
                      color: OptikAdminTokens.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OptikAdminTokens.line, width: 0.5)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: HScroll(
                      minWidth: 640,
                      child: Table(
                      border:
                          TableBorder.all(color: OptikAdminTokens.line, width: 0.5),
                      columnWidths: const {
                        0: FlexColumnWidth(
                            2.8), // Nama Produk + Audit Trail Dokumen Nota
                        1: FlexColumnWidth(0.5), // Qty
                        2: FlexColumnWidth(1.4), // Jual
                        3: FlexColumnWidth(1.4), // Modal / HPP
                        4: FlexColumnWidth(1.4) // Margin Untung
                      },
                      children: [
                        TableRow(
                          decoration:
                              const BoxDecoration(color: OptikAdminTokens.bgMid),
                          children: [
                            'Produk',
                            'Qty',
                            'Jual',
                            'Modal',
                            'Margin'
                          ]
                              .map((txt) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 4),
                                  child: Text(txt,
                                      style: const TextStyle(
                                          color: OptikAdminTokens.textMuted,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center)))
                              .toList(),
                        ),
                        ...dailyItemsSold.map((item) {
                          return TableRow(
                            children: [
                              // 🎯 DEKLARASI DATA 1: Audit Trail Dokumen Terikat Otomatis ke Item
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['nama_produk'].toString(),
                                        style: const TextStyle(
                                            color: OptikAdminTokens.navy,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 3),
                                    Text(
                                        "${item['no_invoice']} • ${item['nama_pelanggan']}",
                                        style: const TextStyle(
                                            color: OptikAdminTokens.textMuted,
                                            fontSize: 8.5,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(item['qty'].toString(),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.textSecondary, fontSize: 11),
                                      textAlign: TextAlign.center)),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_formatRupiah(item['harga_jual']),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.navy, fontSize: 11),
                                      textAlign: TextAlign.end)),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                      _formatRupiah(item['harga_modal']),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.textMuted, fontSize: 11),
                                      textAlign: TextAlign.end)),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_formatRupiah(item['margin']),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.success,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.end)),
                            ],
                          );
                        }), // ➔ SIKLUS MAP PRODUK BERAKHIR AMAN DI SINI

                        // 🏛️ BARIS BARU: KESIMPULAN REKONSILIASI TOTAL ASET DI LUAR ITERASI MAP
                        TableRow(
                          decoration:
                              const BoxDecoration(color: OptikAdminTokens.bgMid),
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: const Text('Total',
                                    style: TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold))),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    '${dailyItemsSold.fold(0, (sum, item) => sum + (item['qty'] as int))}',
                                    style: const TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center)),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(_formatRupiah(dailyOmzetPemasukan),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.end)),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(_formatRupiah(dailyTotalHppModal),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.end)),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    _formatRupiah(dailyOmzetPemasukan -
                                        dailyTotalHppModal),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.end)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                ),
          const SizedBox(height: 20),

          // 🏛 PANEL D: REKAMAN MUTASI OPERASIONAL DENGAN USER IDENTIFIER SISTEM
          const Text("Beban OPEX & mutasi operasional",
              style: TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          txKasManual.isEmpty
              ? const PremiumEmptyState(
                  message:
                      'Tidak ada rekaman mutasi operasional pada tanggal ini.',
                  icon: Icons.receipt_long_outlined,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: txKasManual.length,
                  itemBuilder: (context, index) {
                    final tx = txKasManual[index];
                    bool isPemasukan = tx['jenis_transaksi'] == 'PEMASUKAN' ||
                        tx['jenis_transaksi'] == 'PIUTANG';
                    int nominal =
                        int.tryParse(tx['nominal']?.toString() ?? '0') ?? 0;

                    final isApproved =
                        tx['status_konfirmasi']?.toString().toUpperCase() ==
                            'APPROVED';
                    final isAutoSystem = _isPosSaleRef(tx) || _isClosingShift(tx);
                    final isNgawangManual = !isApproved && !isAutoSystem;

                    return Card(
                      color: isNgawangManual
                          ? OptikAdminTokens.bgMid
                          : OptikAdminTokens.card,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                              color: isNgawangManual
                                  ? OptikAdminTokens.warning.withOpacity(0.4)
                                  : (isAutoSystem && !isApproved
                                      ? OptikAdminTokens.accentSoft.withOpacity(0.3)
                                      : OptikAdminTokens.line),
                              width: isNgawangManual ? 1.0 : 0.5)),
                      child: ListTile(
                        onLongPress: () => _showOptionDialog(tx),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                tx['kategori']?.toString() ?? 'Tanpa kategori',
                                style: TextStyle(
                                    color: isNgawangManual
                                        ? OptikAdminTokens.textSecondary
                                        : OptikAdminTokens.navy,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isNgawangManual)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: OptikAdminTokens.warning.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  "Menunggu pusat",
                                  style: TextStyle(
                                      color: OptikAdminTokens.warning,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (isAutoSystem)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: OptikAdminTokens.accentSoft.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _isClosingShift(tx) ? "Tutup toko" : "POS / DP",
                                  style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tx['deskripsi'] ?? '-',
                                  style: TextStyle(
                                      color: isNgawangManual
                                          ? OptikAdminTokens.lineStrong
                                          : OptikAdminTokens.textMuted,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic)),
                              const SizedBox(height: 2),
                              Text(
                                  "Oleh: ${tx['nama_kasir'] ?? 'Sistem'} · Kanal: ${tx['metode_pembayaran'] ?? 'Tunai'}",
                                  style: TextStyle(
                                      color: isNgawangManual
                                          ? OptikAdminTokens.accentSoft.withOpacity(0.3)
                                          : OptikAdminTokens.accentSoft.withOpacity(0.6),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        trailing: Text(
                          "${isPemasukan ? '+' : '-'} ${_formatRupiah(nominal)}",
                          style: TextStyle(
                              color: isNgawangManual
                                  ? OptikAdminTokens.textMuted
                                  : (isPemasukan
                                      ? OptikAdminTokens.success
                                      : OptikAdminTokens.danger),
                              fontSize: 12,
                              decoration: isNgawangManual
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }),
        ],
      ),
    );
  }

  Widget _buildRowFinansialCorporate(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 11)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  // ==========================================================================
  // TOP-LEVEL UI SCENE FRAMING METHOD BUILD OVERRIDE
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: OptikAdminTokens.navy, size: 20),
          onPressed: () {
            final role =
                widget.profile['role']?.toString().toLowerCase() ?? '';
            setState(() {
              if (selectedDateStr != null) {
                selectedDateStr = null;
              } else if (selectedTokoId != null &&
                  (role == 'owner' ||
                      (widget.profile['toko_id']?.toString().toUpperCase() ==
                          'PUSAT'))) {
                selectedTokoId = null;
                _fetchTransaksiGlobalOwner();
              } else {
                Navigator.pop(context);
              }
            });
          },
        ),
        title: Text(
          selectedDateStr != null
              ? "Laba rugi · ${_formatTanggalIndonesia(selectedDateStr!)}"
              : selectedTokoId != null
                  ? "Jurnal · ${_tokoLabel(selectedTokoId)}"
                  : "Keuangan & Kas",
          style: const TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2),
        ),
        centerTitle: true,
        actions: [
          if (_canAccessGl)
            IconButton(
              icon: const Icon(Icons.account_balance_rounded,
                  color: OptikAdminTokens.navy, size: 20),
              tooltip: 'General Ledger',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EnterpriseGlPage(
                      profile: widget.profile,
                      initialTokoId: selectedTokoId,
                    ),
                  ),
                );
              },
            ),
          // 🚀 TOMBOL REKONSILIASI BRANKAS MANUAL COA (KHUSUS OWNER)
          if (widget.profile['role']?.toString().toLowerCase() == 'owner')
            IconButton(
              icon: const Icon(Icons.gavel_rounded,
                  color: OptikAdminTokens.warning, size: 20),
              tooltip: "Persetujuan COA manual",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          CoaApprovalPage(profile: widget.profile)),
                ).then((_) => _fetchTransaksiPerCabang(selectedTokoId ??
                    'PUSAT')); // Auto-refresh ringkasan ledger ruko pas kembali
              },
            ),
          // 📊 CONTROL 3: MONITORING REFRESH TIMESTAMPS LINTAS RUKO CABANG
          if (selectedDateStr == null && selectedTokoId != null) ...[
            Center(
              child: Text(
                "Sinkron: $lastSyncTime  ",
                style: const TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: OptikAdminTokens.navy, size: 20),
              tooltip: "Tarik Data Terbaru Cabang",
              onPressed: () => _fetchTransaksiPerCabang(selectedTokoId!),
            ),
          ],
          if (selectedDateStr != null)
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded,
                  color: OptikAdminTokens.navy, size: 20),
              tooltip: "Ekspor PDF laporan harian",
              onPressed: _exportDailyLedgerPdf,
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : _orchestrateBukuBesarFlowLayout(),
      floatingActionButton: selectedTokoId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddTransactionDialog,
              foregroundColor: OptikAdminTokens.snow,
              elevation: 6,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Catat kas',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
    );
  }
}
