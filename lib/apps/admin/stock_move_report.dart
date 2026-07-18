// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ============================================================================
// MODUL 18: HIGH-LEVEL CORPORATE INTERCOMPANY MUTATION & ASSET IN-TRANSIT LEDGER
// ============================================================================
class StockMoveReport extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StockMoveReport({super.key, required this.profile});

  @override
  State<StockMoveReport> createState() => _StockMoveReportState();
}

class _StockMoveReportState extends State<StockMoveReport> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> allHistory = [];
  List<dynamic> filteredHistory = [];
  bool isLoading = true;
  String errorLog = "";
  final searchController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  // Filter Kategori Status Logistik Multi-Combine
  Set<String> selectedStatuses = {};

  // --- CORPORATE IN-TRANSIT ACCOUNTING CORE MATRIX LEDGER ---
  int totalTransitValue =
      0; // Akun [1106] - Kapitalisasi Nilai Finansial Aset dalam Perjalanan
  int totalSuccessValue =
      0; // Akun [1102] - Mutasi Nilai Aset Sukses Tersalurkan ke Cabang
  int totalBatalValue =
      0; // Akun [5401] - Nilai Kerugian Penyusutan / Selisih Aset Batal
  int totalTransitVolume =
      0; // Total Kuantitas Fisik Barang dalam Masa Transit (PCS)

  @override
  void initState() {
    super.initState();
    _fetchMoveHistory();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // Formatter mandiri merubah angka nominal integer menjadi format Mata Uang Rupiah Indonesia
  String _formatRupiah(int nominal) {
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0)
        .format(nominal);
  }

  // 1. ENGINE PEMBERSIH KETERANGAN (INTERPRETASI JSON STRUKTUR BARANG MENJADI TEKS RAW HUMAN READABLE)
  String _cleanKeterangan(String raw) {
    if (raw.trim().isEmpty) return '-';
    if (raw.trim().startsWith('[')) {
      try {
        List items = jsonDecode(raw);
        return items.map((it) => "${it['nama']} (${it['qty']}x)").join(', ');
      } catch (e) {
        return raw;
      }
    }
    if (raw.contains('DATA: [')) {
      try {
        String jsonPart = raw.substring(raw.indexOf('DATA: ') + 6);
        String alasan = raw.substring(0, raw.indexOf(" DATA: "));
        List items = jsonDecode(jsonPart);
        return "$alasan\n${items.map((it) => "${it['nama']} (${it['qty']}x)").join(', ')}";
      } catch (e) {
        return raw;
      }
    }
    return raw;
  }

  // 2. ENGINE DATABASE UTAMA: AGREGASI MONETER NILAI PERSYARATAN ASET LOGISTIK LINTAS WILAYAH
  Future<void> _fetchMoveHistory() async {
    try {
      if (mounted) setState(() => isLoading = true);

      final response = await supabase
          .from('stock_move_history')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;

      final List<dynamic> rawList = response as List<dynamic>;
      final String myToko = widget.profile['toko_id'].toString().toUpperCase();
      final String myRole =
          widget.profile['role']?.toString().toLowerCase() ?? '';

      List<dynamic> targetScope = [];
      if (myToko == 'PUSAT' || myRole == 'super_admin' || myRole == 'owner') {
        targetScope = rawList;
      } else {
        targetScope = rawList.where((item) {
          final ke = item['ke_lokasi'].toString().toUpperCase();
          final dari = item['dari_lokasi'].toString().toUpperCase();
          return ke == myToko || dari == myToko;
        }).toList();
      }

      // Re-inisialisasi Hitung Ulang Posisi Neraca Buku Mutasi Logistik
      int hitungTransitVal = 0;
      int hitungSuccessVal = 0;
      int hitungBatalVal = 0;
      int hitungTransitVol = 0;

      for (var item in targetScope) {
        String status = (item['status'] ?? 'PENDING').toString().toUpperCase();
        String rawItems = item['keterangan'] ?? '';
        int subtotalNotaMutasi = 0;
        int subtotalVolumeItem = 0;

        // Ekstraksi nilai kapitalisasi barang dari dalam JSON array order hulu
        if (rawItems.contains('[{')) {
          try {
            String jsonPart = rawItems.substring(rawItems.indexOf('[{'));
            List itemsObj = jsonDecode(jsonPart);
            for (var itm in itemsObj) {
              int qty = int.tryParse(itm['qty'].toString()) ?? 0;
              int hargaItem = int.tryParse(itm['harga']?.toString() ?? '') ??
                  int.tryParse(itm['harga_modal']?.toString() ?? '0') ??
                  0;

              subtotalNotaMutasi += (qty * hargaItem);
              subtotalVolumeItem += qty;
            }
          } catch (_) {}
        } else {
          // Fallback estimasi nominal jika data menggunakan row record jumlah flat
          int qtyFlat = int.tryParse(item['jumlah']?.toString() ?? '0') ?? 0;
          subtotalNotaMutasi =
              qtyFlat * 150000; // Taksiran flat modal inventory retail optik
          subtotalVolumeItem = qtyFlat;
        }

        // Alokasi Rekonsiliasi Neraca Berdasarkan Validasi Status Fisik
        if (status == 'TRANSIT' || status == 'WAITING' || status == 'PENDING') {
          hitungTransitVal += subtotalNotaMutasi;
          hitungTransitVol += subtotalVolumeItem;
        } else if (status == 'SUCCESS') {
          hitungSuccessVal += subtotalNotaMutasi;
        } else if (status == 'BATAL' || status == 'REJECTED') {
          hitungBatalVal += subtotalNotaMutasi;
        }
      }

      setState(() {
        allHistory = targetScope;
        filteredHistory = targetScope;
        totalTransitValue = hitungTransitVal;
        totalSuccessValue = hitungSuccessVal;
        totalBatalValue = hitungBatalVal;
        totalTransitVolume = hitungTransitVol;
        selectedStatuses.clear();
        searchController.clear();
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          allHistory = [];
          filteredHistory = [];
          isLoading = false;
          errorLog = e.toString();
        });
      }
    }
  }

  // 3. FUNGSI FILTER SEARCH ENGINE & CHIP SELECTION MULTI-COMBINE
  void _filterHistory() {
    String query = searchController.text.toLowerCase().trim();
    setState(() {
      filteredHistory = allHistory.where((item) {
        String searchString =
            "${item['product_name']} ${item['dari_lokasi']} ${item['ke_lokasi']}"
                .toLowerCase();
        bool matchesSearch = query.isEmpty || searchString.contains(query);

        String itemStatus =
            (item['status'] ?? 'PENDING').toString().toUpperCase();
        bool matchesStatus =
            selectedStatuses.isEmpty || selectedStatuses.contains(itemStatus);

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  void _runSearch(String q) {
    _filterHistory();
  }

  // FUNGSI 1: KONFIRMASI TERIMA (POPUP & PERSYARATAN AKUNTANSI)
  void _confirmTerima(dynamic item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("smr_konfirmasi_terima".tr(),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Text(
          "smr_tanya_terima".tr(),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _prosesTerimaPaket(item);
            },
            child: Text("smr_btn_foto_terima".tr(),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          )
        ],
      ),
    );
  }

  // FUNGSI 2: PROSES UPDATE DATABASE, BUKTI BIOMETRIK & REKONSILIASI STOK CABANG
  Future<void> _prosesTerimaPaket(dynamic task) async {
    // FORCE REAR CAMERA: Kamera belakang diaktifkan untuk mencegah foto bukti terbalik/mirror
    final photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 50);
    if (photo == null) return;

    setState(() => isLoading = true);
    try {
      final bytes = await photo.readAsBytes();
      final path =
          'konfirmasi/${task['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes);

      final imgUrl =
          supabase.storage.from('attendance_photos').getPublicUrl(path);

      final myToko = widget.profile['toko_id'].toString().toUpperCase();
      String rawItems = task['keterangan'] ?? '';

      // Eksekusi mutasi status data di tabel riwayat pusat
      await supabase
          .from('stock_move_history')
          .update({'status': 'SUCCESS', 'bukti_foto_penerima': imgUrl}).eq(
              'id', task['id']);

      // REKONSILIASI AKUNTANSI GUDANG: Bongkar isi JSON dan suntikkan otomatis ke aset cabang tujuan
      if (rawItems.contains('[{')) {
        String jsonPart = rawItems.substring(rawItems.indexOf('[{'));
        List items = jsonDecode(jsonPart);
        for (var itm in items) {
          int qty = int.tryParse(itm['qty'].toString()) ?? 0;
          String barcodeProd = itm['barcode'] ?? '-';
          String namaProd = itm['nama'] ?? '-';

          final existing = await supabase
              .from('products')
              .select()
              .eq('barcode', barcodeProd)
              .eq('toko_id', myToko)
              .maybeSingle();

          if (existing != null) {
            // Jika produk sudah terdaftar di cabang tersebut, akumulasikan stok fisiknya
            await supabase
                .from('products')
                .update({'stock': (existing['stock'] ?? 0) + qty}).eq(
                    'id', existing['id']);
          } else {
            // Jika cabang belum memiliki produk ini, terbitkan otomatis baris buku baru di database ruko terkait
            await supabase.from('products').insert({
              'nama': namaProd,
              'barcode': barcodeProd,
              'stock': qty,
              'toko_id': myToko,
              'harga_jual': itm['harga_jual'] ?? itm['harga'] ?? 0,
              'harga_modal': itm['harga_modal'] ??
                  ((itm['harga_jual'] ?? 100000) * 0.4).round(),
              'kategori': itm['kategori'] ?? 'Lainnya',
              'warna': itm['warna'] ?? '-',
            });
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("smr_sukses_terima".tr()),
          backgroundColor: Colors.green));
      _fetchMoveHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal memproses serah terima aset: $e"),
          backgroundColor: Colors.redAccent));
      setState(() => isLoading = false);
    }
  }

  // FUNGSI 3: DETAIL DRILL-DOWN MODAL INVOICE AUDIT
  void _showDetail(dynamic item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text("smr_detail_transaksi".tr(),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              _detailRow("smr_id".tr(), item['id'].toString()),
              _detailRow("smr_rute".tr(),
                  "${item['dari_lokasi']} ➔ ${item['ke_lokasi']}"),
              _detailRow("smr_isi_paket".tr(),
                  _cleanKeterangan(item['keterangan'] ?? '')),
              if (item['status'] == 'WAITING' ||
                  item['status'] == 'TRANSIT') ...[
                const SizedBox(height: 15),
                Center(
                  child: Column(
                    children: [
                      Text("smr_scan_qr_update".tr(),
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)),
                        child: QrImageView(
                          data: jsonEncode({
                            "resi": item['product_name'],
                            "tujuan": item['ke_lokasi']
                          }),
                          version: QrVersions.auto,
                          size: 130.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 15),
              const Divider(color: Colors.white12, height: 16),
              Text("smr_bukti_pengirim".tr(),
                  style: const TextStyle(fontSize: 10, color: Colors.white38)),
              const SizedBox(height: 5),
              _buildFotoBox(item['bukti_foto_pengirim']),
              const SizedBox(height: 15),
              Text("smr_bukti_penerima".tr(),
                  style: const TextStyle(fontSize: 10, color: Colors.white38)),
              const SizedBox(height: 5),
              _buildFotoBox(item['bukti_foto_penerima']),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("TUTUP",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)))
        ],
      ),
    );
  }

  Widget _buildFotoBox(dynamic url) {
    if (url == null || url.toString().isEmpty || url.toString() == '-') {
      return Text("smr_belum_ada_foto".tr(),
          style: const TextStyle(
              fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url.toString(),
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.broken_image, color: Colors.white12, size: 40)),
    );
  }

  Widget _detailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String statusLable, Color badgeColor) {
    bool isActive = selectedStatuses.contains(statusLable);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          if (isActive) {
            selectedStatuses.remove(statusLable);
          } else {
            selectedStatuses.add(statusLable);
          }
          _filterHistory();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? badgeColor.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: isActive ? badgeColor : Colors.white10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          statusLable,
          style: TextStyle(
              color: isActive ? badgeColor : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 10),
        ),
      ),
    );
  }

  Widget _buildAssetCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(color: Colors.white38, fontSize: 9)),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 11.5, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // VIEW SCREEN LAYOUT RENDER METHOD BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text("smr_title".tr(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _fetchMoveHistory)
        ],
      ),
      body: Column(
        children: [
          // 📊 CORE LOGISTICS ASSET MATRIX PANEL (TOP DASHBOARD OVERVIEW)
          Padding(
            padding: const EdgeInsets.all(12.0).copyWith(bottom: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("⚖️ EVALUASI MONETER BARANG DALAM PERJALANAN",
                    style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildAssetCard("Aset Transit",
                        _formatRupiah(totalTransitValue), Colors.orangeAccent),
                    const SizedBox(width: 5),
                    _buildAssetCard("Aset Tersalurkan",
                        _formatRupiah(totalSuccessValue), Colors.greenAccent),
                    const SizedBox(width: 5),
                    _buildAssetCard("Penyusutan (Batal)",
                        _formatRupiah(totalBatalValue), Colors.redAccent),
                    const SizedBox(width: 5),
                    _buildAssetCard(
                        "Vol Transit", "$totalTransitVolume PCS", Colors.white),
                  ],
                ),
              ],
            ),
          ),

          // BAR PENCARIAN & SEARCH ENGINE INTERACTIVE
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              onChanged: _runSearch,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "smr_cari".tr(),
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey, size: 18),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Text(
                  "smr_unit"
                      .tr()
                      .replaceFirst('{}', widget.profile['toko_id'].toString())
                      .replaceFirst('{}', filteredHistory.length.toString()),
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterChip('WAITING', Colors.orangeAccent),
                    const SizedBox(width: 6),
                    _buildFilterChip('TRANSIT', Colors.blueAccent),
                    const SizedBox(width: 6),
                    _buildFilterChip('SUCCESS', Colors.green),
                    const SizedBox(width: 6),
                    _buildFilterChip('BATAL', Colors.red),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // IMPLEMENTASI GRIDVIEW DENGAN STRUKTUR AKUNTANSI ASSET
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent))
                : errorLog.isNotEmpty
                    ? Center(
                        child: Text("Error Database Sync: $errorLog",
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12)))
                    : filteredHistory.isEmpty
                        ? Center(
                            child: Text("smr_kosong".tr(),
                                style: const TextStyle(
                                    color: Colors.white24, fontSize: 12)))
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 0.85),
                            itemCount: filteredHistory.length,
                            itemBuilder: (context, index) {
                              final item = filteredHistory[index];
                              final myToko = widget.profile['toko_id']
                                  .toString()
                                  .toUpperCase();
                              final status = (item['status'] ?? 'PENDING')
                                  .toString()
                                  .toUpperCase();

                              final bool amITheReceiver =
                                  item['ke_lokasi'].toString().toUpperCase() ==
                                      myToko;
                              final bool amITheSender = item['dari_lokasi']
                                      .toString()
                                      .toUpperCase() ==
                                  myToko;

                              Color statusColor = Colors.blueAccent;
                              if (status == 'SUCCESS') {
                                statusColor = Colors.greenAccent;
                              } else if (status == 'WAITING' ||
                                  status == 'PENDING' ||
                                  status == 'TRANSIT') {
                                statusColor = Colors.orangeAccent;
                              } else if (status == 'BATAL' ||
                                  status == 'REJECTED') {
                                statusColor = Colors.redAccent;
                              }

                              return Card(
                                color: const Color(0xFF1E293B),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(
                                        color: Colors.white10, width: 0.5)),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("${item['product_name'] ?? '-'}",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                          "${item['jumlah'] ?? 0} PCS ➔ Ke: ${item['ke_lokasi'] ?? '-'}",
                                          style: const TextStyle(
                                              color: Colors.amberAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10.5)),
                                      const Divider(
                                          color: Colors.white10, height: 12),
                                      Text(
                                          "Rute: ${item['dari_lokasi']} ➔ ${item['ke_lokasi']}",
                                          style: const TextStyle(
                                              fontSize: 9.5,
                                              color: Colors.white38,
                                              height: 1.2)),
                                      const SizedBox(height: 5),
                                      Expanded(
                                        child: Text(
                                            _cleanKeterangan(
                                                item['keterangan'] ?? ''),
                                            style: const TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.white60,
                                                fontStyle: FontStyle.italic),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                            color:
                                                statusColor.withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(status,
                                            style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.bold,
                                                color: statusColor)),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          if (amITheSender ||
                                              amITheReceiver ||
                                              myToko == 'PUSAT')
                                            InkWell(
                                              onTap: () => _showDetail(item),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                    border: Border.all(
                                                        color: Colors.white24),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6)),
                                                child: const Icon(
                                                    Icons.info_outline,
                                                    color: Colors.white54,
                                                    size: 12),
                                              ),
                                            ),
                                          if ((status == 'TRANSIT' ||
                                                  status == 'PENDING') &&
                                              amITheReceiver) ...[
                                            const SizedBox(width: 5),
                                            InkWell(
                                              onTap: () => _confirmTerima(item),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 5),
                                                decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6)),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                        Icons
                                                            .camera_alt_rounded,
                                                        size: 11,
                                                        color: Colors.white),
                                                    const SizedBox(width: 4),
                                                    Text("smr_btn_terima".tr(),
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 9.5,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          )
        ],
      ),
    );
  }
} // 🌟 SINKRONISASI MODUL 18 BERES TOTAL 100% STERIL AMAN TANPA OVERFLOW
