/// Denah etalase: tumpukan kardus A (bawah) → B → C …
/// Lebar layer atas tidak boleh melebihi layer di bawahnya.
enum EtalaseAlign { left, center, right }

class EtalaseBoxProduct {
  const EtalaseBoxProduct({
    required this.productId,
    required this.sku,
    required this.name,
    required this.qty,
  });

  final String productId;
  final String sku;
  final String name;

  /// Snapshot stok master saat sync (bukan input manual denah).
  final int qty;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'sku': sku,
        'name': name,
        // qty tidak disimpan sebagai sumber kebenaran — diisi ulang dari master.
      };

  static EtalaseBoxProduct fromJson(Map<String, dynamic> m) => EtalaseBoxProduct(
        productId: '${m['productId'] ?? ''}',
        sku: '${m['sku'] ?? ''}',
        name: '${m['name'] ?? ''}',
        qty: (m['qty'] as num?)?.toInt() ?? 0,
      );

  EtalaseBoxProduct copyWith({String? name, int? qty}) => EtalaseBoxProduct(
        productId: productId,
        sku: sku,
        name: name ?? this.name,
        qty: qty ?? this.qty,
      );
}

enum EtalaseStockFlag { ok, low, empty }

abstract final class EtalaseStockRules {
  EtalaseStockRules._();

  static const maxProductsPerBox = 2;
  static const lowStockAt = 5;

  static EtalaseStockFlag flagFor(int qty) {
    if (qty <= 0) return EtalaseStockFlag.empty;
    if (qty <= lowStockAt) return EtalaseStockFlag.low;
    return EtalaseStockFlag.ok;
  }
}

class EtalaseBox {
  EtalaseBox({
    required this.layer,
    required this.col,
    List<EtalaseBoxProduct>? products,
  }) : products = List<EtalaseBoxProduct>.from(products ?? const []);

  /// 0 = A (paling bawah).
  final int layer;
  final int col;
  final List<EtalaseBoxProduct> products;

  String get code {
    final letter = String.fromCharCode('A'.codeUnitAt(0) + layer);
    return '$letter${col + 1}';
  }

  /// Nama mengikuti produk yang dipilih.
  String get displayName {
    if (products.isEmpty) return code;
    if (products.length == 1) return products.first.name;
    return '${products[0].name} · ${products[1].name}';
  }

  bool get canAddProduct =>
      products.length < EtalaseStockRules.maxProductsPerBox;

  Map<String, dynamic> toJson() => {
        'layer': layer,
        'col': col,
        'products': products.map((p) => p.toJson()).toList(),
      };

  static EtalaseBox fromJson(Map<String, dynamic> m) => EtalaseBox(
        layer: (m['layer'] as num?)?.toInt() ?? 0,
        col: (m['col'] as num?)?.toInt() ?? 0,
        products: [
          for (final p in (m['products'] as List? ?? const []))
            EtalaseBoxProduct.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );

  EtalaseBox copy() => EtalaseBox(
        layer: layer,
        col: col,
        products: [
          for (final p in products) p.copyWith(),
        ],
      );
}

class EtalaseUnit {
  EtalaseUnit({
    required this.id,
    required this.name,
    required List<int> layerWidths,
    this.align = EtalaseAlign.left,
    List<EtalaseBox>? boxes,
  })  : layerWidths = List<int>.from(layerWidths),
        boxes = boxes ?? _buildBoxes(layerWidths);

  final String id;
  String name;

  /// Index 0 = A (bawah). Nilai = jumlah kardus ke samping di layer itu.
  final List<int> layerWidths;
  EtalaseAlign align;
  final List<EtalaseBox> boxes;

  int get layerCount => layerWidths.length;
  int get bottomWidth => layerWidths.isEmpty ? 0 : layerWidths.first;

  static List<EtalaseBox> _buildBoxes(List<int> widths) {
    final out = <EtalaseBox>[];
    for (var layer = 0; layer < widths.length; layer++) {
      for (var col = 0; col < widths[layer]; col++) {
        out.add(EtalaseBox(layer: layer, col: col));
      }
    }
    return out;
  }

  /// Buat etalase: [layerWidths] index 0 = A (bawah). Atas tidak boleh > bawah.
  static EtalaseUnit create({
    required String name,
    required List<int> layerWidths,
    EtalaseAlign align = EtalaseAlign.left,
  }) {
    final widths = sanitizeWidths(layerWidths);
    if (!widthsValid(widths)) {
      throw ArgumentError('Lebar layer tidak valid: $layerWidths');
    }
    return EtalaseUnit(
      id: 'e_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Etalase' : name.trim(),
      layerWidths: widths,
      align: align,
    );
  }

  /// Convenience: semua layer sama lebar awal.
  static EtalaseUnit createUniform({
    required String name,
    required int layers,
    required int columns,
    EtalaseAlign align = EtalaseAlign.left,
  }) {
    if (layers < 1 || columns < 1) {
      throw ArgumentError('layers/columns harus ≥ 1');
    }
    return create(
      name: name,
      layerWidths: List<int>.filled(layers, columns),
      align: align,
    );
  }

  /// Layer atas tidak boleh lebih lebar dari layer di bawahnya.
  static bool widthsValid(List<int> widths) {
    if (widths.isEmpty) return false;
    for (final w in widths) {
      if (w < 1) return false;
    }
    for (var i = 1; i < widths.length; i++) {
      if (widths[i] > widths[i - 1]) return false;
    }
    return true;
  }

  /// Perbaiki lebar ilegal (clamp atas ≤ bawah) tanpa membuang seluruh denah.
  static List<int> sanitizeWidths(List<int> raw) {
    if (raw.isEmpty) return const [4];
    final out = <int>[];
    for (var i = 0; i < raw.length; i++) {
      var v = raw[i];
      if (v < 1) v = 1;
      if (v > 8) v = 8;
      if (i > 0 && v > out[i - 1]) v = out[i - 1];
      out.add(v);
    }
    return out;
  }

  /// Samakan daftar kardus dengan lebar layer; pertahankan isi yang masih muat.
  static List<EtalaseBox> reconcileBoxes(
    List<int> widths,
    List<EtalaseBox> raw,
  ) {
    final built = _buildBoxes(widths);
    for (final box in built) {
      for (final r in raw) {
        if (r.layer != box.layer || r.col != box.col) continue;
        box.products
          ..clear()
          ..addAll([
            for (final p in r.products.take(EtalaseStockRules.maxProductsPerBox))
              p.copyWith(),
          ]);
        break;
      }
    }
    return built;
  }

  /// Ubah lebar satu layer; pertahankan isi kardus yang masih ada.
  bool setLayerWidth(int layer, int width) {
    if (layer < 0 || layer >= layerWidths.length) return false;
    final next = List<int>.from(layerWidths);
    next[layer] = width;
    if (!widthsValid(next)) return false;

    final kept = reconcileBoxes(next, boxes);
    layerWidths
      ..clear()
      ..addAll(next);
    boxes
      ..clear()
      ..addAll(kept);
    return true;
  }

  EtalaseBox? boxAt(int layer, int col) {
    for (final b in boxes) {
      if (b.layer == layer && b.col == col) return b;
    }
    return null;
  }

  /// Offset kolom untuk rata kiri/tengah/kanan relatif lebar bawah.
  int colOffset(int layer) {
    final w = layerWidths[layer];
    final base = bottomWidth;
    final gap = base - w;
    return switch (align) {
      EtalaseAlign.left => 0,
      EtalaseAlign.right => gap,
      EtalaseAlign.center => gap ~/ 2,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'layerWidths': layerWidths,
        'align': align.name,
        'boxes': boxes.map((b) => b.toJson()).toList(),
      };

  static EtalaseUnit fromJson(Map<String, dynamic> m) {
    final rawWidths = [
      for (final w in (m['layerWidths'] as List? ?? const [4]))
        (w as num).toInt(),
    ];
    final widths = sanitizeWidths(rawWidths);
    final alignName = '${m['align'] ?? 'left'}';
    final align = EtalaseAlign.values.firstWhere(
      (a) => a.name == alignName,
      orElse: () => EtalaseAlign.left,
    );
    final rawBoxes = [
      for (final b in (m['boxes'] as List? ?? const []))
        EtalaseBox.fromJson(Map<String, dynamic>.from(b as Map)),
    ];
    return EtalaseUnit(
      id: '${m['id'] ?? 'e'}',
      name: '${m['name'] ?? 'Etalase'}',
      layerWidths: widths,
      align: align,
      boxes: reconcileBoxes(widths, rawBoxes),
    );
  }
}

abstract final class EtalaseLayoutStore {
  EtalaseLayoutStore._();

  static String prefKey(String tokoId) {
    final id = tokoId.trim().toUpperCase();
    final norm =
        id.isEmpty || id == 'CABANG-PUSAT' || id == 'PUSAT' ? 'PUSAT' : id;
    return 'etalase_layout_v2_$norm';
  }

  /// Jejak penempatan SKU (tanpa qty) — deteksi drop setelah sync master.
  static String placementFingerprint(List<EtalaseUnit> units) {
    final parts = <String>[];
    for (final u in units) {
      for (final b in u.boxes) {
        for (final p in b.products) {
          parts.add('${u.id}|${b.layer}|${b.col}|${p.productId}|${p.sku}');
        }
      }
    }
    parts.sort();
    return parts.join(';');
  }

  /// Isi ulang nama+stok dari master; buang SKU yang sudah tidak ada.
  /// Return true jika daftar penempatan berubah (perlu persist).
  static bool syncFromMaster(
    List<EtalaseUnit> units,
    List<Map<String, dynamic>> products,
  ) {
    final before = placementFingerprint(units);
    final byId = {
      for (final p in products) '${p['id']}': p,
    };
    final bySku = <String, Map<String, dynamic>>{};
    for (final p in products) {
      final sku = '${p['sku']}'.trim().toUpperCase();
      if (sku.isEmpty) continue;
      bySku.putIfAbsent(sku, () => p);
    }
    for (final u in units) {
      for (final box in u.boxes) {
        final kept = <EtalaseBoxProduct>[];
        for (final cur in box.products) {
          if (cur.productId.isEmpty && cur.sku.isEmpty) continue;
          final m = byId[cur.productId] ?? bySku[cur.sku.toUpperCase()];
          if (m == null) continue;
          kept.add(EtalaseBoxProduct(
            productId: '${m['id']}',
            sku: '${m['sku'] ?? cur.sku}',
            name: '${m['nama'] ?? cur.name}',
            qty: (m['stock'] as num?)?.toInt() ?? 0,
          ));
        }
        box.products
          ..clear()
          ..addAll(kept.take(EtalaseStockRules.maxProductsPerBox));
      }
    }
    return before != placementFingerprint(units);
  }
}
