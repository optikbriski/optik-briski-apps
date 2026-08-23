import 'package:supabase_flutter/supabase_flutter.dart';

/// Canonical product identity: SKU first, then barcode. Never nama-only for stock.
class ProductIdentity {
  ProductIdentity._();

  static String? normalizeSku(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'NO SKU') return null;
    return s;
  }

  static String? normalizeBarcode(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty || s == '-') return null;
    return s;
  }

  static final _thousandDots = RegExp(r'^\d{1,3}(\.\d{3})+$');

  static int? _parseMoney(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    var s = raw.toString().trim();
    if (s.isEmpty || s == '-') return null;
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(s)?.round();
    }
    if (_thousandDots.hasMatch(s)) {
      return int.tryParse(s.replaceAll('.', ''));
    }
    return int.tryParse(s) ?? double.tryParse(s)?.round();
  }

  /// Harga jual kasir/etalase. `harga_jual` dulu (diskon), lalu `harga`.
  static int sellPriceOf(Map<String, dynamic> item) {
    return _parseMoney(item['harga_jual']) ?? _parseMoney(item['harga']) ?? 0;
  }

  /// Modal buku gudang. Jangan int.tryParse — `150000.0` / `150.000` pecah jadi 0.
  static int modalPriceOf(Map<String, dynamic> item) {
    return _parseMoney(item['harga_modal']) ?? 0;
  }

  /// Tulis kedua kolom harga supaya POS/master/member tidak pecah.
  static Map<String, dynamic> catalogPriceFields(int sell, {int? modal}) {
    return {
      'harga': sell,
      'harga_jual': sell,
      if (modal != null) 'harga_modal': modal,
    };
  }

  static Map<String, dynamic> cartPriceFields(int sell) => {
        'harga': sell,
        'harga_jual': sell,
      };

  /// Foto katalog. `image_url` dulu, lalu `foto_url`.
  static String catalogImageOf(Map<String, dynamic> item) {
    for (final key in const ['image_url', 'foto_url']) {
      final u = (item[key] ?? '').toString().trim();
      if (u.isNotEmpty && u != '-') return u;
    }
    return '';
  }

  static Map<String, dynamic> catalogImageFields(String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty || u == '-') return const {};
    return {'image_url': u, 'foto_url': u};
  }

  /// Resolve SKU from a product map / logistics line.
  static String? skuOf(Map<String, dynamic> item) {
    return normalizeSku(item['sku']) ??
        normalizeSku(item['product_sku']) ??
        normalizeBarcode(item['barcode']);
  }

  /// Find product row at [tokoId] by SKU, then barcode.
  static Future<Map<String, dynamic>?> findAtToko({
    required String tokoId,
    String? sku,
    String? barcode,
    String select =
        'id, sku, barcode, nama, stock, reserved_qty, toko_id, harga, harga_jual, harga_modal, kategori, warna, image_url, foto_url',
  }) async {
    final client = Supabase.instance.client;
    final toko = tokoId.trim().toUpperCase();
    final s = normalizeSku(sku);
    final b = normalizeBarcode(barcode);

    if (s != null) {
      final bySku = await client
          .from('products')
          .select(select)
          .eq('toko_id', toko)
          .eq('sku', s)
          .maybeSingle();
      if (bySku != null) return Map<String, dynamic>.from(bySku);

      // Fallback case-insensitive (samakan dengan RPC apply_stock_delta).
      final loose = await client
          .from('products')
          .select(select)
          .eq('toko_id', toko)
          .ilike('sku', s)
          .limit(5);
      final looseRows = List<Map<String, dynamic>>.from(loose);
      if (looseRows.length == 1) return looseRows.first;
      final exactFold = looseRows.where(
        (r) => (r['sku'] ?? '').toString().trim().toUpperCase() == s.toUpperCase(),
      );
      if (exactFold.length == 1) return exactFold.first;
    }
    if (b != null) {
      final byBarcode = await client
          .from('products')
          .select(select)
          .eq('toko_id', toko)
          .eq('barcode', b)
          .maybeSingle();
      if (byBarcode != null) return Map<String, dynamic>.from(byBarcode);

      final looseB = await client
          .from('products')
          .select(select)
          .eq('toko_id', toko)
          .ilike('barcode', b)
          .limit(5);
      final looseRows = List<Map<String, dynamic>>.from(looseB);
      if (looseRows.length == 1) return looseRows.first;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> findPusat({
    String? sku,
    String? barcode,
  }) =>
      findAtToko(tokoId: 'PUSAT', sku: sku, barcode: barcode);

  /// Pastikan SKU PUSAT punya baris di [tokoId] (stok tetap 0 jika baru).
  static Future<void> ensureAtToko({
    required String tokoId,
    required String sku,
  }) async {
    final s = normalizeSku(sku);
    if (s == null) return;
    final toko = tokoId.trim().toUpperCase();
    if (toko.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'ensure_product_at_toko',
        params: {
          'p_sku': s,
          'p_toko': toko,
          'p_template': <String, dynamic>{},
        },
      );
    } catch (_) {
      // Fallback: salin metadata dari PUSAT, stock = 0 (jangan salin stok PUSAT).
      final pusat = await findPusat(sku: s);
      if (pusat == null) return;
      final existing = await findAtToko(tokoId: toko, sku: s, select: 'id');
      if (existing != null) return;
      final row = Map<String, dynamic>.from(pusat);
      row.remove('id');
      row.remove('created_at');
      row['toko_id'] = toko;
      row['stock'] = 0;
      row['reserved_qty'] = 0;
      row.addAll(catalogPriceFields(
        sellPriceOf(pusat),
        modal: _parseMoney(pusat['harga_modal']),
      ));
      final img = catalogImageOf(pusat);
      if (img.isNotEmpty) {
        row.addAll(catalogImageFields(img));
      }
      try {
        await Supabase.instance.client.from('products').insert(row);
      } catch (_) {}
    }
  }

  /// Katalog dari PUSAT, stok/pending dari [tokoId].
  /// Produk pusat yang belum ada di cabang tetap tampil (stok 0) dan
  /// opsional didaftarkan ke toko tanpa menyalin qty PUSAT.
  static Future<List<Map<String, dynamic>>> listPusatCatalogWithTokoStock({
    required String tokoId,
    String? kategoriEq,
    List<String>? kategoriNeq,
    String? search,
    int limit = 80,
    bool ensureMissingRows = true,
  }) async {
    final client = Supabase.instance.client;
    final toko = tokoId.trim().toUpperCase();
    final q = (search ?? '').trim();

    var pusatQuery = client.from('products').select().eq('toko_id', 'PUSAT');
    if (kategoriEq != null && kategoriEq.isNotEmpty) {
      pusatQuery = pusatQuery.eq('kategori', kategoriEq);
    }
    if (kategoriNeq != null) {
      for (final k in kategoriNeq) {
        pusatQuery = pusatQuery.neq('kategori', k);
      }
    }
    if (q.isNotEmpty) {
      pusatQuery =
          pusatQuery.or('sku.ilike.%$q%,nama.ilike.%$q%,barcode.ilike.%$q%');
    }

    final pusatRes = await pusatQuery.order('nama').limit(limit);
    final pusatList = List<Map<String, dynamic>>.from(
      (pusatRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    if (pusatList.isEmpty) return const [];

    final skus = <String>[];
    for (final p in pusatList) {
      final s = skuOf(p);
      if (s != null) skus.add(s);
    }
    if (skus.isEmpty) return pusatList;

    // Semua baris SKU (semua toko) → stok toko login + total jaringan (untuk bandingan Master)
    final allRes = await client
        .from('products')
        .select('id, sku, barcode, stock, reserved_qty, toko_id')
        .inFilter('sku', skus);

    final bySkuLocal = <String, Map<String, dynamic>>{};
    final totalReal = <String, int>{};
    final totalPending = <String, int>{};
    for (final raw in (allRes as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      final s = normalizeSku(m['sku']);
      if (s == null) continue;
      final t = (m['toko_id'] ?? '').toString().trim().toUpperCase();
      final real = int.tryParse('${m['stock'] ?? 0}') ?? 0;
      final pend = int.tryParse('${m['reserved_qty'] ?? 0}') ?? 0;
      totalReal[s] = (totalReal[s] ?? 0) + real;
      totalPending[s] = (totalPending[s] ?? 0) + pend;
      if (t == toko) bySkuLocal[s] = m;
    }

    final missing = <String>[];
    final merged = <Map<String, dynamic>>[];
    for (final pusat in pusatList) {
      final s = skuOf(pusat);
      if (s == null) {
        merged.add({
          ...pusat,
          'toko_id': toko,
          'stock': 0,
          'reserved_qty': 0,
          'total_stock': 0,
          'total_pending': 0,
        });
        continue;
      }
      final local = bySkuLocal[s];
      final tr = totalReal[s] ?? 0;
      final tp = totalPending[s] ?? 0;
      if (local == null) {
        missing.add(s);
        merged.add({
          ...pusat,
          'id': pusat['id'],
          'toko_id': toko,
          'stock': 0,
          'reserved_qty': 0,
          'total_stock': tr,
          'total_pending': tp,
          '_catalog_only': true,
        });
      } else {
        merged.add({
          ...pusat,
          'id': local['id'],
          'toko_id': toko,
          'stock': local['stock'] ?? 0,
          'reserved_qty': local['reserved_qty'] ?? 0,
          'sku': local['sku'] ?? pusat['sku'],
          'barcode': local['barcode'] ?? pusat['barcode'],
          'total_stock': tr,
          'total_pending': tp,
        });
      }
    }

    if (ensureMissingRows && missing.isNotEmpty && toko != 'PUSAT') {
      // Daftarkan baris toko (stok 0) — jangan salin qty PUSAT.
      for (final s in missing) {
        await ensureAtToko(tokoId: toko, sku: s);
      }
      final refreshed = await client
          .from('products')
          .select('id, sku, barcode, stock, reserved_qty, toko_id')
          .inFilter('sku', missing);
      for (final raw in (refreshed as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final s = normalizeSku(m['sku']);
        if (s == null) continue;
        final t = (m['toko_id'] ?? '').toString().trim().toUpperCase();
        if (t == toko) bySkuLocal[s] = m;
      }
      for (var i = 0; i < merged.length; i++) {
        final s = skuOf(merged[i]);
        if (s == null) continue;
        final local = bySkuLocal[s];
        if (local == null) continue;
        final next = {
          ...merged[i],
          'id': local['id'],
          'stock': local['stock'] ?? 0,
          'reserved_qty': local['reserved_qty'] ?? 0,
          'toko_id': toko,
        };
        next.remove('_catalog_only');
        merged[i] = next;
      }
    }

    return merged;
  }
}
