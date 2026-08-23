import '../attendance/attendance_admin_scope.dart';
import 'stock_move_report_rules.dart';

/// Aturan Tracking Logistics — UI + tes harus sama dengan SQL 000032/000044.
abstract final class LogisticsTrackingRules {
  /// Tile / halaman: admin toko/pusat. Bukan owner etalase. Bukan kasir.
  static bool bolehBuka(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canOpenLogistics(profile);

  static bool isOpenStatus(String? status) =>
      StockMoveReportRules.isOpenStatus(status);

  /// Pcs keranjang. Jangan `jumlah` mentah / int.tryParse `12.0`.
  static int volumeOf(Map<String, dynamic> move) =>
      StockMoveReportRules.volumeOf(move);

  /// Hub peta semua cabang tenant. Bukan admin_toko di PUSAT. Bukan owner.
  static bool isHub(Map<String, dynamic> profile) =>
      StockMoveReportRules.isTenantWideHistoryView(profile);

  static bool statusBolehKurir(String? status) =>
      StockMoveReportRules.canAssignKurir(status);

  /// Set/hapus kurir: gudang asal saja, status masih terbuka.
  /// Cabang tujuan tidak boleh ganti kurir DO Pusat.
  static bool bolehAssignKurir({
    required Map<String, dynamic> profile,
    required String? dari,
    required String? status,
  }) {
    if (!statusBolehKurir(status)) return false;
    return AttendanceAdminScope.canManageInventoryToko(profile, dari);
  }
}
