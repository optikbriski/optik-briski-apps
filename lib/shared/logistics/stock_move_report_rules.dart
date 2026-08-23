import '../attendance/attendance_admin_scope.dart';
import 'do_cart_lines.dart';
import 'do_lifecycle_rules.dart';
import 'product_identity.dart';
import 'stock_mutation_service.dart';

/// Aturan laporan mutasi — UI/tes.
/// RLS + trigger 000028 / RPC 000040 yang menahan celah saat toko jalan.
abstract final class StockMoveReportRules {
  static const openStatuses = <String>{
    DoLifecycleRules.movePreparing,
    DoLifecycleRules.moveWaiting,
    DoLifecycleRules.moveQueued,
    DoLifecycleRules.moveTransit,
    DoLifecycleRules.movePending,
  };

  static bool isOpenStatus(String? status) =>
      openStatuses.contains(DoLifecycleRules.norm(status));

  static String kindOf(Map<String, dynamic> item) {
    final tipe = DoLifecycleRules.norm(item['tipe']?.toString());
    final resi = DoLifecycleRules.norm(item['product_name']?.toString());
    final ket = (item['keterangan'] ?? '').toString();
    if (tipe == DoLifecycleRules.tipeRetur || resi.startsWith('RET-')) {
      return 'retur';
    }
    if (tipe == DoLifecycleRules.tipeRequest ||
        resi.startsWith('RO-') ||
        ket.contains('RequestOrder#')) {
      return 'ro';
    }
    if (tipe == DoLifecycleRules.tipeDelivery || resi.startsWith('DO-')) {
      return 'do';
    }
    return 'other';
  }

  /// Pcs: jumlah baris keranjang, fallback `jumlah`. Jangan int.tryParse.
  static int volumeOf(Map<String, dynamic> item) {
    var vol = 0;
    for (final itm
        in DoCartLines.parseKeterangan((item['keterangan'] ?? '').toString())) {
      vol += DoCartLines.qtyOf(itm);
    }
    if (vol <= 0) vol = StockQty.parseCount(item['jumlah']);
    return vol < 0 ? 0 : vol;
  }

  /// Nilai laporan = qty × modal (jujur gudang). Jual hanya jika modal 0.
  static int nilaiOf(Map<String, dynamic> item) {
    var n = 0;
    for (final itm
        in DoCartLines.parseKeterangan((item['keterangan'] ?? '').toString())) {
      final qty = DoCartLines.qtyOf(itm);
      final modal = ProductIdentity.modalPriceOf(itm);
      final jual = ProductIdentity.sellPriceOf(itm);
      final unit = modal > 0 ? modal : jual;
      n += qty * unit;
    }
    return n;
  }

  static String kpiBucket(String? status) {
    if (DoLifecycleRules.isPreparing(status)) return 'disiapkan';
    if (DoLifecycleRules.isReceiveReady(status)) return 'jalan';
    final s = DoLifecycleRules.norm(status);
    if (s == DoLifecycleRules.moveSuccess) return 'diterima';
    if (s == DoLifecycleRules.moveBatal || s == DoLifecycleRules.moveRejected) {
      return 'batal';
    }
    return 'lain';
  }

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
