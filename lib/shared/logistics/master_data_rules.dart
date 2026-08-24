import '../attendance/attendance_admin_scope.dart';
import 'product_identity.dart';
import 'stock_mutation_service.dart';

/// Aturan Master Data — UI + tes harus sama dengan SQL 000035/000047.
abstract final class MasterDataRules {
  /// Tile / halaman: owner, admin pusat, admin toko. Bukan kasir.
  static bool bolehBuka(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canEditProductCatalog(profile);

  /// Lihat semua cabang di list. Owner / admin_pusat, atau toko Pusat.
  /// PUSAT = CABANG-PUSAT.
  static bool lihatSemuaToko(Map<String, dynamic> profile) {
    if (AttendanceAdminScope.isOwner(profile) ||
        AttendanceAdminScope.isAdminPusat(profile) ||
        AttendanceAdminScope.isSuperAdmin(profile)) {
      return true;
    }
    return AttendanceAdminScope.isPusatTokoId(
      AttendanceAdminScope.tokoOf(profile),
    );
  }

  /// Cabang filter / sebar katalog. Bukan gudang Pusat.
  static bool isCabangToko(String? tokoId) {
    final t = (tokoId ?? '').trim();
    if (t.isEmpty) return false;
    if (t == 'SEMUA' || t == 'BROADCAST_ALL') return false;
    return !AttendanceAdminScope.isPusatTokoId(t);
  }

  static bool sameStore(String? a, String? b) =>
      AttendanceAdminScope.sameTokoId(a, b);

  /// Harga form / JSON `150000.0` / `150.000`.
  static int hargaOf(Object? raw) => ProductIdentity.moneyOf(raw);

  /// Stok tampilan. JSON `7.0` dan `7` sama.
  static int stokOf(Object? raw) => StockQty.parseCount(raw);
}
