import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/logistics/stock_realtime.dart';
import '../../../shared/member/member_cart.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_layout.dart';
import 'member_cart_page.dart';
import 'member_option_picker.dart';

enum _CatalogSort { namaAsc, hargaAsc, hargaDesc }

/// Katalog Member — browse-only di beranda, atau mode belanja di Belanja Online.
class MemberCatalogPage extends StatefulWidget {
  const MemberCatalogPage({
    super.key,
    this.browseOnly = true,
    this.embeddedInShop = false,
    this.initialKategori,
    this.onOpenCart,
  });

  /// true = lihat harga/detail saja (tanpa keranjang).
  final bool browseOnly;

  /// true = dipakai sebagai tab di MemberShopShell (tanpa tombol back).
  final bool embeddedInShop;

  final String? initialKategori;

  /// Dipanggil saat user ingin buka keranjang (tab shell), bukan push route.
  final VoidCallback? onOpenCart;

  @override
  State<MemberCatalogPage> createState() => _MemberCatalogPageState();
}

class _MemberCatalogPageState extends State<MemberCatalogPage> {
  final _repo = MemberRepository();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _loading = true;
  bool _showSearch = false;
  String? _error;
  /// null = Semua; 'Lainnya' = bukan Frame/Lensa (sama pola Product Master).
  String? _kategori;
  String? _subKategori;
  /// null = semua harga; selain itu harga tepat (harga_jual/harga).
  int? _harga;
  _CatalogSort _sort = _CatalogSort.namaAsc;
  List<Map<String, dynamic>> _all = const [];
  StockRealtimeSubscription? _stockRt;
  Timer? _stockRtDebounce;

  static const _mainCats = ['Semua', 'Frame', 'Lensa', 'Lainnya'];

  int get _activeFilterCount {
    var n = 0;
    if (_kategori != null) n++;
    if (_subKategori != null) n++;
    if (_harga != null) n++;
    return n;
  }

  bool get _hasActiveFilter => _activeFilterCount > 0;

  void _clearFilters() {
    _kategori = null;
    _subKategori = null;
    _harga = null;
  }

  @override
  void initState() {
    super.initState();
    final initKat = (widget.initialKategori ?? '').trim();
    if (initKat.isNotEmpty && initKat.toLowerCase() != 'semua') {
      _kategori = initKat;
    }
    if (!widget.browseOnly) {
      MemberCart.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
      MemberCart.instance.addListener(_onCart);
      MemberSession.instance.addListener(_onPreferredToko);
    }
    _load();
    _startStockRealtime();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  void _onPreferredToko() {
    _startStockRealtime();
    unawaited(_load(silent: true));
  }

  String get _stockTokoId {
    if (widget.browseOnly) return 'PUSAT';
    final pref = (MemberSession.instance.preferredTokoId ?? '').trim().toUpperCase();
    if (pref.isNotEmpty && pref != 'PUSAT') return pref;
    return 'PUSAT';
  }

  void _startStockRealtime() {
    // Belanja Online: stok cabang pilihan; browse: PUSAT (katalog).
    unawaited(_stockRt?.dispose() ?? Future.value());
    _stockRt = StockRealtime.subscribeToko(
      tokoId: _stockTokoId,
      onEvent: (ev) {
        if (!mounted || ev.sku.isEmpty) return;
        var patched = false;
        final next = _all.map((p) {
          final sku = (p['sku'] ?? '').toString().trim().toUpperCase();
          if (sku != ev.sku) return p;
          patched = true;
          final m = Map<String, dynamic>.from(p);
          if (ev.stock != null) m['stock'] = ev.stock;
          if (ev.reservedQty != null) m['reserved_qty'] = ev.reservedQty;
          if (ev.availableQty != null) {
            m['available_qty'] = ev.availableQty;
          } else if (ev.stock != null || ev.reservedQty != null) {
            final st = int.tryParse('${m['stock'] ?? 0}') ?? 0;
            final rs = int.tryParse('${m['reserved_qty'] ?? 0}') ?? 0;
            m['available_qty'] = st > rs ? st - rs : 0;
          }
          return m;
        }).toList();
        if (!patched) {
          _stockRtDebounce?.cancel();
          _stockRtDebounce = Timer(const Duration(milliseconds: 350), () {
            if (mounted) unawaited(_load(silent: true));
          });
          return;
        }
        setState(() => _all = next);
      },
    );
  }

  @override
  void dispose() {
    _stockRtDebounce?.cancel();
    unawaited(_stockRt?.dispose() ?? Future.value());
    if (!widget.browseOnly) {
      MemberCart.instance.removeListener(_onCart);
      MemberSession.instance.removeListener(_onPreferredToko);
    }
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.listCatalog(
        limit: 300,
        tokoId: widget.browseOnly ? null : _stockTokoId,
      );
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
        if (list.isEmpty) _error = 'empty';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  bool _matchKategori(Map<String, dynamic> p) {
    final k = (p['kategori'] ?? '').toString().trim().toLowerCase();
    if (_kategori == null) return true;
    if (_kategori == 'Lainnya') {
      return k != 'frame' && k != 'lensa' && k.isNotEmpty;
    }
    return k == _kategori!.toLowerCase();
  }

  int _priceOf(Map<String, dynamic> p) =>
      int.tryParse('${p['harga'] ?? 0}') ?? 0;

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final list = _all.where((p) {
      if (!_matchKategori(p)) return false;
      if (_subKategori != null) {
        final sub = (p['sub_kategori'] ?? '').toString().trim();
        if (sub.toLowerCase() != _subKategori!.toLowerCase()) return false;
      }
      if (_harga != null && _priceOf(p) != _harga) return false;
      if (q.isEmpty) return true;
      final nama = (p['nama'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      final barcode = (p['barcode'] ?? '').toString().toLowerCase();
      final warna = (p['warna'] ?? '').toString().toLowerCase();
      final sub = (p['sub_kategori'] ?? '').toString().toLowerCase();
      return nama.contains(q) ||
          sku.contains(q) ||
          barcode.contains(q) ||
          warna.contains(q) ||
          sub.contains(q);
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case _CatalogSort.hargaAsc:
          return _priceOf(a).compareTo(_priceOf(b));
        case _CatalogSort.hargaDesc:
          return _priceOf(b).compareTo(_priceOf(a));
        case _CatalogSort.namaAsc:
          return (a['nama'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['nama'] ?? '').toString().toLowerCase());
      }
    });
    return list;
  }

  Future<void> _openSortSheet() async {
    final picked = await showMemberOptionPicker<_CatalogSort>(
      context,
      title: 'Urutkan',
      icon: Icons.swap_vert_rounded,
      selected: _sort,
      searchable: false,
      options: const [
        MemberPickerOption(
          value: _CatalogSort.namaAsc,
          label: 'Nama A–Z',
          icon: Icons.sort_by_alpha_rounded,
        ),
        MemberPickerOption(
          value: _CatalogSort.hargaAsc,
          label: 'Harga terendah',
          icon: Icons.arrow_upward_rounded,
        ),
        MemberPickerOption(
          value: _CatalogSort.hargaDesc,
          label: 'Harga tertinggi',
          icon: Icons.arrow_downward_rounded,
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Widget _squareAction({
    required IconData icon,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: OptikMemberTokens.lineSoft),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: OptikMemberTokens.ink, size: 22),
              if (badge > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: OptikMemberTokens.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _subOptions {
    final set = <String>{};
    for (final p in _all) {
      if (!_matchKategori(p)) continue;
      final s = (p['sub_kategori'] ?? '').toString().trim();
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Harga unik dalam kategori (+ sub) yang sedang dipilih.
  List<int> get _hargaOptions {
    final set = <int>{};
    for (final p in _all) {
      if (!_matchKategori(p)) continue;
      if (_subKategori != null) {
        final sub = (p['sub_kategori'] ?? '').toString().trim();
        if (sub.toLowerCase() != _subKategori!.toLowerCase()) continue;
      }
      final h = _priceOf(p);
      if (h > 0) set.add(h);
    }
    final list = set.toList()..sort();
    return list;
  }

  int _countForCat(String cat) {
    if (cat == 'Semua') return _all.length;
    return _all.where((p) {
      final k = (p['kategori'] ?? '').toString().trim().toLowerCase();
      if (cat == 'Lainnya') {
        return k != 'frame' && k != 'lensa' && k.isNotEmpty;
      }
      return k == cat.toLowerCase();
    }).length;
  }

  String _money(dynamic v) {
    final n = int.tryParse('$v') ?? 0;
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(n);
  }

  Widget _premiumChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [
                      OptikMemberTokens.blueDeep,
                      OptikMemberTokens.blue,
                    ],
                  )
                : null,
            color: selected ? null : OptikMemberTokens.blueMist,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? OptikMemberTokens.blueDeep.withOpacity(0.0)
                  : OptikMemberTokens.lineSoft,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : OptikMemberTokens.blueDeep,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: OptikMemberTokens.inkMuted.withOpacity(0.9),
        fontWeight: FontWeight.w800,
        fontSize: 10.5,
        letterSpacing: 1.1,
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void apply(VoidCallback fn) {
              setState(fn);
              setModal(() {});
            }

            final subs = _subOptions;
            final hargas = _hargaOptions;
            final bottom = MediaQuery.paddingOf(ctx).bottom;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
              ),
              decoration: const BoxDecoration(
                color: OptikMemberTokens.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: OptikMemberTokens.lineSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filter katalog',
                            style: TextStyle(
                              color: OptikMemberTokens.blueDeep,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _hasActiveFilter
                              ? () => apply(_clearFilters)
                              : null,
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _filterSectionLabel('Kategori'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in _mainCats)
                                _premiumChip(
                                  label: c == 'Semua'
                                      ? 'Semua · ${_countForCat(c)}'
                                      : '$c · ${_countForCat(c)}',
                                  selected:
                                      (c == 'Semua' && _kategori == null) ||
                                          _kategori == c,
                                  onTap: () => apply(() {
                                    _kategori = c == 'Semua' ? null : c;
                                    _subKategori = null;
                                    _harga = null;
                                  }),
                                ),
                            ],
                          ),
                          if (subs.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _filterSectionLabel('Sub kategori'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _premiumChip(
                                  label: 'Semua',
                                  selected: _subKategori == null,
                                  onTap: () => apply(() {
                                    _subKategori = null;
                                    _harga = null;
                                  }),
                                ),
                                for (final s in subs)
                                  _premiumChip(
                                    label: s,
                                    selected: _subKategori?.toLowerCase() ==
                                        s.toLowerCase(),
                                    onTap: () => apply(() {
                                      _subKategori = s;
                                      _harga = null;
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          if (hargas.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _filterSectionLabel('Harga'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _premiumChip(
                                  label: 'Semua',
                                  selected: _harga == null,
                                  onTap: () => apply(() => _harga = null),
                                ),
                                for (final h in hargas)
                                  _premiumChip(
                                    label: _money(h),
                                    selected: _harga == h,
                                    onTap: () => apply(() => _harga = h),
                                  ),
                              ],
                            ),
                          ],
                          SizedBox(height: 16 + bottom),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + bottom),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tampilkan hasil'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String get _titleLabel {
    if (_kategori != null && _kategori!.isNotEmpty) {
      return _kategori!.toUpperCase();
    }
    return widget.browseOnly ? 'KATALOG' : 'BELANJA';
  }

  void _openCart(BuildContext context) {
    if (widget.onOpenCart != null) {
      widget.onOpenCart!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MemberCartPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final cartQty = MemberCart.instance.totalQty;
    final layout = MemberLayout.of(context);
    final cols = layout.isTablet ? 3 : 2;
    final browseOnly = widget.browseOnly;

    return Scaffold(
      backgroundColor: OptikMemberTokens.white,
      appBar: AppBar(
        backgroundColor: OptikMemberTokens.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        automaticallyImplyLeading: !widget.embeddedInShop,
        leading: widget.embeddedInShop
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: OptikMemberTokens.ink,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        title: Text(
          _titleLabel,
          style: const TextStyle(
            color: OptikMemberTokens.ink,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Cari',
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (_showSearch) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _searchFocus.requestFocus();
                });
              }
            },
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
              color: OptikMemberTokens.ink,
            ),
          ),
          if (!browseOnly && !widget.embeddedInShop)
            IconButton(
              tooltip: 'Keranjang',
              onPressed: () => _openCart(context),
              icon: Badge(
                isLabelVisible: cartQty > 0,
                backgroundColor: OptikMemberTokens.danger,
                label: Text('$cartQty'),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: OptikMemberTokens.ink,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: OptikMemberTokens.blue,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                4,
                layout.pagePadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showSearch) ...[
                      TextField(
                        controller: _search,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Cari nama, SKU, barcode…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                ),
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        _squareAction(
                          icon: Icons.swap_vert_rounded,
                          onTap: _openSortSheet,
                        ),
                        const SizedBox(width: 10),
                        _squareAction(
                          icon: Icons.tune_rounded,
                          onTap: _openFilterSheet,
                          badge: _activeFilterCount,
                        ),
                        const Spacer(),
                        Text(
                          _loading
                              ? 'Memuat…'
                              : '${items.length} produk',
                          style: TextStyle(
                            color: OptikMemberTokens.inkMuted,
                            fontSize: layout.menuSubtitleSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            ..._buildProductSlivers(items, cols),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProductSlivers(
    List<Map<String, dynamic>> items,
    int cols,
  ) {
    if (_loading && _all.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error == 'empty') {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 48, color: OptikMemberTokens.inkMuted),
                SizedBox(height: 12),
                Text(
                  'Katalog pusat masih kosong, atau migrasi RPC belum dijalankan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: OptikMemberTokens.inkMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (_error != null && _all.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Gagal memuat katalog.\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: OptikMemberTokens.inkMuted),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Coba lagi')),
              ],
            ),
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'Tidak ada produk untuk filter ini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: OptikMemberTokens.inkMuted),
            ),
          ),
        ),
      ];
    }

    final pad = MemberLayout.of(context).pagePadding;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 18,
            crossAxisSpacing: 12,
            childAspectRatio: cols >= 3 ? 0.62 : 0.58,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _ProductCard(
              product: items[i],
              money: _money,
              browseOnly: widget.browseOnly,
              onOpenCart: () => _openCart(context),
            ),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.money,
    required this.browseOnly,
    this.onOpenCart,
  });

  final Map<String, dynamic> product;
  final String Function(dynamic) money;
  final bool browseOnly;
  final VoidCallback? onOpenCart;

  int get _harga => int.tryParse('${product['harga'] ?? 0}') ?? 0;
  int? get _hargaAsli {
    final v = int.tryParse('${product['harga_asli'] ?? ''}');
    if (v == null || v <= _harga) return null;
    return v;
  }

  int? get _diskonPersen {
    final asli = _hargaAsli;
    if (asli == null || asli <= 0 || _harga <= 0) return null;
    return (((asli - _harga) / asli) * 100).round();
  }

  int? get _availableQty {
    final v = int.tryParse('${product['available_qty'] ?? ''}');
    return v;
  }

  bool get _outOfStock {
    final a = _availableQty;
    return a != null && a <= 0;
  }

  @override
  Widget build(BuildContext context) {
    final nama = (product['nama'] ?? '-').toString();
    final img = (product['image_url'] ?? '').toString().trim();
    final blocked = MemberCart.isOnlineBlocked(product);
    final diskon = _diskonPersen;
    final asli = _hargaAsli;
    // Pre-order diizinkan meski stok pusat/cabang 0 (RO saat checkout).
    final canBuy = !browseOnly && !blocked;

    return InkWell(
      onTap: () => _showDetail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: const Color(0xFFF3F3F3),
                  child: img.isEmpty
                      ? const Center(
                          child: Icon(
                            Icons.visibility_outlined,
                            size: 36,
                            color: OptikMemberTokens.inkMuted,
                          ),
                        )
                      : Image.network(
                          img,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.visibility_outlined,
                              size: 36,
                              color: OptikMemberTokens.inkMuted,
                            ),
                          ),
                        ),
                ),
                if (diskon != null && diskon > 0)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      color: OptikMemberTokens.white,
                      child: Text(
                        '-$diskon%',
                        style: const TextStyle(
                          color: Color(0xFFC45C4A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (!browseOnly && _outOfStock)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      color: Colors.black.withValues(alpha: 0.65),
                      child: const Text(
                        'Pre-order',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (!browseOnly)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: canBuy
                          ? OptikMemberTokens.ink
                          : OptikMemberTokens.inkMuted,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          if (blocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Lensa custom tidak dijual online.',
                                ),
                              ),
                            );
                            return;
                          }
                          _quickAdd(context);
                        },
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nama,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: OptikMemberTokens.ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              if (asli != null)
                Text(
                  money(asli),
                  style: const TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                money(_harga),
                style: TextStyle(
                  color: asli != null
                      ? const Color(0xFFC45C4A)
                      : OptikMemberTokens.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Popup HANYA saat user memilih/tambah produk yang stoknya habis.
  Future<bool> _confirmPreOrder(BuildContext context) async {
    final nama = (product['nama'] ?? 'produk').toString();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Stok habis'),
        content: Text(
          '“$nama” stoknya habis.\n\n'
          'Tetap bisa dipesan sebagai pre-order.\n'
          'Estimasi tiba 5–7 hari kerja setelah pembayaran lunas.\n\n'
          'Lanjutkan pre-order, atau cari produk lain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cari produk lain'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjutkan pre-order'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _quickAdd(BuildContext context) async {
    if (_outOfStock) {
      final yes = await _confirmPreOrder(context);
      if (!yes || !context.mounted) return;
    }
    final err = await MemberCart.instance.addProduct(product);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _outOfStock ? 'Ditambah (pre-order)' : 'Ditambah ke keranjang',
        ),
        action: SnackBarAction(
          label: 'Lihat',
          onPressed: () {
            if (onOpenCart != null) {
              onOpenCart!();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MemberCartPage()),
              );
            }
          },
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final nama = (product['nama'] ?? '-').toString();
    final kat = (product['kategori'] ?? '-').toString();
    final sub = (product['sub_kategori'] ?? '').toString();
    final warna = (product['warna'] ?? '-').toString();
    final sku = (product['sku'] ?? '-').toString();
    final barcode = (product['barcode'] ?? '-').toString();
    final lensa = (product['jenis_lensa'] ?? '').toString();
    final img = (product['image_url'] ?? '').toString().trim();
    final asli = _hargaAsli;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OptikMemberTokens.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.lineSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (img.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.network(img, fit: BoxFit.cover),
                  ),
                )
              else
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F3F3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.visibility_outlined,
                      size: 48, color: OptikMemberTokens.inkMuted),
                ),
              const SizedBox(height: 14),
              Text(
                nama,
                style: const TextStyle(
                  color: OptikMemberTokens.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  if (asli != null)
                    Text(
                      money(asli),
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 14,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    money(_harga),
                    style: TextStyle(
                      color: asli != null
                          ? const Color(0xFFC45C4A)
                          : OptikMemberTokens.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _kv('Kategori', sub.isEmpty ? kat : '$kat · $sub'),
              _kv('Warna', warna),
              if (lensa.isNotEmpty) _kv('Jenis lensa', lensa),
              _kv('SKU', sku),
              _kv('Barcode', barcode),
              const SizedBox(height: 8),
              if (_availableQty != null)
                _kv(
                  'Stok',
                  _outOfStock
                      ? 'Habis — bisa pre-order'
                      : 'Tersedia ($_availableQty)',
                ),
              Text(
                browseOnly
                    ? 'Harga referensi dari katalog pusat (master data). '
                        'Untuk membeli, buka Belanja Online.'
                    : 'Harga & stok dari master data pusat. '
                        'Stok cabang dicek ulang saat checkout. '
                        'Lensa custom tidak dijual online.',
                style: const TextStyle(
                  color: OptikMemberTokens.inkMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              if (browseOnly)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Tutup'),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tutup'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: MemberCart.isOnlineBlocked(product)
                            ? null
                            : () async {
                                if (_outOfStock) {
                                  final yes = await _confirmPreOrder(ctx);
                                  if (!yes || !ctx.mounted) return;
                                }
                                final err = await MemberCart.instance
                                    .addProduct(product);
                                if (!ctx.mounted) return;
                                if (err != null) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(err)),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _outOfStock
                                          ? 'Ditambah (pre-order)'
                                          : 'Ditambah ke keranjang',
                                    ),
                                    action: SnackBarAction(
                                      label: 'Lihat',
                                      onPressed: () {
                                        if (onOpenCart != null) {
                                          onOpenCart!();
                                        } else {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const MemberCartPage(),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: Text(
                          MemberCart.isOnlineBlocked(product)
                              ? 'Tidak bisa online'
                              : _outOfStock
                                  ? 'Pre-order'
                                  : 'Ke keranjang',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: const TextStyle(
                color: OptikMemberTokens.inkMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                color: OptikMemberTokens.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
