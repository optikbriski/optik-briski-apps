import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'request_order_page.dart';
import '../../shared/logistics/product_identity.dart';
import '../../shared/logistics/stock_actor_gate.dart';
import '../../shared/logistics/stock_mutation_service.dart';
import '../../shared/logistics/stock_realtime.dart';
import '../../shared/qr/product_code.dart';
import '../../shared/responsive.dart';
import '../../shared/tenant/tenant_service.dart';
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
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  /// Toko yang sedang dilihat di list (filter cabang / toko login).
  String? get _viewingTokoScope {
    final userToko =
        widget.profile['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
    final isHakAksesPusat = userToko == 'PUSAT' ||
        widget.profile['role'] == 'owner' ||
        widget.profile['role'] == 'admin_pusat';
    final unit = filterUnit.trim().toUpperCase();
    if (!isHakAksesPusat) return userToko;
    if (unit.isNotEmpty && unit != 'SEMUA' && unit != 'BROADCAST_ALL') {
      return unit;
    }
    return null; // semua cabang
  }

  Future<void> _pickCabangFilter() async {
    final options = units
        .where((u) => u != 'SEMUA')
        .map(
          (u) => AdminPickerOption<String>(
            value: u,
            label: _cabangLabel(u),
            icon: u == 'PUSAT'
                ? Icons.hub_outlined
                : Icons.storefront_outlined,
          ),
        )
        .toList();

    final result = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cabang',
      options: options,
      selected: filterUnit == 'SEMUA' ? null : filterUnit,
      clearLabel: 'Semua cabang',
      clearSubtitle: 'Tampilkan semua cabang',
      clearIcon: Icons.hub_outlined,
      searchHint: 'Cari nama cabang...',
      filterOption: (o, q) =>
          o.label.toLowerCase().contains(q) ||
          o.value.toLowerCase().contains(q),
    );

    if (result == null || !mounted) return;
    setState(() {
      filterUnit = result.isClear ? 'SEMUA' : result.value!;
    });
  }

  List<String> get _subKategoriOptions {
    if (inputKat == 'Frame') {
      return ['Plastik', 'Besi', 'Kayu', 'Titanium'];
    }
    if (inputKat == 'Lensa') {
      return [
        'Supersin',
        'Blueray',
        'Photochromic',
        'Bluechromic',
        'Night Driving',
        'Antifog',
      ];
    }
    return const [];
  }

  String _stokAwalCabangLabel(String? value) {
    if (value == null) return 'Pilih lokasi stok awal…';
    if (value == 'BROADCAST_ALL') return 'Stok awal: PUSAT';
    if (value == 'PUSAT') return 'pm_pusat'.tr();
    return 'Stok awal: ${value.toUpperCase()}';
  }

  Future<void> _pickKategori() async {
    const options = ['Frame', 'Lensa', 'Lainnya'];
    final result = await showAdminPicker<String>(
      context: context,
      title: 'pm_kat'.tr(),
      options: options
          .map((k) => AdminPickerOption(value: k, label: k))
          .toList(),
      selected: inputKat,
      searchable: false,
    );
    if (result == null || result.value == null || !mounted) return;
    setState(() {
      inputKat = result.value!;
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
  }

  Future<void> _pickSubKategori() async {
    final subs = _subKategoriOptions;
    if (subs.isEmpty) return;
    final result = await showAdminPicker<String>(
      context: context,
      title: 'pm_bahan_coating'.tr(),
      options: subs.map((s) => AdminPickerOption(value: s, label: s)).toList(),
      selected: inputSub,
      searchable: false,
    );
    if (result == null || result.value == null || !mounted) return;
    setState(() => inputSub = result.value);
  }

  Future<void> _pickJenisLensa() async {
    const options = ['Standar', 'Progresif', 'Kryptok'];
    final result = await showAdminPicker<String>(
      context: context,
      title: 'pm_jenis_lensa'.tr(),
      options: options
          .map((e) => AdminPickerOption(value: e, label: e))
          .toList(),
      selected: selectedJenisLensa,
      searchable: false,
    );
    if (result == null || result.value == null || !mounted) return;
    setState(() => selectedJenisLensa = result.value);
  }

  Future<void> _pickStokAwalCabang() async {
    final options = <AdminPickerOption<String>>[
      const AdminPickerOption(
        value: 'BROADCAST_ALL',
        label: 'Stok awal: PUSAT',
        subtitle: 'Produk terdaftar di semua toko (stok 0)',
        icon: Icons.hub_outlined,
      ),
      AdminPickerOption(
        value: 'PUSAT',
        label: 'pm_pusat'.tr(),
        icon: Icons.store_outlined,
      ),
      ...listCabang.map(
        (cabang) => AdminPickerOption(
          value: cabang.toString(),
          label: 'Stok awal: ${cabang.toString().toUpperCase()}',
          icon: Icons.storefront_outlined,
        ),
      ),
    ];

    final result = await showAdminPicker<String>(
      context: context,
      title: 'Stok awal ke',
      subtitle: 'Katalog otomatis semua toko',
      options: options,
      selected: selectedCabang,
      searchable: listCabang.length > 6,
      headerIcon: Icons.store_rounded,
    );
    if (result == null || result.value == null || !mounted) return;
    setState(() => selectedCabang = result.value);
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
            color: OptikAdminTokens.navy.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? OptikAdminTokens.warning.withOpacity(0.55)
                  : OptikAdminTokens.lineStrong,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.storefront_outlined : Icons.hub_outlined,
                size: 18,
                color: selected ? OptikAdminTokens.warning : OptikAdminTokens.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected ? 'Cabang terpilih' : 'Semua cabang',
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.45),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _cabangLabel(filterUnit),
                      style: TextStyle(
                        color: selected
                            ? OptikAdminTokens.warning
                            : OptikAdminTokens.navy,
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
                  icon: const Icon(Icons.close, color: OptikAdminTokens.textMuted, size: 18),
                ),
              const Icon(Icons.search, color: OptikAdminTokens.warning, size: 18),
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
  /// SKU kanonik baris yang diedit — identitas tidak boleh berubah diam-diam.
  String? editSkuOriginal;
  /// Toko baris yang sedang diedit (untuk revisi Real stock).
  String? editTokoId;
  int? _editStockBefore;
  int? _editPendingBefore;
  List<dynamic> listCabang = [];
  /// Target stok awal saat create. Katalog selalu ke PUSAT + semua toko.
  String? selectedCabang = 'BROADCAST_ALL';

  StockRealtimeSubscription? _stockRt;
  Timer? _stockRtDebounce;
  /// Event stok masuk saat `_fetch` masih loading → refresh ulang setelah selesai.
  bool _stockRtPendingRefresh = false;

  //--- 4. SIKLUS HIDUP WIDGET (INIT & DISPOSE MEMORI)
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _stockRtDebounce?.cancel();
    unawaited(_stockRt?.dispose() ?? Future.value());
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

  void _startStockRealtime() {
    unawaited(_stockRt?.dispose() ?? Future.value());
    _stockRt = StockRealtime.subscribeAllProducts(
      onEvent: (_) {
        _stockRtDebounce?.cancel();
        _stockRtDebounce = Timer(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          if (isLoading) {
            _stockRtPendingRefresh = true;
            return;
          }
          unawaited(_fetch(silent: true));
        });
      },
    );
  }

  void _flushPendingStockRealtimeRefresh() {
    if (!_stockRtPendingRefresh || !mounted || isLoading) return;
    _stockRtPendingRefresh = false;
    unawaited(_fetch(silent: true));
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
        _startStockRealtime();
        // Semua SKU PUSAT wajib terdaftar di semua toko (stok tidak ikut).
        if (isCanEdit) {
          unawaited(_syncPusatCatalogToAllTokoQuiet());
        }
      }
    } catch (e) {
      debugPrint("Init error: $e");
    }
  }

  /// Tegakkan katalog PUSAT = semua cabang 100% (stok tidak disentuh).
  Future<void> _syncPusatCatalogToAllTokoQuiet() async {
    try {
      await Supabase.instance.client.rpc('enforce_catalog_parity');
      if (mounted) await _fetch();
    } catch (e) {
      // Fallback nama RPC lama (migrasi belum jalan)
      try {
        await Supabase.instance.client.rpc('backfill_pusat_catalog_to_all_toko');
        if (mounted) await _fetch();
      } catch (e2) {
        debugPrint('Quiet catalog parity: $e / $e2');
      }
    }
  }

  /// Pastikan SKU terdaftar di semua toko (stok 0). RPC dulu, fallback insert client.
  Future<void> _propagateSkuToAllToko({
    required String sku,
    Map<String, dynamic>? template,
  }) async {
    final client = Supabase.instance.client;
    try {
      await client.rpc('propagate_pusat_sku_to_all_toko', params: {
        'p_sku': sku,
        'p_tenant_id': TenantService.instance.boundId,
      });
      return;
    } catch (e) {
      debugPrint('RPC propagate_pusat_sku_to_all_toko gagal, fallback: $e');
    }

    final base = Map<String, dynamic>.from(template ?? const {});
    for (final k in [
      'id',
      'created_at',
      'breakdown_stok',
      'total_stock',
      'total_pending',
      'total_available',
    ]) {
      base.remove(k);
    }
    base['sku'] = sku;
    base['stock'] = 0;
    base['reserved_qty'] = 0;

    for (final cabang in listCabang) {
      final toko = cabang.toString().toUpperCase();
      if (toko.isEmpty || toko == 'PUSAT') continue;
      try {
        await ProductIdentity.ensureAtToko(tokoId: toko, sku: sku);
      } catch (e) {
        debugPrint('Gagal daftar SKU $sku di $toko: $e');
        try {
          final existing = await ProductIdentity.findAtToko(
            tokoId: toko,
            sku: sku,
            select: 'id',
          );
          if (existing != null) continue;
          final row = Map<String, dynamic>.from(base);
          row['toko_id'] = toko;
          row['stock'] = 0;
          row['reserved_qty'] = 0;
          await client.from('products').insert(row);
        } catch (e2) {
          debugPrint('Fallback insert SKU $sku @ $toko: $e2');
        }
      }
    }
  }

  Future<void> _syncPusatCatalogToAllToko() async {
    setState(() => isLoading = true);
    try {
      try {
        dynamic res;
        try {
          res = await Supabase.instance.client.rpc('enforce_catalog_parity');
        } catch (_) {
          res = await Supabase.instance.client
              .rpc('backfill_pusat_catalog_to_all_toko');
        }
        if (!mounted) return;
        final map = res is Map ? Map<String, dynamic>.from(res) : null;
        final ok = map?['parity_ok'] == true || map?['gaps'] == 0;
        final pusat = map?['pusat_skus'] ?? map?['skus'] ?? '?';
        final gaps = map?['gaps'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            ok
                ? 'Katalog 100% sama: PUSAT & semua cabang ($pusat SKU). Stok tidak diubah.'
                : 'Katalog disinkron ($pusat SKU). Sisa gap: ${gaps ?? "?"}. Stok tidak diubah.',
          ),
          backgroundColor: ok ? OptikAdminTokens.success : OptikAdminTokens.warning,
        ));
      } catch (e) {
        // Fallback: tiap SKU PUSAT di list gabungan
        var n = 0;
        for (final raw in listProdukAll) {
          final item = raw as Map;
          final sku = ProductIdentity.normalizeSku(item['sku']) ??
              ProductIdentity.normalizeBarcode(item['barcode']);
          if (sku == null) continue;
          await _propagateSkuToAllToko(
            sku: sku,
            template: Map<String, dynamic>.from(item),
          );
          n++;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Katalog disinkron via fallback ($n SKU). Stok tidak diubah.'),
          backgroundColor: OptikAdminTokens.success,
        ));
      }
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal sinkron: $e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. ALGORITMA UTAMA: AMBIL DATA & GABUNGKAN STOK PRODUK ANTAR-GUDANG
  Future<void> _fetch({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);
    try {
      // Selalu ambil semua toko lalu filter cabang di client,
      // supaya breakdown stok per cabang tetap lengkap.
      final data = await Supabase.instance.client
          .from('products')
          .select()
          .order('created_at', ascending: false);
      List<dynamic> rawList = data as List<dynamic>;

      // Group by SKU casefold (selaras RPC / ledger), bukan nama.
      Map<String, Map<String, dynamic>> mapGabung = {};
      for (var item in rawList) {
        final rawKey = ProductIdentity.normalizeSku(item['sku']) ??
            ProductIdentity.normalizeBarcode(item['barcode']) ??
            'ID-${item['id']}';
        final skuKey = rawKey.toUpperCase();
        final itemMap = Map<String, dynamic>.from(item as Map);
        final realSekarang = StockQty.realOf(itemMap);
        final pendingSekarang = StockQty.pendingOf(itemMap);
        final availableSekarang = StockQty.availableOf(itemMap);
        String lokasiToko =
            item['toko_id']?.toString().toUpperCase() ?? 'PUSAT';

        if (!mapGabung.containsKey(skuKey)) {
          mapGabung[skuKey] = Map<String, dynamic>.from(item);
          mapGabung[skuKey]!['breakdown_stok'] = [
            {
              "cabang": lokasiToko,
              "stok": realSekarang,
              "pending": pendingSekarang,
              "available": availableSekarang,
            }
          ];
          mapGabung[skuKey]!['total_stock'] = realSekarang;
          mapGabung[skuKey]!['total_pending'] = pendingSekarang;
          mapGabung[skuKey]!['total_available'] = availableSekarang;
        } else {
          mapGabung[skuKey]!['total_stock'] =
              (mapGabung[skuKey]!['total_stock'] ?? 0) + realSekarang;
          mapGabung[skuKey]!['total_pending'] =
              (mapGabung[skuKey]!['total_pending'] ?? 0) + pendingSekarang;
          mapGabung[skuKey]!['total_available'] =
              (mapGabung[skuKey]!['total_available'] ?? 0) + availableSekarang;

          List<Map<String, dynamic>> breakdown =
              List<Map<String, dynamic>>.from(
                  mapGabung[skuKey]!['breakdown_stok']);
          breakdown.add({
            "cabang": lokasiToko,
            "stok": realSekarang,
            "pending": pendingSekarang,
            "available": availableSekarang,
          });
          mapGabung[skuKey]!['breakdown_stok'] = breakdown;
          // Prefer baris PUSAT sebagai representasi master
          if (lokasiToko == 'PUSAT') {
            final prev = mapGabung[skuKey]!;
            mapGabung[skuKey] = Map<String, dynamic>.from(item);
            mapGabung[skuKey]!['breakdown_stok'] = breakdown;
            mapGabung[skuKey]!['total_stock'] = prev['total_stock'];
            mapGabung[skuKey]!['total_pending'] = prev['total_pending'];
            mapGabung[skuKey]!['total_available'] = prev['total_available'];
          }
        }
      }

      if (mounted) {
        setState(() {
          listProdukAll = mapGabung.values.toList();
          isLoading = false;
        });
        _flushPendingStockRealtimeRefresh();
      }
    } catch (e) {
      debugPrint("Fetch data error: $e");
      if (mounted) {
        setState(() => isLoading = false);
        _flushPendingStockRealtimeRefresh();
      }
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

  Map<String, dynamic>? _breakdownAtToko(Map item, String toko) {
    final target = toko.trim().toUpperCase();
    final breakdown = item['breakdown_stok'];
    if (breakdown is! List) {
      final own = (item['toko_id'] ?? '').toString().toUpperCase();
      if (own == target) {
        final real = StockQty.realOf(Map<String, dynamic>.from(item));
        final pending = StockQty.pendingOf(Map<String, dynamic>.from(item));
        return {
          'cabang': own,
          'stok': real,
          'pending': pending,
          'available': StockQty.available(real, pending),
        };
      }
      return null;
    }
    for (final b in breakdown) {
      if (b is! Map) continue;
      if ((b['cabang'] ?? '').toString().toUpperCase() == target) {
        return Map<String, dynamic>.from(b);
      }
    }
    return null;
  }

  int _stockAtToko(Map item, String toko) =>
      int.tryParse('${_breakdownAtToko(item, toko)?['stok'] ?? 0}') ?? 0;

  int _pendingAtToko(Map item, String toko) =>
      int.tryParse('${_breakdownAtToko(item, toko)?['pending'] ?? 0}') ?? 0;

  int _availableAtToko(Map item, String toko) {
    final b = _breakdownAtToko(item, toko);
    if (b == null) return 0;
    final avail = int.tryParse('${b['available']}');
    if (avail != null) return avail;
    return StockQty.available(
      int.tryParse('${b['stok'] ?? 0}') ?? 0,
      int.tryParse('${b['pending'] ?? 0}') ?? 0,
    );
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
          backgroundColor: OptikAdminTokens.warning));
      return;
    }

    // 2. Validasi Jika Kasir Memilih Barcode Bawaan Tapi Kolom Masih Kosong
    if (barcodeMode == 'MANUAL_PRODUCT' &&
        barcodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Barcode Bawaan Produk Wajib Diisi / Di-scan!"),
          backgroundColor: OptikAdminTokens.warning));
      return;
    }

    // UPDATE / ADD: wajib scan QR karyawan yang SAMA dengan "via siapa" login kode.
    final allowed = await StockActorGate.requireMatchingViaKaryawanQr(
      context: context,
      profile: widget.profile,
      actionLabel: editId == null
          ? 'tambah produk ke Master Produk'
          : 'ubah data Master Produk',
    );
    if (!allowed || !mounted) return;

    setState(() => isLoading = true);
    try {
      // Duplikat barcode: cek di PUSAT (katalog kanonik).
      if (editId == null && barcodeMode == 'MANUAL_PRODUCT') {
        final bc = barcodeController.text.trim();
        final checkExist = await Supabase.instance.client
            .from('products')
            .select('nama')
            .eq('toko_id', 'PUSAT')
            .ilike('barcode', bc)
            .limit(1)
            .maybeSingle();

        if (checkExist != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Barcode sudah terdaftar untuk: ${checkExist['nama']}'),
              backgroundColor: OptikAdminTokens.danger));
          setState(() => isLoading = false);
          return;
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
              backgroundColor: OptikAdminTokens.warning));
          setState(() => isLoading = false);
          return;
        }

        int stokInput = int.tryParse(stokController.text) ?? 0;

        final mut = StockMutationService();
        final actor =
            (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString();
        final sku = (basePayload['sku'] ?? finalBarcode).toString();
        final client = Supabase.instance.client;

        // Katalog selalu: PUSAT + semua toko (stok 0). Qty awal hanya di lokasi alokasi.
        final pusatData = Map<String, dynamic>.from(basePayload);
        pusatData['toko_id'] = 'PUSAT';
        pusatData['stock'] = 0;
        pusatData['reserved_qty'] = 0;
        await client.from('products').insert(pusatData);

        await _propagateSkuToAllToko(
          sku: sku,
          template: basePayload,
        );

        final openingToko =
            (selectedCabang == null ||
                    selectedCabang == 'BROADCAST_ALL' ||
                    selectedCabang == 'PUSAT')
                ? 'PUSAT'
                : selectedCabang!.toString().toUpperCase();

        if (stokInput > 0) {
          await mut.opening(
            tokoId: openingToko,
            sku: sku,
            qty: stokInput,
            actorNama: actor,
          );
        }
      } else {
        // Identitas SKU tetap (hindari rewrite diam-diam yang bikin update 0 baris).
        final sku = (editSkuOriginal ??
                ProductIdentity.normalizeSku(basePayload['sku']) ??
                ProductIdentity.normalizeBarcode(basePayload['barcode']))
            ?.trim();
        if (sku == null || sku.isEmpty) {
          throw 'SKU wajib untuk edit produk.';
        }

        final updateData = Map<String, dynamic>.from(basePayload);
        updateData['sku'] = sku;
        updateData['barcode'] = sku;

        // Revisi stok: minta alasan DULU sebelum commit metadata.
        final tokoRev =
            (editTokoId ?? 'PUSAT').toString().trim().toUpperCase();
        final newStock = int.tryParse(stokController.text.trim());
        final before = _editStockBefore ?? 0;
        final pendingBefore = _editPendingBefore ?? 0;
        String? alasanStock;
        if (newStock != null && newStock != before) {
          if (newStock < pendingBefore) {
            throw 'Stok Real baru ($newStock) tidak boleh di bawah booking '
                '($pendingBefore) di ${_cabangLabel(tokoRev)}.';
          }
          alasanStock = await _askRevisiAlasan(
            before: before,
            after: newStock,
            toko: tokoRev,
            pending: pendingBefore,
          );
          if (alasanStock == null || alasanStock.trim().isEmpty) {
            throw 'Revisi stok dibatalkan — alasan wajib.';
          }
        }

        await Supabase.instance.client
            .from('products')
            .update(updateData)
            .eq('sku', sku);

        if (alasanStock != null && newStock != null) {
          final actor = (widget.profile['nama'] ??
                  widget.profile['email'] ??
                  '')
              .toString();
          await StockMutationService().reviseTo(
            tokoId: tokoRev,
            sku: sku,
            newStock: newStock,
            alasan: alasanStock.trim(),
            actorNama: actor,
          );
        }
      }

      if (mounted) {
        _reset();
        _fetch();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("pm_sukses_simpan".tr()),
            backgroundColor: OptikAdminTokens.success));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal: $e"), backgroundColor: OptikAdminTokens.danger));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<String?> _askRevisiAlasan({
    required int before,
    required int after,
    required String toko,
    int pending = 0,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Alasan revisi stok',
          style: TextStyle(color: OptikAdminTokens.navy, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Toko ${_cabangLabel(toko)}: Real $before → $after pcs'
              '${pending > 0 ? '\nBooking $pending (Real baru ≥ booking).' : ''}\n'
              'Wajib isi alasan (tercatat di ledger ADJUST).',
              style: const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: OptikAdminTokens.navy),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan',
                labelStyle: TextStyle(color: OptikAdminTokens.textMuted),
                hintText: 'Contoh: stock opname / selisih fisik',
                hintStyle: TextStyle(color: OptikAdminTokens.lineStrong),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (ok != true) return null;
    return text;
  }

  /// Revisi Real stock dari detail produk (per toko) — wajib scan QR karyawan.
  Future<void> _revisiStokDariDetail({
    required String sku,
    required String tokoId,
    required int currentReal,
    required String namaProduk,
    int currentPending = 0,
  }) async {
    final allowed = await StockActorGate.requireMatchingViaKaryawanQr(
      context: context,
      profile: widget.profile,
      actionLabel: 'revisi stok',
    );
    if (!allowed || !mounted) return;

    final stockCtrl = TextEditingController(text: currentReal.toString());
    final alasanCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: const Text(
          'Revisi Stok Real',
          style: TextStyle(color: OptikAdminTokens.navy, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$namaProduk\n'
              'Toko: ${_cabangLabel(tokoId)}\n'
              'Real $currentReal · Booking $currentPending · '
              'Tersedia ${StockQty.available(currentReal, currentPending)}',
              style: const TextStyle(color: OptikAdminTokens.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: OptikAdminTokens.navy),
              decoration: InputDecoration(
                labelText: 'Stok Real baru',
                labelStyle: const TextStyle(color: OptikAdminTokens.textMuted),
                helperText: currentPending > 0
                    ? 'Minimal $currentPending (tidak boleh di bawah booking)'
                    : null,
              ),
            ),
            TextField(
              controller: alasanCtrl,
              style: const TextStyle(color: OptikAdminTokens.navy),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan (wajib)',
                labelStyle: TextStyle(color: OptikAdminTokens.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final newStock = int.tryParse(stockCtrl.text.trim());
    final alasan = alasanCtrl.text.trim();
    stockCtrl.dispose();
    alasanCtrl.dispose();
    if (ok != true || !mounted) return;
    if (newStock == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stok baru tidak valid.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    if (alasan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Alasan revisi wajib.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    if (newStock == currentReal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada perubahan stok.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    if (newStock < currentPending) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Real baru ($newStock) di bawah booking ($currentPending).',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }

    try {
      await StockMutationService().reviseTo(
        tokoId: tokoId,
        sku: sku,
        newStock: newStock,
        alasan: alasan,
        actorNama:
            (widget.profile['nama'] ?? widget.profile['email'] ?? '').toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Revisi ${_cabangLabel(tokoId)}: $currentReal → $newStock pcs',
        ),
        backgroundColor: OptikAdminTokens.success,
      ));
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal revisi: $e'),
        backgroundColor: OptikAdminTokens.danger,
      ));
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
    editSkuOriginal = null;
    editTokoId = null;
    _editStockBefore = null;
    _editPendingBefore = null;

    sphCtrl.text = "0.00";
    cylCtrl.text = "0.00";
    addCtrl.text = "0.00";

    setState(() {
      editId = null;
      inputKat = 'Frame';
      inputSub = 'Plastik';
      selectedJenisLensa = null;
      selectedCabang = 'BROADCAST_ALL';
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
          color: OptikAdminTokens.navy,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: OptikAdminTokens.slate,
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
              color: OptikAdminTokens.bg,
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
              color: OptikAdminTokens.bg,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'SKU: ${sku.trim()}',
          style: const TextStyle(
            color: OptikAdminTokens.warning,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          payload,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: OptikAdminTokens.navy.withOpacity(0.55),
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
    var displayPending =
        int.tryParse('${item['total_pending'] ?? item['reserved_qty'] ?? 0}') ??
            0;
    var displayAvailable = int.tryParse(
            '${item['total_available'] ?? StockQty.available(displayTotalStock, displayPending)}') ??
        0;
    var labelStokAtas = 'Total Real';

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
      labelStokAtas = 'Real Cabang';
      displayTotalStock = 0;
      displayPending = 0;
      displayAvailable = 0;
      for (final b in visibleBreakdown) {
        if (b['cabang'].toString().toUpperCase() == userToko) {
          displayTotalStock = int.tryParse('${b['stok']}') ?? 0;
          displayPending = int.tryParse('${b['pending'] ?? 0}') ?? 0;
          displayAvailable = int.tryParse('${b['available'] ?? 0}') ??
              StockQty.available(displayTotalStock, displayPending);
          break;
        }
      }
    }

    final sku = (item['sku'] ?? item['barcode'] ?? '').toString();
    final kategori = (item['kategori'] ?? '-').toString();
    final sub = (item['sub_kategori'] ?? '-').toString();
    final cabangAktif =
        visibleBreakdown
            .where((e) =>
                (int.tryParse('${e['available'] ?? e['stok']}') ?? 0) > 0)
            .length;

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
              border: Border.all(color: OptikAdminTokens.navy.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: OptikAdminTokens.accentSoft.withOpacity(0.08),
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
                        OptikAdminTokens.accentSoft.withOpacity(0.16),
                        OptikAdminTokens.accentSoft.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "pm_detail_produk".tr().toUpperCase(),
                        style: TextStyle(
                          color: OptikAdminTokens.navy.withOpacity(0.45),
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
                          color: OptikAdminTokens.navy,
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
                          _detailChip(kategori, OptikAdminTokens.ice),
                          if (sub != '-' && sub.isNotEmpty)
                            _detailChip(sub, OptikAdminTokens.ice),
                          if (sku.isNotEmpty)
                            _detailChip('SKU $sku', OptikAdminTokens.warning),
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
                                color: OptikAdminTokens.warning,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _detailMetricCard(
                                label: labelStokAtas,
                                value: '$displayTotalStock Pcs',
                                color: OptikAdminTokens.success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _detailMetricCard(
                                label: 'Booking',
                                value: '$displayPending Pcs',
                                color: OptikAdminTokens.warning,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _detailMetricCard(
                                label: 'Tersedia',
                                value: '$displayAvailable Pcs',
                                color: OptikAdminTokens.success,
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
                                  color: OptikAdminTokens.accentSoft.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.storefront_rounded,
                                    color: OptikAdminTokens.navy, size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "pm_distribusi_stok".tr().toUpperCase(),
                                      style: const TextStyle(
                                        color: OptikAdminTokens.navy,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    Text(
                                      '$cabangAktif cabang berstok · ${visibleBreakdown.length} lokasi',
                                      style: TextStyle(
                                        color: OptikAdminTokens.navy.withOpacity(0.4),
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _detailActionChip(
                                icon: Icons.history_rounded,
                                label: 'Riwayat',
                                color: OptikAdminTokens.navy,
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
                                  color: OptikAdminTokens.success,
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
                            final pending =
                                int.tryParse('${lokasi['pending'] ?? 0}') ?? 0;
                            final available = int.tryParse(
                                    '${lokasi['available'] ?? StockQty.available(stok, pending)}') ??
                                0;
                            final isPusat = cabang == 'PUSAT';
                            final label = cabang.startsWith('CABANG-')
                                ? cabang.replaceFirst('CABANG-', '')
                                : cabang;
                            final stockColor = available <= 0
                                ? OptikAdminTokens.textMuted
                                : available < 5
                                    ? OptikAdminTokens.warning
                                    : OptikAdminTokens.success;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(
                                color: OptikAdminTokens.navy.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPusat
                                      ? OptikAdminTokens.accentSoft.withOpacity(0.35)
                                      : OptikAdminTokens.snow.withOpacity(0.06),
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
                                              ? OptikAdminTokens.navy
                                              : OptikAdminTokens.ice)
                                          .withOpacity(0.14),
                                    ),
                                    child: Icon(
                                      isPusat
                                          ? Icons.warehouse_rounded
                                          : Icons.store_mall_directory_rounded,
                                      size: 17,
                                      color: isPusat
                                          ? OptikAdminTokens.navy
                                          : OptikAdminTokens.ice,
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
                                            color: OptikAdminTokens.navy,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        if (isPusat)
                                          Text(
                                            'Gudang pusat',
                                            style: TextStyle(
                                              color:
                                                  OptikAdminTokens.slate.withOpacity(0.35),
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      'Real $stok · Booking $pending · Tersedia $available',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: stockColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                  if (isHakAksesPusat || cabang == userToko) ...[
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: 'Revisi stok Real',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 32, minHeight: 32),
                                      icon: const Icon(
                                        Icons.edit_note_rounded,
                                        color: OptikAdminTokens.warning,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        final skuKey = (item['sku'] ??
                                                item['barcode'] ??
                                                '')
                                            .toString();
                                        if (skuKey.isEmpty) return;
                                        Navigator.pop(ctx);
                                        await _revisiStokDariDetail(
                                          sku: skuKey,
                                          tokoId: cabang,
                                          currentReal: stok,
                                          currentPending: pending,
                                          namaProduk:
                                              (item['nama'] ?? '-').toString(),
                                        );
                                      },
                                    ),
                                  ],
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
                        backgroundColor: OptikAdminTokens.navy,
                        foregroundColor: OptikAdminTokens.bg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Tutup',
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
        color: OptikAdminTokens.navy.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: OptikAdminTokens.navy.withOpacity(0.4),
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
        color: OptikAdminTokens.navy.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.line),
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
          Text(l, style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11)),
          Text(v,
              style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 12))
        ]),
      );

  Widget _buildLensStepper(String label, TextEditingController ctrl) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 10)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
              color: OptikAdminTokens.lineStrong, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: OptikAdminTokens.danger, size: 18),
                  onPressed: () => setState(() => ctrl.text =
                      _formatOptic((double.tryParse(ctrl.text) ?? 0) - 0.25))),
              SizedBox(
                  width: 50,
                  child: Text(ctrl.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
              IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: OptikAdminTokens.success, size: 18),
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
                            color: OptikAdminTokens.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),

                    TextField(
                      style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Cari cabang...",
                        filled: true,
                        fillColor: OptikAdminTokens.snow.withOpacity(0.05),
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
                          style: TextStyle(color: OptikAdminTokens.navy, fontSize: 13)),
                      value: isSelectAll,
                      onChanged: (val) => setStateDialog(() {
                        isSelectAll = val!;
                        selectedCabangMap.updateAll((key, _) => val);
                      }),
                    ),
                    const Divider(color: OptikAdminTokens.line),

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
                                    color: OptikAdminTokens.navy, fontSize: 13)),
                            onChanged: (val) => setStateDialog(
                                () => selectedCabangMap[toko] = val!),
                          );
                        },
                      ),
                    ),

                    const Divider(color: OptikAdminTokens.line),

// 🎯 FIX FOOTER COUNTER (Line 650+)
                    if (hasSelection) ...[
                      Text(
                        'Hanya mendaftarkan katalog di cabang (stok Real tetap 0). '
                        'Isi stok lewat revisi / RO / DO.',
                        style: TextStyle(
                          color: OptikAdminTokens.navy.withOpacity(0.5),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OptikAdminTokens.navy,
                            foregroundColor: OptikAdminTokens.bg,
                          ),
                          onPressed: () {
                            final target = selectedCabangMap.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();
                            _tampilkanKonfirmasiAlokasi(item, target, 0, () {
                              Navigator.pop(context);
                              _executeBulkAddBranch(
                                  item, target, 0, existingStocks);
                            });
                          },
                          child: const Text(
                            'Daftarkan',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
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
            Icon(Icons.warning_amber_rounded, color: OptikAdminTokens.warning),
            SizedBox(width: 10),
            Text('Konfirmasi daftar cabang',
                style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Daftarkan produk ke cabang (stok Real 0).\n\n'
          'Produk: ${item['nama']}\n'
          'Cabang:\n${cabangs.where((c) => c.toUpperCase() != 'PUSAT').map(_cabangLabel).join(', ')}\n\n'
          'Stok Real diubah lewat Master Produk (revisi + scan QR) '
          'atau mutasi RO/DO/Retur/POS. '
          'Daftar cabang tidak menambah qty stok.',
          style:
              const TextStyle(color: OptikAdminTokens.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal',
                  style: TextStyle(color: OptikAdminTokens.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.bg,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Ya, daftarkan',
                style: TextStyle(fontWeight: FontWeight.bold)),
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

      // Katalog: PUSAT + semua toko (stok 0). Qty fisik tetap lewat RO/DO.
      final detailTokos = <Map<String, dynamic>>[];

      for (final toko in cabangTargets) {
        final branch = await client
            .from('products')
            .select('id, stock')
            .eq('toko_id', toko)
            .eq('sku', sku)
            .maybeSingle();
        final lama = int.tryParse(branch?['stock']?.toString() ?? '0') ?? 0;
        detailTokos.add({
          'toko': toko,
          'created': branch == null,
          'stock_before': lama,
          'stock_after': lama,
          'qty_delta': 0,
        });
      }

      final pusat = await client
          .from('products')
          .select('id')
          .eq('toko_id', 'PUSAT')
          .eq('sku', sku)
          .maybeSingle();
      if (pusat == null) {
        final row = Map<String, dynamic>.from(baseProduct);
        row.remove('id');
        row.remove('created_at');
        row.remove('breakdown_stok');
        row.remove('total_stock');
        row['toko_id'] = 'PUSAT';
        row['stock'] = 0;
        row['nama'] = nama;
        row['sku'] = sku;
        if (barcode.isNotEmpty) row['barcode'] = barcode;
        await client.from('products').insert(row);
      }

      await _propagateSkuToAllToko(
        sku: sku,
        template: Map<String, dynamic>.from(baseProduct),
      );

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
          backgroundColor: logOk ? OptikAdminTokens.success : OptikAdminTokens.warning));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal revisi: $e'), backgroundColor: OptikAdminTokens.danger));
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
                const Icon(Icons.history_rounded, color: OptikAdminTokens.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    productNama == null || productNama.isEmpty
                        ? 'Riwayat Add Branch'
                        : 'Riwayat: $productNama',
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
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
                        style: TextStyle(color: OptikAdminTokens.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: OptikAdminTokens.line, height: 18),
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
                                color: OptikAdminTokens.navy,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            if (sku.isNotEmpty)
                              Text(
                                'SKU: $sku',
                                style: const TextStyle(
                                    color: OptikAdminTokens.textMuted, fontSize: 11),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              when,
                              style: TextStyle(
                                color: OptikAdminTokens.slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Oleh: $siapa',
                              style: const TextStyle(
                                  color: OptikAdminTokens.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              qty > 0
                                  ? 'Qty revisi: +$qty Pcs / toko'
                                  : 'Daftar produk saja (qty 0)',
                              style: const TextStyle(
                                  color: OptikAdminTokens.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Toko (${tokos.length}): ${tokos.join(', ')}',
                              style: const TextStyle(
                                color: OptikAdminTokens.textSecondary,
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
                                      color: OptikAdminTokens.textMuted,
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
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal muat riwayat: $e'),
        backgroundColor: OptikAdminTokens.danger,
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
      style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle:
            const TextStyle(fontSize: 12, color: OptikAdminTokens.textMuted),
        prefixIcon: Icon(icon, color: OptikAdminTokens.navy, size: 18),
        filled: true,
        fillColor: OptikAdminTokens.bgMid,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OptikAdminTokens.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OptikAdminTokens.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: OptikAdminTokens.navy.withOpacity(0.45),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(dynamic item) {
    String namaRapi = _toTitleCase(item['nama']?.toString() ?? '-');

    final viewingToko = _viewingTokoScope;

    late final int displayReal;
    late final int displayPending;
    late final int displayAvailable;
    late final String labelStok;
    late final String lokasiLabel;

    if (viewingToko != null) {
      final map = item as Map;
      displayReal = _stockAtToko(map, viewingToko);
      displayPending = _pendingAtToko(map, viewingToko);
      displayAvailable = _availableAtToko(map, viewingToko);
      labelStok = 'Real ';
      lokasiLabel = _cabangLabel(viewingToko);
    } else {
      displayReal =
          int.tryParse('${item['total_stock'] ?? item['stock'] ?? 0}') ?? 0;
      displayPending = int.tryParse('${item['total_pending'] ?? 0}') ?? 0;
      displayAvailable = int.tryParse('${item['total_available'] ?? 0}') ??
          StockQty.available(displayReal, displayPending);
      labelStok = 'Total Real ';
      lokasiLabel = 'Semua cabang';
    }
    final stockBadge =
        '$labelStok$displayReal · Booking $displayPending · Tersedia $displayAvailable';

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
              color: OptikAdminTokens.lineStrong, borderRadius: BorderRadius.circular(10)),
          child: (item['image_url'] != null &&
                  item['image_url'].toString().isNotEmpty &&
                  item['image_url'].toString() != '-')
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(item['image_url'], fit: BoxFit.cover))
              : const Icon(Icons.image, color: OptikAdminTokens.line),
        ),
        title: Text(namaRapi,
            style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text("${item['kategori']} | ${item['sub_kategori'] ?? '-'}",
                style: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  viewingToko == null
                      ? Icons.hub_outlined
                      : Icons.location_on,
                  color: viewingToko == null
                      ? OptikAdminTokens.navy
                      : OptikAdminTokens.ice,
                  size: 11,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    lokasiLabel,
                    style: TextStyle(
                      color: viewingToko == null
                          ? OptikAdminTokens.navy
                          : OptikAdminTokens.ice,
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
                    color: OptikAdminTokens.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ],
        ),
        trailing: R.isCompact(context)
            ? IconButton(
                icon: const Icon(Icons.more_vert,
                    color: OptikAdminTokens.textMuted, size: 20),
                tooltip: 'Detail stok',
                onPressed: () async {
                  final sel = await showAdminPicker<String>(
                    context: context,
                    title: 'Aksi produk',
                    searchable: false,
                    options: [
                      AdminPickerOption(
                        value: 'detail',
                        label: stockBadge,
                        icon: Icons.view_week_rounded,
                      ),
                    ],
                  );
                  if (sel == null || sel.isClear) return;
                  if (sel.value == 'detail') showProductDetail(item);
                },
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                          color: OptikAdminTokens.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        stockBadge,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: OptikAdminTokens.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1.25),
                      )),
                  const SizedBox(width: OptikAdminTokens.spaceSm),
                  IconButton(
                      iconSize: 20,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.view_week_rounded,
                          color: OptikAdminTokens.navy, size: 20),
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
                      final map = item as Map;
                      final scopeToko = _viewingTokoScope ?? 'PUSAT';
                      final canonSku =
                          ProductIdentity.normalizeSku(map['sku']) ??
                              ProductIdentity.normalizeBarcode(map['barcode']);
                      editId = map['id'].toString();
                      editSkuOriginal = canonSku;
                      editTokoId = scopeToko;
                      _editStockBefore = _stockAtToko(map, scopeToko);
                      _editPendingBefore = _pendingAtToko(map, scopeToko);
                      nameController.text = map['nama'] ?? '';
                      hargaController.text = _formatRupiahLocal(map['harga'] ?? 0)
                          .replaceAll('Rp', '')
                          .replaceAll('.', '')
                          .trim();
                      hargaModalController.text =
                          map['harga_modal']?.toString() ?? '0';
                      stokController.text = '$_editStockBefore';
                      barcodeController.text =
                          (canonSku ?? map['barcode'] ?? '').toString();
                      warnaCtrl.text = map['warna'] ?? '';
                      barcodeMode = 'MANUAL_PRODUCT';
                      inputKat = map['kategori'] ?? 'Frame';
                      selectedCabang = editTokoId;
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
          if (isCanEdit)
            IconButton(
              tooltip:
                  'Samakan katalog 100%: PUSAT = semua cabang (stok tidak diubah)',
              icon: const Icon(Icons.sync_alt_rounded,
                  color: OptikAdminTokens.navy),
              onPressed: isLoading ? null : _syncPusatCatalogToAllToko,
            ),
          IconButton(
            tooltip: 'Riwayat Add Branch',
            icon: const Icon(Icons.history_rounded, color: OptikAdminTokens.navy),
            onPressed: () => _showBranchRevisionHistory(),
          ),
          if (editId != null)
            IconButton(
                icon: const Icon(Icons.refresh, color: OptikAdminTokens.warning),
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
              PremiumPanel(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                borderRadius: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PremiumSectionHeader(
                      label: 'pm_data_entry'.tr(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      editId == null
                          ? 'Isi data produk baru. Simpan wajib scan barcode karyawan.'
                          : 'Mengedit produk · stok mengikuti toko yang difilter.',
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.45),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (barcodeController.text.isNotEmpty) ...[
                      Center(
                        child: Column(
                          children: [
                            _buildProductCodes(
                              barcodeController.text,
                              productId: editId,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'pm_barcode_sistem'.tr(),
                              style: const TextStyle(
                                color: OptikAdminTokens.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(children: [
                      Expanded(
                        child: AdminPickerField(
                          label: 'pm_kat'.tr(),
                          valueText: inputKat,
                          icon: Icons.category_outlined,
                          onTap: _pickKategori,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: inputKat == 'Lainnya'
                            ? _buildInput(inputSubController, 'pm_sub_kat'.tr(),
                                Icons.category,
                                autoCaps: true)
                            : AdminPickerField(
                                label: 'pm_bahan_coating'.tr(),
                                valueText: inputSub ?? 'Pilih…',
                                hint: 'Pilih…',
                                icon: Icons.layers_outlined,
                                onTap: _pickSubKategori,
                              ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    AdminPickerField(
                      label: 'Mode barcode',
                      valueText: barcodeMode == 'MANUAL_PRODUCT'
                          ? 'Barcode bawaan'
                          : 'Generate otomatis',
                      icon: Icons.qr_code_2_rounded,
                      onTap: () async {
                        final sel = await showAdminPicker<String>(
                          context: context,
                          title: 'Mode barcode',
                          subtitle: 'Cara isi barcode produk baru',
                          headerIcon: Icons.qr_code_2_rounded,
                          searchable: false,
                          selected: barcodeMode,
                          options: const [
                            AdminPickerOption(
                              value: 'AUTOMATIC',
                              label: 'Generate otomatis',
                              subtitle: 'Sistem membuat barcode unik',
                              icon: Icons.auto_awesome_rounded,
                            ),
                            AdminPickerOption(
                              value: 'MANUAL_PRODUCT',
                              label: 'Barcode bawaan',
                              subtitle: 'Scan / ketik barcode produk',
                              icon: Icons.qr_code_scanner_rounded,
                            ),
                          ],
                        );
                        if (sel == null ||
                            sel.isClear ||
                            sel.value == null) {
                          return;
                        }
                        setState(() => barcodeMode = sel.value!);
                      },
                    ),
                    if (barcodeMode == 'MANUAL_PRODUCT') ...[
                      const SizedBox(height: 12),
                      _buildInput(
                        barcodeController,
                        'Scan / ketik barcode produk',
                        Icons.qr_code_scanner_rounded,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildInput(
                      nameController,
                      inputKat == 'Lensa'
                          ? 'pm_merk_lensa'.tr()
                          : 'pm_nama_frame'.tr(),
                      Icons.edit,
                      autoCaps: true,
                    ),
                    if (inputKat == 'Frame') ...[
                      const SizedBox(height: 12),
                      _buildInput(
                        warnaCtrl,
                        'pm_warna_frame'.tr(),
                        Icons.palette,
                        autoCaps: true,
                      ),
                    ],
                    if (inputKat == 'Lensa') ...[
                      const SizedBox(height: 12),
                      AdminPickerField(
                        label: 'pm_jenis_lensa'.tr(),
                        valueText: selectedJenisLensa ?? 'Pilih…',
                        hint: 'Pilih…',
                        icon: Icons.visibility_outlined,
                        onTap: _pickJenisLensa,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child:
                                _buildLensStepper('pm_uk_sph'.tr(), sphCtrl),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child:
                                _buildLensStepper('pm_uk_cyl'.tr(), cylCtrl),
                          ),
                          if (selectedJenisLensa == 'Progresif' ||
                              selectedJenisLensa == 'Kryptok') ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildLensStepper(
                                  'pm_uk_add'.tr(), addCtrl),
                            ),
                          ]
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInput(
                            hargaController,
                            'pm_harga_jual'.tr(),
                            Icons.payments,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildInput(
                            hargaModalController,
                            'pm_harga_modal'.tr(),
                            Icons.monetization_on,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInput(
                      stokController,
                      editId == null
                          ? 'Stok Real awal'
                          : 'Stok Real (${_cabangLabel(editTokoId ?? 'PUSAT')}) — ubah = revisi',
                      Icons.inventory_2_outlined,
                      isNumber: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      editId == null
                          ? 'Stok awal = Real di lokasi terpilih. Simpan wajib scan barcode karyawan.'
                          : 'Ubah data / revisi stok wajib scan barcode karyawan (via login kode APK).',
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.42),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    if (editId == null) ...[
                      const SizedBox(height: 12),
                      AdminPickerField(
                        label: 'Lokasi stok awal',
                        valueText: _stokAwalCabangLabel(selectedCabang),
                        hint: 'Pilih lokasi stok awal…',
                        icon: Icons.store_rounded,
                        onTap: _pickStokAwalCabang,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Katalog otomatis ke Pusat + semua cabang (stok cabang lain 0).',
                        style: TextStyle(
                          color: OptikAdminTokens.navy.withOpacity(0.42),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: foto != null
                            ? OptikAdminTokens.success
                            : OptikAdminTokens.navy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: foto != null
                              ? OptikAdminTokens.success.withOpacity(0.55)
                              : OptikAdminTokens.line,
                        ),
                      ),
                      onPressed: _pickImage,
                      icon: Icon(
                        foto != null
                            ? Icons.check_circle_rounded
                            : Icons.add_a_photo_outlined,
                        size: 18,
                      ),
                      label: Text(
                        foto != null
                            ? "${'pm_foto_terpilih'.tr()}${foto!.name}"
                            : 'pm_upload_foto'.tr(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    PremiumPrimaryButton(
                      label: editId == null
                          ? 'pm_btn_tambah_db'.tr()
                          : 'pm_btn_update_db'.tr(),
                      icon: Icons.qr_code_scanner_rounded,
                      loading: isLoading,
                      onPressed: isLoading ? null : _save,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      () {
                        final via =
                            (widget.profile['login_via_karyawan_nama'] ?? '')
                                .toString()
                                .trim();
                        if (via.isEmpty) {
                          return 'Wajib login via kode APK + scan barcode karyawan (NIK POS) yang sama sebelum simpan.';
                        }
                        return 'Sebelum simpan: scan barcode karyawan POS via "$via".';
                      }(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.4),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
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
                  color: OptikAdminTokens.warning,
                ),
                PremiumStatItem(
                  label: 'Total Stok',
                  value: '$totalStock PCS',
                  color: OptikAdminTokens.navy,
                ),
                PremiumStatItem(
                  label: 'Frame',
                  value: '$frameCount',
                  color: OptikAdminTokens.navy,
                ),
                PremiumStatItem(
                  label: 'Lensa',
                  value: '$lensaCount',
                  color: OptikAdminTokens.slate,
                ),
              ],
            ),

            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 13),
              decoration: InputDecoration(
                  hintText: 'Cari nama, sub kategori, warna, SKU…',
                  hintStyle: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: OptikAdminTokens.warning, size: 18),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close,
                              color: OptikAdminTokens.textMuted, size: 18),
                          onPressed: () {
                            searchController.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: OptikAdminTokens.snow.withOpacity(0.03),
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
                      ? OptikAdminTokens.warning
                      : OptikAdminTokens.textSecondary,
                ),
                label: Text(
                  filtersOpen ? 'Tutup filter' : 'Filter',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _hasActiveFilters || filtersOpen
                        ? OptikAdminTokens.warning
                        : OptikAdminTokens.textSecondary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  foregroundColor: OptikAdminTokens.warning,
                ),
              ),
            ),
            if (filtersOpen) ...[
              if (isCanEdit) ...[
                const SizedBox(height: OptikAdminTokens.spaceSm),
                Text('Filter cabang',
                    style: TextStyle(
                        color: OptikAdminTokens.navy.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildCabangFilterControl(),
                const SizedBox(height: OptikAdminTokens.spaceMd),
              ],
              AdminPickerField(
                label: 'Grup tampilan',
                valueText: switch (groupMode) {
                  'none' => 'Tanpa grup',
                  'harga' => 'Grup harga',
                  'sub' => 'Grup sub kategori',
                  _ => groupMode,
                },
                icon: Icons.view_list_rounded,
                onTap: () async {
                  final sel = await showAdminPicker<String>(
                    context: context,
                    title: 'Grup tampilan',
                    searchable: false,
                    selected: groupMode,
                    options: const [
                      AdminPickerOption(
                        value: 'none',
                        label: 'Tanpa grup',
                        icon: Icons.list_rounded,
                      ),
                      AdminPickerOption(
                        value: 'harga',
                        label: 'Grup harga',
                        icon: Icons.payments_outlined,
                      ),
                      AdminPickerOption(
                        value: 'sub',
                        label: 'Grup sub kategori',
                        icon: Icons.category_outlined,
                      ),
                    ],
                  );
                  if (sel == null || sel.isClear) return;
                  setState(() {
                    groupMode = sel.value!;
                    _collapsedGroups.clear();
                  });
                },
              ),
              const SizedBox(height: OptikAdminTokens.spaceMd),
              AdminPickerField(
                label: 'Filter kategori',
                valueText:
                    filterKat == 'SEMUA' ? 'Semua' : filterKat,
                icon: Icons.filter_alt_outlined,
                onTap: () async {
                  final sel = await showAdminPicker<String>(
                    context: context,
                    title: 'Filter kategori',
                    searchable: false,
                    selected: filterKat == 'SEMUA' ? null : filterKat,
                    clearLabel: 'Semua',
                    clearIcon: Icons.apps_rounded,
                    options: const [
                      AdminPickerOption(
                        value: 'Frame',
                        label: 'Frame',
                        icon: Icons.visibility_outlined,
                      ),
                      AdminPickerOption(
                        value: 'Lensa',
                        label: 'Lensa',
                        icon: Icons.lens_outlined,
                      ),
                      AdminPickerOption(
                        value: 'Lainnya',
                        label: 'Lainnya',
                        icon: Icons.more_horiz_rounded,
                      ),
                    ],
                  );
                  if (sel == null) return;
                  setState(() =>
                      filterKat = sel.isClear ? 'SEMUA' : sel.value!);
                },
              ),
              if (_hargaOptions.isNotEmpty) ...[
                const SizedBox(height: OptikAdminTokens.spaceMd),
                AdminPickerField(
                  label: 'Filter harga',
                  valueText: filterHarga == 'SEMUA'
                      ? 'Semua'
                      : _formatRupiahLocal(
                          int.tryParse(filterHarga) ?? filterHarga),
                  icon: Icons.attach_money_rounded,
                  onTap: () async {
                    final sel = await showAdminPicker<String>(
                      context: context,
                      title: 'Filter harga',
                      searchable: _hargaOptions.length > 8,
                      selected:
                          filterHarga == 'SEMUA' ? null : filterHarga,
                      clearLabel: 'Semua',
                      clearIcon: Icons.apps_rounded,
                      options: [
                        for (final h in _hargaOptions)
                          AdminPickerOption(
                            value: h.toString(),
                            label: _formatRupiahLocal(h),
                            icon: Icons.payments_outlined,
                          ),
                      ],
                    );
                    if (sel == null) return;
                    setState(() => filterHarga =
                        sel.isClear ? 'SEMUA' : sel.value!);
                  },
                ),
              ],
              if (_subKatOptions.isNotEmpty) ...[
                const SizedBox(height: OptikAdminTokens.spaceMd),
                AdminPickerField(
                  label: 'Filter sub kategori',
                  valueText:
                      filterSubKat == 'SEMUA' ? 'Semua' : filterSubKat,
                  icon: Icons.subdirectory_arrow_right_rounded,
                  onTap: () async {
                    final sel = await showAdminPicker<String>(
                      context: context,
                      title: 'Filter sub kategori',
                      searchable: _subKatOptions.length > 8,
                      selected: filterSubKat == 'SEMUA' ? null : filterSubKat,
                      clearLabel: 'Semua',
                      clearIcon: Icons.apps_rounded,
                      options: [
                        for (final s in _subKatOptions)
                          AdminPickerOption(
                            value: s,
                            label: s,
                            icon: Icons.label_outline_rounded,
                          ),
                      ],
                      filterOption: (o, q) =>
                          o.label.toLowerCase().contains(q),
                    );
                    if (sel == null) return;
                    setState(() => filterSubKat =
                        sel.isClear ? 'SEMUA' : sel.value!);
                  },
                ),
              ],
            ],
            const SizedBox(height: OptikAdminTokens.spaceMd),

            isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: OptikAdminTokens.warning))
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
                                            color: OptikAdminTokens.warning,
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
                                              color: OptikAdminTokens.navy
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
