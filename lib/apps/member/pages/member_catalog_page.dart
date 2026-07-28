import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';

/// Katalog Member — sinkron katalog PUSAT (sama sumber POS / catalog parity).
class MemberCatalogPage extends StatefulWidget {
  const MemberCatalogPage({super.key});

  @override
  State<MemberCatalogPage> createState() => _MemberCatalogPageState();
}

class _MemberCatalogPageState extends State<MemberCatalogPage> {
  final _repo = MemberRepository();
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  /// null = Semua; 'Lainnya' = bukan Frame/Lensa (sama pola Product Master).
  String? _kategori;
  String? _subKategori;
  /// null = semua harga; selain itu harga tepat (harga_jual/harga).
  int? _harga;
  List<Map<String, dynamic>> _all = const [];

  static const _mainCats = ['Semua', 'Frame', 'Lensa', 'Lainnya'];

  int get _activeFilterCount {
    var n = 0;
    if (_kategori != null) n++;
    if (_subKategori != null) n++;
    if (_harga != null) n++;
    return n;
  }

  bool get _hasActiveFilter => _activeFilterCount > 0;

  String get _filterSummary {
    if (!_hasActiveFilter) return 'Semua produk';
    final parts = <String>[
      if (_kategori != null) _kategori!,
      if (_subKategori != null) _subKategori!,
      if (_harga != null) _money(_harga),
    ];
    return parts.join(' · ');
  }

  void _clearFilters() {
    _kategori = null;
    _subKategori = null;
    _harga = null;
  }

  void _resetFilters() => setState(_clearFilters);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listCatalog(limit: 300);
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
    return _all.where((p) {
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

  Widget _filterBar() {
    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openFilterSheet,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hasActiveFilter
                  ? OptikMemberTokens.blue.withOpacity(0.45)
                  : OptikMemberTokens.lineSoft,
            ),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      OptikMemberTokens.blueDeep,
                      OptikMemberTokens.blue,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter',
                      style: TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _filterSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasActiveFilter) ...[
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_activeFilterCount',
                    style: const TextStyle(
                      color: OptikMemberTokens.blueDeep,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus filter',
                  onPressed: _resetFilters,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: OptikMemberTokens.inkMuted,
                ),
              ],
              Icon(
                Icons.keyboard_arrow_up_rounded,
                color: OptikMemberTokens.blueDeep.withOpacity(0.8),
              ),
            ],
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return MemberPremiumScaffold(
      title: 'Katalog',
      subtitle: 'Sinkron katalog pusat',
      body: RefreshIndicator(
        color: OptikMemberTokens.blue,
        onRefresh: _load,
        // Satu scroll: search/filter ikut naik — produk tidak kepotong.
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
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
                        fillColor: OptikMemberTokens.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: OptikMemberTokens.lineSoft),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: OptikMemberTokens.lineSoft),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _filterBar(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _loading
                                ? 'Memuat katalog pusat…'
                                : '${items.length} produk'
                                    '${_hasActiveFilter ? ' · terfilter' : ''}',
                            style: const TextStyle(
                              color: OptikMemberTokens.inkMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Muat ulang',
                          onPressed: _loading ? null : _load,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          color: OptikMemberTokens.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ..._buildProductSlivers(items),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProductSlivers(List<Map<String, dynamic>> items) {
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

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.68,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _ProductCard(
              product: items[i],
              priceLabel: _money(items[i]['harga']),
            ),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.priceLabel});

  final Map<String, dynamic> product;
  final String priceLabel;

  @override
  Widget build(BuildContext context) {
    final nama = (product['nama'] ?? '-').toString();
    final kat = (product['kategori'] ?? '').toString().trim();
    final img = (product['image_url'] ?? '').toString().trim();

    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OptikMemberTokens.lineSoft),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1) Foto
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: OptikMemberTokens.blueMist,
                      child: img.isEmpty
                          ? const Center(
                              child: Icon(
                                Icons.visibility_outlined,
                                size: 22,
                                color: OptikMemberTokens.blue,
                              ),
                            )
                          : Image.network(
                              img,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.visibility_outlined,
                                  size: 22,
                                  color: OptikMemberTokens.blue,
                                ),
                              ),
                            ),
                    ),
                    if (kat.isNotEmpty)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: OptikMemberTokens.blueDeep.withOpacity(0.88),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            kat.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 2) Nama → 3) Harga
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikMemberTokens.blue,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                    aspectRatio: 16 / 10,
                    child: Image.network(img, fit: BoxFit.cover),
                  ),
                )
              else
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: OptikMemberTokens.blueMist,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.visibility_outlined,
                      size: 48, color: OptikMemberTokens.blue),
                ),
              const SizedBox(height: 14),
              Text(
                nama,
                style: const TextStyle(
                  color: OptikMemberTokens.blueDeep,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                priceLabel,
                style: const TextStyle(
                  color: OptikMemberTokens.blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              _kv('Kategori', sub.isEmpty ? kat : '$kat · $sub'),
              _kv('Warna', warna),
              if (lensa.isNotEmpty) _kv('Jenis lensa', lensa),
              _kv('SKU', sku),
              _kv('Barcode', barcode),
              const SizedBox(height: 8),
              const Text(
                'Harga referensi dari katalog pusat. Ketersediaan stok dicek di cabang.',
                style: TextStyle(
                  color: OptikMemberTokens.inkMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
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
