import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:qr_flutter/qr_flutter.dart';

// =====================================
// STOCK MOVE REPORT (GRIDVIEW EDITION)
// =====================================
class StockMoveReport extends StatefulWidget {
  final Map<String, dynamic> profile;
  const StockMoveReport({super.key, required this.profile});

  @override
  State<StockMoveReport> createState() => _StockMoveReportState();
}

class _StockMoveReportState extends State<StockMoveReport> {
  List<dynamic> allHistory = [];
  List<dynamic> filteredHistory = [];
  bool isLoading = true;
  String errorLog = "";
  final searchController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  // Filter status aktif
  Set<String> selectedStatuses = {};

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

  // 1. FUNGSI PEMBERSIH KETERANGAN (JSON TO HUMAN READABLE)
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

  // 2. FUNGSI TARIK DATA DARI SUPABASE
  Future<void> _fetchMoveHistory() async {
    try {
      if (mounted) setState(() => isLoading = true);

      final response = await Supabase.instance.client
          .from('stock_move_history')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        final myToko = widget.profile['toko_id'].toString().toUpperCase();
        final myRole = widget.profile['role']?.toString().toLowerCase() ?? '';

        if (myToko == 'PUSAT' || myRole == 'super_admin') {
          allHistory = response as List<dynamic>;
        } else {
          allHistory = (response as List<dynamic>).where((item) {
            final ke = item['ke_lokasi'].toString().toUpperCase();
            final dari = item['dari_lokasi'].toString().toUpperCase();
            return ke == myToko || dari == myToko;
          }).toList();
        }

        filteredHistory = allHistory;
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

  // 3. FUNGSI FILTER SEARCH & CHIP STATUS
  void _filterHistory() {
    String query = searchController.text.toLowerCase().trim();
    setState(() {
      filteredHistory = allHistory.where((item) {
        String searchString =
            "${item['product_name']} ${item['keterangan']}".toLowerCase();
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

  // FUNGSI 1: KONFIRMASI TERIMA (POPUP & FOTO)
  void _confirmTerima(dynamic item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // FUNGSI 2: PROSES UPDATE DATABASE & STOK CABANG
  Future<void> _prosesTerimaPaket(dynamic task) async {
    // ✅ FORCE REAR CAMERA: Dipaksa buka kamera belakang agar 100% TIDAK MIRROR
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
      await Supabase.instance.client.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes);

      final imgUrl = Supabase.instance.client.storage
          .from('attendance_photos')
          .getPublicUrl(path);

      await Supabase.instance.client
          .from('stock_move_history')
          .update({'status': 'SUCCESS', 'bukti_foto_penerima': imgUrl}).eq(
              'id', task['id']);

      final myToko = widget.profile['toko_id'].toString().toUpperCase();
      String rawItems = task['keterangan'] ?? '';

      if (rawItems.contains('[{')) {
        String jsonPart = rawItems.substring(rawItems.indexOf('[{'));
        List items = jsonDecode(jsonPart);
        for (var itm in items) {
          int qty = int.tryParse(itm['qty'].toString()) ?? 0;
          String barcodeProd = itm['barcode'] ?? '-';
          String namaProd = itm['nama'] ?? '-';

          final existing = await Supabase.instance.client
              .from('products')
              .select()
              .eq('barcode', barcodeProd)
              .eq('toko_id', myToko)
              .maybeSingle();

          if (existing != null) {
            await Supabase.instance.client
                .from('products')
                .update({'stock': (existing['stock'] ?? 0) + qty}).eq(
                    'id', existing['id']);
          } else {
            await Supabase.instance.client.from('products').insert({
              'nama': namaProd,
              'barcode': barcodeProd,
              'stock': qty,
              'toko_id': myToko,
              'harga': itm['harga'] ?? 0,
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
          content: Text("Gagal: $e"), backgroundColor: Colors.redAccent));
      setState(() => isLoading = false);
    }
  }

  // FUNGSI 3: DETAIL POPUP
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
                  "${item['dari_lokasi']} -> ${item['ke_lokasi']}"),
              _detailRow("smr_isi_paket".tr(),
                  _cleanKeterangan(item['keterangan'] ?? '')),
              if (item['status'] == 'WAITING' ||
                  item['status'] == 'TRANSIT') ...[
                const SizedBox(height: 15),
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 15),
                      Text("smr_scan_qr_update".tr(),
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15)),
                        child: QrImageView(
                          data: jsonEncode({
                            "resi": item['product_name'],
                            "tujuan": item['ke_lokasi']
                          }),
                          version: QrVersions.auto,
                          size: 150.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 15),
              const Divider(color: Colors.white24, height: 20),
              Text("smr_bukti_pengirim".tr(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 5),
              _buildFotoBox(item['bukti_foto_pengirim']),
              const SizedBox(height: 15),
              Text("smr_bukti_penerima".tr(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
                      color: Colors.white, fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }

  Widget _buildFotoBox(dynamic url) {
    if (url == null || url.toString().isEmpty || url.toString() == '-') {
      return Text("smr_belum_ada_foto".tr(),
          style: const TextStyle(fontSize: 11, color: Colors.grey));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(url.toString(),
          height: 150,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.broken_image, color: Colors.grey, size: 50)),
    );
  }

  Widget _detailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? badgeColor.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
              color: isActive ? badgeColor : Colors.grey.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          statusLable,
          style: TextStyle(
            color: isActive ? badgeColor : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text("smr_title".tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchMoveHistory)
        ],
      ),
      body: Column(
        children: [
          // BAR PENCARIAN
          Padding(
            padding: const EdgeInsets.all(15),
            child: TextField(
              controller: searchController,
              onChanged: _runSearch,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "smr_cari".tr(),
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                // ✅ FIX: String format tokens diperbaiki ke '{}' agar sinkron dengan data translasi Bos
                Text(
                  "smr_unit"
                      .tr()
                      .replaceFirst('{}', widget.profile['toko_id'].toString())
                      .replaceFirst('{}', filteredHistory.length.toString()),
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterChip('WAITING', Colors.orangeAccent),
                    const SizedBox(width: 10),
                    _buildFilterChip('TRANSIT', Colors.blueAccent),
                    const SizedBox(width: 10),
                    _buildFilterChip('SUCCESS', Colors.green),
                    const SizedBox(width: 10),
                    _buildFilterChip('BATAL', Colors.red),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),

          // IMPLEMENTASI GRIDVIEW UTAMA
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent))
                : errorLog.isNotEmpty
                    ? Center(
                        child: Text("Error: $errorLog",
                            style: const TextStyle(color: Colors.redAccent)))
                    : filteredHistory.isEmpty
                        ? Center(
                            child: Text("smr_kosong".tr(),
                                style: const TextStyle(color: Colors.grey)))
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 5),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 0.9),
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
                                color: Colors.white.withOpacity(0.05),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: Colors.white.withOpacity(0.1))),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("${item['product_name'] ?? '-'}",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                          "${item['jumlah'] ?? 0} PCS\n${item['ke_lokasi'] ?? 'kosong'}",
                                          style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11)),
                                      const Divider(
                                          color: Colors.white10, height: 15),
                                      Text(
                                          "${item['dari_lokasi']} -> ${item['ke_lokasi']}",
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey,
                                              height: 1.3)),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: Text(
                                            _cleanKeterangan(
                                                item['keterangan'] ?? ''),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white70,
                                                fontStyle: FontStyle.italic),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(status,
                                            style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: statusColor)),
                                      ),
                                      Wrap(
                                        spacing: 5,
                                        runSpacing: 5,
                                        children: [
                                          if (amITheSender ||
                                              amITheReceiver ||
                                              myToko == 'PUSAT')
                                            InkWell(
                                              onTap: () => _showDetail(item),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                    border: Border.all(
                                                        color: Colors.grey),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6)),
                                                child: const Icon(
                                                    Icons.info_outline,
                                                    color: Colors.grey,
                                                    size: 14),
                                              ),
                                            ),
                                          if ((status == 'TRANSIT' ||
                                                  status == 'PENDING') &&
                                              amITheReceiver)
                                            InkWell(
                                              onTap: () => _confirmTerima(item),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 6),
                                                decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6)),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.camera_alt,
                                                        size: 12,
                                                        color: Colors.white),
                                                    const SizedBox(width: 4),
                                                    Text("smr_btn_terima".tr(),
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
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
}
