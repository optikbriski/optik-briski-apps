/// Barcode / QR payload khusus produk (SKU), terpisah dari invoice & logistik.
///
/// Format:
///   `OBRPROD|v1|<sku>`
///   `OBRPROD|v1|<sku>|<product_id>`
///
/// Disimpan di DB tetap `sku` / `barcode` plain; yang tercetak di label produk
/// memakai payload ini agar scan di POS / cek stok jelas milik produk tersebut.
class ProductCodeData {
  const ProductCodeData({required this.sku, this.productId});

  final String sku;
  final String? productId;
}

class ProductCode {
  ProductCode._();

  static const String prefix = 'OBRPROD';
  static const String version = 'v1';

  /// Encode untuk dicetak di label produk (1D & 2D).
  static String encode({required String sku, String? productId}) {
    final s = sku.trim();
    if (s.isEmpty) return '';
    final id = productId?.trim() ?? '';
    if (id.isEmpty) return '$prefix|$version|$s';
    return '$prefix|$version|$s|$id';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static ProductCodeData? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split('|');
    if (parts.length < 3) return null;
    if (parts[0] != prefix || parts[1] != version) return null;
    final sku = parts[2].trim();
    if (sku.isEmpty) return null;
    final id = parts.length >= 4 ? parts[3].trim() : '';
    return ProductCodeData(
      sku: sku,
      productId: id.isEmpty ? null : id,
    );
  }

  /// Ambil SKU untuk lookup. Terima payload [OBRPROD] atau plain sku/barcode.
  /// Null jika raw jelas milik absensi / invoice link / surat jalan JSON.
  static String? resolveSku(String? raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed.sku;

    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    if (s.startsWith('{')) return null;
    if (s.startsWith('OBR')) return null; // ATT/INV/DO/RO/CUS/PROD handled elsewhere
    if (s.contains('://') && s.contains('/i/')) return null;
    if (s.startsWith('optikbriski://invoice/')) return null;
    return s;
  }
}
