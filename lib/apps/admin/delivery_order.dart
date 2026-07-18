import 'dart:convert'; // ✅ AMAN: Mengaktifkan fungsi jsonEncode untuk bundle payload barang
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; // ✅ AMAN: Untuk menangkap foto bukti surat jalan pengiriman
import 'package:easy_localization/easy_localization.dart';
import 'package:qr_flutter/qr_flutter.dart'; // Siapkan import ini untuk pratinjau resi di part akhir nanti

// Shortcut pintas client Supabase khusus file DO ini
final supabase = Supabase.instance.client;

// ============================================================================
// MODUL 6 DELIVERY ORDER & TRANSAKSI GANTUNG (FULL UNIFIED) - PART 1 OF 6
// ============================================================================
class OutgoingOperation extends StatefulWidget {
  final Map<String, dynamic> profile;
  const OutgoingOperation({super.key, required this.profile});

  @override
  State<OutgoingOperation> createState() => _OutgoingOperationState();
}

class _OutgoingOperationState extends State<OutgoingOperation> {
  String? selectedToko;
  final searchController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  List<String> listToko = [];
  List<dynamic> allProdukPusat = [];
  List<dynamic> listProdukPusat = [];
  List<dynamic> filteredProduk = [];

  bool isFiltering = false;
  bool isLoading = true;
  bool isProcessing = false;

  Map<String, int> selectedItems = {};
  Map<String, TextEditingController> qtyControllers = {};

  // Variabel penyimpan filter kategori yang sedang aktif
  Set<String> selectedCategories = {};

  // Fungsi dinamis pembuat tombol filter Kategori (Frame / Lensa / Lainnya)
  Widget _buildCategoryChip(String category, Color badgeColor) {
    bool isActive = selectedCategories.contains(category);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          if (isActive) {
            selectedCategories.remove(category);
          } else {
            selectedCategories.add(category);
          }
        });
        filterProduk(); // Fungsi filter akan di-inject di Part 2
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
          category,
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
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    searchController.dispose();
    for (var ctrl in qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // 1. MEMUAT DAFTAR CABANG TUJUAN SECARA DINAMIS DARI DATABASE
  Future<void> loadData() async {
    if (mounted) setState(() => isLoading = true);
    try {
      final resToko = await supabase.from('profiles').select('toko_id');

      // Filter nama toko agar bernilai unik dan mengeliminasi nama PUSAT
      final unik = (resToko as List)
          .map((e) => e['toko_id']?.toString() ?? "")
          .where((t) => t.isNotEmpty && t != 'PUSAT')
          .toSet()
          .toList();

      await _fetchProduk();

      if (mounted) {
        setState(() {
          listToko = unik;
          if (listToko.isNotEmpty) selectedToko = listToko.first;
        });
      }
    } catch (e) {
      debugPrint("Load Jaringan Cabang Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. MENARIK SELURUH ITEM INVENTORI YANG TERSEDIA DI PUSAT
  Future<void> _fetchProduk() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        isFiltering = false;
      });
    }
    try {
      final response = await supabase
          .from('products')
          .select()
          .order('nama', ascending: true);

      if (mounted) {
        setState(() {
          listProdukPusat = response as List<dynamic>;
          allProdukPusat = List.from(listProdukPusat);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal ambil data database PUSAT: $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  // 1. FUNGSI LOGIKA FILTER & PENCARIAN MULTI-KATEGORI SECARA INSTAN
  void filterProduk() {
    String query = searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty && selectedCategories.isEmpty) {
        isFiltering = false;
        filteredProduk = [];
      } else {
        isFiltering = true;
        filteredProduk = listProdukPusat.where((item) {
          // A. Jalur Pencarian Teks Nama Produk
          String namaProduk = (item['nama'] ?? '').toString().toLowerCase();
          bool matchesSearch = query.isEmpty || namaProduk.contains(query);

          // B. Jalur Filter Berdasarkan Tombol Kategori Aktif
          String itemCat =
              (item['kategori'] ?? '').toString().toLowerCase().trim();
          bool matchesCategory = selectedCategories.isEmpty ||
              selectedCategories
                  .any((cat) => cat.toLowerCase().trim() == itemCat);

          return matchesSearch && matchesCategory;
        }).toList();
      }
    });
  }

  // 2. FUNGSI MEMILIH / MEMBATALKAN PILIHAN ITEM KE DALAM KERANJANG DO
  void _toggleItem(dynamic item) {
    if (item == null) return;
    String id = item['id'].toString();
    int stokTersedia = int.tryParse(item['stock']?.toString() ?? '0') ?? 0;

    if (stokTersedia <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("do_stok_kosong".tr()),
          backgroundColor: Colors.redAccent));
      return;
    }

    setState(() {
      if (selectedItems.containsKey(id)) {
        selectedItems.remove(id);
      } else {
        selectedItems[id] = 1;
        qtyControllers[id] ??= TextEditingController(text: '1');
      }
    });
  }

  // 3. FUNGSI UPDATE JUMLAH ITEM MENGGUNAKAN TOMBOL PLUS / MINUS STEPPER
  void _updateQty(String id, int delta, int maxStok) {
    setState(() {
      int current = selectedItems[id] ?? 0;
      int next = current + delta;

      if (next <= 0) {
        selectedItems.remove(id);
      } else if (next > maxStok) {
        selectedItems[id] = maxStok;
        qtyControllers[id]?.text = maxStok.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "do_maksimal_stok".tr().replaceAll('{}', maxStok.toString())),
            backgroundColor: Colors.orange));
      } else {
        selectedItems[id] = next;
        qtyControllers[id]?.text = next.toString();
      }
    });
  }

  // 4. FUNGSI VALIDASI AMAN UNTUK MEMASUKKAN ANGKA QUANTITY SECARA MANUAL
  void _setQtyManual(String id, String val, int maxStok) {
    if (val.isEmpty)
      return; // Biarkan kosong sejenak jika user sedang menekan backspace
    int parsed = int.tryParse(val) ?? 1;

    if (parsed > maxStok) {
      setState(() {
        selectedItems[id] = maxStok;
        qtyControllers[id]?.text = maxStok.toString();
        // Kembalikan posisi kursor teks ke bagian paling ujung kanan agar ketikan tidak patah
        qtyControllers[id]?.selection = TextSelection.fromPosition(
            TextPosition(offset: qtyControllers[id]!.text.length));
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "do_maksimal_stok".tr().replaceAll('{}', maxStok.toString())),
          backgroundColor: Colors.orange));
    } else if (parsed <= 0) {
      setState(() {
        selectedItems[id] = 1;
        qtyControllers[id]?.text = '1';
        qtyControllers[id]?.selection =
            TextSelection.fromPosition(const TextPosition(offset: 1));
      });
    } else {
      setState(() {
        selectedItems[id] = parsed;
      });
    }
  }

  // 5. BUNDLE DATA KERANJANG MENJADI PAYLOAD JSON UNTUK DISIMPAN KE SUPABASE
  String buildCartJson() {
    List<Map<String, dynamic>> detailItems = [];
    for (var entry in selectedItems.entries) {
      final prod =
          allProdukPusat.firstWhere((p) => p['id'].toString() == entry.key);
      detailItems.add({
        'id_produk': prod['id'],
        'nama': prod['nama'] ?? '-',
        'kategori': prod['kategori'] ?? '-',
        'sub_kategori': prod['sub_kategori'] ?? '-',
        'warna': prod['warna'] ?? '-',
        'jenis_lensa': prod['jenis_lensa'] ?? '-',
        'sph_r': prod['sph_r'] ?? 0,
        'cyl_r': prod['cyl_r'] ?? 0,
        'add_r': prod['add_r'] ?? 0,
        'barcode': prod['barcode'] ?? '-',
        'qty': entry.value
      });
    }
    return jsonEncode(detailItems);
  }

  // 6. MENGHITUNG TOTAL BARANG YANG AKAN MASUK SURAT JALAN PENGIRIMAN
  int _calculateTotalQty() {
    return selectedItems.values.fold(0, (sum, item) => sum + item);
  }

  // 1. FUNGSI DATABASE: VALIDASI STOK, POTONG STOK PUSAT, & SIMPAN KE DRAF GANTUNG
  Future<void> saveDraft() async {
    if (selectedToko == null || selectedItems.isEmpty) return;
    setState(() => isProcessing = true);

    try {
      // Step A: Validasi ketersediaan stok fisik di Gudang Pusat satu per satu
      for (var entry in selectedItems.entries) {
        final res = await supabase
            .from('products')
            .select('stock, nama')
            .eq('id', entry.key)
            .single();

        int currentStock = int.tryParse(res['stock'].toString()) ?? 0;
        if (currentStock < entry.value) {
          throw "Stok ${res['nama']} tidak mencukupi untuk dialokasikan!";
        }

        // Kurangi stok di PUSAT karena barang sudah disisihkan untuk draf ini
        await supabase
            .from('products')
            .update({'stock': currentStock - entry.value}).eq('id', entry.key);
      }

      // Step B: Masukkan data bundle keranjang ke tabel transaksi gantung
      await supabase.from('draft_pengiriman').insert({
        'tujuan': selectedToko,
        'items': buildCartJson(),
        'created_at': DateTime.now().toIso8601String()
      });

      if (mounted) {
        setState(() {
          selectedItems.clear();
          qtyControllers.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("do_sukses_draf".tr()),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Gagal menyimpan draf: $e"),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
        _fetchProduk(); // Sinkronisasi ulang tampilan stok terbaru di halaman utama
      }
    }
  }

  // 2. FUNGSI POP-UP DIALOG KONFIRMASI SEBELUM PROSES JEPTER KAMERA SURAT JALAN
  void confirmAndSend() {
    if (selectedToko == null || selectedItems.isEmpty) return;

    // Formulasi pesan konfirmasi dinamis bahasa tr()
    String confirmMsg = "do_konfirmasi_kirim"
        .tr()
        .replaceFirst('()', _calculateTotalQty().toString())
        .replaceFirst(']', selectedToko!);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.local_shipping, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Text("do_kirim_langsung".tr(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15))
        ]),
        content: Text(confirmMsg,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL",
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _handleProcessWithPhoto(); // Lanjut ke fungsi eksekusi kamera biner di Part 4
            },
            child: Text("do_btn_jepret".tr(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // 1. FUNGSI UTAMA: PROSES JEPRET KAMERA BUKTI, UPLOAD STORAGE, DAN INSERT HISTORY MUTASI
  Future<void> _handleProcessWithPhoto() async {
    // Membuka kamera dengan kualitas terkompresi (50%) agar hemat penyimpanan bucket Supabase
    final photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice
            .rear, // Paksa kamera belakang agar tulisan surat jalan tidak mirror
        imageQuality: 50);
    if (photo == null) return;

    setState(() => isProcessing = true);

    try {
      final bytes = await photo.readAsBytes();
      final path = 'pengiriman/${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Upload berkas gambar secara biner ke bucket attendance_photos
      await Supabase.instance.client.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));

      final imgUrl = Supabase.instance.client.storage
          .from('attendance_photos')
          .getPublicUrl(path);

      // Loop pengaman: Validasi & eksekusi pemotongan stok di Gudang Pusat secara real-time
      for (var entry in selectedItems.entries) {
        final current = await Supabase.instance.client
            .from('products')
            .select('stock, nama')
            .eq('id', entry.key)
            .single();

        int stockSekarang = int.tryParse(current['stock'].toString()) ?? 0;
        if (stockSekarang < entry.value)
          throw "Stok ${current['nama']} mendadak habis atau tidak mencukupi!";

        await Supabase.instance.client
            .from('products')
            .update({'stock': stockSekarang - entry.value}).eq('id', entry.key);
      }

      // Formula pembuatan nomor resi surat jalan otomatis (DO-xxxxx)
      String resiDO =
          "DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";

      // Catat log resmi ke tabel riwayat mutasi barang (Status: TRANSIT untuk kurir jalan)
      await Supabase.instance.client.from('stock_move_history').insert({
        'product_name': resiDO,
        'dari_lokasi': 'PUSAT',
        'ke_lokasi': selectedToko,
        'jumlah': _calculateTotalQty(),
        'tipe': 'OUTGOING',
        'status': 'TRANSIT',
        'bukti_foto_pengirim': imgUrl,
        'keterangan': buildCartJson(),
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return; // Pelindung async gap build context
      setState(() {
        selectedItems.clear();
        qtyControllers.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("do_sukses_transit".tr()),
          backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal memproses pengiriman: $e"),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
        _fetchProduk(); // Tarik ulang data stok terbaru di katalog depan
      }
    }
  }

  // 2. TAMPILAN ANTARMUKA LAYOUT UTAMA KARTU MUTASI BARANG PUSAT
  @override
  Widget build(BuildContext context) {
    final displayList = isFiltering ? filteredProduk : listProdukPusat;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text("do_title".tr(),
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        actions: [
          // Tombol Akses Halaman Transaksi Gantung (Menuju Part 5)
          IconButton(
              icon: const Icon(Icons.inventory_2,
                  color: Colors.orangeAccent, size: 22),
              tooltip: "do_trip_gantung".tr(),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const DraftManagerPage()));
              })
        ],
      ),
      body: Column(
        children: [
          // --- PANEL HEADER: PILIH CABANG TUJUAN & SEARCH BAR ---
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: listToko.contains(selectedToko) ? selectedToko : null,
                  decoration: InputDecoration(
                    labelText: "do_cabang_tujuan".tr(),
                    labelStyle:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: listToko
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedToko = val),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: searchController,
                  onChanged: (v) => filterProduk(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                      hintText: "do_cari_produk".tr(),
                      hintStyle:
                          const TextStyle(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.grey, size: 18),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 15),

                // Horizontal Chips Filter Kategori Item
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('Frame', Colors.blueAccent),
                      const SizedBox(width: 10),
                      _buildCategoryChip('Lensa', Colors.orangeAccent),
                      const SizedBox(width: 10),
                      _buildCategoryChip('Lainnya', Colors.green),
                    ],
                  ),
                )
              ],
            ),
          ),

          // --- AREA KATALOG DAFTAR STOK BARANG GUDANG PUSAT ---
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent))
                : displayList.isEmpty
                    ? Center(
                        child: Text("retur_stok_kosong".tr(),
                            style: const TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          if (item == null) return const SizedBox.shrink();

                          String id = item['id'].toString();
                          int maxStok =
                              int.tryParse(item['stock']?.toString() ?? '0') ??
                                  0;
                          bool isSelected = selectedItems.containsKey(id);

                          String kategori =
                              (item['kategori']?.toString().trim() ?? '')
                                  .toLowerCase();
                          String warnaRaw =
                              item['warna']?.toString().trim() ?? "";
                          String warna = warnaRaw.isEmpty ? '-' : warnaRaw;
                          String subKategoriRaw =
                              item['sub_kategori']?.toString().trim() ?? '';
                          String subKategori =
                              subKategoriRaw.isEmpty ? '-' : subKategoriRaw;
                          String jenisLensaRaw =
                              item['jenis_lensa']?.toString().trim() ?? '';
                          String jenisLensa =
                              jenisLensaRaw.isEmpty ? '-' : jenisLensaRaw;

                          // Ekstraksi spek matriks lensa optik
                          String rawSph = (item['sph_r'] ??
                                  item['sph_l'] ??
                                  item['sph'] ??
                                  '')
                              .toString()
                              .trim();
                          String rawCyl = (item['cyl_r'] ??
                                  item['cyl_l'] ??
                                  item['cyl'] ??
                                  '')
                              .toString()
                              .trim();
                          String rawAdd = (item['add_r'] ??
                                  item['add_l'] ??
                                  item['add'] ??
                                  '')
                              .toString()
                              .trim();
                          String ukTunggal =
                              (item['ukuran_lensa'] ?? item['ukuran'] ?? '')
                                  .toString()
                                  .trim();

                          String ukuranRangkuman = "-";
                          List<String> parts = [];
                          double? numSph = double.tryParse(rawSph);
                          double? numCyl = double.tryParse(rawCyl);
                          double? numAdd = double.tryParse(rawAdd);

                          if (numSph != null && numSph != 0.0)
                            parts.add("Sph: ${numSph.toStringAsFixed(2)}");
                          if (numCyl != null && numCyl != 0.0)
                            parts.add("Cyl: ${numCyl.toStringAsFixed(2)}");
                          if (numAdd != null && numAdd != 0.0)
                            parts.add("Add: ${numAdd.toStringAsFixed(2)}");

                          if (parts.isNotEmpty) {
                            ukuranRangkuman = parts.join(' | ');
                          } else if (ukTunggal.isNotEmpty && ukTunggal != "0") {
                            double? numTunggal = double.tryParse(ukTunggal);
                            ukuranRangkuman = numTunggal != null
                                ? numTunggal.toStringAsFixed(2)
                                : ukTunggal;
                          }

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blueAccent.withOpacity(0.08)
                                  : Colors.white.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isSelected
                                      ? Colors.blueAccent.withOpacity(0.7)
                                      : Colors.white.withOpacity(0.05),
                                  width: isSelected ? 1.5 : 1),
                            ),
                            child: Row(
                              children: [
                                // Media Foto Item
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.white.withOpacity(0.05),
                                    child: (item['image_url'] != null &&
                                            item['image_url']
                                                .toString()
                                                .trim()
                                                .isNotEmpty &&
                                            item['image_url'] != '-')
                                        ? Image.network(item['image_url'],
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) =>
                                                const Icon(
                                                    Icons.image_not_supported,
                                                    color: Colors.white10,
                                                    size: 20))
                                        : const Icon(Icons.image_not_supported,
                                            color: Colors.white10, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Deskripsi Item Metadata
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item['nama'] ?? '-',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Text(kategori.toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      if (kategori == 'frame')
                                        Text(
                                            "Bahan: $subKategori | Warna: $warna",
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.5),
                                                fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)
                                      else if (kategori == 'lensa')
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                "Jenis: $jenisLensa | Coating: $subKategori",
                                                style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.5),
                                                    fontSize: 11),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            const SizedBox(height: 2),
                                            Text("Ukuran: $ukuranRangkuman",
                                                style: const TextStyle(
                                                    color: Colors.blueAccent,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w500),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis)
                                          ],
                                        )
                                      else
                                        Text("Detail: $warna",
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.5),
                                                fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                  color: Colors.greenAccent,
                                                  shape: BoxShape.circle)),
                                          const SizedBox(width: 6),
                                          Text("Stok Pusat: $maxStok Pcs",
                                              style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 11)),
                                        ],
                                      )
                                    ],
                                  ),
                                ),

                                // Pengatur Stepper Angka Belanja DO di Sisi Kanan
                                const SizedBox(width: 10),
                                isSelected
                                    ? Row(
                                        children: [
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle,
                                                  color: Colors.redAccent,
                                                  size: 20),
                                              onPressed: () =>
                                                  _updateQty(id, -1, maxStok)),
                                          SizedBox(
                                            width: 35,
                                            child: TextField(
                                              controller: qtyControllers[id],
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13),
                                              decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          vertical: 4),
                                                  enabledBorder:
                                                      UnderlineInputBorder(
                                                          borderSide: BorderSide(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.1)))),
                                              onChanged: (val) => _setQtyManual(
                                                  id, val, maxStok),
                                            ),
                                          ),
                                          IconButton(
                                              icon: const Icon(Icons.add_circle,
                                                  color: Colors.greenAccent,
                                                  size: 20),
                                              onPressed: () =>
                                                  _updateQty(id, 1, maxStok)),
                                        ],
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.add_box,
                                            color: Colors.blueAccent, size: 24),
                                        onPressed: () => _toggleItem(item)),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // --- BOTTOM BAR ACTION ACTION BUTTONS ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: (isProcessing || selectedItems.isEmpty)
                        ? null
                        : saveDraft,
                    child: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : Text("do_btn_simpan".tr(),
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: (isProcessing || selectedItems.isEmpty)
                        ? null
                        : confirmAndSend,
                    child: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text("do_btn_kirim".tr(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class DraftManagerPage extends StatefulWidget {
  const DraftManagerPage({super.key});
  @override
  State<DraftManagerPage> createState() => _DraftManagerPageState();
}

class _DraftManagerPageState extends State<DraftManagerPage> {
  List<dynamic> allDrafts = [];
  List<dynamic> filteredDrafts = [];
  bool isLoading = true;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // 1. TARIK DATA DAFTAR TRANSAKSI GANTUNG DARI DATABASE SUPABASE
  Future<void> _refreshData() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('draft_pengiriman')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          allDrafts = data;
          _filterDrafts();
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Fetch Drafts: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. FUNGSI LOGIKA FILTER DAN PENCARIAN DRAF SECARA INSTAN
  void _filterDrafts() {
    String query = searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        filteredDrafts = List.from(allDrafts);
      } else {
        filteredDrafts = allDrafts.where((draft) {
          String tujuan = (draft['tujuan'] ?? '').toString().toLowerCase();
          String itemsStr = (draft['items'] ?? '').toString().toLowerCase();
          String idStr = "drf-${draft['id']}".toLowerCase();
          return tujuan.contains(query) ||
              itemsStr.contains(query) ||
              idStr.contains(query);
        }).toList();
      }
    });
  }

  // 3. HELPER FORMAT TANGGAL LOKAL ERP (DD/MM/YYYY HH:MM)
  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "-";
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "-";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text("draf_title".tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // BAR INPUT PENCARIAN DATA DRAF
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: searchController,
              onChanged: (v) => _filterDrafts(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "draf_cari".tr(),
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey, size: 18),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),

          // AREA UTAMA DAFTAR GRID TRANSAKSI GANTUNG
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent))
                : filteredDrafts.isEmpty
                    ? Center(
                        child: Text("draf_kosong".tr(),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 14)))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 320,
                                mainAxisExtent: 265,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16),
                        itemCount: filteredDrafts.length,
                        itemBuilder: (context, index) {
                          final draft = filteredDrafts[index];
                          String tujuan =
                              draft['tujuan']?.toString() ?? 'Cabang';
                          String idDraft = "DRF-${draft['id']}";
                          String tanggal = _formatDate(draft['created_at']);

                          int totalQty = 0;
                          List<String> previewItems = [];

                          if (draft['items'] != null) {
                            try {
                              List itemsList =
                                  jsonDecode(draft['items'].toString());
                              for (var itm in itemsList) {
                                totalQty +=
                                    int.tryParse(itm['qty'].toString()) ?? 0;
                                if (previewItems.length < 2) {
                                  previewItems
                                      .add("${itm['nama']} (${itm['qty']}x)");
                                }
                              }
                              if (itemsList.length > 2) {
                                // ✅ FIX TOKEN: Diganti dari '()' ke '{}' agar sinkron dengan bahasa ERP Bos
                                previewItems.add("draf_item_lainnya"
                                    .tr()
                                    .replaceFirst('{}',
                                        (itemsList.length - 2).toString()));
                              }
                            } catch (e) {
                              debugPrint("JSON Parse Error: $e");
                            }
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
                                  width: 1.2),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                                color: Colors.orangeAccent
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            child: const Icon(Icons.inventory_2,
                                                color: Colors.orangeAccent,
                                                size: 16),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.04),
                                                borderRadius:
                                                    BorderRadius.circular(6)),
                                            child: Text(idDraft,
                                                style: const TextStyle(
                                                    color: Colors.orangeAccent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                    letterSpacing: 0.5)),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(tujuan,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Text(tanggal,
                                          style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.4),
                                              fontSize: 10)),
                                      Divider(
                                          color: Colors.white.withOpacity(0.08),
                                          height: 20),
                                      Row(
                                        children: [
                                          Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                  color: Colors.greenAccent,
                                                  shape: BoxShape.circle)),
                                          const SizedBox(width: 6),
                                          // ✅ FIX TOKEN: Diganti dari '()' ke '{}' agar sinkron
                                          Text(
                                              "draf_total_pcs"
                                                  .tr()
                                                  .replaceFirst('{}',
                                                      totalQty.toString()),
                                              style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ...previewItems.map((str) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 3),
                                          child: Text("• $str",
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.6),
                                                  fontSize: 11,
                                                  height: 1.2),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis))),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10)),
                                    onPressed: () async {
                                      final res = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  DraftDetailPage(
                                                      draft: draft)));
                                      if (res == true) {
                                        _refreshData();
                                      }
                                    },
                                    child: Text("draf_btn_detail".tr(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11)),
                                  ),
                                )
                              ],
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

// ============================================================================
// HALAMAN 2: DETAIL TRANSAKSI GANTUNG -> PROSES AKHIR (EDITABLE) - PART 6 OF 6
// ============================================================================
class DraftDetailPage extends StatefulWidget {
  final dynamic draft;
  const DraftDetailPage({super.key, required this.draft});

  @override
  State<DraftDetailPage> createState() => _DraftDetailPageState();
}

class _DraftDetailPageState extends State<DraftDetailPage> {
  bool isProcessing = false;
  final ImagePicker picker = ImagePicker();
  final TextEditingController alasanController = TextEditingController();
  List<dynamic> originalItems = [];
  List<dynamic> localItems = [];

  @override
  void initState() {
    super.initState();
    try {
      String raw = widget.draft['items'].toString();
      originalItems = jsonDecode(raw);
      localItems = jsonDecode(raw);
    } catch (e) {
      debugPrint("Gagal parse items: $e");
    }
  }

  @override
  void dispose() {
    alasanController.dispose();
    super.dispose();
  }

  void _increaseQty(int index) {
    setState(() {
      int currentQty = int.tryParse(localItems[index]['qty'].toString()) ?? 0;
      localItems[index]['qty'] = currentQty + 1;
    });
  }

  void _decreaseQty(int index) {
    int currentQty = int.tryParse(localItems[index]['qty'].toString()) ?? 0;
    if (currentQty > 1) {
      setState(() {
        localItems[index]['qty'] = currentQty - 1;
      });
    } else {
      _confirmRemove(index);
    }
  }

  // 1. DIALOG KONFIRMASI PENGHAPUSAN ITEM DARI MANIFES DRAF
  void _confirmRemove(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("draf_hapus_title".tr(),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Text(
            "draf_hapus_desc".tr().replaceFirst(
                '{}', localItems[index]['nama']?.toString() ?? '-'),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL",
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => localItems.removeAt(index));
            },
            child: Text("draf_btn_hapus".tr(),
                style: const TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // 2. DIALOG INPUT ALASAN PEMBATALAN TRANSAKSI GANTUNG
  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("draf_batal_title".tr(),
            style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "draf_batal_desc".tr(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: alasanController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "draf_batal_hint".tr(),
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            )
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("draf_btn_tutup".tr(),
                  style: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (alasanController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("draf_err_alasan".tr()),
                    backgroundColor: Colors.orange));
                return;
              }
              Navigator.pop(ctx);
              _cancelDraft(alasanController.text.trim());
            },
            child: Text("draf_bun_proses_batal".tr(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // 3. FUNGSI DATABASE: BATALKAN DRAF & KEMBALIKAN STOK FISIK KE GUDANG PUSAT
  Future<void> _cancelDraft(String alasan) async {
    setState(() => isProcessing = true);
    try {
      for (var itm in originalItems) {
        int qty = int.tryParse(itm['qty'].toString()) ?? 0;
        String idProduk = itm['id_produk'].toString();

        final current = await Supabase.instance.client
            .from('products')
            .select('stock')
            .eq('id', idProduk)
            .single();

        int stokSekarang = int.tryParse(current['stock'].toString()) ?? 0;

        // Pulihkan kembali stok pusat yang sempat dikunci saat pembuatan draf
        await Supabase.instance.client
            .from('products')
            .update({'stock': stokSekarang + qty}).eq('id', idProduk);
      }

      await Supabase.instance.client
          .from('draft_pengiriman')
          .delete()
          .eq('id', widget.draft['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("draf_sukses_batal".tr()),
          backgroundColor: Colors.green));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal membatalkan draf: $e"),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // 4. DIALOG MODAL TAMPILAN RESI DAN PRATINJAU QR CODE SURAT JALAN
  void _showQRDialog(String resi, String qrPayload, String tujuan) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("draf_siap_kirim".tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${'draf_resi'.tr()} $resi",
                style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 5),
            Text("${'draf_tujuan_resi'.tr()} $tujuan",
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),

            // Generator QR Code Manifes Surat Jalan Kurir
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 180.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "draf_instruksi_qr".tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            )
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () async {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context, true);
              },
              child: Text("draf_btn_selesai".tr(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // 5. FUNGSI DATABASE: SINKRONISASI UPDATE SELISIH STOK & KIRIM DRAF JADI DO TRANSIT
  Future<void> sendDraft() async {
    if (localItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("draf_err_kosong".tr()),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => isProcessing = true);

    try {
      // Jepret bukti foto berkas manifest kurir
      final photo = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 50);
      if (photo == null) {
        setState(() => isProcessing = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("draf_err_foto_batal".tr()),
            backgroundColor: Colors.orange));
        return;
      }

      final bytes = await photo.readAsBytes();
      final path =
          'pengiriman/draft_${widget.draft['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('attendance_photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true));

      final imgUrl = Supabase.instance.client.storage
          .from('attendance_photos')
          .getPublicUrl(path);

      // Algoritma Rekonsiliasi: Hitung selisih perubahan kuantiti item draf lama vs draf baru
      for (var ori in originalItems) {
        String idProduk = ori['id_produk'].toString();
        int oriQty = int.tryParse(ori['qty'].toString()) ?? 0;

        var localMatch = localItems
            .where((item) => item['id_produk'].toString() == idProduk)
            .toList();

        int finalQty = 0;
        if (localMatch.isNotEmpty) {
          finalQty = int.tryParse(localMatch.first['qty'].toString()) ?? 0;
        }

        int selisih = oriQty - finalQty;
        if (selisih != 0) {
          final current = await Supabase.instance.client
              .from('products')
              .select('stock, nama')
              .eq('id', idProduk)
              .single();

          int stokPusat = int.tryParse(current['stock'].toString()) ?? 0;

          // Jika terjadi penambahan kuantiti item draf, validasi sisa stok gudang pusat terlebih dahulu
          if (selisih < 0 && stokPusat < (selisih.abs())) {
            throw "Stok ${current['nama']} di PUSAT sisa $stokPusat. Tidak cukup untuk menambah pesanan!";
          }
          await Supabase.instance.client
              .from('products')
              .update({'stock': stokPusat + selisih}).eq('id', idProduk);
        }
      }

      String resiDO =
          "DO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
      int totalQty = 0;
      for (var itm in localItems) {
        totalQty += int.tryParse(itm['qty'].toString()) ?? 0;
      }

      String qrPayload =
          jsonEncode({"resi": resiDO, "tujuan": widget.draft['tujuan']});

      // Lepas data draf menjadi riwayat mutasi aktif berstatus WAITING / TRANSIT
      await Supabase.instance.client.from('stock_move_history').insert({
        'product_name': resiDO,
        'dari_lokasi': 'PUSAT',
        'ke_lokasi': widget.draft['tujuan'],
        'jumlah': totalQty,
        'tipe': 'OUTGOING',
        'status': 'WAITING',
        'bukti_foto_pengirim': imgUrl,
        'keterangan': jsonEncode(localItems),
        'created_at': DateTime.now().toIso8601String(),
      });

      // Hapus lembaran draf penampungan sementara
      await Supabase.instance.client
          .from('draft_pengiriman')
          .delete()
          .eq('id', widget.draft['id']);

      if (!mounted) return;
      setState(() => isProcessing = false);
      _showQRDialog(resiDO, qrPayload, widget.draft['tujuan']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal memproses draf: $e"),
          backgroundColor: Colors.red));
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text("draf_detail_title".tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // HEADER KARTU DETAIL INFO TUJUAN CABANG
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("draf_tujuan".tr(),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(widget.draft['tujuan'] ?? '-',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text("draf_label_gantung".tr(),
                      style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                )
              ],
            ),
          ),

          // LIST VIEW EDITOR DAFTAR ITEMS DI DALAM DRAF
          Expanded(
            child: localItems.isEmpty
                ? Center(
                    child: Text("draf_item_kosong".tr(),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: localItems.length,
                    itemBuilder: (context, index) {
                      final itm = localItems[index];
                      int qty = int.tryParse(itm['qty'].toString()) ?? 0;
                      return Card(
                        color: const Color(0xFF1E293B),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.03))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(itm['nama'] ?? '-',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                        "${'draf_barcode'.tr()}${itm['barcode'] ?? '-'}",
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 11)),
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
                                      onPressed: () => _decreaseQty(index),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4)),
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color:
                                            Colors.blueAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text("$qty",
                                        style: const TextStyle(
                                            color: Colors.blueAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ),
                                  IconButton(
                                      icon: const Icon(Icons.add_circle_outline,
                                          color: Colors.greenAccent, size: 20),
                                      onPressed: () => _increaseQty(index),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.redAccent, size: 20),
                                      onPressed: () => _confirmRemove(index),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4)),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // PANEL ACTION PANEL ACTION UTAMA FOOTER BAR
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : _showCancelDialog,
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Colors.redAccent, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text("draf_btn_batalkan".tr(),
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : sendDraft,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text("draf_btn_konfirmasi_kirim".tr(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
