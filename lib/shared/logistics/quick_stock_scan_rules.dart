import '../attendance/attendance_admin_scope.dart';
import '../qr/product_code.dart';

/// Aturan Pindai Stok Cepat — UI + tes harus sama dengan SQL 000034.
abstract final class QuickStockScanRules {
  static const int maxCodeChars = 200;

  /// Tile hub: admin toko/pusat. Bukan owner etalase. Bukan kasir.
  static bool bolehBuka(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventory(profile);

  /// Scan stok toko ini? admin_toko hanya toko sendiri. Bukan cabang orang.
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
    if (s.startsWith('OBR') && !ProductCode.looksLike(s)) return false;
    return ProductCode.resolveSku(s) != null;
  }

  /// Scan hanya baca. Stok rak tidak boleh berubah.
  static bool stokTetap({
    required int stockBefore,
    required int stockAfter,
  }) =>
      stockBefore == stockAfter;
}
