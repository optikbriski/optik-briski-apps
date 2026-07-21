// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/logistics/request_order_service.dart';
import '../../shared/safe_image_picker.dart';

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

  // Filter jenis mutasi: all | restock (DO) | request (RO) | retur
  String selectedKind = 'all';

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

  /// Klasifikasi: restock (DO), request (RO), retur — termasuk data legacy OUTGOING.
  String _moveKind(dynamic item) {
    final tipe = (item['tipe'] ?? '').toString().toUpperCase();
    final resi = (item['product_name'] ?? '').toString().toUpperCase();
    final ket = (item['keterangan'] ?? '').toString();

    if (tipe == 'RETUR' || resi.startsWith('RET-')) return 'retur';
    if (tipe == 'REQUEST' ||
        resi.startsWith('RO-') ||
        ket.contains('RequestOrder#')) {
      return 'request';
    }
    if (tipe == 'DELIVERY' || resi.startsWith('DO-')) return 'restock';
    return 'restock';
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'request':
        return 'Request';
      case 'retur':
        return 'Retur';
      case 'restock':
      default:
        return 'Restock';
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'request':
        return Colors.cyanAccent;
      case 'retur':
        return Colors.purpleAccent;
      case 'restock':
      default:
        return Colors.amberAccent;
    }
  }

  String _emptyMessageForKind() {
    switch (selectedKind) {
      case 'restock':
        return 'smr_kosong_restock'.tr();
      case 'request':
        return 'smr_kosong_request'.tr();
      case 'retur':
        return 'smr_kosong_retur'.tr();
      default:
        return 'smr_kosong'.tr();
    }
  }

  void _recomputeKpis(List<dynamic> scope) {
    int hitungTransitVal = 0;
    int hitungSuccessVal = 0;
    int hitungBatalVal = 0;
    int hitungTransitVol = 0;

    for (var item in scope) {
      String status = (item['status'] ?? 'PENDING').toString().toUpperCase();
      String rawItems = item['keterangan'] ?? '';
      int subtotalNotaMutasi = 0;
      int subtotalVolumeItem = 0;

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
        int qtyFlat = int.tryParse(item['jumlah']?.toString() ?? '0') ?? 0;
        subtotalNotaMutasi = qtyFlat * 150000;
        subtotalVolumeItem = qtyFlat;
      }

      if (status == 'TRANSIT' || status == 'WAITING' || status == 'PENDING') {
        hitungTransitVal += subtotalNotaMutasi;
        hitungTransitVol += subtotalVolumeItem;
      } else if (status == 'SUCCESS') {
        hitungSuccessVal += subtotalNotaMutasi;
      } else if (status == 'BATAL' || status == 'REJECTED') {
        hitungBatalVal += subtotalNotaMutasi;
      }
    }

    totalTransitValue = hitungTransitVal;
    totalSuccessValue = hitungSuccessVal;
    totalBatalValue = hitungBatalVal;
    totalTransitVolume = hitungTransitVol;
  }

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

      setState(() {
        allHistory = targetScope;
        selectedKind = 'all';
        selectedStatuses.clear();
        searchController.clear();
        errorLog = '';
        isLoading = false;
      });
      _filterHistory();
    } catch (e) {
      if (mounted) {
        setState(() {
          allHistory = [];
          filteredHistory = [];
          totalTransitValue = 0;
          totalSuccessValue = 0;
          totalBatalValue = 0;
          totalTransitVolume = 0;
          isLoading = false;
          errorLog = e.toString();
        });
      }
    }
  }

  // 3. FUNGSI FILTER: jenis (DO/RO/Retur) + status + pencarian
  void _filterHistory() {
    String query = searchController.text.toLowerCase().trim();
    setState(() {
      filteredHistory = allHistory.where((item) {
        final kind = _moveKind(item);
        final matchesKind =
            selectedKind == 'all' || kind == selectedKind;

        String searchString =
            "${item['product_name']} ${item['dari_lokasi']} ${item['ke_lokasi']} ${item['keterangan']}"
                .toLowerCase();
        bool matchesSearch = query.isEmpty || searchString.contains(query);

        String itemStatus =
            (item['status'] ?? 'PENDING').toString().toUpperCase();
        bool matchesStatus =
            selectedStatuses.isEmpty || selectedStatuses.contains(itemStatus);

        return matchesKind && matchesSearch && matchesStatus;
      }).toList();
      _recomputeKpis(filteredHistory);
    });
  }

  static const _bg = Color(0xFF0B1220);
  static const _panel = Color(0xFF121A2B);
  static const _panelSoft = Color(0xFF1A2438);
  static const _line = Color(0xFF2A3548);

  int _countKind(String kind) {
    if (kind == 'all') return allHistory.length;
    return allHistory.where((e) => _moveKind(e) == kind).length;
  }

  void _selectKind(String kind) {
    setState(() => selectedKind = kind);
    _filterHistory();
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
    // Desktop/web: fall back ke galeri (image_picker butuh cameraDelegate).
    final photo = await pickImageSafe(
      picker: picker,
      context: context,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 50,
    );
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
      final verifierId =
          widget.profile['id']?.toString() ??
              widget.profile['user_id']?.toString() ??
              supabase.auth.currentUser?.id ??
              '';
      final verifierName = widget.profile['nama']?.toString() ??
          widget.profile['full_name']?.toString() ??
          'Admin';

      await supabase.from('stock_move_history').update({
        'status': 'SUCCESS',
        'bukti_foto_penerima': imgUrl,
        'verified_by': verifierId,
        'verified_by_name': verifierName,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', task['id']);

      // Sinkron Request Order yang tertaut ke mutasi ini → SUCCESS
      try {
        await RequestOrderService().markSuccessFromMove(
          stockMoveId: task['id'].toString(),
          resi: task['product_name']?.toString(),
        );
      } catch (_) {}

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
              if ((item['verified_by_name'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty ||
                  item['verified_at'] != null) ...[
                const SizedBox(height: 12),
                _detailRow(
                  'Diterima oleh',
                  item['verified_by_name']?.toString() ?? '-',
                ),
                _detailRow(
                  'Waktu terima',
                  () {
                    final raw = item['verified_at']?.toString();
                    if (raw == null || raw.isEmpty) return '-';
                    final dt = DateTime.tryParse(raw)?.toLocal();
                    if (dt == null) return raw;
                    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
                  }(),
                ),
              ],
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

  Widget _buildStatusChip(String statusLabel, Color badgeColor) {
    final isActive = selectedStatuses.contains(statusLabel);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() {
            if (isActive) {
              selectedStatuses.remove(statusLabel);
            } else {
              selectedStatuses.add(statusLabel);
            }
          });
          _filterHistory();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? badgeColor.withOpacity(0.16) : _panelSoft,
            border: Border.all(
                color: isActive ? badgeColor.withOpacity(0.7) : _line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              color: isActive ? badgeColor : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindTile({
    required String kind,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final active = selectedKind == kind;
    final count = _countKind(kind);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: active ? color.withOpacity(0.14) : _panelSoft,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _selectKind(kind),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? color.withOpacity(0.55) : Colors.transparent,
                ),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      size: 16,
                      color: active ? color : const Color(0xFF94A3B8)),
                  const SizedBox(height: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? color : const Color(0xFF94A3B8),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _moveCard(dynamic item) {
    final myToko = widget.profile['toko_id'].toString().toUpperCase();
    final status = (item['status'] ?? 'PENDING').toString().toUpperCase();
    final kind = _moveKind(item);
    final kindColor = _kindColor(kind);
    final amITheReceiver =
        item['ke_lokasi'].toString().toUpperCase() == myToko;
    final amITheSender =
        item['dari_lokasi'].toString().toUpperCase() == myToko;

    Color statusColor = Colors.blueAccent;
    if (status == 'SUCCESS') {
      statusColor = const Color(0xFF4ADE80);
    } else if (status == 'WAITING' ||
        status == 'PENDING' ||
        status == 'TRANSIT') {
      statusColor = const Color(0xFFFBBF24);
    } else if (status == 'BATAL' || status == 'REJECTED') {
      statusColor = const Color(0xFFF87171);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['product_name'] ?? '-'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _miniBadge(_kindLabel(kind), kindColor),
                const SizedBox(width: 6),
                _miniBadge(status, statusColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${item['jumlah'] ?? 0} PCS  ·  ${item['dari_lokasi'] ?? '-'} → ${item['ke_lokasi'] ?? '-'}',
              style: TextStyle(
                color: kindColor.withOpacity(0.95),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _cleanKeterangan(item['keterangan'] ?? ''),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (amITheSender || amITheReceiver || myToko == 'PUSAT')
                  TextButton.icon(
                    onPressed: () => _showDetail(item),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 16),
                    label: const Text('Detail',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                const Spacer(),
                if ((status == 'WAITING' ||
                        status == 'TRANSIT' ||
                        status == 'PENDING') &&
                    amITheReceiver)
                  FilledButton.icon(
                    onPressed: () => _confirmTerima(item),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 15),
                    label: Text("smr_btn_terima".tr(),
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
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
    final unitLabel = "smr_unit"
        .tr()
        .replaceFirst('{}', widget.profile['toko_id'].toString())
        .replaceFirst('{}', filteredHistory.length.toString());

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          children: [
            Text("smr_title".tr(),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Text("smr_subtitle".tr(),
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _fetchMoveHistory,
            style: IconButton.styleFrom(
              backgroundColor: _panelSoft,
              side: const BorderSide(color: _line),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Jenis mutasi — akses utama (dengan count)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _line),
              ),
              child: Row(
                children: [
                  _kindTile(
                    kind: 'all',
                    label: 'Semua',
                    icon: Icons.layers_rounded,
                    color: Colors.white70,
                  ),
                  _kindTile(
                    kind: 'restock',
                    label: 'Restock',
                    icon: Icons.local_shipping_rounded,
                    color: const Color(0xFFFBBF24),
                  ),
                  _kindTile(
                    kind: 'request',
                    label: 'Request',
                    icon: Icons.playlist_add_check_rounded,
                    color: const Color(0xFF22D3EE),
                  ),
                  _kindTile(
                    kind: 'retur',
                    label: 'Retur',
                    icon: Icons.undo_rounded,
                    color: const Color(0xFFC084FC),
                  ),
                ],
              ),
            ),
          ),

          // KPI ringkas 1 baris
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text("smr_kpi_title".tr(),
                      style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                ),
                Row(
                  children: [
                    _kpiPill('Transit', _formatRupiah(totalTransitValue),
                        const Color(0xFFFBBF24)),
                    _kpiPill('Tersalur', _formatRupiah(totalSuccessValue),
                        const Color(0xFF4ADE80)),
                    _kpiPill('Batal', _formatRupiah(totalBatalValue),
                        const Color(0xFFF87171)),
                    _kpiPill('Vol', '$totalTransitVolume PCS', Colors.white),
                  ],
                ),
              ],
            ),
          ),

          // Search + status dalam satu panel
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: _runSearch,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "smr_cari".tr(),
                      hintStyle: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF94A3B8), size: 20),
                      filled: true,
                      fillColor: _panelSoft,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          unitLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF60A5FA),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selectedStatuses.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => selectedStatuses.clear());
                            _filterHistory();
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: const Color(0xFF94A3B8),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('Reset status',
                              style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildStatusChip('WAITING', const Color(0xFFFBBF24)),
                      _buildStatusChip('TRANSIT', const Color(0xFF60A5FA)),
                      _buildStatusChip('SUCCESS', const Color(0xFF4ADE80)),
                      _buildStatusChip('BATAL', const Color(0xFFF87171)),
                      _buildStatusChip('PENDING', const Color(0xFFF59E0B)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF60A5FA)))
                : errorLog.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text("Error Database Sync: $errorLog",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFF87171), fontSize: 12)),
                        ))
                    : filteredHistory.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: _panel,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: _line),
                                    ),
                                    child: const Icon(
                                        Icons.inventory_2_outlined,
                                        color: Color(0xFF64748B),
                                        size: 28),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    _emptyMessageForKind(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                            itemCount: filteredHistory.length,
                            itemBuilder: (context, index) =>
                                _moveCard(filteredHistory[index]),
                          ),
          ),
        ],
      ),
    );
  }
}
