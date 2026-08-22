import '../attendance/attendance_admin_scope.dart';
import 'inventory_stock_rules.dart';

/// Aturan Request Order — UI + tes harus sama dengan SQL 000033.
abstract final class RequestOrderRules {
  static bool transisiOk(String? from, String? to) =>
      InventoryStockRules.roTransitionOk(from, to);

  /// Antrian cabang + kirim ke Pusat. Kasir/admin toko sendiri. Bukan cabang orang.
  static bool bolehBukaCabang(Map<String, dynamic> profile) {
    final toko = AttendanceAdminScope.tokoOf(profile);
    return AttendanceAdminScope.canRequestRoToko(profile, toko);
  }

  /// Board Pusat: approve / siapkan / kirim. Bukan owner. Bukan admin cabang.
  static bool bolehProsesPusat(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventoryToko(profile, 'PUSAT');

  static bool bolehKirimKePusat({
    required Map<String, dynamic> profile,
    required String? tokoId,
    required String? status,
  }) {
    if (InventoryStockRules.normRo(status) != InventoryStockRules.roPending) {
      return false;
    }
    return AttendanceAdminScope.canRequestRoToko(profile, tokoId);
  }

  static bool bolehApprove({
    required Map<String, dynamic> profile,
    required String? status,
  }) {
    final s = InventoryStockRules.normRo(status);
    if (s != InventoryStockRules.roPending &&
        s != InventoryStockRules.roSent &&
        s != InventoryStockRules.roApproved) {
      return false;
    }
    return bolehProsesPusat(profile);
  }

  static bool bolehTolak({
    required Map<String, dynamic> profile,
    required String? status,
  }) {
    final s = InventoryStockRules.normRo(status);
    if (s == InventoryStockRules.roShipping ||
        s == InventoryStockRules.roSuccess) {
      return false;
    }
    return bolehApprove(profile, status) ||
        (s == InventoryStockRules.roPreparing && bolehProsesPusat(profile));
  }

  static bool bolehKirim({
    required Map<String, dynamic> profile,
    required String? status,
  }) {
    final s = InventoryStockRules.normRo(status);
    if (s != InventoryStockRules.roPreparing &&
        s != InventoryStockRules.roApproved) {
      return false;
    }
    return bolehProsesPusat(profile);
  }
}
