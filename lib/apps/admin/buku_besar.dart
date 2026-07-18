// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'coa_approval_page.dart';

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

  // --- NEW EXTENSION SYSTEM: DRILL-DOWN DATA AUDIT HARIAN (STAGE 3 ACTIVE) ---
  List<Map<String, dynamic>> dailyItemsSold = [];
  int dailyOmzetPemasukan = 0;
  int dailyTotalHppModal = 0;
  int dailyBiayaPengeluaran = 0;

  // --- DETAILED FISCAL TAXATION HARIAN (STAGE 3 BREAKDOWN) ---
  int dailyDppNetto = 0;
  int dailyPpnKeluaran = 0;

  // 🚀 SUNTIK BALIK: Variabel filter dan sync hulu yang terhapus
  String selectedPeriodFilter = 'SEMUA';
  String lastSyncTime = 'Belum Sinkron';

  DateTime? customStartDate;
  DateTime? customEndDate;

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
      _showSnackEror("❌ Gagal konsolidasi peta cabang korporat: $e");
    }
  }

  void _showSnackEror(String msg) {
    setState(() => isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
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
        }
      }

      for (var item in dataFinance) {
        int nominal = int.tryParse(item['nominal'].toString()) ?? 0;
        String kategori = item['kategori']?.toString().toUpperCase() ?? '';

// 🚀 SEPARASI MUTLAK: Deteksi via referensi_id (Otomatis POS vs Isi Manual Kasir)
        bool isApproved =
            item['status_konfirmasi']?.toString().toUpperCase() == 'APPROVED';
        bool isAutoPOS = item['referensi_id'] !=
            null; // Transaksi POS/DP asli pasti punya referensi_id

        // Lolos otomatis jika sudah APPROVED atau jika buatan sistem POS otomatis
        bool isValidTransaksi = isApproved || isAutoPOS;

        if (item['jenis_transaksi'] == 'PEMASUKAN' ||
            item['jenis_transaksi'] == 'PIUTANG') {
          if (isValidTransaksi) {
            bool isUangLaci = kategori.contains('MODAL') ||
                kategori.contains('KEMBALIAN') ||
                kategori.contains('SALDO') ||
                kategori.contains('KAS');

            // 🚀 SUNTIKAN: Pemasukan manual non-POS yang di-approve owner resmi masuk laci kasir
            if (!isUangLaci && !isAutoPOS) {
              hitungUangMasukDariPos += nominal;
            }
          }
        } else if (item['jenis_transaksi'] == 'PENGELUARAN' ||
            item['jenis_transaksi'] == 'HUTANG') {
          if (isValidTransaksi) {
            // 🌟 Pengeluaran manual tetep tertahan kecuali sudah approved
            hitungPengeluaran += nominal;
          }
        }

        String tanggalKey = item['tanggal_transaksi'] ??
            item['created_at'].toString().split('T')[0];
        if (!temporaryGroup.containsKey(tanggalKey)) {
          temporaryGroup[tanggalKey] = [];
        }
        temporaryGroup[tanggalKey]!.add(item);
      }

      final Set<String> setTanggalMaster = {};
      setTanggalMaster.addAll(tempDailyPosCash.keys);
      setTanggalMaster.addAll(temporaryGroup.keys);

      setState(() {
        jurnalGroupedByDay = temporaryGroup;
        dailyPosCashIn = tempDailyPosCash;
        dailyPosDebt = tempDailyPosDebt;
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
      _showSnackEror("❌ Gagal memetakan database finansial korporat: $e");
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
        'LAINNYA': 0
      };

      for (var sale in salesData) {
        String currentInvoice = sale['no_invoice'] ?? 'INV-UNKNOWN';
        String currentPatient = sale['nama_pelanggan'] ?? 'Pasien Anonim';
        String currentMetode =
            sale['metode_pembayaran']?.toString().trim().toUpperCase() ??
                'CASH';
        if (currentMetode == 'TUNAI') currentMetode = 'CASH';

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
      int pengeluaranHariIni = txHariIni
          .where((e) =>
              (e['jenis_transaksi'] == 'PENGELUARAN' ||
                  e['jenis_transaksi'] ==
                      'HUTANG') && // 🚀 KUNCI: Harus murni grup pengeluaran, bukan nge-exclude pemasukan!
              (e['status_konfirmasi']?.toString().toUpperCase() == 'APPROVED' ||
                  e['referensi_id'] != null))
          .fold(
              0,
              (sum, item) =>
                  sum + (int.tryParse(item['nominal'].toString()) ?? 0));

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
      _showSnackEror("❌ Gagal memuat rincian finansial & audit instrumen: $e");
    }
  }

  // --- DIALOG ENTRI JURNAL MANUAL BERBASIS CHART OF ACCOUNTS (COA) STANDARD ---
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
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Catat Keuangan Manual (COA Ledger)",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: isSaving
                  ? const SizedBox(
                      height: 100,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: Colors.blueAccent)))
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
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              const Icon(Icons.calendar_today,
                                  color: Colors.blueAccent, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                  "Tanggal Buku: ${selectedDate.toString().split(' ')[0]}",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedJenis,
                          dropdownColor: const Color(0xFF0F172A),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: "Klasifikasi Akun Akuntansi",
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none)),
                          items: const [
                            DropdownMenuItem(
                                value: 'PEMASUKAN',
                                child: Text("[4102] Pemasukan Kas / Modal")),
                            DropdownMenuItem(
                                value: 'PENGELUARAN',
                                child: Text("[5101] Beban OPEX / Operasional")),
                            DropdownMenuItem(
                                value: 'PIUTANG',
                                child: Text("[1103] Pencatatan Piutang Usaha")),
                            DropdownMenuItem(
                                value: 'HUTANG',
                                child: Text(
                                    "[2101] Pencatatan Hutang Dagang Supplier")),
                          ],
                          onChanged: (val) =>
                              setInnerState(() => selectedJenis = val!),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: kategoriCtrl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: "Nama Kategori Akun Akrual",
                              hintText: "e.g. Listrik, Sewa Ruko, Modal Awal",
                              hintStyle: const TextStyle(color: Colors.white24),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
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
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                          decoration: InputDecoration(
                              labelText: "Total Nominal Tagihan (Rp)",
                              prefixText: "Rp ",
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
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
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                            decoration: InputDecoration(
                                labelText:
                                    "Biaya yang Dibayarkan Sekarang (Rp)",
                                prefixText: "Rp ",
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
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
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: "Memo / Deskripsi Bukti Audit",
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 12),

                        InkWell(
                          onTap: () async {
                            final ImagePicker picker = ImagePicker();
                            // Membuka kamera laptop/HP secara native di browser
                            final XFile? image = await picker.pickImage(
                                source: ImageSource.camera, imageQuality: 70);
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
                                    ? Colors.teal.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: fileBuktiFoto != null
                                        ? Colors.tealAccent
                                        : Colors.white10,
                                    width: 1)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  fileBuktiFoto != null
                                      ? Icons.check_circle_rounded
                                      : Icons.camera_alt_rounded,
                                  color: fileBuktiFoto != null
                                      ? Colors.tealAccent
                                      : Colors.blueAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  fileBuktiFoto != null
                                      ? "FOTO STRUK BERHASIL TERLAMPIR"
                                      : "AMBIL FOTO STRUK / INVOICE BUKTI",
                                  style: TextStyle(
                                      color: fileBuktiFoto != null
                                          ? Colors.tealAccent
                                          : Colors.white70,
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
                              child: DropdownButtonFormField<String>(
                            value: selectedMetode,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                                labelText: "Kanal Likuiditas",
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none)),
                            items: ['CASH', 'BCA', 'MANDIRI', 'QRIS', 'LAINNYA']
                                .map((val) => DropdownMenuItem(
                                    value: val, child: Text(val)))
                                .toList(),
                            onChanged: (val) =>
                                setInnerState(() => selectedMetode = val!),
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                              child: DropdownButtonFormField<String>(
                            value: selectedStatus,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                                labelText: "Klarifikasi Status",
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none)),
                            items: ['LUNAS', 'BELUM LUNAS']
                                .map((val) => DropdownMenuItem(
                                    value: val, child: Text(val)))
                                .toList(),
                            onChanged: (val) =>
                                setInnerState(() => selectedStatus = val!),
                          )),
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
                              style: TextStyle(color: Colors.grey))),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
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
                          await supabase.from('finance_transactions').insert({
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
                          });

                          Navigator.pop(ctx);
                          _fetchTransaksiPerCabang(selectedTokoId ?? 'PUSAT');
                        } catch (e) {
                          setInnerState(() => isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text("❌ Gagal menyimpan entri & file: $e"),
                              backgroundColor: Colors.red));
                        }
                      },
                      child: const Text("SIMPAN JURNAL"),
                    )
                  ],
          );
        });
      },
    );
  }

// --- POP-UP REKONSILIASI: OTORISASI APPROVAL & DELETE RECORD CONTROL ---
  void _showOptionDialog(Map<String, dynamic> item) {
    // Membaca hak akses user yang sedang login aktif di aplikasi
    String role = widget.profile['role']?.toString().toLowerCase() ?? 'kasir';
    bool isPending =
        item['status_konfirmasi']?.toString().toUpperCase() == 'PENDING';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Pilih Tindakan Audit",
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎯 SUNTIK UTAMA PUSAT: Tombol Konfirmasi Otorisasi (Hanya muncul jika user adalah Owner & data masih PENDING)
            if (role == 'owner' && isPending) ...[
              ListTile(
                leading: const Icon(Icons.check_circle_rounded,
                    color: Colors.tealAccent, size: 20),
                title: const Text("Setujui (Approve) Transaksi",
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => isLoading = true);
                  try {
                    // Update status di Supabase dari PENDING menjadi APPROVED
                    await supabase.from('finance_transactions').update(
                        {'status_konfirmasi': 'APPROVED'}).eq('id', item['id']);

                    // Tarik data terbaru untuk langsung mengkalkulasi ulang Saldo Toko resmi
                    _fetchTransaksiPerCabang(selectedTokoId ?? 'PUSAT');
                  } catch (e) {
                    _showSnackEror("❌ Gagal menyetujui mutasi kas: $e");
                  }
                },
              ),
              const Divider(color: Colors.white10, height: 1),
            ],

            // Tombol Hapus Record (Bawaan)
            ListTile(
              leading:
                  const Icon(Icons.delete, color: Colors.redAccent, size: 20),
              title: const Text("Hapus Rekaman Transaksi",
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await supabase
                      .from('finance_transactions')
                      .delete()
                      .eq('id', item['id']);
                  _fetchTransaksiPerCabang(selectedTokoId ?? 'PUSAT');
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("❌ Gagal menghapus rekaman: $e"),
                      backgroundColor: Colors.red));
                }
              },
            ),
          ],
        ),
      ),
    );
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
      return const Center(
        child: Text("Belum mendeteksi perputaran dana di cabang mana pun.",
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: listCabangUnik.length,
      itemBuilder: (context, index) {
        String tokoId = listCabangUnik[index];
        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.store, color: Colors.white, size: 16),
            ),
            title: Text(
              tokoId == 'PUSAT'
                  ? 'OPTIK B. RISKI - PUSAT'
                  : 'OPTIK B. RISKI - $tokoId',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            trailing: const Icon(Icons.arrow_forward_ios,
                color: Colors.white12, size: 14),
            onTap: () {
              setState(() => selectedTokoId = tokoId);
              _fetchTransaksiPerCabang(tokoId);
            },
          ),
        );
      },
    );
  }

  // ==========================================================================
  // STAGE 2: DASBOR JURNAL KALENDER HARIAN (5 KARTU SINKRON & STRUKTUR FISKAL)
  // ==========================================================================
  Widget _buildStage2JurnalHarian() {
    return Column(
      children: [
        // 📦 PANEL OVERVIEW 5 KARTU HORIZONTAL SEJAJAR (CORE TIER ATAS CORPO-STYLE)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Row(
            children: [
              _buildTopOverviewCard("↓ Kas Masuk POS",
                  _formatRupiah(totalPemasukanPOS), Colors.greenAccent),
              const SizedBox(width: 4),
              _buildTopOverviewCard("↑ Pengeluaran",
                  _formatRupiah(totalPengeluaran), Colors.redAccent),
              const SizedBox(width: 4),
              _buildTopOverviewCard("👓 Jualan Riil",
                  _formatRupiah(totalPenjualanRiilCabang), Colors.blueAccent),
              const SizedBox(width: 4),
              _buildTopOverviewCard("⏳ Belum Bayar",
                  _formatRupiah(totalSisaTagihanCabang), Colors.orangeAccent),
              const SizedBox(width: 4),
              _buildTopOverviewCard(
                  "🏛 Saldo Toko", _formatRupiah(saldoTokoAkhir), Colors.white),
            ],
          ),
        ),

        // 🏛️ EXTENSION PANEL: DEKLARASI FISKAL PAJAK & REVENUE EFFICIENCY
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10, width: 0.5)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("DPP (Dasar Pengenaan Pajak / Omzet Netto):",
                      style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                  Text(_formatRupiah(globalDppNetto),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Alokasi PPN Keluaran Terutang (11%):",
                      style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                  Text(_formatRupiah(globalPpnKeluaran),
                      style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Jurnal Keuangan Harian",
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
// 📦 CONTROL 1: DROPDOWN FILTER MULTI-PERIODE ENTERPRISE UPGRADED
              DropdownButton<String>(
                value: selectedPeriodFilter,
                dropdownColor: const Color(0xFF1E293B),
                underline: const SizedBox(),
                style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(
                      value: 'SEMUA', child: Text("📊 SEMUA LAPORAN")),
                  DropdownMenuItem(
                      value: 'HARI INI', child: Text("⏳ HARI INI")),
                  DropdownMenuItem(
                      value: 'MINGGU_INI', child: Text("🗓️ MINGGU INI")),
                  DropdownMenuItem(
                      value: '14_HARI', child: Text("🗓️ 14 HARI")),
                  DropdownMenuItem(
                      value: '1_BULAN', child: Text("🗓️ 1 BULAN")),
                  DropdownMenuItem(
                      value: '3_BULAN', child: Text("🗓️ 3 BULAN")),
                  DropdownMenuItem(
                      value: '6_BULAN', child: Text("🗓️ 6 BULAN")),
                  DropdownMenuItem(
                      value: '1_TAHUN', child: Text("🗓️ 1 TAHUN")),
                  DropdownMenuItem(
                      value: '2_TAHUN', child: Text("🗓️ 2 TAHUN")),
                  DropdownMenuItem(
                      value: '3_TAHUN', child: Text("🗓️ 3 TAHUN")),
                  DropdownMenuItem(
                      value: 'KUSTOM', child: Text("📅 PILIH KALENDER...")),
                ],
                onChanged: (val) async {
                  if (val == 'KUSTOM') {
                    // Memicu jendela kalender range kustom resmi material design
                    DateTimeRange? picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Colors.blueAccent,
                              onPrimary: Colors.white,
                              surface: Color(0xFF1E293B),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        selectedPeriodFilter = 'KUSTOM';
                        customStartDate = picked.start;
                        customEndDate = picked.end;
                      });
                    }
                  } else if (val != null) {
                    setState(() {
                      selectedPeriodFilter = val;
                    });
                  }
                },
              ),
            ],
          ),
        ),

// 🎯 KALENDER HARIAN SINKRONISASI TOTAL DENGAN PEWARNAAN CONDITION RESPONSIVE
        Expanded(
          child: Builder(
            builder: (context) {
// Engine Akuntansi Multi-Periode untuk Rekonsiliasi Kalender
              String todayStr = DateTime.now().toIso8601String().split('T')[0];
              DateTime now = DateTime.now();
              DateTime todayMidnight = DateTime(now.year, now.month, now.day);

              List<String> displayedDates = listTanggalJurnal.where((tgl) {
                try {
                  DateTime itemDate = DateTime.parse(tgl);
                  DateTime itemDateMidnight =
                      DateTime(itemDate.year, itemDate.month, itemDate.day);

                  if (selectedPeriodFilter == 'HARI INI') {
                    return itemDateMidnight.isAtSameMomentAs(todayMidnight);
                  } else if (selectedPeriodFilter == 'MINGGU_INI') {
                    DateTime limit =
                        todayMidnight.subtract(const Duration(days: 7));
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '14_HARI') {
                    DateTime limit =
                        todayMidnight.subtract(const Duration(days: 14));
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '1_BULAN') {
                    DateTime limit = DateTime(now.year, now.month - 1, now.day);
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '3_BULAN') {
                    DateTime limit = DateTime(now.year, now.month - 3, now.day);
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '6_BULAN') {
                    DateTime limit = DateTime(now.year, now.month - 6, now.day);
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '1_TAHUN') {
                    DateTime limit = DateTime(now.year - 1, now.month, now.day);
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '2_TAHUN') {
                    DateTime limit = DateTime(now.year - 2, now.month, now.day);
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == '3_TAHUN') {
                    DateTime limit = DateTime(now.year - 3, now.month, now.day);
                    return itemDateMidnight.isAfter(limit) ||
                        itemDateMidnight.isAtSameMomentAs(limit);
                  } else if (selectedPeriodFilter == 'KUSTOM') {
                    if (customStartDate != null && customEndDate != null) {
                      DateTime startStart = DateTime(customStartDate!.year,
                          customStartDate!.month, customStartDate!.day);
                      DateTime endEnd = DateTime(customEndDate!.year,
                          customEndDate!.month, customEndDate!.day);
                      return (itemDateMidnight.isAfter(startStart) ||
                              itemDateMidnight.isAtSameMomentAs(startStart)) &&
                          (itemDateMidnight.isBefore(endEnd) ||
                              itemDateMidnight.isAtSameMomentAs(endEnd));
                    }
                  }
                } catch (_) {}
                return selectedPeriodFilter == 'SEMUA';
              }).toList();

              if (displayedDates.isEmpty) {
                return const Center(
                  child: Text(
                      "Tidak ada arsip pembukuan untuk periode terpilih.",
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(15).copyWith(top: 5),
                itemCount: displayedDates.length,
                itemBuilder: (context, index) {
                  String tglKey = displayedDates[index];
                  List<Map<String, dynamic>> listTxHariIni =
                      jurnalGroupedByDay[tglKey] ?? [];

// 🚀 Pemisahan via referensi_id untuk indikator sirkulasi harian kalender
                  int financeIn = listTxHariIni
                      .where((e) =>
                          (e['jenis_transaksi'] == 'PEMASUKAN' ||
                              e['jenis_transaksi'] == 'PIUTANG') &&
                          (e['status_konfirmasi']?.toString().toUpperCase() ==
                                  'APPROVED' ||
                              e['referensi_id'] != null))
                      .fold(
                          0,
                          (sum, item) =>
                              sum +
                              (int.tryParse(item['nominal'].toString()) ?? 0));

                  int dayOut = listTxHariIni
                      .where((e) =>
                          (e['jenis_transaksi'] != 'PEMASUKAN' &&
                              e['jenis_transaksi'] != 'PIUTANG') &&
                          (e['status_konfirmasi']?.toString().toUpperCase() ==
                                  'APPROVED' ||
                              e['referensi_id'] != null))
                      .fold(
                          0,
                          (sum, item) =>
                              sum +
                              (int.tryParse(item['nominal'].toString()) ?? 0));

                  int dayIn = (dailyPosCashIn[tglKey] ?? 0) + financeIn;
                  int dayNet = dayIn - dayOut;
                  int dayDebt = dailyPosDebt[tglKey] ?? 0;

                  Color netColor;
                  if (dayDebt > 0) {
                    netColor = Colors.grey;
                  } else if (dayNet < 0) {
                    netColor = Colors.redAccent;
                  } else {
                    netColor = Colors.tealAccent;
                  }

                  return Card(
                    color: const Color(0xFF1E293B),
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      leading: const CircleAvatar(
                          backgroundColor: Color(0xFF0F172A),
                          child: Icon(Icons.calendar_today,
                              color: Colors.tealAccent, size: 14)),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatTanggalIndonesia(tglKey).toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
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
                                  ? Colors.amber.withOpacity(0.15)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tglKey == todayStr
                                  ? "OPEN SESSION"
                                  : "CLOSED AUDITED",
                              style: TextStyle(
                                color: tglKey == todayStr
                                    ? Colors.amber
                                    : Colors.white38,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Text("In: ${_formatRupiah(dayIn)}",
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 11)),
                            const SizedBox(width: 10),
                            Text("Out: ${_formatRupiah(dayOut)}",
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 11)),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Net: ${_formatRupiah(dayNet)}",
                              style: TextStyle(
                                  color: netColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.white12, size: 12),
                        ],
                      ),
                      onTap: () async {
                        setState(() {
                          selectedDateStr = tglKey;
                        });
                        await _loadAuditDetailHariIni(tglKey);
                      },
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

  Widget _buildTopOverviewCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // STAGE 3: LAPORAN ENTERPRISE AUDIT JEROAN LABA-RUGI & DETAILED AUDIT TRAIL
  // ==========================================================================
  Widget _buildStage3RincianItemPerHari() {
    List<Map<String, dynamic>> txKasManual =
        jurnalGroupedByDay[selectedDateStr] ?? [];

    int totalPemasukanKasManual = txKasManual
        .where((e) =>
            (e['jenis_transaksi'] == 'PEMASUKAN' ||
                e['jenis_transaksi'] == 'PIUTANG') &&
            (e['status_konfirmasi']?.toString().toUpperCase() == 'APPROVED' ||
                e['referensi_id'] !=
                    null)) // 🚀 KUNCI: POS otomatis bypass hitungan laba bersih harian ruko
        .fold(
            0,
            (sum, item) =>
                sum + (int.tryParse(item['nominal'].toString()) ?? 0));

    int untungKotorProduk = dailyOmzetPemasukan - dailyTotalHppModal;
    int labaBersihReal =
        untungKotorProduk + totalPemasukanKasManual - dailyBiayaPengeluaran;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 📊 PANEL A: RINGKASAN EKSEKUTIF FINANSIAL HARIAN DENGAN INTEGRATED TAXATION BREAKDOWN
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10, width: 0.5)),
            child: Column(
              children: [
                _buildRowFinansialCorporate("Total Penjualan (Omzet Bruto POS)",
                    _formatRupiah(dailyOmzetPemasukan), Colors.white),
                // 🎯 SUNTIK DATA 3: Konsistensi Deklarasi Pajak Mikro Di Jeroan Laba Rugi
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("↳ DPP (Omzet Netto):",
                          style:
                              TextStyle(color: Colors.white24, fontSize: 10)),
                      Text(_formatRupiah(dailyDppNetto),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("↳ Titipan PPN Keluaran (11%):",
                          style:
                              TextStyle(color: Colors.white24, fontSize: 10)),
                      Text(_formatRupiah(dailyPpnKeluaran),
                          style: TextStyle(
                              color: Colors.amber.withOpacity(0.4),
                              fontSize: 10)),
                    ],
                  ),
                ),
                _buildRowFinansialCorporate("Total HPP / Modal Pokok Barang",
                    "- ${_formatRupiah(dailyTotalHppModal)}", Colors.white70),
                const Divider(color: Colors.white10, height: 16),
                _buildRowFinansialCorporate(
                    "Pemasukan Kas Manual (Non-Produk)",
                    "+ ${_formatRupiah(totalPemasukanKasManual)}",
                    Colors.greenAccent),
                _buildRowFinansialCorporate(
                    "Beban Biaya Operasional (OPEX)",
                    "- ${_formatRupiah(dailyBiayaPengeluaran)}",
                    Colors.redAccent),
                const Divider(color: Colors.white24, thickness: 1, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("LABA BERSIH HARIAN (NET PROFIT)",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    Text(_formatRupiah(labaBersihReal),
                        style: TextStyle(
                            color: labaBersihReal >= 0
                                ? Colors.tealAccent
                                : Colors.orangeAccent,
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
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10, width: 0.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    "💳 AUDIT REKONSILIASI KANAL SETORAN LIKUIDITAS HARIAN",
                    style: TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: dailyPaymentBreakdown.entries.map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 5, horizontal: 8),
                      decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: Colors.white10, width: 0.5)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("${e.key}: ",
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                          Text(_formatRupiah(e.value),
                              style: const TextStyle(
                                  color: Colors.white,
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
          const Text("📦 MATRIKS BARANG KELUAR & PROFIT MARGIN",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          dailyItemsSold.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Center(
                      child: Text(
                          "Tidak ada sirkulasi produk keluar pada hari ini.",
                          style:
                              TextStyle(color: Colors.white38, fontSize: 11))),
                )
              : Container(
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10, width: 0.5)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Table(
                      border:
                          TableBorder.all(color: Colors.white10, width: 0.5),
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
                              const BoxDecoration(color: Color(0xFF0F172A)),
                          children: [
                            'PRODUK / AUDIT TRAIL',
                            'QTY',
                            'JUAL',
                            'MODAL',
                            'MARGIN'
                          ]
                              .map((txt) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 4),
                                  child: Text(txt,
                                      style: const TextStyle(
                                          color: Colors.white38,
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
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 3),
                                    Text(
                                        "${item['no_invoice']} • ${item['nama_pelanggan']}",
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 8.5,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(item['qty'].toString(),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11),
                                      textAlign: TextAlign.center)),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_formatRupiah(item['harga_jual']),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11),
                                      textAlign: TextAlign.end)),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                      _formatRupiah(item['harga_modal']),
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 11),
                                      textAlign: TextAlign.end)),
                              Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(_formatRupiah(item['margin']),
                                      style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.end)),
                            ],
                          );
                        }), // ➔ SIKLUS MAP PRODUK BERAKHIR AMAN DI SINI

                        // 🏛️ BARIS BARU: KESIMPULAN REKONSILIASI TOTAL ASET DI LUAR ITERASI MAP
                        TableRow(
                          decoration:
                              const BoxDecoration(color: Color(0xFF0F172A)),
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: const Text('TOTAL EVALUASI PERSYARATAN',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold))),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    '${dailyItemsSold.fold(0, (sum, item) => sum + (item['qty'] as int))}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center)),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(_formatRupiah(dailyOmzetPemasukan),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.end)),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(_formatRupiah(dailyTotalHppModal),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.end)),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    _formatRupiah(dailyOmzetPemasukan -
                                        dailyTotalHppModal),
                                    style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.end)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          const SizedBox(height: 20),

          // 🏛 PANEL D: REKAMAN MUTASI OPERASIONAL DENGAN USER IDENTIFIER SISTEM
          const Text("🏛 BEBAN OPEX & MUTASI OPERASIONAL LAINNYA",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          txKasManual.isEmpty
              ? const Center(
                  child: Text(
                      "Tidak ada rekaman mutasi operasional manual pada tanggal ini.",
                      style: TextStyle(color: Colors.white24, fontSize: 11)))
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

                    bool isApproved =
                        tx['status_konfirmasi']?.toString().toUpperCase() ==
                            'APPROVED';
                    bool isAutoSystem = tx['referensi_id'] != null;
                    bool isNgawangManual = !isApproved &&
                        !isAutoSystem; // Karantina murni isian manual kasir ruko

                    return Card(
                      color: isNgawangManual
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                              color: isNgawangManual
                                  ? Colors.orangeAccent.withOpacity(0.4)
                                  : (isAutoSystem && !isApproved
                                      ? Colors.tealAccent.withOpacity(0.3)
                                      : Colors.white10),
                              width: isNgawangManual ? 1.0 : 0.5)),
                      child: ListTile(
                        onLongPress: () => _showOptionDialog(tx),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                tx['kategori']?.toString().toUpperCase() ??
                                    'KAS UNCLASSIFIED',
                                style: TextStyle(
                                    color: isNgawangManual
                                        ? Colors.white60
                                        : Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold)),
                            if (isNgawangManual)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  "⏳ MANUAL PENDING PUSAT",
                                  style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (isAutoSystem && !isApproved)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.tealAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  "🎯 VALID AUTOMATIC POS/DP",
                                  style: TextStyle(
                                      color: Colors.tealAccent,
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
                                          ? Colors.white24
                                          : Colors.white38,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic)),
                              const SizedBox(height: 2),
                              Text(
                                  "Oleh: ${tx['nama_kasir'] ?? 'System'} • Kanal: ${tx['metode_pembayaran'] ?? 'CASH'}",
                                  style: TextStyle(
                                      color: isNgawangManual
                                          ? Colors.blueAccent.withOpacity(0.3)
                                          : Colors.blueAccent.withOpacity(0.6),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        trailing: Text(
                          "${isPemasukan ? '+' : '-'} ${_formatRupiah(nominal)}",
                          style: TextStyle(
                              color: isNgawangManual
                                  ? Colors.white30
                                  : (isPemasukan
                                      ? Colors.greenAccent
                                      : Colors.redAccent),
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
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          onPressed: () {
            setState(() {
              if (selectedDateStr != null) {
                selectedDateStr = null;
              } else if (selectedTokoId != null &&
                  widget.profile['role'] == 'owner') {
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
              ? "📅 NET INCOME STATEMENT: $selectedDateStr"
              : selectedTokoId != null
                  ? "🏪 RINGKASAN LEDGER: $selectedTokoId"
                  : "🏢 ARSIP INTEGRATED GENERAL LEDGER PUSAT",
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5),
        ),
        centerTitle: true,
        actions: [
          // 🚀 TOMBOL REKONSILIASI BRANKAS MANUAL COA (KHUSUS OWNER)
          if (widget.profile['role']?.toString().toLowerCase() == 'owner')
            IconButton(
              icon: const Icon(Icons.gavel_rounded,
                  color: Colors.orangeAccent, size: 20),
              tooltip: "Buka Vault Karantina COA",
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
                "Sync: $lastSyncTime  ",
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Colors.blueAccent, size: 20),
              tooltip: "Tarik Data Terbaru Cabang",
              onPressed: () => _fetchTransaksiPerCabang(selectedTokoId!),
            ),
          ],
          if (selectedDateStr != null)
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded,
                  color: Colors.tealAccent, size: 20),
              tooltip: "Ekspor Berkas PDF/Excel",
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        "💾 Laporan Keuangan Hari $selectedDateStr Berhasil Diekspor ke PDF!"),
                    backgroundColor: Colors.teal,
                  ),
                );
              },
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent))
          : _orchestrateBukuBesarFlowLayout(),
      floatingActionButton: selectedTokoId != null
          ? FloatingActionButton.extended(
              backgroundColor: Colors.blueAccent,
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text("Catat Kas (COA)",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 12)),
              onPressed: _showAddTransactionDialog,
            )
          : null,
    );
  }
}
