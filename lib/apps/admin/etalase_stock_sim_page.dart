import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/invoice/invoice_settings_service.dart';
import '../../shared/stock/etalase_layout.dart';
import '../../shared/stock/etalase_layout_repository.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Denah etalase toko — kardus bertumpuk, produk dari master per toko.
class EtalaseStockSimPage extends StatefulWidget {
  const EtalaseStockSimPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<EtalaseStockSimPage> createState() => _EtalaseStockSimPageState();
}

class _EtalaseStockSimPageState extends State<EtalaseStockSimPage>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  late final AnimationController _pulse;
  late final EtalaseLayoutRepository _repo;

  String _tokoId = '';
  List<String> _tokoList = const [];
  List<EtalaseUnit> _units = [];
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String _query = '';
  String? _selectedBoxKey;

  @override
  void initState() {
    super.initState();
    _repo = EtalaseLayoutRepository(
      tenantId: AttendanceAdminScope.tenantIdOf(widget.profile),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final mine = AttendanceAdminScope.tokoOf(widget.profile);
    final all = AttendanceAdminScope.canViewAllStores(widget.profile);
    List<String> tokoList = [];
    if (all) {
      try {
        tokoList = await InvoiceSettingsService().listCabang();
      } catch (_) {
        tokoList = mine.isEmpty ? ['PUSAT'] : [mine];
      }
      if (tokoList.isEmpty) {
        tokoList = mine.isEmpty ? ['PUSAT'] : [mine];
      }
    } else {
      tokoList = mine.isEmpty ? ['PUSAT'] : [mine];
    }
    final mineNorm = InvoiceSettingsService.normalizeTokoId(mine);
    final normalizedList = {
      for (final t in tokoList) InvoiceSettingsService.normalizeTokoId(t),
    }.toList()
      ..sort();
    final toko = normalizedList.contains(mineNorm)
        ? mineNorm
        : (normalizedList.isNotEmpty ? normalizedList.first : 'PUSAT');
    setState(() {
      _tokoList = normalizedList;
      _tokoId = toko;
    });
    await _reloadToko(toko);
  }

  Future<void> _reloadToko(String toko) async {
    final id = InvoiceSettingsService.normalizeTokoId(toko);
    setState(() {
      _loading = true;
      _tokoId = id;
      _selectedBoxKey = null;
    });
    final units = await _repo.load(id);
    final products = await _loadProducts(id);
    final placementChanged =
        EtalaseLayoutStore.syncFromMaster(units, products);
    // SKU yang hilang dari master harus ikut terhapus di cache/remote.
    if (placementChanged) {
      await _repo.save(id, units);
    }
    if (!mounted) return;
    setState(() {
      _units = units;
      _products = products;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadProducts(String toko) async {
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id, sku, barcode, nama, stock, toko_id')
          .inFilter('toko_id', AttendanceAdminScope.storeIdAliases(toko))
          .order('nama')
          .limit(2500);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      try {
        final rows = await Supabase.instance.client
            .from('products')
            .select('id, sku, barcode, nama, toko_id')
            .inFilter('toko_id', AttendanceAdminScope.storeIdAliases(toko))
            .order('nama')
            .limit(2500);
        return List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {
        return const [];
      }
    }
  }

  int _masterStockOf(String productId, String sku) {
    for (final p in _products) {
      if ('${p['id']}' == productId) {
        return (p['stock'] as num?)?.toInt() ?? 0;
      }
    }
    final key = sku.toUpperCase();
    for (final p in _products) {
      if ('${p['sku']}'.toUpperCase() == key) {
        return (p['stock'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  Future<void> _persist() async {
    final ok = await _repo.save(_tokoId, _units);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Tersimpan di perangkat ini. Sync cloud gagal — cek jaringan, lalu tap refresh.',
        ),
        backgroundColor: OptikAdminTokens.warning,
      ));
    }
  }

  List<({EtalaseUnit unit, EtalaseBox box, EtalaseBoxProduct product})>
      get _hits {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <({EtalaseUnit unit, EtalaseBox box, EtalaseBoxProduct product})>[];
    for (final u in _units) {
      for (final b in u.boxes) {
        for (final p in b.products) {
          if (p.sku.toLowerCase().contains(q) ||
              p.name.toLowerCase().contains(q) ||
              b.displayName.toLowerCase().contains(q) ||
              b.code.toLowerCase().contains(q)) {
            out.add((unit: u, box: b, product: p));
          }
        }
      }
    }
    return out;
  }

  bool _boxLit(EtalaseUnit unit, EtalaseBox box) {
    final key = '${unit.id}:${box.code}';
    if (_selectedBoxKey == key) return true;
    return _hits.any((h) => h.unit.id == unit.id && h.box.code == box.code);
  }

  Future<void> _addEtalase() async {
    final result = await showDialog<_NewEtalaseDraft>(
      context: context,
      barrierColor: OptikAdminTokens.navy.withOpacity(0.45),
      builder: (ctx) => _AddEtalaseDialog(
        defaultName: 'Etalase ${_units.length + 1}',
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _units = [
        ..._units,
        EtalaseUnit.create(
          name: result.name,
          layerWidths: result.layerWidths,
        ),
      ];
    });
    await _persist();
  }

  Future<void> _openBox(EtalaseUnit unit, EtalaseBox box) async {
    setState(() => _selectedBoxKey = '${unit.id}:${box.code}');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OptikAdminTokens.snow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: _BoxEditor(
            unitName: unit.name,
            box: box,
            productsCatalog: _products,
            masterStockOf: _masterStockOf,
            onChanged: () async {
              setState(() {});
              await _persist();
            },
          ),
        );
      },
    );
    if (mounted) setState(() => _selectedBoxKey = null);
  }

  Future<void> _setAlign(EtalaseUnit unit, EtalaseAlign align) async {
    setState(() => unit.align = align);
    await _persist();
  }

  Future<void> _trimLayer(EtalaseUnit unit, int layer) async {
    final cur = unit.layerWidths[layer];
    final maxAllowed = layer == 0
        ? 8
        : unit.layerWidths[layer - 1];
    final minAllowed = layer == unit.layerCount - 1
        ? 1
        : unit.layerWidths[layer + 1];
    final ctrl = TextEditingController(text: '$cur');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lebar layer ${String.fromCharCode(65 + layer)}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Jumlah kardus ke samping',
            helperText: 'Min $minAllowed · max $maxAllowed (≤ layer bawah)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      ctrl.dispose();
      return;
    }
    final w = int.tryParse(ctrl.text.trim()) ?? cur;
    ctrl.dispose();
    if (!unit.setLayerWidth(layer, w.clamp(minAllowed, maxAllowed))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lebar tidak valid — atas tidak boleh lebih lebar dari bawah.'),
        backgroundColor: OptikAdminTokens.danger,
      ));
      return;
    }
    setState(() {});
    await _persist();
  }

  Future<void> _deleteUnit(EtalaseUnit unit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus etalase?'),
        content: Text('Hapus ${unit.name} beserta isi kardusnya.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: OptikAdminTokens.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _units = [for (final u in _units) if (u.id != unit.id) u]);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final hit = _hits.isEmpty ? null : _hits.first;
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Denah etalase',
        subtitle: _tokoId.isEmpty ? 'Stok per kardus' : 'Toko $_tokoId',
        actions: [
          IconButton(
            tooltip: 'Refresh produk',
            onPressed: _loading ? null : () => _reloadToko(_tokoId),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addEtalase,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah etalase'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    children: [
                      if (_tokoList.length > 1) ...[
                        AdminPickerField(
                          label: 'Toko',
                          valueText: _tokoId,
                          onTap: () async {
                            final sel = await showAdminPicker<String>(
                              context: context,
                              title: 'Pilih toko',
                              selected: _tokoId,
                              options: [
                                for (final t in _tokoList)
                                  AdminPickerOption(value: t, label: t),
                              ],
                            );
                            if (sel == null || sel.isClear || sel.value == null) {
                              return;
                            }
                            await _reloadToko(sel.value!);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Cari produk / SKU di kardus…',
                          prefixIcon: Icon(Icons.search_rounded,
                              color: OptikAdminTokens.navy),
                          filled: true,
                          fillColor: OptikAdminTokens.snow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_loading) ...[
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: _StockLegend(),
                  ),
                ],
                if (hit != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _FindBanner(
                      unitName: hit.unit.name,
                      box: hit.box,
                      product: hit.product,
                      stock: _masterStockOf(
                        hit.product.productId,
                        hit.product.sku,
                      ),
                    ),
                  ),
                Expanded(
                  child: _units.isEmpty
                      ? Center(
                          child: Text(
                            'Belum ada etalase.\nTap “Tambah etalase” — isi tumpuk (huruf) & ke samping (angka).',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: OptikAdminTokens.slate),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                          itemCount: _units.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 28),
                          itemBuilder: (context, i) {
                            final unit = _units[i];
                            return _EtalaseCard(
                              unit: unit,
                              pulse: _pulse,
                              stockOf: _masterStockOf,
                              boxLit: (b) => _boxLit(unit, b),
                              onBoxTap: (b) => _openBox(unit, b),
                              onAlign: (a) => _setAlign(unit, a),
                              onEditLayer: (layer) => _trimLayer(unit, layer),
                              onDelete: () => _deleteUnit(unit),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _FindBanner extends StatelessWidget {
  const _FindBanner({
    required this.unitName,
    required this.box,
    required this.product,
    required this.stock,
  });

  final String unitName;
  final EtalaseBox box;
  final EtalaseBoxProduct product;
  final int stock;

  @override
  Widget build(BuildContext context) {
    final letter = String.fromCharCode(65 + box.layer);
    final row = box.layer == 0
        ? 'layer bawah ($letter)'
        : 'layer $letter (di atas ${String.fromCharCode(64 + box.layer)})';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OptikAdminTokens.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          '${product.name} (${product.sku}) · $unitName · $row · kardus ${box.col + 1} dari kiri · $stock pcs',
          style: TextStyle(
            color: OptikAdminTokens.onHighlight,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _EtalaseCard extends StatelessWidget {
  const _EtalaseCard({
    required this.unit,
    required this.pulse,
    required this.stockOf,
    required this.boxLit,
    required this.onBoxTap,
    required this.onAlign,
    required this.onEditLayer,
    required this.onDelete,
  });

  final EtalaseUnit unit;
  final Animation<double> pulse;
  final int Function(String productId, String sku) stockOf;
  final bool Function(EtalaseBox) boxLit;
  final ValueChanged<EtalaseBox> onBoxTap;
  final ValueChanged<EtalaseAlign> onAlign;
  final ValueChanged<int> onEditLayer;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    '${unit.layerCount} layer · bawah ${unit.bottomWidth} kardus',
                    style: TextStyle(color: OptikAdminTokens.slate, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Hapus etalase',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: OptikAdminTokens.danger),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final a in EtalaseAlign.values)
              ChoiceChip(
                label: Text(switch (a) {
                  EtalaseAlign.left => 'Rata kiri',
                  EtalaseAlign.center => 'Rata tengah',
                  EtalaseAlign.right => 'Rata kanan',
                }),
                selected: unit.align == a,
                onSelected: (_) => onAlign(a),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (var layer = 0; layer < unit.layerCount; layer++)
              ActionChip(
                label: Text(
                  'Lebar ${String.fromCharCode(65 + layer)}: ${unit.layerWidths[layer]}',
                ),
                onPressed: () => onEditLayer(layer),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE4E7EC)),
            boxShadow: [
              BoxShadow(
                color: OptikAdminTokens.navy.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              children: [
                // Tampil atas → bawah: layer terakhir di atas, A di bawah.
                for (var visual = unit.layerCount - 1; visual >= 0; visual--) ...[
                  if (visual < unit.layerCount - 1) const SizedBox(height: 8),
                  _LayerRow(
                    unit: unit,
                    layer: visual,
                    pulse: pulse,
                    stockOf: stockOf,
                    boxLit: boxLit,
                    onBoxTap: onBoxTap,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.unit,
    required this.layer,
    required this.pulse,
    required this.stockOf,
    required this.boxLit,
    required this.onBoxTap,
  });

  final EtalaseUnit unit;
  final int layer;
  final Animation<double> pulse;
  final int Function(String productId, String sku) stockOf;
  final bool Function(EtalaseBox) boxLit;
  final ValueChanged<EtalaseBox> onBoxTap;

  @override
  Widget build(BuildContext context) {
    final width = unit.layerWidths[layer];
    final offset = unit.colOffset(layer);
    final base = unit.bottomWidth;
    return Row(
      children: [
        for (var slot = 0; slot < base; slot++) ...[
          if (slot > 0) const SizedBox(width: 8),
          Expanded(
            child: slot >= offset && slot < offset + width
                ? Builder(
                    builder: (_) {
                      final col = slot - offset;
                      final box = unit.boxAt(layer, col);
                      if (box == null) return const SizedBox(height: 88);
                      return _CardboardBox(
                        box: box,
                        pulse: pulse,
                        stockOf: stockOf,
                        lit: boxLit(box),
                        onTap: () => onBoxTap(box),
                      );
                    },
                  )
                : const SizedBox(height: 88),
          ),
        ],
      ],
    );
  }
}

class _StockLegend extends StatelessWidget {
  const _StockLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: const [
        _LegendItem(
          badge: _StatusBadge.habisPreview(),
          label: 'Stok 0 (habis)',
        ),
        _LegendItem(
          badge: _StatusBadge.lowPreview(),
          label: 'Stok 1–5 (tipis)',
        ),
        _LegendItem(
          badge: _StatusBadge.okPreview(),
          label: 'Aman / belum diisi (tanpa badge)',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.badge, required this.label});

  final Widget badge;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: OptikAdminTokens.slate,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Badge status stok — hanya untuk kardus yang sudah ada produk.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.flag,
    this.qty,
  });

  const _StatusBadge.habisPreview()
      : flag = EtalaseStockFlag.empty,
        qty = 0;

  const _StatusBadge.lowPreview()
      : flag = EtalaseStockFlag.low,
        qty = 3;

  const _StatusBadge.okPreview()
      : flag = EtalaseStockFlag.ok,
        qty = null;

  final EtalaseStockFlag flag;
  final int? qty;

  @override
  Widget build(BuildContext context) {
    if (flag == EtalaseStockFlag.ok) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: OptikAdminTokens.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: OptikAdminTokens.lineStrong),
        ),
        child: Text(
          '—',
          style: TextStyle(
            color: OptikAdminTokens.slate,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final isEmpty = flag == EtalaseStockFlag.empty;
    final bg = isEmpty ? OptikAdminTokens.danger : OptikAdminTokens.warning;
    final label = isEmpty ? 'HABIS' : '! ${qty ?? ''}'.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: bg.withOpacity(0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: OptikAdminTokens.snow,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CardboardBox extends StatelessWidget {
  const _CardboardBox({
    required this.box,
    required this.pulse,
    required this.stockOf,
    required this.lit,
    required this.onTap,
  });

  final EtalaseBox box;
  final Animation<double> pulse;
  final int Function(String productId, String sku) stockOf;
  final bool lit;
  final VoidCallback onTap;

  int _qtyOf(EtalaseBoxProduct p) => stockOf(p.productId, p.sku);

  EtalaseStockFlag? get _flag {
    // Kardus belum diisi produk → bukan peringatan stok.
    if (box.products.isEmpty) return null;
    return box.products
        .map((p) => EtalaseStockRules.flagFor(_qtyOf(p)))
        .reduce((a, b) {
      if (a == EtalaseStockFlag.empty || b == EtalaseStockFlag.empty) {
        return EtalaseStockFlag.empty;
      }
      if (a == EtalaseStockFlag.low || b == EtalaseStockFlag.low) {
        return EtalaseStockFlag.low;
      }
      return EtalaseStockFlag.ok;
    });
  }

  int? get _worstQty {
    if (box.products.isEmpty) return null;
    return box.products.map(_qtyOf).reduce((a, b) => a < b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    const kraft = Color(0xFFC9B28A);
    const kraftDeep = Color(0xFFA8926A);
    final flag = _flag;
    final emptySlot = box.products.isEmpty;
    final alert = flag == EtalaseStockFlag.empty || flag == EtalaseStockFlag.low;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = lit ? 0.3 + pulse.value * 0.4 : 0.0;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: lit ? 1.03 : 1,
            duration: const Duration(milliseconds: 200),
            child: Opacity(
              opacity: emptySlot ? 0.72 : 1,
              child: Container(
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: emptySlot
                        ? const [
                            Color(0xFFE8DFC8),
                            Color(0xFFD4C4A0),
                            Color(0xFFC2B08C),
                          ]
                        : const [Color(0xFFD8C8A4), kraft, kraftDeep],
                  ),
                  border: Border.all(
                    color: flag == EtalaseStockFlag.empty
                        ? OptikAdminTokens.danger
                        : flag == EtalaseStockFlag.low
                            ? OptikAdminTokens.warning
                            : (lit ? OptikAdminTokens.navy : kraftDeep),
                    width: alert || lit ? 2 : 0.8,
                  ),
                  boxShadow: lit
                      ? [
                          BoxShadow(
                            color: OptikAdminTokens.navy.withOpacity(glow),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7D9B8),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    if (flag != null && flag != EtalaseStockFlag.ok)
                      Positioned(
                        top: 8,
                        right: 5,
                        child: _StatusBadge(flag: flag, qty: _worstQty),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 12, 7, 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            box.code,
                            style: const TextStyle(
                              color: Color(0xFF3E3424),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: Text(
                              emptySlot ? 'kosong' : box.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFF3E3424)
                                    .withOpacity(emptySlot ? 0.55 : 0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (!emptySlot)
                            for (final p in box.products)
                              Text(
                                '${p.sku}: ${_qtyOf(p)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: EtalaseStockRules.flagFor(_qtyOf(p)) ==
                                          EtalaseStockFlag.empty
                                      ? OptikAdminTokens.danger
                                      : EtalaseStockRules.flagFor(_qtyOf(p)) ==
                                              EtalaseStockFlag.low
                                          ? OptikAdminTokens.warning
                                          : const Color(0xFF3E3424)
                                              .withOpacity(0.75),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoxEditor extends StatefulWidget {
  const _BoxEditor({
    required this.unitName,
    required this.box,
    required this.productsCatalog,
    required this.masterStockOf,
    required this.onChanged,
  });

  final String unitName;
  final EtalaseBox box;
  final List<Map<String, dynamic>> productsCatalog;
  final int Function(String productId, String sku) masterStockOf;
  final VoidCallback onChanged;

  @override
  State<_BoxEditor> createState() => _BoxEditorState();
}

class _BoxEditorState extends State<_BoxEditor> {
  @override
  void initState() {
    super.initState();
    _pullMasterStock();
  }

  void _pullMasterStock() {
    for (var i = 0; i < widget.box.products.length; i++) {
      final p = widget.box.products[i];
      widget.box.products[i] = p.copyWith(
        qty: widget.masterStockOf(p.productId, p.sku),
      );
    }
  }

  Future<void> _addProduct() async {
    if (!widget.box.canAddProduct) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Maksimal 2 produk per kardus.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    if (widget.productsCatalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Belum ada produk di master toko ini.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    final taken = widget.box.products.map((p) => p.productId).toSet();
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih produk',
      searchable: true,
      searchHint: 'Cari nama / SKU…',
      options: [
        for (final p in widget.productsCatalog)
          if (!taken.contains('${p['id']}'))
            AdminPickerOption(
              value: '${p['id']}',
              label: '${p['nama'] ?? '-'}',
              subtitle:
                  'SKU ${p['sku'] ?? '-'} · stok master ${p['stock'] ?? 0}',
              icon: Icons.inventory_2_outlined,
            ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null || !mounted) return;
    final row = widget.productsCatalog.firstWhere(
      (p) => '${p['id']}' == sel.value,
    );
    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    setState(() {
      widget.box.products.add(EtalaseBoxProduct(
        productId: '${row['id']}',
        sku: '${row['sku'] ?? ''}',
        name: '${row['nama'] ?? ''}',
        qty: stock,
      ));
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.unitName} · ${box.code}',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          box.products.isEmpty
              ? 'Belum ada produk'
              : box.displayName,
          style: TextStyle(color: OptikAdminTokens.slate),
        ),
        const SizedBox(height: 6),
        Text(
          'Stok otomatis dari master produk toko — tidak diubah di denah.',
          style: TextStyle(
            color: OptikAdminTokens.slate.withOpacity(0.9),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < box.products.length; i++) ...[
          Builder(
            builder: (_) {
              final p = box.products[i];
              final stock = widget.masterStockOf(p.productId, p.sku);
              final flag = EtalaseStockRules.flagFor(stock);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text(
                  'SKU ${p.sku} · stok master $stock pcs',
                  style: TextStyle(
                    color: flag == EtalaseStockFlag.empty
                        ? OptikAdminTokens.danger
                        : OptikAdminTokens.slate,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (flag != EtalaseStockFlag.ok)
                      Icon(
                        flag == EtalaseStockFlag.empty
                            ? Icons.circle
                            : Icons.priority_high_rounded,
                        color: OptikAdminTokens.danger,
                        size: 18,
                      ),
                    IconButton(
                      tooltip: 'Hapus dari kardus',
                      onPressed: () {
                        setState(() => box.products.removeAt(i));
                        widget.onChanged();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: OptikAdminTokens.danger,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: box.canAddProduct ? _addProduct : null,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            box.canAddProduct
                ? 'Tambah produk (max 2)'
                : 'Penuh (2 produk)',
          ),
        ),
      ],
    );
  }
}

class _NewEtalaseDraft {
  const _NewEtalaseDraft({
    required this.name,
    required this.layerWidths,
  });

  final String name;
  final List<int> layerWidths;
}

class _AddEtalaseDialog extends StatefulWidget {
  const _AddEtalaseDialog({required this.defaultName});

  final String defaultName;

  @override
  State<_AddEtalaseDialog> createState() => _AddEtalaseDialogState();
}

class _AddEtalaseDialogState extends State<_AddEtalaseDialog> {
  late final TextEditingController _name;
  /// Index huruf paling atas: 0=A … 7=H.
  int _topLetterIndex = 1;
  /// Lebar per layer, index 0 = A. Boleh beda; bawah ≥ atas.
  late List<int> _widths;

  static const _maxLetters = 8;
  static const _maxCols = 8;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.defaultName);
    _widths = [4, 3]; // A=4, B=3 — contoh bebas, bukan template sama
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setTopLetter(int index) {
    setState(() {
      _topLetterIndex = index;
      final need = index + 1;
      if (_widths.length < need) {
        while (_widths.length < need) {
          final below = _widths.last;
          _widths.add(below > 1 ? below - 1 : 1);
        }
      } else if (_widths.length > need) {
        _widths = _widths.sublist(0, need);
      }
      _normalizeWidths();
    });
  }

  void _setLayerWidth(int layer, int width) {
    setState(() {
      final maxW = layer == 0 ? _maxCols : _widths[layer - 1];
      _widths[layer] = width.clamp(1, maxW);
      // Cascade clamp ke atas supaya tetap valid.
      for (var i = layer + 1; i < _widths.length; i++) {
        if (_widths[i] > _widths[i - 1]) {
          _widths[i] = _widths[i - 1];
        }
      }
    });
  }

  void _normalizeWidths() {
    for (var i = 0; i < _widths.length; i++) {
      final maxW = i == 0 ? _maxCols : _widths[i - 1];
      if (_widths[i] > maxW) _widths[i] = maxW;
      if (_widths[i] < 1) _widths[i] = 1;
    }
  }

  int _maxForLayer(int layer) =>
      layer == 0 ? _maxCols : _widths[layer - 1];

  String get _letterStack => [
        for (var i = 0; i <= _topLetterIndex; i++)
          String.fromCharCode(65 + i),
      ].join(' → ');

  String get _widthSummary => [
        for (var i = 0; i < _widths.length; i++)
          '${String.fromCharCode(65 + i)}=${_widths[i]}',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogW = size.width < 520 ? size.width - 32.0 : 460.0;
    final dialogH = size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogW, maxHeight: dialogH),
        child: Material(
          color: OptikAdminTokens.snow,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      OptikAdminTokens.navy,
                      OptikAdminTokens.navy.withOpacity(0.88),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tambah etalase',
                      style: TextStyle(
                        color: OptikAdminTokens.onHighlight,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tiap layer atur sendiri jumlah kardusnya. Syaratnya hanya satu: layer bawah harus lebih banyak atau sama dengan layer di atasnya.',
                      style: TextStyle(
                        color: OptikAdminTokens.onHighlight.withOpacity(0.85),
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nama etalase',
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Contoh: Depan kasir',
                          filled: true,
                          fillColor: OptikAdminTokens.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: OptikAdminTokens.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: OptikAdminTokens.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: OptikAdminTokens.navy,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel(
                        title: 'Berapa layer ke atas',
                        badge: 'HURUF',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pilih huruf paling atas. A selalu di lantai. Pilih C berarti ada layer A, B, dan C — lalu atur sendiri berapa kardus di masing-masing layer.',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _maxLetters; i++)
                            _LetterChip(
                              letter: String.fromCharCode(65 + i),
                              selected: _topLetterIndex == i,
                              onTap: () => _setTopLetter(i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _PreviewPill(
                        icon: Icons.layers_rounded,
                        text: 'Layer aktif: $_letterStack',
                      ),
                      const SizedBox(height: 22),
                      const _SectionLabel(
                        title: 'Jumlah kardus per layer',
                        badge: 'ANGKA',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Atur bebas per huruf. Angka di layer atas tidak boleh lebih besar dari layer tepat di bawahnya (contoh A=5, B=3, C=2 boleh; A=3, B=5 tidak boleh).',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var layer = 0; layer < _widths.length; layer++) ...[
                        if (layer > 0) const SizedBox(height: 14),
                        _LayerWidthEditor(
                          letter: String.fromCharCode(65 + layer),
                          subtitle: layer == 0
                              ? 'Paling bawah (lantai kabinet)'
                              : 'Di atas layer ${String.fromCharCode(64 + layer)} · max ${_maxForLayer(layer)}',
                          width: _widths[layer],
                          maxWidth: _maxForLayer(layer),
                          onSelect: (n) => _setLayerWidth(layer, n),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _PreviewPill(
                        icon: Icons.grid_view_rounded,
                        text: 'Lebar: $_widthSummary',
                      ),
                      const SizedBox(height: 16),
                      _MiniGridPreview(widths: List<int>.from(_widths)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OptikAdminTokens.navy,
                          side: BorderSide(color: OptikAdminTokens.lineStrong),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          if (!EtalaseUnit.widthsValid(_widths)) return;
                          Navigator.pop(
                            context,
                            _NewEtalaseDraft(
                              name: _name.text.trim().isEmpty
                                  ? widget.defaultName
                                  : _name.text.trim(),
                              layerWidths: List<int>.from(_widths),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: OptikAdminTokens.navy,
                          foregroundColor: OptikAdminTokens.onHighlight,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Simpan'),
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
}

class _LayerWidthEditor extends StatelessWidget {
  const _LayerWidthEditor({
    required this.letter,
    required this.subtitle,
    required this.width,
    required this.maxWidth,
    required this.onSelect,
  });

  final String letter;
  final String subtitle;
  final int width;
  final int maxWidth;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OptikAdminTokens.navy,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    color: OptikAdminTokens.onHighlight,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Layer $letter · $width kardus',
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      subtitle,
                      softWrap: true,
                      style: TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var n = 1; n <= maxWidth; n++)
                _NumberChip(
                  number: n,
                  selected: width == n,
                  onTap: () => onSelect(n),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.badge});

  final String title;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            softWrap: true,
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: OptikAdminTokens.ice.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _LetterChip extends StatelessWidget {
  const _LetterChip({
    required this.letter,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? OptikAdminTokens.navy : OptikAdminTokens.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? OptikAdminTokens.navy : OptikAdminTokens.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            letter,
            style: TextStyle(
              color: selected
                  ? OptikAdminTokens.onHighlight
                  : OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? OptikAdminTokens.navy : OptikAdminTokens.snow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? OptikAdminTokens.navy : OptikAdminTokens.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: selected
                  ? OptikAdminTokens.onHighlight
                  : OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: OptikAdminTokens.ice.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: OptikAdminTokens.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              softWrap: true,
              style: TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniGridPreview extends StatelessWidget {
  const _MiniGridPreview({required this.widths});

  final List<int> widths;

  @override
  Widget build(BuildContext context) {
    final base = widths.isEmpty ? 1 : widths.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pratinjau susunan',
            style: TextStyle(
              color: OptikAdminTokens.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          for (var visual = widths.length - 1; visual >= 0; visual--) ...[
            if (visual < widths.length - 1) const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    String.fromCharCode(65 + visual),
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      for (var slot = 0; slot < base; slot++) ...[
                        if (slot > 0) const SizedBox(width: 4),
                        Expanded(
                          child: slot < widths[visual]
                              ? Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFD8C8A4),
                                        Color(0xFFC9B28A),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFA8926A),
                                      width: 0.7,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${String.fromCharCode(65 + visual)}${slot + 1}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF3E3424),
                                    ),
                                  ),
                                )
                              : const SizedBox(height: 22),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
