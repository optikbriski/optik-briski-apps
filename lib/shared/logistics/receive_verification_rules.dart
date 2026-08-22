import '../attendance/attendance_admin_scope.dart';
import 'do_lifecycle_rules.dart';

/// Aturan Verifikasi Terima — UI/tes.
/// RLS + trigger + RPC 000029 yang menahan celah saat toko jalan.
abstract final class ReceiveVerificationRules {
  /// Antrian + lonceng: admin toko/pusat. Bukan owner. Bukan kasir.
  static bool canOpenIncomingQueue(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventory(profile);

  static bool canReceiveAtToko(
    Map<String, dynamic> profile,
    String? ke,
    String? status,
  ) {
    if (!DoLifecycleRules.isReceiveReady(status)) return false;
    return AttendanceAdminScope.canReceiveStockToko(profile, ke);
  }

  static bool photoRequiredForReceive = true;

  static bool photoOk(String? url) {
    final u = (url ?? '').trim();
    return u.isNotEmpty && u != '-';
  }

  /// RO SUCCESS hanya setelah surat jalan SUCCESS.
  static bool canCloseRoFromMove(String? moveStatus) =>
      DoLifecycleRules.norm(moveStatus) == DoLifecycleRules.moveSuccess;

  static bool verifierIdOk(String? submitted, String? authUid) {
    final a = (authUid ?? '').trim();
    if (a.isEmpty) return false;
    final s = (submitted ?? '').trim();
    return s.isEmpty || s == a;
  }
}
