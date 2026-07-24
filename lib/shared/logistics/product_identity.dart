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
    String select = 'id, sku, barcode, nama, stock, toko_id, harga, harga_jual, harga_modal, kategori, warna',
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
    }
    if (b != null) {
      final byBarcode = await client
          .from('products')
          .select(select)
          .eq('toko_id', toko)
          .eq('barcode', b)
          .maybeSingle();
      if (byBarcode != null) return Map<String, dynamic>.from(byBarcode);
    }
    return null;
  }

  static Future<Map<String, dynamic>?> findPusat({
    String? sku,
    String? barcode,
  }) =>
      findAtToko(tokoId: 'PUSAT', sku: sku, barcode: barcode);
}
