import '../attendance/attendance_admin_scope.dart';
import '../logistics/product_identity.dart';

/// Aturan pesanan online: satu tenant, toko yang sama, uang JSON.
abstract final class MemberOnlineOrderRules {
  static int moneyOf(Object? raw) => ProductIdentity.moneyOf(raw);

  static int countOf(Object? raw) => ProductIdentity.countOf(raw);

  static bool sameStore(String? a, String? b) =>
      AttendanceAdminScope.sameTokoId(a, b);

  static bool isPusatToko(String? tokoId) =>
      AttendanceAdminScope.isPusatTokoId(tokoId);

  static bool isPusatRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'owner' || r == 'admin_pusat' || r == 'super_admin';
  }

  /// Antrian Admin: pusat lihat semua cabang tenant; staf hanya toko sendiri.
  static bool orderBelongsToStaff({
    required bool pusatRole,
    String? staffTokoId,
    String? orderTokoId,
  }) {
    if (pusatRole) return true;
    return sameStore(staffTokoId, orderTokoId);
  }

  static bool hasPreorder(Map<String, dynamic> order) {
    final note = (order['store_note'] ?? '').toString().toLowerCase();
    if (note.contains('pre-order') || note.contains('preorder')) return true;
    final items = order['items'];
    if (items is! List) return false;
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['pre_order'] == true) return true;
      if (countOf(m['preorder_qty']) > 0) return true;
    }
    return false;
  }

  static bool isActivePaid(Map<String, dynamic> order) {
    final s = (order['status'] ?? '').toString();
    return s == 'paid' || s == 'packing' || s == 'ready' || s == 'shipped';
  }
}
