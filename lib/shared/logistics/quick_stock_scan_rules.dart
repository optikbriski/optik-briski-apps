import '../attendance/attendance_admin_scope.dart';
import '../qr/product_code.dart';
import 'stock_mutation_service.dart';

/// Aturan Pindai Stok Cepat — UI + tes harus sama dengan SQL 000034/000046.
abstract final class QuickStockScanRules {
  static const int maxCodeChars = 200;

  /// Tile hub: admin toko/pusat. Bukan owner etalase. Bukan kasir.
  static bool bolehBuka(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventory(profile);

  /// Scan stok toko ini? admin_toko hanya toko sendiri. PUSAT = CABANG-PUSAT.
  static bool bolehScanToko(
    Map<String, dynamic> profile,
    String? tokoId,
  ) =>
      AttendanceAdminScope.canManageInventoryToko(profile, tokoId);

  /// Label produk / barcode. Bukan QR invoice, absensi, surat jalan.
  static bool codeOk(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s.length > maxCodeChars) return false;
    if (s.startsWith('{')) return false;
    if (s.startsWith('optikbriski://') || s.startsWith('rekasa://')) {
      return false;
    }
    if (s.contains('://') && s.contains('/i/')) return false;
    if (s.toUpperCase().startsWith('OBR') && !ProductCode.looksLike(s)) {
      return false;
    }
    return ProductCode.resolveSku(s) != null;
  }

  /// Angka stok rak. JSON `7.0` dan `7` sama.
  static int stockOf(Object? raw) => StockQty.parseCount(raw);

  /// Scan hanya baca. Stok rak tidak boleh berubah.
  static bool stokTetap({
    required Object? stockBefore,
    required Object? stockAfter,
  }) =>
      stockOf(stockBefore) == stockOf(stockAfter);
}
