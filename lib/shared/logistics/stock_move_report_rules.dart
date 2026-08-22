import '../attendance/attendance_admin_scope.dart';
import 'do_lifecycle_rules.dart';

/// Aturan laporan mutasi — UI/tes.
/// RLS + trigger 000028 yang menahan celah saat toko jalan.
abstract final class StockMoveReportRules {
  /// Hub semua cabang: admin_pusat / super_admin. Bukan owner.
  /// Bukan admin_toko di PUSAT.
  static bool isTenantWideHistoryView(Map<String, dynamic> profile) {
    return AttendanceAdminScope.isAdminPusat(profile) ||
        AttendanceAdminScope.isSuperAdmin(profile);
  }

  /// Item JSON / qty hanya gudang asal, status masih disiapkan.
  static bool canEditMoveLineItems({
    required Map<String, dynamic> profile,
    required String dari,
    required String? status,
  }) {
    if (!DoLifecycleRules.isPreparing(status)) return false;
    return AttendanceAdminScope.canManageInventoryToko(profile, dari);
  }

  /// Cabang tujuan tidak REST-write. Terima hanya RPC.
  static bool canReceiverRestPatchMove(Map<String, dynamic> profile) => false;

  static bool canAssignKurir(String? status) {
    final s = DoLifecycleRules.norm(status);
    return s == DoLifecycleRules.movePreparing ||
        s == DoLifecycleRules.moveWaiting ||
        s == DoLifecycleRules.moveTransit ||
        s == DoLifecycleRules.movePending;
  }

  static bool canCancelFromReport({
    required Map<String, dynamic> profile,
    required String dari,
    required String? status,
  }) {
    if (!DoLifecycleRules.canCancelMove(status)) return false;
    return AttendanceAdminScope.canManageInventoryToko(profile, dari);
  }

  static bool canReceiveFromReport({
    required Map<String, dynamic> profile,
    required String ke,
    required String? status,
  }) {
    if (!DoLifecycleRules.isReceiveReady(status)) return false;
    return AttendanceAdminScope.canReceiveStockToko(profile, ke);
  }
}
