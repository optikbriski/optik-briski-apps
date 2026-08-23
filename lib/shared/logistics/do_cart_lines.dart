import 'dart:convert';

import 'product_identity.dart';

/// Baris keranjang DO/draf/retur — harga, foto, qty, SKU satu rumus.
abstract final class DoCartLines {
  static Map<String, dynamic> fromProduct(
    Map<String, dynamic> prod,
    int qty,
  ) {
    final sku = ProductIdentity.skuOf(prod);
    if (sku == null) {
      throw 'Produk ${prod['nama']} belum punya SKU. Lengkapi di Product Master.';
    }
    final n = qty < 1 ? 0 : qty;
    if (n <= 0) {
      throw 'Qty surat jalan harus > 0 (${prod['nama'] ?? sku}).';
    }
    final sell = ProductIdentity.sellPriceOf(prod);
    final modal = ProductIdentity.modalPriceOf(prod);
    final img = ProductIdentity.catalogImageOf(prod);
    return {
      'id_produk': prod['id'],
      'nama': prod['nama'] ?? '-',
      'kategori': prod['kategori'] ?? '-',
      'sub_kategori': prod['sub_kategori'] ?? '-',
      'warna': prod['warna'] ?? '-',
      'jenis_lensa': prod['jenis_lensa'] ?? '-',
      'sph_r': prod['sph_r'] ?? 0,
      'cyl_r': prod['cyl_r'] ?? 0,
      'add_r': prod['add_r'] ?? 0,
      'barcode': prod['barcode'] ?? sku,
      'sku': sku,
      ...ProductIdentity.catalogPriceFields(sell, modal: modal),
      'qty': n,
      ...ProductIdentity.catalogImageFields(img),
    };
  }

  /// Rapikan baris draf/retur yang sudah tersimpan (harga JSON / foto).
  static Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    final qty = qtyOf(raw);
    if (qty <= 0) {
      throw 'Qty surat jalan harus > 0.';
    }
    final sku = ProductIdentity.skuOf(raw);
    if (sku == null) {
      throw 'Item tanpa SKU tidak bisa masuk surat jalan.';
    }
    final sell = ProductIdentity.sellPriceOf(raw);
    final modal = ProductIdentity.modalPriceOf(raw);
    final img = ProductIdentity.catalogImageOf(raw);
    return {
      ...raw,
      'sku': sku,
      'barcode': ProductIdentity.normalizeBarcode(raw['barcode']) ?? sku,
      ...ProductIdentity.catalogPriceFields(sell, modal: modal),
      'qty': qty,
      ...ProductIdentity.catalogImageFields(img),
    };
  }

  /// Item di `keterangan` — boleh ada prefix teks sebelum `[`.
  /// Jangan cari `[{` (gagal jika JSON `[ {`).
  static List<Map<String, dynamic>> parseKeterangan(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const [];
    final start = s.indexOf('[');
    if (start < 0) return const [];
    try {
      final decoded = jsonDecode(s.substring(start));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static int qtyOf(Map<String, dynamic> item) {
    final raw = item['qty'];
    if (raw == null) return 0;
    if (raw is int) return raw < 0 ? 0 : raw;
    if (raw is num) {
      final n = raw.round();
      return n < 0 ? 0 : n;
    }
    final s = raw.toString().trim();
    if (s.isEmpty || s == '-') return 0;
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt < 0 ? 0 : asInt;
    final asD = double.tryParse(s);
    if (asD == null) return 0;
    final n = asD.round();
    return n < 0 ? 0 : n;
  }

  static int totalQty(Iterable<Map<String, dynamic>> items) =>
      items.fold<int>(0, (s, it) => s + qtyOf(it));

  static String encode(List<Map<String, dynamic>> items) => jsonEncode(items);
}
