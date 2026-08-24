import '../attendance/attendance_admin_scope.dart';
import '../logistics/product_identity.dart';

/// Aturan garansi frame/lensa: satu tenant, toko yang sama, uang JSON, window 7 hari.
abstract final class GaransiRules {
  static const windowDays = 7;

  static int moneyOf(Object? raw) => ProductIdentity.moneyOf(raw);

  static bool sameStore(String? a, String? b) =>
      AttendanceAdminScope.sameTokoId(a, b);

  static bool isPusatToko(String? tokoId) =>
      AttendanceAdminScope.isPusatTokoId(tokoId);

  /// Pusat / owner / admin_pusat / super_admin. Cabang biasa hanya toko sendiri.
  static bool canViewAllStores({
    String? tokoId,
    String? role,
    Map<String, dynamic>? profile,
  }) {
    final p = profile ??
        {
          'toko_id': tokoId,
          'role': role,
        };
    if (AttendanceAdminScope.isPusatOperator(p)) return true;
    return isPusatToko(AttendanceAdminScope.tokoOf(p));
  }

  static List<String> storeAliases(String? tokoId) =>
      AttendanceAdminScope.storeIdAliases(tokoId);

  /// Lunas: status + sisa. Jangan `int.tryParse` — `150000.0` jadi 0.
  static bool isSaleLunas(Map<String, dynamic> sale) {
    final st =
        (sale['status_pembayaran'] ?? '').toString().trim().toLowerCase();
    return st == 'lunas' && moneyOf(sale['sisa_tagihan']) <= 0;
  }

  static String requireTokoId(Object? raw) {
    final t = (raw ?? '').toString().trim();
    if (t.isEmpty) {
      throw StateError('Toko nota wajib. Tidak boleh memakai Pusat merek lain.');
    }
    return t;
  }
}
