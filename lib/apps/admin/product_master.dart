import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'request_order_page.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/qr/product_code.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

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
  String filterSubKat = 'SEMUA';
  /// `SEMUA` or exact harga as string, e.g. `100000`.
  String filterHarga = 'SEMUA';
  /// `none` | `harga` | `sub`
  String groupMode = 'none';
  bool filtersOpen = false;
  /// Collapsed group keys when [groupMode] is harga/sub.
  final Set<String> _collapsedGroups = <String>{};

  bool get _hasActiveFilters =>
      filterUnit != 'SEMUA' ||
      filterKat != 'SEMUA' ||
      filterSubKat != 'SEMUA' ||
      filterHarga != 'SEMUA' ||
      groupMode != 'none';

  String _cabangLabel(String raw) {
    final t = raw.trim().toUpperCase();
    if (t == 'SEMUA') return 'Semua cabang';
    if (t == 'PUSAT') return 'PUSAT';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  Future<void> _pickCabangFilter() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final q = query.trim().toLowerCase();
            final filtered = units.where((u) {
              if (q.isEmpty) return true;
              final id = u.toLowerCase();
              final label = _cabangLabel(u).toLowerCase();
              return label.contains(q) || id.contains(q);
            }).toList();

            return Dialog(
              backgroundColor: OptikAdminTokens.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pilih cabang',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tutup',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close,
                                color: Colors.white38, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        autofocus: true,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Cari nama cabang...',
                          hintStyle: const TextStyle(
                              color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search,
                              color: Colors.orangeAccent, size: 18),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) =>
                            setDialogState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'Cabang tidak ditemukan',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.white.withOpacity(0.06),
                                ),
                                itemBuilder: (context, i) {
                                  final u = filtered[i];
                                  final selected = filterUnit.toUpperCase() ==
                                      u.toUpperCase();
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    leading: Icon(
                                      u == 'SEMUA'
                                          ? Icons.hub_outlined
                                          : Icons.storefront_outlined,
                                      size: 18,
                                      color: selected
                                          ? Colors.orangeAccent
                                          : Colors.white38,
                                    ),
                                    title: Text(
                                      _cabangLabel(u),
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.orangeAccent
                                            : Colors.white,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: selected
                                        ? const Icon(Icons.check_circle,
                                            color: Colors.orangeAccent,
                                            size: 18)
                                        : null,
                                    onTap: () => Navigator.pop(context, u),
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
    if (chosen != null && mounted) {
      setState(() => filterUnit = chosen);
    }
  }

  Widget _buildCabangFilterControl() {
    final selected = filterUnit != 'SEMUA';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _pickCabangFilter,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.orangeAccent.withOpacity(0.55)
                  : OptikAdminTokens.lineStrong,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.storefront_outlined : Icons.hub_outlined,
                size: 18,
                color: selected ? Colors.orangeAccent : Colors.white54,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected ? 'Cabang terpilih' : 'Semua cabang',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _cabangLabel(filterUnit),
                      style: TextStyle(
                        color: selected ? Colors.orangeAccent : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (selected)
                IconButton(
                  tooltip: 'Reset ke semua cabang',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => setState(() => filterUnit = 'SEMUA'),
                  icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                ),
              const Icon(Icons.search, color: Colors.orangeAccent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleGroupCollapsed(String key) {
    setState(() {
      if (_collapsedGroups.contains(key)) {
        _collapsedGroups.remove(key);
      } else {
        _collapsedGroups.add(key);
      }
    });
  }

  // 🎯 SELEKSI MODE BARCODE BARU
  String barcodeMode =
      'AUTOMATIC'; // Pilihan: 'AUTOMATIC' atau 'MANUAL_PRODUCT'

  List<String> units = ['SEMUA'];
  /// Full merged catalog from last fetch (before search/filter).
  List<dynamic> listProdukAll = [];
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
      // Selalu ambil semua toko lalu filter cabang di client,
      // supaya breakdown stok per cabang tetap lengkap.
      final data = await Supabase.instance.client
          .from('products')
          .select()
          .order('created_at', ascending: false);
      List<dynamic> rawList = data as List<dynamic>;

      // Group by SKU (canonical), bukan nama — hindari merge produk beda SKU.
      Map<String, Map<String, dynamic>> mapGabung = {};
      for (var item in rawList) {
        final skuKey = ProductIdentity.normalizeSku(item['sku']) ??
            ProductIdentity.normalizeBarcode(item['barcode']) ??
            'ID-${item['id']}';
        int stokSekarang = int.tryParse(item['stock'].toString()) ?? 0;
        String lokasiToko =
            item['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

        if (!mapGabung.containsKey(skuKey)) {
          mapGabung[skuKey] = Map<String, dynamic>.from(item);
          mapGabung[skuKey]!['breakdown_stok'] = [
            {"cabang": lokasiToko, "stok": stokSekarang}
          ];
          mapGabung[skuKey]!['total_stock'] = stokSekarang;
        } else {
          mapGabung[skuKey]!['total_stock'] =
              (mapGabung[skuKey]!['total_stock'] ?? 0) + stokSekarang;

          List<Map<String, dynamic>> breakdown =
              List<Map<String, dynamic>>.from(
                  mapGabung[skuKey]!['breakdown_stok']);
          breakdown.add({"cabang": lokasiToko, "stok": stokSekarang});
          mapGabung[skuKey]!['breakdown_stok'] = breakdown;
          // Prefer baris PUSAT sebagai representasi master
          if (lokasiToko == 'PUSAT') {
            final prev = mapGabung[skuKey]!;
            mapGabung[skuKey] = Map<String, dynamic>.from(item);
            mapGabung[skuKey]!['breakdown_stok'] = breakdown;
            mapGabung[skuKey]!['total_stock'] = prev['total_stock'];
          }
        }
      }

      if (mounted) {
        setState(() {
          listProdukAll = mapGabung.values.toList();
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch data error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool _productMatchesQuery(Map item, String query) {
    if (query.isEmpty) return true;
    final haystacks = <String>[
      (item['nama'] ?? '').toString(),
      (item['barcode'] ?? '').toString(),
      (item['sku'] ?? '').toString(),
      (item['kategori'] ?? '').toString(),
      (item['sub_kategori'] ?? '').toString(),
      (item['warna'] ?? '').toString(),
      (item['jenis_lensa'] ?? '').toString(),
      (item['toko_id'] ?? '').toString(),
      _formatRupiahLocal(item['harga']),
      (item['harga'] ?? '').toString(),
    ];
    return haystacks.any((s) => s.toLowerCase().contains(query));
  }

  int _stockAtToko(Map item, String toko) {
    final target = toko.trim().toUpperCase();
    final breakdown = item['breakdown_stok'];
    if (breakdown is! List) {
      final own = (item['toko_id'] ?? '').toString().toUpperCase();
      if (own == target) {
        return int.tryParse('${item['stock'] ?? 0}') ?? 0;
      }
      return 0;
    }
    for (final b in breakdown) {
      if (b is! Map) continue;
      if ((b['cabang'] ?? '').toString().toUpperCase() == target) {
        return int.tryParse('${b['stok']}') ?? 0;
      }
    }
    return 0;
  }

  bool _hasTokoRow(Map item, String toko) {
    final target = toko.trim().toUpperCase();
    final breakdown = item['breakdown_stok'];
    if (breakdown is! List) {
      return (item['toko_id'] ?? '').toString().toUpperCase() == target;
    }
    for (final b in breakdown) {
      if (b is! Map) continue;
      if ((b['cabang'] ?? '').toString().toUpperCase() == target) {
        return true;
      }
    }
    return false;
  }

  List<dynamic> get _filteredProduk {
    final query = searchController.text.toLowerCase().trim();
    final unit = filterUnit.trim().toUpperCase();
    return listProdukAll.where((raw) {
      final item = raw as Map;
      if (!_productMatchesQuery(item, query)) return false;
      if (filterKat != 'SEMUA' &&
          (item['kategori'] ?? '').toString() != filterKat) {
        return false;
      }
      if (filterSubKat != 'SEMUA') {
        final sub = (item['sub_kategori'] ?? '').toString().trim();
        if (sub.toLowerCase() != filterSubKat.toLowerCase()) return false;
      }
      if (filterHarga != 'SEMUA') {
        final h = int.tryParse((item['harga'] ?? 0).toString()) ?? 0;
        if (h.toString() != filterHarga) return false;
      }
      // Filter cabang: tampilkan produk yang punya baris di toko itu
      if (unit.isNotEmpty && unit != 'SEMUA' && unit != 'BROADCAST_ALL') {
        if (!_hasTokoRow(item, unit)) return false;
      }
      return true;
    }).toList();
  }

  List<int> get _hargaOptions {
    final set = <int>{};
    for (final raw in listProdukAll) {
      final h = int.tryParse((raw['harga'] ?? 0).toString()) ?? 0;
      if (h > 0) set.add(h);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _subKatOptions {
    final set = <String>{};
    for (final raw in listProdukAll) {
      final s = (raw['sub_kategori'] ?? '').toString().trim();
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Groups filtered products. Key = section title.
  List<MapEntry<String, List<dynamic>>> get _groupedProduk {
    final items = _filteredProduk;
    if (groupMode == 'none') {
      return [MapEntry('', items)];
    }

    final map = <String, List<dynamic>>{};
    for (final item in items) {
      String key;
      if (groupMode == 'harga') {
        key = _formatRupiahLocal(item['harga']);
      } else {
        final sub = (item['sub_kategori'] ?? '').toString().trim();
        key = sub.isEmpty ? 'Tanpa Sub Kategori' : sub;
      }
      map.putIfAbsent(key, () => []).add(item);
    }

    final entries = map.entries.toList();
    if (groupMode == 'harga') {
      entries.sort((a, b) {
        final ha = int.tryParse(
                (a.value.first['harga'] ?? 0).toString()) ??
            0;
        final hb = int.tryParse(
                (b.value.first['harga'] ?? 0).toString()) ??
            0;
        return ha.compareTo(hb);
      });
    } else {
      entries.sort(
          (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    }
    return entries;
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Colors.orangeAccent.withOpacity(0.22),
      checkmarkColor: Colors.orangeAccent,
      backgroundColor: OptikAdminTokens.card,
      side: BorderSide(
        color: selected
            ? Colors.orangeAccent.withOpacity(0.7)
            : OptikAdminTokens.lineStrong,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.orangeAccent : OptikAdminTokens.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
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
        'barcode': finalBarcode,
        'sku': finalBarcode, // SKU produk = barcode (bukan QR payload)
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

        final mut = StockMutationService();
        final actor =
            (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();
        final sku = (basePayload['sku'] ?? finalBarcode).toString();

        if (selectedCabang == "BROADCAST_ALL") {
          var pusatData = Map<String, dynamic>.from(basePayload);
          pusatData['toko_id'] = 'PUSAT';
          pusatData['stock'] = 0;
          await Supabase.instance.client.from('products').insert(pusatData);
          if (stokInput > 0) {
            await mut.opening(
              tokoId: 'PUSAT',
              sku: sku,
              qty: stokInput,
              actorNama: actor,
            );
          }

          for (var cabang in listCabang) {
            try {
              var branchData = Map<String, dynamic>.from(basePayload);
              branchData['toko_id'] = cabang.toString().toUpperCase();
              branchData['stock'] = 0;
              await Supabase.instance.client
                  .from('products')
                  .insert(branchData);
            } catch (e) {
              debugPrint("Gagal otomatis broadcast ke cabang $cabang: $e");
            }
          }
        } else {
          var specificData = Map<String, dynamic>.from(basePayload);
          specificData['toko_id'] = selectedCabang;
          specificData['stock'] = 0;
          await Supabase.instance.client.from('products').insert(specificData);
          if (stokInput > 0) {
            await mut.opening(
              tokoId: selectedCabang!,
              sku: sku,
              qty: stokInput,
              actorNama: actor,
            );
          }
        }
      } else {
        // Metadata sync ke semua toko (SKU) — stok tidak diubah di sini.
        final updateData = Map<String, dynamic>.from(basePayload);
        final sku = ProductIdentity.normalizeSku(updateData['sku']) ??
            ProductIdentity.normalizeBarcode(updateData['barcode']);
        if (sku == null) throw 'SKU wajib untuk edit produk.';
        await Supabase.instance.client
            .from('products')
            .update(updateData)
            .eq('sku', sku);
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

  /// Produk: 1D + 2D berisi payload khusus produk ([ProductCode]), bukan invoice/DO.
  Widget _buildProductCodes(String sku, {String? productId}) {
    final payload = ProductCode.encode(sku: sku, productId: productId);
    if (payload.isEmpty) return const SizedBox.shrink();

    Widget panel({required String title, required Widget child}) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
    }

    return Column(
      children: [
        panel(
          title: 'BARCODE 1D · PRODUK',
          child: SizedBox(
            width: 260,
            height: 72,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: payload,
              drawText: false,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 10),
        panel(
          title: 'QR 2D · PRODUK',
          child: SizedBox(
            width: 140,
            height: 140,
            child: BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: payload,
              drawText: false,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'SKU: ${sku.trim()}',
          style: const TextStyle(
            color: Colors.orangeAccent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          payload,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Request Order hanya lewat menu Logistik (bukan pintasan Master Data).

  // 2. POP-UP DETAIL PRODUK (premium) + distribusi stok cabang
  void showProductDetail(dynamic item) {
    final userToko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
    final isHakAksesPusat = userToko == 'PUSAT' ||
        widget.profile['role'] == 'owner' ||
        widget.profile['role'] == 'admin_pusat';

    var displayTotalStock =
        int.tryParse('${item['total_stock'] ?? item['stock'] ?? 0}') ?? 0;
    var labelStokAtas = "pm_total_stok".tr();

    final rawBreakdown = List<Map<String, dynamic>>.from(
      ((item['breakdown_stok'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)),
    );

    final visibleBreakdown = rawBreakdown.where((lokasi) {
      final cabang = lokasi['cabang']?.toString().toUpperCase() ?? '';
      return isHakAksesPusat || cabang == userToko;
    }).toList()
      ..sort((a, b) {
        final ca = (a['cabang'] ?? '').toString().toUpperCase();
        final cb = (b['cabang'] ?? '').toString().toUpperCase();
        if (ca == 'PUSAT' && cb != 'PUSAT') return -1;
        if (cb == 'PUSAT' && ca != 'PUSAT') return 1;
        final sa = int.tryParse('${a['stok']}') ?? 0;
        final sb = int.tryParse('${b['stok']}') ?? 0;
        if (sa != sb) return sb.compareTo(sa);
        return ca.compareTo(cb);
      });

    if (!isHakAksesPusat) {
      labelStokAtas = 'Stok Cabang';
      displayTotalStock = 0;
      for (final b in visibleBreakdown) {
        if (b['cabang'].toString().toUpperCase() == userToko) {
          displayTotalStock = int.tryParse('${b['stok']}') ?? 0;
          break;
        }
      }
    }

    final sku = (item['sku'] ?? item['barcode'] ?? '').toString();
    final kategori = (item['kategori'] ?? '-').toString();
    final sub = (item['sub_kategori'] ?? '-').toString();
    final cabangAktif =
        visibleBreakdown.where((e) => (int.tryParse('${e['stok']}') ?? 0) > 0).length;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: R.constrainedDialog(
          context: ctx,
          preferWidth: 440,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            decoration: BoxDecoration(
              color: OptikAdminTokens.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2DD4BF).withOpacity(0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hero header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2DD4BF).withOpacity(0.16),
                        Colors.blueAccent.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "pm_detail_produk".tr().toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (sku.isNotEmpty) ...[
                        _buildProductCodes(
                          sku,
                          productId: item['id']?.toString(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        _toTitleCase(item['nama'] ?? '-'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          _detailChip(kategori, Colors.blueAccent),
                          if (sub != '-' && sub.isNotEmpty)
                            _detailChip(sub, const Color(0xFF2DD4BF)),
                          if (sku.isNotEmpty)
                            _detailChip('SKU $sku', Colors.orangeAccent),
                        ],
                      ),
                    ],
                  ),
                ),

                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Spec + stock summary cards
                        Row(
                          children: [
                            Expanded(
                              child: _detailMetricCard(
                                label: "pm_harga_jual".tr(),
                                value: _formatRupiahLocal(item['harga']),
                                color: Colors.amberAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _detailMetricCard(
                                label: labelStokAtas,
                                value: '$displayTotalStock Pcs',
                                color: const Color(0xFF34D399),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _detailInfoPanel(
                          children: [
                            _row("pm_kat".tr(), kategori),
                            _row("pm_bahan_coating".tr(), sub),
                            if (kategori == 'Frame')
                              _row("pm_warna_frame".tr(),
                                  (item['warna'] ?? '-').toString()),
                            if (kategori == 'Lensa') ...[
                              _row("pm_jenis_lensa".tr(),
                                  (item['jenis_lensa'] ?? '-').toString()),
                              _row("pm_uk_sph".tr(),
                                  _formatOptic(item['sph_r'])),
                              _row("pm_uk_cyl".tr(),
                                  _formatOptic(item['cyl_r'])),
                              if (item['jenis_lensa'] == 'Progresif' ||
                                  item['jenis_lensa'] == 'Kryptok')
                                _row("pm_uk_add".tr(),
                                    _formatOptic(item['add_r'])),
                            ],
                          ],
                        ),

                        if (visibleBreakdown.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.storefront_rounded,
                                    color: Colors.blueAccent, size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "pm_distribusi_stok".tr().toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    Text(
                                      '$cabangAktif cabang berstok · ${visibleBreakdown.length} lokasi',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _detailActionChip(
                                icon: Icons.history_rounded,
                                label: 'RIWAYAT',
                                color: const Color(0xFF2DD4BF),
                                onTap: () {
                                  final nama = (item['nama'] ?? '').toString();
                                  Navigator.pop(ctx);
                                  Future.delayed(
                                      const Duration(milliseconds: 200), () {
                                    if (mounted) {
                                      _showBranchRevisionHistory(
                                          productNama: nama);
                                    }
                                  });
                                },
                              ),
                              if (isCanEdit) ...[
                                const SizedBox(width: 6),
                                _detailActionChip(
                                  icon: Icons.add_business_rounded,
                                  label: "pm_btn_tambah_cabang".tr(),
                                  color: const Color(0xFF4ADE80),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    Future.delayed(
                                        const Duration(milliseconds: 200), () {
                                      if (mounted) {
                                        _showAddBranchDialog(item);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...visibleBreakdown.map((lokasi) {
                            final cabang =
                                lokasi['cabang']?.toString().toUpperCase() ??
                                    '-';
                            final stok =
                                int.tryParse('${lokasi['stok']}') ?? 0;
                            final isPusat = cabang == 'PUSAT';
                            final label = cabang.startsWith('CABANG-')
                                ? cabang.replaceFirst('CABANG-', '')
                                : cabang;
                            final stockColor = stok <= 0
                                ? Colors.white38
                                : stok < 5
                                    ? Colors.orangeAccent
                                    : const Color(0xFF34D399);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPusat
                                      ? const Color(0xFF2DD4BF).withOpacity(0.35)
                                      : Colors.white.withOpacity(0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: (isPusat
                                              ? const Color(0xFF2DD4BF)
                                              : Colors.blueAccent)
                                          .withOpacity(0.14),
                                    ),
                                    child: Icon(
                                      isPusat
                                          ? Icons.warehouse_rounded
                                          : Icons.store_mall_directory_rounded,
                                      size: 17,
                                      color: isPusat
                                          ? const Color(0xFF2DD4BF)
                                          : Colors.blueAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        if (isPusat)
                                          Text(
                                            'Gudang pusat',
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.35),
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: stockColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: stockColor.withOpacity(0.35)),
                                    ),
                                    child: Text(
                                      '$stok Pcs',
                                      style: TextStyle(
                                        color: stockColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2DD4BF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'TUTUP',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _detailMetricCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailInfoPanel({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(children: children),
    );
  }

  Widget _detailActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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
              backgroundColor: OptikAdminTokens.card,
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
                                fillColor: OptikAdminTokens.bgMid,
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
        backgroundColor: OptikAdminTokens.card,
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
          "Daftarkan produk ke cabang (stok 0).\n\n"
          "Produk: ${item['nama']}\n"
          "Cabang:\n${cabangs.where((c) => c.toUpperCase() != 'PUSAT').join(', ')}\n\n"
          "Stok fisik hanya bergerak lewat RO/DO/Retur/POS. "
          "Add Branch tidak menambah qty stok.",
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

  /// Revisi master: daftar/update baris produk di cabang.
  /// Tidak memotong stok PUSAT dan tidak menulis Logistik (RO/DO).
  /// Setiap aksi dicatat ke `product_branch_revision_logs`.
  Future<void> _executeBulkAddBranch(
      Map<String, dynamic> baseProduct,
      List<String> targets,
      int additionalStock, // ignored: Add Branch always stock 0
      Map<String, int> existingStocks) async {
    setState(() => isLoading = true);
    final client = Supabase.instance.client;
    try {
      final cabangTargets = targets
          .map((t) => t.toString().trim().toUpperCase())
          .where((t) => t.isNotEmpty && t != 'PUSAT')
          .toSet()
          .toList()
        ..sort();
      if (cabangTargets.isEmpty) {
        throw 'Pilih minimal 1 cabang (bukan hanya PUSAT).';
      }

      final nama = (baseProduct['nama'] ?? '').toString().trim();
      final sku = ProductIdentity.normalizeSku(baseProduct['sku']) ??
          ProductIdentity.normalizeBarcode(baseProduct['barcode']);
      final barcode = (baseProduct['barcode'] ?? '').toString().trim();
      if (nama.isEmpty) throw 'Nama produk kosong.';
      if (sku == null) throw 'SKU wajib untuk Add Branch.';

      // Hanya daftar produk di cabang (stok 0). Qty fisik lewat RO/DO.
      final detailTokos = <Map<String, dynamic>>[];

      for (final toko in cabangTargets) {
        Map<String, dynamic>? branch = await client
            .from('products')
            .select('id, stock')
            .eq('toko_id', toko)
            .eq('sku', sku)
            .maybeSingle();

        if (branch != null) {
          final lama = int.tryParse(branch['stock']?.toString() ?? '0') ?? 0;
          detailTokos.add({
            'toko': toko,
            'created': false,
            'stock_before': lama,
            'stock_after': lama,
            'qty_delta': 0,
          });
        } else {
          final row = Map<String, dynamic>.from(baseProduct);
          row.remove('id');
          row.remove('created_at');
          row.remove('breakdown_stok');
          row.remove('total_stock');
          row['toko_id'] = toko;
          row['stock'] = 0;
          row['nama'] = nama;
          row['sku'] = sku;
          if (barcode.isNotEmpty) row['barcode'] = barcode;
          await client.from('products').insert(row);
          detailTokos.add({
            'toko': toko,
            'created': true,
            'stock_before': 0,
            'stock_after': 0,
            'qty_delta': 0,
          });
        }
      }

      final user = client.auth.currentUser;
      var logOk = true;
      try {
        await client.from('product_branch_revision_logs').insert({
          'product_nama': nama,
          'product_sku': sku,
          'product_barcode':
              barcode.isEmpty || barcode == '-' ? null : barcode,
          'tokos': cabangTargets,
          'qty_per_toko': 0,
          'action': 'add_branch',
          'changed_by': user?.id,
          'changed_by_email':
              (widget.profile['email'] ?? user?.email ?? '').toString(),
          'changed_by_nama': (widget.profile['nama'] ??
                  widget.profile['email'] ??
                  user?.email ??
                  '')
              .toString(),
          'changed_by_role': (widget.profile['role'] ?? '').toString(),
          'changed_by_toko':
              (widget.profile['toko_id'] ?? '').toString().toUpperCase(),
          'details': {
            'tokos': detailTokos,
            'product': {
              'nama': nama,
              'sku': sku,
              'barcode': barcode,
              'kategori': baseProduct['kategori'],
            },
          },
        });
      } catch (_) {
        logOk = false;
      }

      await _fetch();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '✅ Produk didaftarkan di ${cabangTargets.length} cabang (stok 0). '
            '${logOk ? 'Tercatat di riwayat.' : 'Riwayat gagal (jalankan SQL 00011).'} '
            'Pengisian stok hanya lewat RO/DO.',
          ),
          backgroundColor: logOk ? Colors.green : Colors.orange));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal revisi: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _showBranchRevisionHistory({String? productNama}) async {
    try {
      final client = Supabase.instance.client;
      final filterNama =
          productNama != null && productNama.trim().isNotEmpty
              ? productNama.trim()
              : null;
      final raw = filterNama == null
          ? await client
              .from('product_branch_revision_logs')
              .select()
              .order('created_at', ascending: false)
              .limit(80)
          : await client
              .from('product_branch_revision_logs')
              .select()
              .eq('product_nama', filterNama)
              .order('created_at', ascending: false)
              .limit(80);
      final rows = List<Map<String, dynamic>>.from(raw);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => R.constrainedDialog(
          context: ctx,
          preferWidth: 560,
          child: AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.history_rounded, color: Colors.tealAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    productNama == null || productNama.isEmpty
                        ? 'Riwayat Add Branch'
                        : 'Riwayat: $productNama',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada riwayat revisi.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12, height: 18),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final when = _formatRevisionWhen(r['created_at']);
                        final tokos = _tokosFromLog(r['tokos']);
                        final siapa = [
                          (r['changed_by_nama'] ?? r['changed_by_email'] ?? '-')
                              .toString(),
                          if ((r['changed_by_role'] ?? '')
                              .toString()
                              .isNotEmpty)
                            r['changed_by_role'].toString(),
                          if ((r['changed_by_toko'] ?? '')
                              .toString()
                              .isNotEmpty)
                            r['changed_by_toko'].toString(),
                        ].join(' · ');
                        final qty =
                            int.tryParse(r['qty_per_toko']?.toString() ?? '0') ??
                                0;
                        final sku = (r['product_sku'] ?? '').toString();
                        final detailLines = _detailLinesFromLog(r['details']);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (r['product_nama'] ?? '-').toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            if (sku.isNotEmpty)
                              Text(
                                'SKU: $sku',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              when,
                              style: TextStyle(
                                color: Colors.tealAccent.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Oleh: $siapa',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              qty > 0
                                  ? 'Qty revisi: +$qty Pcs / toko'
                                  : 'Daftar produk saja (qty 0)',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Toko (${tokos.length}): ${tokos.join(', ')}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                            if (detailLines.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...detailLines.map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    line,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('TUTUP'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal muat riwayat: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  List<String> _tokosFromLog(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  List<String> _detailLinesFromLog(dynamic raw) {
    Map<String, dynamic>? map;
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final tokos = map?['tokos'];
    if (tokos is! List) return const [];
    return tokos.map((e) {
      if (e is! Map) return e.toString();
      final t = (e['toko'] ?? '-').toString();
      final created = e['created'] == true;
      final before = e['stock_before'] ?? 0;
      final after = e['stock_after'] ?? 0;
      final delta = e['qty_delta'] ?? 0;
      if (created) {
        return '• $t: baru (stok $after)${delta != 0 ? ', +$delta' : ''}';
      }
      return '• $t: $before → $after${delta != 0 ? ' (+$delta)' : ''}';
    }).toList();
  }

  String _formatRevisionWhen(dynamic raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return raw.toString();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
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

  Widget _buildProductCard(dynamic item) {
    String namaRapi = _toTitleCase(item['nama']?.toString() ?? '-');

    String userToko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
    bool isHakAksesPusat = userToko == 'PUSAT' ||
        widget.profile['role'] == 'owner' ||
        widget.profile['role'] == 'admin_pusat';

    final unit = filterUnit.trim().toUpperCase();
    final viewingToko = !isHakAksesPusat
        ? userToko
        : (unit.isNotEmpty && unit != 'SEMUA' && unit != 'BROADCAST_ALL'
            ? unit
            : null);

    late final int displayStock;
    late final String labelStok;
    late final String lokasiLabel;

    if (viewingToko != null) {
      displayStock = _stockAtToko(item as Map, viewingToko);
      labelStok = 'Stok: ';
      lokasiLabel = _cabangLabel(viewingToko);
    } else {
      displayStock =
          int.tryParse('${item['total_stock'] ?? item['stock'] ?? 0}') ?? 0;
      labelStok = 'Total Stock: ';
      lokasiLabel = 'Semua cabang';
    }

    return PremiumPanel(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
              color: Colors.black26, borderRadius: BorderRadius.circular(10)),
          child: (item['image_url'] != null &&
                  item['image_url'].toString().isNotEmpty &&
                  item['image_url'].toString() != '-')
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(item['image_url'], fit: BoxFit.cover))
              : const Icon(Icons.image, color: Colors.white10),
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
            Text("${item['kategori']} | ${item['sub_kategori'] ?? '-'}",
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  viewingToko == null
                      ? Icons.hub_outlined
                      : Icons.location_on,
                  color: viewingToko == null
                      ? const Color(0xFF2DD4BF)
                      : Colors.blueAccent,
                  size: 11,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    lokasiLabel,
                    style: TextStyle(
                      color: viewingToko == null
                          ? const Color(0xFF2DD4BF)
                          : Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                color: OptikAdminTokens.card,
                onSelected: (action) {
                  if (action == 'detail') {
                    showProductDetail(item);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'detail',
                    child: Row(
                      children: [
                        const Icon(Icons.view_week_rounded,
                            color: Colors.blueAccent, size: 18),
                        const SizedBox(width: 8),
                        Text('$labelStok$displayStock Pcs',
                            style: const TextStyle(fontSize: 12)),
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
                          color: Colors.orangeAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text("$labelStok$displayStock Pcs",
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  const SizedBox(width: OptikAdminTokens.spaceSm),
                  IconButton(
                      iconSize: 20,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.view_week_rounded,
                          color: Colors.blueAccent, size: 20),
                      onPressed: () => showProductDetail(item)),
                ],
              ),
        onTap: isCanEdit
            ? () {
                Future.delayed(const Duration(milliseconds: 150), () {
                  if (!mounted) return;
                  if (editId == item['id'].toString()) {
                    _reset();
                  } else {
                    setState(() {
                      editId = item['id'].toString();
                      nameController.text = item['nama'] ?? '';
                      hargaController.text = _formatRupiahLocal(item['harga'] ?? 0)
                          .replaceAll('Rp', '')
                          .replaceAll('.', '')
                          .trim();
                      hargaModalController.text =
                          item['harga_modal']?.toString() ?? '0';
                      stokController.text = item['stock']?.toString() ?? '0';
                      barcodeController.text = item['barcode'] ?? '';
                      warnaCtrl.text = item['warna'] ?? '';
                      barcodeMode = 'MANUAL_PRODUCT';
                      inputKat = item['kategori'] ?? 'Frame';
                      String rawSub =
                          item['sub_kategori']?.toString().trim() ?? '';
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
                            item['jenis_lensa']?.toString() ?? '';
                        selectedJenisLensa = [
                          'Standar',
                          'Progresif',
                          'Kryptok'
                        ].contains(rawJenis)
                            ? rawJenis
                            : 'Standar';
                        sphCtrl.text = _formatOptic(item['sph_r']);
                        cylCtrl.text = _formatOptic(item['cyl_r']);
                        addCtrl.text = _formatOptic(item['add_r']);
                      } else {
                        inputSub = null;
                        selectedJenisLensa = null;
                      }
                    });
                  }
                });
              }
            : () => showProductDetail(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listProduk = _filteredProduk;
    final totalItems = listProduk.length;
    final userToko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
    final unit = filterUnit.trim().toUpperCase();
    final String? stockToko = !isCanEdit
        ? userToko
        : (unit.isNotEmpty && unit != 'SEMUA' && unit != 'BROADCAST_ALL'
            ? unit
            : null);
    final totalStock = listProduk.fold<int>(
      0,
      (sum, item) {
        final m = item as Map;
        if (stockToko != null) return sum + _stockAtToko(m, stockToko);
        return sum +
            (int.tryParse('${m['total_stock'] ?? m['stock'] ?? 0}') ?? 0);
      },
    );
    final frameCount = listProduk
        .where((item) => (item['kategori'] ?? '').toString() == 'Frame')
        .length;
    final lensaCount = listProduk
        .where((item) => (item['kategori'] ?? '').toString() == 'Lensa')
        .length;
    final grouped = _groupedProduk;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: "pm_title".tr(),
        actions: [
          IconButton(
            tooltip: 'Riwayat Add Branch',
            icon: const Icon(Icons.history_rounded, color: Colors.tealAccent),
            onPressed: () => _showBranchRevisionHistory(),
          ),
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
                      _buildProductCodes(
                        barcodeController.text,
                        productId: editId,
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
                    dropdownColor: OptikAdminTokens.card,
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
                          dropdownColor: OptikAdminTokens.card,
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
                  dropdownColor: OptikAdminTokens.card,
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
                dropdownColor: OptikAdminTokens.card,
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
                  setState(() => selectedCabang = val?.toString());
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
            PremiumSectionHeader(
              label: "pm_daftar_inventori".tr(),
              padding: const EdgeInsets.only(bottom: 10),
            ),
            PremiumStatGrid(
              padding: const EdgeInsets.only(bottom: OptikAdminTokens.spaceMd),
              items: [
                PremiumStatItem(
                  label: 'Total SKU',
                  value: '$totalItems',
                  color: Colors.orangeAccent,
                ),
                PremiumStatItem(
                  label: 'Total Stok',
                  value: '$totalStock PCS',
                  color: Colors.blueAccent,
                ),
                PremiumStatItem(
                  label: 'Frame',
                  value: '$frameCount',
                  color: Colors.tealAccent,
                ),
                PremiumStatItem(
                  label: 'Lensa',
                  value: '$lensaCount',
                  color: Colors.purpleAccent,
                ),
              ],
            ),

            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                  hintText: 'Cari nama, sub kategori, warna, SKU…',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.orangeAccent, size: 18),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white38, size: 18),
                          onPressed: () {
                            searchController.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.03),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none)),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => filtersOpen = !filtersOpen),
                icon: Icon(
                  filtersOpen
                      ? Icons.filter_alt_off_outlined
                      : Icons.filter_alt_outlined,
                  size: 18,
                  color: _hasActiveFilters || filtersOpen
                      ? Colors.orangeAccent
                      : OptikAdminTokens.textSecondary,
                ),
                label: Text(
                  filtersOpen ? 'Tutup filter' : 'Filter',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _hasActiveFilters || filtersOpen
                        ? Colors.orangeAccent
                        : OptikAdminTokens.textSecondary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  foregroundColor: Colors.orangeAccent,
                ),
              ),
            ),
            if (filtersOpen) ...[
              if (isCanEdit) ...[
                const SizedBox(height: OptikAdminTokens.spaceSm),
                Text('Filter cabang',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildCabangFilterControl(),
                const SizedBox(height: OptikAdminTokens.spaceMd),
              ],
              Text('Grup tampilan',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              PremiumChipWrap(
                children: [
                  _filterChip(
                    label: 'Tanpa grup',
                    selected: groupMode == 'none',
                    onTap: () => setState(() {
                      groupMode = 'none';
                      _collapsedGroups.clear();
                    }),
                  ),
                  _filterChip(
                    label: 'Grup harga',
                    selected: groupMode == 'harga',
                    onTap: () => setState(() {
                      groupMode = 'harga';
                      _collapsedGroups.clear();
                    }),
                  ),
                  _filterChip(
                    label: 'Grup sub kategori',
                    selected: groupMode == 'sub',
                    onTap: () => setState(() {
                      groupMode = 'sub';
                      _collapsedGroups.clear();
                    }),
                  ),
                ],
              ),
              const SizedBox(height: OptikAdminTokens.spaceMd),
              Text('Filter kategori',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              PremiumChipWrap(
                children: [
                  for (final k in const ['SEMUA', 'Frame', 'Lensa', 'Lainnya'])
                    _filterChip(
                      label: k == 'SEMUA' ? 'Semua' : k,
                      selected: filterKat == k,
                      onTap: () => setState(() => filterKat = k),
                    ),
                ],
              ),
              if (_hargaOptions.isNotEmpty) ...[
                const SizedBox(height: OptikAdminTokens.spaceMd),
                Text('Filter harga',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                PremiumChipWrap(
                  children: [
                    _filterChip(
                      label: 'Semua',
                      selected: filterHarga == 'SEMUA',
                      onTap: () => setState(() => filterHarga = 'SEMUA'),
                    ),
                    for (final h in _hargaOptions)
                      _filterChip(
                        label: _formatRupiahLocal(h),
                        selected: filterHarga == h.toString(),
                        onTap: () =>
                            setState(() => filterHarga = h.toString()),
                      ),
                  ],
                ),
              ],
              if (_subKatOptions.isNotEmpty) ...[
                const SizedBox(height: OptikAdminTokens.spaceMd),
                Text('Filter sub kategori',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                PremiumChipWrap(
                  children: [
                    _filterChip(
                      label: 'Semua',
                      selected: filterSubKat == 'SEMUA',
                      onTap: () => setState(() => filterSubKat = 'SEMUA'),
                    ),
                    for (final s in _subKatOptions)
                      _filterChip(
                        label: s,
                        selected:
                            filterSubKat.toLowerCase() == s.toLowerCase(),
                        onTap: () => setState(() => filterSubKat = s),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: OptikAdminTokens.spaceMd),

            isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.orangeAccent))
                : listProduk.isEmpty
                    ? PremiumEmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: searchController.text.trim().isEmpty
                            ? 'Belum ada data inventori.'
                            : 'Tidak ada yang cocok dengan pencarian/filter.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final group in grouped) ...[
                            if (group.key.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 6),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () =>
                                        _toggleGroupCollapsed(group.key),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: OptikAdminTokens.card
                                            .withOpacity(0.55),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: OptikAdminTokens.lineStrong,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _collapsedGroups
                                                    .contains(group.key)
                                                ? Icons.chevron_right_rounded
                                                : Icons
                                                    .expand_more_rounded,
                                            color: Colors.orangeAccent,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${group.key.toUpperCase()}  (${group.value.length})',
                                              style: TextStyle(
                                                color: OptikAdminTokens
                                                    .textMuted
                                                    .withOpacity(0.95),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _collapsedGroups
                                                    .contains(group.key)
                                                ? 'Buka'
                                                : 'Tutup',
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.45),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!_collapsedGroups.contains(group.key))
                              for (final item in group.value)
                                _buildProductCard(item),
                          ],
                        ],
                      ),
          ],
        ),
      ),
    );
  }
}
