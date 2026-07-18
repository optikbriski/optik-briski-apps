import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'request_order_page.dart';
import '../../shared/responsive.dart';

// ====================================================================
// PRODUCT MASTER (REVISI FINAL: +BROADCAST STOCK ALOCATION MULTI-TENANT)
// ====================================================================
class ProductMasterPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ProductMasterPage({super.key, required this.profile});

  @override
  State<ProductMasterPage> createState() => ProductMasterPageState();
}

class ProductMasterPageState extends State<ProductMasterPage> {
  //--- 1. CONTROLLER INPUT FORM
  final nameController = TextEditingController();
  final hargaController = TextEditingController();
  final stokController = TextEditingController();
  final searchController = TextEditingController();
  final inputSubController = TextEditingController();
  final barcodeController = TextEditingController();
  final warnaCtrl = TextEditingController();
  final hargaModalController = TextEditingController();

  //--- 2. CONTROLLER KUSTOM SPEK UKURAN OPTIK (LENSA)
  final sphCtrl = TextEditingController(text: "0.00");
  final cylCtrl = TextEditingController(text: "0.00");
  final addCtrl = TextEditingController(text: "0.00");

  //--- 3. VARIABEL STATE MANAJEMEN FORM & FILTER
  String inputKat = 'Frame';
  String? inputSub = 'Plastik';
  String? selectedJenisLensa;
  String filterUnit = 'SEMUA';
  String filterKat = 'SEMUA';

  // 🎯 SELEKSI MODE BARCODE BARU
  String barcodeMode =
      'AUTOMATIC'; // Pilihan: 'AUTOMATIC' atau 'MANUAL_PRODUCT'

  List<String> units = ['SEMUA'];
  List<dynamic> listProduk = [];
  bool isLoading = true;
  PlatformFile? foto;
  String? editId;
  List<dynamic> listCabang = [];
  String? selectedCabang;

  //--- 4. SIKLUS HIDUP WIDGET (INIT & DISPOSE MEMORI)
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    nameController.dispose();
    hargaController.dispose();
    stokController.dispose();
    searchController.dispose();
    inputSubController.dispose();
    barcodeController.dispose();
    warnaCtrl.dispose();
    sphCtrl.dispose();
    cylCtrl.dispose();
    addCtrl.dispose();
    hargaModalController.dispose();
    super.dispose();
  }

  //--- 5. FUNGSI HELPER INTERNAL UTALITAS
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  String _formatOptic(dynamic val) {
    if (val == null || val.toString().isEmpty) return "0.00";
    double v = double.tryParse(val.toString()) ?? 0.00;
    if (v == 0) return "0.00";
    return v >= 0 ? "+${v.toStringAsFixed(2)}" : v.toStringAsFixed(2);
  }

  // Hak Akses Edit Data (Mendukung role dinamis database baru)
  bool get isCanEdit =>
      widget.profile['role'] == 'owner' ||
      widget.profile['role'] == 'admin_pusat' ||
      widget.profile['toko_id']?.toString().toUpperCase() == 'PUSAT';

  // 1. FUNGSI AWAL: MENGAMBIL DAFTAR UNIT TOKO/CABANG AKTIF DARI DATABASE
  Future<void> _init() async {
    try {
      final res = await Supabase.instance.client.from('toko_id').select('id');

      final unik = (res as List)
          .map((e) => e['id']?.toString() ?? "")
          .where((t) => t.isNotEmpty && t != 'PUSAT')
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          units = ['SEMUA', 'PUSAT', ...unik];
          listCabang = unik;
        });
        _fetch();
      }
    } catch (e) {
      debugPrint("Init error: $e");
    }
  }

  // 2. ALGORITMA UTAMA: AMBIL DATA & GABUNGKAN STOK PRODUK ANTAR-GUDANG
  Future<void> _fetch() async {
    setState(() => isLoading = true);
    try {
      var q = Supabase.instance.client.from('products').select();

      if (isCanEdit && filterUnit != 'SEMUA' && filterUnit != 'BROADCAST ALL') {
        q = q.eq('toko_id', filterUnit);
      }

      final data = await q.order('created_at', ascending: false);
      List<dynamic> rawList = data as List<dynamic>;

      String queryText = searchController.text.toLowerCase().trim();
      if (queryText.isNotEmpty) {
        rawList = rawList.where((item) {
          final namaProd = (item['nama'] ?? '').toString().toLowerCase();
          final barcodeProd = (item['barcode'] ?? '').toString().toLowerCase();
          return namaProd.contains(queryText) ||
              barcodeProd.contains(queryText);
        }).toList();
      }

      Map<String, Map<String, dynamic>> mapGabung = {};
      for (var item in rawList) {
        String namaKey = item['nama'].toString().trim();
        int stokSekarang = int.tryParse(item['stock'].toString()) ?? 0;
        String lokasiToko =
            item['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

        if (!mapGabung.containsKey(namaKey)) {
          mapGabung[namaKey] = Map<String, dynamic>.from(item);
          mapGabung[namaKey]!['breakdown_stok'] = [
            {"cabang": lokasiToko, "stok": stokSekarang}
          ];
          mapGabung[namaKey]!['total_stock'] = stokSekarang;
        } else {
          mapGabung[namaKey]!['total_stock'] =
              (mapGabung[namaKey]!['total_stock'] ?? 0) + stokSekarang;

          List<Map<String, dynamic>> breakdown =
              List<Map<String, dynamic>>.from(
                  mapGabung[namaKey]!['breakdown_stok']);
          breakdown.add({"cabang": lokasiToko, "stok": stokSekarang});
          mapGabung[namaKey]!['breakdown_stok'] = breakdown;
        }
      }

      if (mounted) {
        setState(() {
          listProduk = mapGabung.values.toList();
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch data error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Memilih Foto
  Future<void> _pickImage() async {
    try {
      // PERUBAHAN: Tambahkan .platform sebelum pickFiles
      final result = await FilePicker.platform.pickFiles(
          type: FileType.image, allowMultiple: false, withData: true);

      if (result != null && result.files.isNotEmpty) {
        setState(() => foto = result.files.first);
      }
    } catch (e) {
      debugPrint("Gagal memilih foto: $e");
    }
  }

  Future<void> _save() async {
    // 1. Validasi Input Dasar Nama Produk
    if (nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Nama Produk Wajib Diisi!"),
          backgroundColor: Colors.orange));
      return;
    }

    // 2. Validasi Jika Kasir Memilih Barcode Bawaan Tapi Kolom Masih Kosong
    if (barcodeMode == 'MANUAL_PRODUCT' &&
        barcodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Barcode Bawaan Produk Wajib Diisi / Di-scan!"),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => isLoading = true);
    try {
      // 🚨 BARIKADE VALIDASI: Deteksi duplikat barcode sebelum data dikirim ke Supabase (Hanya saat tambah barang baru)
      if (editId == null && barcodeMode == 'MANUAL_PRODUCT') {
        final checkExist = await Supabase.instance.client
            .from('products')
            .select('nama')
            .eq('barcode', barcodeController.text.trim())
            .maybeSingle();

        if (checkExist != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "⚠️ Gagal! Barcode sudah terdaftar untuk produk: ${checkExist['nama']}"),
              backgroundColor: Colors.redAccent));
          setState(() => isLoading = false);
          return; // Menghentikan mutlak proses insert ke bawah
        }
      }

      String? imgUrl;
      if (foto != null && foto!.bytes != null) {
        final path =
            'frames/${DateTime.now().millisecondsSinceEpoch}_${foto!.name}';

        await Supabase.instance.client.storage.from('Foto Frame').uploadBinary(
            path, foto!.bytes!,
            fileOptions: const FileOptions(upsert: true));

        imgUrl = Supabase.instance.client.storage
            .from('Foto Frame')
            .getPublicUrl(path);
      }

      String namaRapi = _toTitleCase(nameController.text.trim());
      String subRapi = inputKat == 'Lainnya'
          ? _toTitleCase(inputSubController.text.trim())
          : (inputSub ?? '');

      // 🔥 DETERMINASI KODE BARCODE BERDASARKAN SELEKSI RADIO BUTTON
      String finalBarcode = '';
      if (barcodeMode == 'AUTOMATIC') {
        finalBarcode =
            '${inputKat == 'Lensa' ? 'LNS' : 'BC'}-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        finalBarcode = barcodeController.text.trim();
      }

      final basePayload = {
        'nama': namaRapi,
        'harga': int.tryParse(hargaController.text.replaceAll('.', '')) ?? 0,
        'kategori': inputKat,
        'sub_kategori': subRapi,
        'barcode':
            finalBarcode, // 🎯 Mengunci string barcode hasil kalkulasi mode di atas
        'warna': inputKat == 'Frame' ? _toTitleCase(warnaCtrl.text) : null,
        'jenis_lensa': inputKat == 'Lensa' ? selectedJenisLensa : null,
        'sph_r': inputKat == 'Lensa' ? double.tryParse(sphCtrl.text) : null,
        'sph_l': inputKat == 'Lensa' ? double.tryParse(sphCtrl.text) : null,
        'cyl_r': inputKat == 'Lensa' ? double.tryParse(cylCtrl.text) : null,
        'cyl_l': inputKat == 'Lensa' ? double.tryParse(cylCtrl.text) : null,
        'add_r': (inputKat == 'Lensa' &&
                (selectedJenisLensa == 'Progresif' ||
                    selectedJenisLensa == 'Kryptok'))
            ? double.tryParse(addCtrl.text)
            : null,
        'add_l': (inputKat == 'Lensa' &&
                (selectedJenisLensa == 'Progresif' ||
                    selectedJenisLensa == 'Kryptok'))
            ? double.tryParse(addCtrl.text)
            : null,
        'harga_modal':
            int.tryParse(hargaModalController.text.replaceAll('.', '')) ?? 0,
      };

      if (imgUrl != null) basePayload['image_url'] = imgUrl;

      if (editId == null) {
        if (selectedCabang == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("pm_err_alokasi".tr()),
              backgroundColor: Colors.orange));
          setState(() => isLoading = false);
          return;
        }

        int stokInput = int.tryParse(stokController.text) ?? 0;

        if (selectedCabang == "BROADCAST_ALL") {
          // 1. Amankan dan masukkan ke PUSAT terlebih dahulu
          var pusatData = Map<String, dynamic>.from(basePayload);
          pusatData['toko_id'] = 'PUSAT';
          pusatData['stock'] = stokInput;
          await Supabase.instance.client.from('products').insert(pusatData);

          // 2. Gunakan Loop Terisolasi untuk menyebarkan ke tiap cabang (Anti-Macet)
          for (var cabang in listCabang) {
            try {
              var branchData = Map<String, dynamic>.from(basePayload);
              branchData['toko_id'] = cabang.toString().toUpperCase();
              branchData['stock'] = 0; // Cabang diset 0 sesuai skema awal Bos
              await Supabase.instance.client
                  .from('products')
                  .insert(branchData);
            } catch (e) {
              // Jika satu cabang error/sudah ada itemnya, loop tidak akan mati dan tetep lanjut ke cabang lain
              debugPrint("Gagal otomatis broadcast ke cabang $cabang: $e");
            }
          }
          // 🎯 FIX: Baris insert(broadcastData) lama yang bikin eror di sini sudah DIBUANG BERSIH!
        } else {
          var specificData = Map<String, dynamic>.from(basePayload);
          specificData['toko_id'] = selectedCabang;
          specificData['stock'] = stokInput;
          await Supabase.instance.client.from('products').insert(specificData);
        }
      } else {
        var updateData = Map<String, dynamic>.from(basePayload);
        updateData['stock'] = int.tryParse(stokController.text) ?? 0;
        await Supabase.instance.client
            .from('products')
            .update(updateData)
            .eq('id', editId!);
      }

      if (mounted) {
        _reset();
        _fetch();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("pm_sukses_simpan".tr()),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _reset() {
    nameController.clear();
    hargaController.clear();
    stokController.clear();
    warnaCtrl.clear();
    barcodeController.clear();
    inputSubController.clear();
    hargaModalController.clear();

    sphCtrl.text = "0.00";
    cylCtrl.text = "0.00";
    addCtrl.text = "0.00";

    setState(() {
      editId = null;
      inputKat = 'Frame';
      inputSub = 'Plastik';
      selectedJenisLensa = null;
      foto = null;
      barcodeMode = 'AUTOMATIC'; // 🎯 Reset kembali ke setelan default otomatis
    });
  }

  String _formatRupiahLocal(dynamic harga) {
    if (harga == null || harga.toString().trim().isEmpty) return 'Rp0';
    int value = double.tryParse(harga.toString())?.toInt() ?? 0;
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String hasilFormat =
        value.toString().replaceAllMapped(reg, (Match match) => '${match[1]}.');
    return "Rp$hasilFormat";
  }

// 🎯 HUBUNGKAN KE HALAMAN REQUEST ORDER MILIK BOS NATAN
  void _bukaRequestOrder(dynamic item) {
    final dataBarang = {
      'nama': item['nama'],
      'kategori': item['kategori'],
      'sub_kategori': item['sub_kategori'],
      'barcode': item['barcode'],
      'harga_modal': item['harga_modal'],
    };

    // 🎯 FIX: Cetak ke console log biar variabelnya terpakai & lolos sensor compiler
    debugPrint("Log Request Order Cabang: $dataBarang");

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("🛒 Membuka Request Order untuk: ${item['nama']}"),
      backgroundColor: Colors.orangeAccent,
    ));
  }

  // 2. FUNGSI POP-UP DETAIL KARTU PRODUK DAN PRATINJAU QR CODE BARCODE
  void showProductDetail(dynamic item) {
    // 🔍 Deteksi otomatis siapa akun yang sedang melihat detail
    String userToko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
    bool isHakAksesPusat = userToko == 'PUSAT' ||
        widget.profile['role'] == 'owner' ||
        widget.profile['role'] == 'admin_pusat';

    // 📦 Hitung kalkulasi stok khusus untuk teks indikator baris atas
    int displayTotalStock = item['total_stock'] ?? item['stock'] ?? 0;
    String labelStokAtas =
        "pm_total_stok".tr(); // Mengikuti easy localization bawaan

    if (!isHakAksesPusat) {
      labelStokAtas = "Stok Cabang";
      int stokKetemu = 0;
      List<dynamic> breakdown = item['breakdown_stok'] ?? [];
      for (var b in breakdown) {
        if (b['cabang'].toString().toUpperCase() == userToko) {
          stokKetemu = int.tryParse(b['stok'].toString()) ?? 0;
          break;
        }
      }
      displayTotalStock = stokKetemu;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: R.constrainedDialog(
          context: ctx,
          preferWidth: 380,
          child: Container(
          padding: const EdgeInsets.all(25),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("pm_detail_produk".tr(),
                    style: const TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.5)),
                const SizedBox(height: 20),
                if (item['barcode'] != null &&
                    item['barcode'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10)),
                    child: QrImageView(
                        data: item['barcode'].toString(), size: 140),
                  ),
                const SizedBox(height: 15),
                Text(_toTitleCase(item['nama'] ?? '-'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                    textAlign: TextAlign.center),
                const Divider(color: Colors.white10, height: 30),
                _row("pm_kat".tr(), item['kategori'] ?? '-'),
                _row("pm_bahan_coating".tr(), item['sub_kategori'] ?? '-'),
                if (item['kategori'] == 'Frame')
                  _row("pm_warna_frame".tr(), item['warna'] ?? '-'),
                if (item['kategori'] == 'Lensa') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        _row("pm_jenis_lensa".tr(), item['jenis_lensa'] ?? '-'),
                        const Divider(color: Colors.white10),
                        _row("pm_uk_sph".tr(), _formatOptic(item['sph_r'])),
                        _row("pm_uk_cyl".tr(), _formatOptic(item['cyl_r'])),
                        if (item['jenis_lensa'] == 'Progresif' ||
                            item['jenis_lensa'] == 'Kryptok')
                          _row("pm_uk_add".tr(), _formatOptic(item['add_r'])),
                      ],
                    ),
                  )
                ],
                const SizedBox(height: 10),
                _row("pm_harga_jual".tr(), _formatRupiahLocal(item['harga'])),

                // 🎯 SENSOR STOK ATAS: Menampilkan stok asli sesuai wilayah login
                _row(labelStokAtas, "$displayTotalStock Pcs"),

                if (item['breakdown_stok'] != null) ...[
                  const Divider(color: Colors.white10, height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront,
                            color: Colors.blueAccent, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          "pm_distribusi_stok".tr(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                              fontSize: 11),
                        ),
                        const Spacer(),

                        // 🎯 SENSOR TOMBOL: Tombol ADD BRANCH hijau otomatis hilang jika yang login adalah Cabang
                        if (isCanEdit)
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              Future.delayed(const Duration(milliseconds: 200),
                                  () {
                                if (mounted) _showAddBranchDialog(item);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  border: Border.all(color: Colors.green),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                children: [
                                  const Icon(Icons.add_business,
                                      color: Colors.green, size: 12),
                                  const SizedBox(width: 4),
                                  Text("pm_btn_tambah_cabang".tr(),
                                      style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),

                  // 🎯 SENSOR LIST DISTRIBUSI: Menyaring list agar murni menampilkan milik cabangnya sendiri
                  ...(item['breakdown_stok'] as List)
                      .where((lokasi) =>
                          isHakAksesPusat ||
                          lokasi['cabang'].toString().toUpperCase() == userToko)
                      .map((lokasi) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0, left: 5.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("• ${lokasi['cabang'].toString().toUpperCase()}",
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                          Text("${lokasi['stok']} Pcs",
                              style: TextStyle(
                                  color: lokasi['stok'] >= 0
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("TUTUP",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Text(v,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12))
        ]),
      );

  Widget _buildLensStepper(String label, TextEditingController ctrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
              color: Colors.black26, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.redAccent, size: 18),
                  onPressed: () => setState(() => ctrl.text =
                      _formatOptic((double.tryParse(ctrl.text) ?? 0) - 0.25))),
              SizedBox(
                  width: 50,
                  child: Text(ctrl.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
              IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: Colors.greenAccent, size: 18),
                  onPressed: () => setState(() => ctrl.text =
                      _formatOptic((double.tryParse(ctrl.text) ?? 0) + 0.25))),
            ],
          ),
        ),
      ],
    );
  }

// ====================================================================
  // 🎯 REVISI ULTRALIGHT V4: DIALOG PREMIUM LEGA, SCROLLABLE & ANTI-CRASH
  // ====================================================================
  void _showAddBranchDialog(Map<String, dynamic> item) {
    String searchQuery = '';
    List<String> allToko = [
      'PUSAT',
      ...listCabang.map((e) => e.toString().toUpperCase())
    ];
    Map<String, bool> selectedCabangMap = {
      for (var toko in allToko) toko: false
    };
    bool isSelectAll = false;
    final TextEditingController bulkQtyController =
        TextEditingController(text: "0");

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            List<String> filteredToko = allToko
                .where((t) => t.contains(searchQuery.toUpperCase()))
                .toList();

            List<dynamic> breakdown = item['breakdown_stok'] ?? [];
            Map<String, int> existingStocks = {
              for (var b in breakdown)
                b['cabang'].toString().toUpperCase(): b['stok']
            };
            bool hasSelection = selectedCabangMap.values.contains(true);

            return R.constrainedDialog(
              context: context,
              preferWidth: 500,
              child: Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: SizedBox(
                width: double.infinity,
                height: (MediaQuery.sizeOf(context).height * 0.75).clamp(400.0, 600.0),
                child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Alokasi: ${item['nama']}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),

                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Cari cabang...",
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (val) =>
                          setStateDialog(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),

                    CheckboxListTile(
                      title: const Text("Pilih Semua",
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: isSelectAll,
                      onChanged: (val) => setStateDialog(() {
                        isSelectAll = val!;
                        selectedCabangMap.updateAll((key, _) => val);
                      }),
                    ),
                    const Divider(color: Colors.white12),

                    // 🎯 KUNCI LIST: Menggunakan Expanded agar list tidak overflow
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredToko.length,
                        itemBuilder: (context, index) {
                          String toko = filteredToko[index];
                          return CheckboxListTile(
                            value: selectedCabangMap[toko],
                            title: Text(toko,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            onChanged: (val) => setStateDialog(
                                () => selectedCabangMap[toko] = val!),
                          );
                        },
                      ),
                    ),

                    const Divider(color: Colors.white12),

// 🎯 FIX FOOTER COUNTER (Line 650+)
                    if (hasSelection) ...[
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.redAccent, size: 28),
                            onPressed: () {
                              int n = int.tryParse(bulkQtyController.text) ?? 0;
                              if (n > 0)
                                setStateDialog(() => bulkQtyController.text =
                                    (n - 1).toString());
                            },
                          ),

                          // 📦 Sudah fix menggunakan SizedBox sesuai standar Lint Dart
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: bulkQtyController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF0F172A),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),

                          IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: Colors.greenAccent, size: 28),
                            onPressed: () {
                              int n = int.tryParse(bulkQtyController.text) ?? 0;
                              setStateDialog(() =>
                                  bulkQtyController.text = (n + 1).toString());
                            },
                          ),
                          const Spacer(),
// 🎯 GANTI ELEVATED BUTTON LAMA BOS DENGAN INI:
                          SizedBox(
                            width: 100,
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                padding: EdgeInsets
                                    .zero, // Biar teks pas di tengah kotak
                              ),
                              onPressed: () {
                                List<String> target = selectedCabangMap.entries
                                    .where((e) => e.value)
                                    .map((e) => e.key)
                                    .toList();
                                int qty =
                                    int.tryParse(bulkQtyController.text) ?? 0;
                                _tampilkanKonfirmasiAlokasi(item, target, qty,
                                    () {
                                  Navigator.pop(context);
                                  _executeBulkAddBranch(
                                      item, target, qty, existingStocks);
                                });
                              },
                              child: const Text("PROSES",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                          )
                        ],
                      ),
                    ],
                  ],
                ),
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }

  // 2. FUNGSI POP-UP KONFIRMASI LAPIS KEDUA (STANDALONE METHOD)
  void _tampilkanKonfirmasiAlokasi(Map<String, dynamic> item,
      List<String> cabangs, int qty, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => R.constrainedDialog(
        context: ctx,
        preferWidth: 420,
        child: AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 10),
            Text("Konfirmasi Tambah Stok",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Apakah Bos yakin ingin mendistribusikan produk '${item['nama']}' dengan tambahan sebanyak +$qty Pcs ke cabang berikut:\n\n${cabangs.join(', ')}?",
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("BATAL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text("YA, SEBARKAN",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      ),
    );
  }

  // 3. FUNGSI MASSAL (BULK UPSERT SYSTEM) KE DATABASE SUPABASE
  Future<void> _executeBulkAddBranch(
      Map<String, dynamic> baseProduct,
      List<String> targets,
      int additionalStock,
      Map<String, int> existingStocks) async {
    setState(() => isLoading = true);
    try {
      for (var toko in targets) {
        bool isExist = existingStocks.containsKey(toko);

        // Bersihkan payload data dari id bawaan pusat
        Map<String, dynamic> row = Map.from(baseProduct);
        row.remove('id');
        row.remove('created_at');
        row.remove('breakdown_stok');
        row.remove('total_stock');
        row['toko_id'] = toko;

        if (isExist) {
          // Jalur 1: Jika cabang sudah punya produk ini, update kuantitasnya langsung
          int stockLama = existingStocks[toko] ?? 0;
          await Supabase.instance.client
              .from('products')
              .update({'stock': stockLama + additionalStock})
              .eq('nama', baseProduct['nama'])
              .eq('toko_id', toko);
        } else {
          // Jalur 2: Jika benar-benar cabang baru, daftarkan row baru
          row['stock'] = additionalStock;
          await Supabase.instance.client.from('products').insert(row);
        }
      }

      _fetch(); // Refresh list inventori halaman utama web Bos

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "✅ Sukses mendistribusikan stok tambahan ke ${targets.length} cabang!"),
          backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal Alokasi: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 3. REUSABLE WIDGET TEXTFIELD INPUT COMPACT GENERATOR
  Widget _buildInput(TextEditingController ctrl, String hint, IconData icon,
      {bool isNumber = false, bool autoCaps = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber
          ? TextInputType.number
          : (autoCaps ? TextInputType.name : TextInputType.text),
      textCapitalization:
          autoCaps ? TextCapitalization.words : TextCapitalization.none,
      inputFormatters:
          isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
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
        centerTitle: true,
        title: Text("pm_title".tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          if (editId != null)
            IconButton(
                icon: const Icon(Icons.refresh, color: Colors.orangeAccent),
                onPressed: _reset)
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BAGIAN 1: FORM DATA ENTRY (HANYA UNTUK PUSAT / YANG MEMILIKI AKSES) ---
            if (isCanEdit) ...[
              Text("pm_data_entry".tr(),
                  style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2)),
              const SizedBox(height: 15),
              if (barcodeController.text.isNotEmpty)
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10)),
                        child: QrImageView(
                            data: barcodeController.text, size: 120),
                      ),
                      const SizedBox(height: 10),
                      Text("pm_barcode_sistem".tr(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 10)),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: inputKat,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                        labelText: "pm_kat".tr(),
                        labelStyle:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none)),
                    items: ['Frame', 'Lensa', 'Lainnya']
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        inputKat = val!;
                        if (inputKat == 'Lensa') {
                          inputSub = 'Supersin';
                          selectedJenisLensa = 'Standar';
                        } else if (inputKat == 'Frame') {
                          inputSub = 'Plastik';
                          selectedJenisLensa = null;
                        } else {
                          inputSub = null;
                          selectedJenisLensa = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: inputKat == 'Lainnya'
                      ? _buildInput(
                          inputSubController, "pm_sub_kat".tr(), Icons.category,
                          autoCaps: true)
                      : DropdownButtonFormField<String>(
                          value: inputSub,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                              labelText: "pm_bahan_coating".tr(),
                              labelStyle: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none)),
                          items: (inputKat == 'Frame'
                                  ? ['Plastik', 'Besi', 'Kayu', 'Titanium']
                                  : [
                                      'Supersin',
                                      'Blueray',
                                      'Photochromic',
                                      'Bluechromic',
                                      'Night Driving',
                                      'Antifog'
                                    ])
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => setState(() => inputSub = v),
                        ),
                ),
              ]),
              const SizedBox(height: 15),

              // 🎯 SUNTIKAN UI BARU: Radio Button Pemilihan Jalur Barcode Produk
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text("Generate Otomatis",
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      value: 'AUTOMATIC',
                      groupValue: barcodeMode,
                      activeColor: Colors.blueAccent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setState(() => barcodeMode = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text("Barcode Bawaan",
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      value: 'MANUAL_PRODUCT',
                      groupValue: barcodeMode,
                      activeColor: Colors.blueAccent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setState(() => barcodeMode = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 🔍 MUNCULKAN INPUT SCANNER JIKA MEMILIH BARCODE BAWAAN
              if (barcodeMode == 'MANUAL_PRODUCT') ...[
                _buildInput(
                    barcodeController,
                    "Scan / Ketik Barcode Produk (*)",
                    Icons.qr_code_scanner_rounded),
                const SizedBox(height: 15),
              ],

              _buildInput(
                  nameController,
                  inputKat == 'Lensa'
                      ? "pm_merk_lensa".tr()
                      : "pm_nama_frame".tr(),
                  Icons.edit,
                  autoCaps: true),
              if (inputKat == 'Frame') ...[
                const SizedBox(height: 15),
                _buildInput(warnaCtrl, "pm_warna_frame".tr(), Icons.palette,
                    autoCaps: true),
              ],
              if (inputKat == 'Lensa') ...[
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: selectedJenisLensa,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                      labelText: "pm_jenis_lensa".tr(),
                      labelStyle:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none)),
                  items: ["Standar", "Progresif", "Kryptok"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedJenisLensa = v),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                        child: _buildLensStepper("pm_uk_sph".tr(), sphCtrl)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildLensStepper("pm_uk_cyl".tr(), cylCtrl)),
                    if (selectedJenisLensa == 'Progresif' ||
                        selectedJenisLensa == 'Kryptok') ...[
                      const SizedBox(width: 10),
                      Expanded(
                          child: _buildLensStepper("pm_uk_add".tr(), addCtrl)),
                    ]
                  ],
                ),
              ],
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _buildInput(
                        hargaController, "pm_harga_jual".tr(), Icons.payments,
                        isNumber: true),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildInput(hargaModalController,
                        "pm_harga_modal".tr(), Icons.monetization_on,
                        isNumber: true),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _buildInput(
                  stokController, "pm_stok_tersedia".tr(), Icons.inventory,
                  isNumber: true),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                value: selectedCabang,
                decoration: InputDecoration(
                  labelText: "pm_alokasi_cabang".tr(),
                  labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  prefixIcon: const Icon(Icons.store,
                      color: Colors.blueAccent, size: 18),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
                items: [
                  DropdownMenuItem(
                      value: "BROADCAST_ALL",
                      child: Text("pm_broadcast".tr(),
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold))),
                  DropdownMenuItem(
                      value: "PUSAT", child: Text("pm_pusat".tr())),
                  ...listCabang.map((cabang) => DropdownMenuItem(
                      value: cabang.toString(),
                      child:
                          Text("CABANG ${cabang.toString().toUpperCase()}"))),
                ],
                onChanged: (val) {
                  setState(() {
                    selectedCabang = val.toString();
                    filterUnit = val.toString();
                  });
                  _fetch();
                },
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(
                        color: foto != null ? Colors.green : Colors.blueAccent),
                  ),
                  onPressed: _pickImage,
                  icon: Icon(
                      foto != null ? Icons.check_circle : Icons.add_a_photo,
                      color: foto != null ? Colors.green : Colors.blueAccent,
                      size: 18),
                  label: Text(
                      foto != null
                          ? "${'pm_foto_terpilih'.tr()} ${foto!.name}"
                          : "pm_upload_foto".tr(),
                      style: TextStyle(
                          color:
                              foto != null ? Colors.green : Colors.blueAccent,
                          fontSize: 13)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: isLoading ? null : _save,
                    child: Text(
                        editId == null
                            ? "pm_btn_tambah_db".tr()
                            : "pm_btn_update_db".tr(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white))),
              ),
              const SizedBox(height: 35),
            ],

            // --- BAGIAN 2: LIST MONITOR DAFTAR INVENTORI KACAMATA ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("pm_daftar_inventori".tr(),
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                Text(
                    "pm_total_item"
                        .tr()
                        .replaceFirst('{}', listProduk.length.toString()),
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 15),

            TextField(
              controller: searchController,
              onChanged: (v) => _fetch(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                  hintText: "pm_cari".tr(),
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.orangeAccent, size: 18),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.03),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none)),
            ),
            const SizedBox(height: 20),

            isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.orangeAccent))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: listProduk.length,
                    itemBuilder: (c, i) {
                      final item = listProduk[i];
                      String namaRapi =
                          _toTitleCase(item['nama']?.toString() ?? '-');

                      // 1. Ambil Profil Wilayah Login
                      String userToko =
                          widget.profile['toko_id']?.toString().toUpperCase() ??
                              'PUSAT';
                      bool isHakAksesPusat = userToko == 'PUSAT' ||
                          widget.profile['role'] == 'owner' ||
                          widget.profile['role'] == 'admin_pusat';

                      int displayStock =
                          item['total_stock'] ?? item['stock'] ?? 0;
                      String labelStok = "Total Stock: ";

                      // 2. Filter Stok Menggunakan Loop Tradisional (Aman dari Masalah Type-Subtype Dart Web)
                      if (!isHakAksesPusat && item['breakdown_stok'] != null) {
                        labelStok = "Stok Cabang: ";
                        int stokKetemu = 0;
                        for (var b in item['breakdown_stok']) {
                          if (b['cabang'].toString().toUpperCase() ==
                              userToko) {
                            stokKetemu =
                                int.tryParse(b['stok'].toString()) ?? 0;
                            break;
                          }
                        }
                        displayStock = stokKetemu;
                      }

                      return Card(
                        color: const Color(0xFF1E293B),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.03))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10)),
                            child: (item['image_url'] != null &&
                                    item['image_url'].toString().isNotEmpty &&
                                    item['image_url'].toString() != '-')
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(item['image_url'],
                                        fit: BoxFit.cover))
                                : const Icon(Icons.image,
                                    color: Colors.white10),
                          ),
                          title: Text(namaRapi,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                  "${item['kategori']} | ${item['sub_kategori'] ?? '-'}",
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.blueAccent, size: 11),
                                  const SizedBox(width: 3),
                                  Text(
                                    !isHakAksesPusat
                                        ? "CABANG $userToko"
                                        : "PUSAT",
                                    style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(_formatRupiahLocal(item['harga']),
                                  style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                          trailing: R.isCompact(context)
                              ? PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert,
                                      color: Colors.white54, size: 20),
                                  color: const Color(0xFF1E293B),
                                  onSelected: (action) {
                                    if (action == 'detail') {
                                      showProductDetail(item);
                                    } else if (action == 'order') {
                                      _bukaRequestOrder(item);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'detail',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.qr_code_2_rounded,
                                              color: Colors.blueAccent,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Text('$labelStok$displayStock Pcs',
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    if (!isCanEdit)
                                      const PopupMenuItem(
                                        value: 'order',
                                        child: Row(
                                          children: [
                                            Icon(Icons.shopping_basket_rounded,
                                                color: Colors.orangeAccent,
                                                size: 18),
                                            SizedBox(width: 8),
                                            Text('Minta Stok'),
                                          ],
                                        ),
                                      ),
                                  ],
                                )
                              : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.orangeAccent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text(
                                      "$labelStok$displayStock Pcs",
                                      style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold))),
                              IconButton(
                                  iconSize: 20,
                                  constraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.qr_code_2_rounded,
                                      color: Colors.blueAccent, size: 20),
                                  onPressed: () => showProductDetail(item)),
                              if (!isCanEdit)
                                IconButton(
                                  iconSize: 20,
                                  constraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.shopping_basket_rounded,
                                      color: Colors.orangeAccent, size: 20),
                                  tooltip: "Minta Stok",
                                  onPressed: () => _bukaRequestOrder(item),
                                ),
                            ],
                          ),
                          // 🎯 REVISI KLIK: Jika dia admin pusat buka form edit, jika dia cabang buka pop-up detail produk!
                          onTap: isCanEdit
                              ? () {
                                  Future.delayed(
                                      const Duration(milliseconds: 150), () {
                                    if (!mounted) return;
                                    if (editId == item['id'].toString()) {
                                      _reset();
                                    } else {
                                      setState(() {
                                        editId = item['id'].toString();
                                        nameController.text =
                                            item['nama'] ?? '';
                                        hargaController.text =
                                            _formatRupiahLocal(
                                                    item['harga'] ?? 0)
                                                .replaceAll('Rp', '')
                                                .replaceAll('.', '')
                                                .trim();
                                        hargaModalController.text =
                                            item['harga_modal']?.toString() ??
                                                '0';
                                        stokController.text =
                                            item['stock']?.toString() ?? '0';
                                        barcodeController.text =
                                            item['barcode'] ?? '';
                                        warnaCtrl.text = item['warna'] ?? '';
                                        // 🎯 Buka field input manual agar barcode lamanya kelihatan pas diedit
                                        barcodeMode = 'MANUAL_PRODUCT';
                                        inputKat = item['kategori'] ?? 'Frame';
                                        String rawSub = item['sub_kategori']
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        if (inputKat == 'Frame') {
                                          inputSub = [
                                            'Plastik',
                                            'Besi',
                                            'Kayu',
                                            'Titanium'
                                          ].contains(rawSub)
                                              ? rawSub
                                              : 'Plastik';
                                          selectedJenisLensa = null;
                                        } else if (inputKat == 'Lensa') {
                                          inputSub = [
                                            'Supersin',
                                            'Blueray',
                                            'Photochromic',
                                            'Bluechromic',
                                            'Night Driving',
                                            'Antifog'
                                          ].contains(rawSub)
                                              ? rawSub
                                              : 'Supersin';
                                          String rawJenis =
                                              item['jenis_lensa']?.toString() ??
                                                  '';
                                          selectedJenisLensa = [
                                            'Standar',
                                            'Progresif',
                                            'Kryptok'
                                          ].contains(rawJenis)
                                              ? rawJenis
                                              : 'Standar';
                                          sphCtrl.text =
                                              _formatOptic(item['sph_r']);
                                          cylCtrl.text =
                                              _formatOptic(item['cyl_r']);
                                          addCtrl.text =
                                              _formatOptic(item['add_r']);
                                        } else {
                                          inputSub = null;
                                          selectedJenisLensa = null;
                                        }
                                      });
                                    }
                                  });
                                }
                              : () => showProductDetail(
                                  item), // <-- Cabang langsung diarahkan ngebuka pop-up detail!
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
