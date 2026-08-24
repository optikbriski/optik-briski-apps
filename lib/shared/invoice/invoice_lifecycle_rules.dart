import '../attendance/attendance_admin_scope.dart';
import '../logistics/product_identity.dart';

/// Aturan board DP · PENDING · READY · CLEAR — UI/tes.
/// RLS + trigger 000025 / 000050 yang menahan celah saat toko jalan.
abstract final class InvoiceLifecycleRules {
  static const trackPending = 'PENDING_PO';
  static const trackSiapPelunasan = 'SIAP_PELUNASAN';
  static const trackSiapDiambil = 'SIAP_DIAMBIL';
  static const trackClearAlias = 'CLEAR';
  static const trackDiambil = 'DIAMBIL';

  static const linePendingRo = 'PENDING_RO';
  static const lineReady = 'READY';
  static const lineDiambil = 'DIAMBIL';

  static const payDp = 'DP';
  static const payLunas = 'LUNAS';

  static String normalizeTrack(String? raw) {
    final t = (raw ?? '').trim().toUpperCase();
    if (t == trackClearAlias) return trackSiapDiambil;
    if (t.isEmpty) return trackPending;
    return t;
  }

  static String normalizeLine(String? raw) {
    final s = (raw ?? lineReady).trim().toUpperCase();
    if (s == linePendingRo || s == 'PENDING') return linePendingRo;
    if (s == lineDiambil) return lineDiambil;
    return lineReady;
  }

  static String normalizePay(String? raw) {
    final p = (raw ?? '').trim().toUpperCase();
    if (p == payDp) return payDp;
    if (p == payLunas) return payLunas;
    return p;
  }

  static bool isCancelled(String? tracking, [String? pay]) {
    final t = (tracking ?? '').trim().toUpperCase();
    final p = (pay ?? '').trim().toUpperCase();
    return t == 'BATAL' ||
        t == 'BATAL_VOUCHER' ||
        t == 'CANCELLED' ||
        p == 'BATAL';
  }

  /// JSON `150000.0` / `150.000` — jangan int.tryParse.
  static int moneyOf(Object? raw) => ProductIdentity.moneyOf(raw);

  /// PUSAT = CABANG-PUSAT.
  static bool sameStore(String? a, String? b) =>
      AttendanceAdminScope.sameTokoId(a, b);

  static bool isPusatToko(String? tokoId) =>
      AttendanceAdminScope.isPusatTokoId(tokoId);

  /// DP board: status DP atau masih ada sisa. Bukan angka dari klien.
  static bool isDp(Map<String, dynamic> sale) {
    final pay = normalizePay(sale['status_pembayaran']?.toString());
    final sisa = moneyOf(sale['sisa_tagihan']);
    return pay == payDp || sisa > 0;
  }

  static bool isClear(Map<String, dynamic> sale) {
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    return sale['diambil_at'] != null || tracking == trackDiambil;
  }

  static bool isReady(Map<String, dynamic> sale) {
    if (isDp(sale) || isClear(sale)) return false;
    final tracking = normalizeTrack(sale['tracking_status']?.toString());
    return tracking == trackSiapDiambil;
  }

  static bool isPending(Map<String, dynamic> sale) {
    if (isDp(sale) || isClear(sale) || isReady(sale)) return false;
    return true;
  }

  /// Sisa pelunasan dari baris nota. Klien tidak boleh kirim nominal sendiri.
  static int remainingFromRow(Map<String, dynamic> sale) {
    final sisa = moneyOf(sale['sisa_tagihan']);
    final dibayar = moneyOf(sale['dibayarkan']);
    final total = moneyOf(sale['total_harga']);
    if (sisa > 0) return sisa;
    final gap = total - dibayar;
    return gap < 0 ? 0 : gap;
  }

  /// PENDING_RO → READY → DIAMBIL. Tidak boleh lompat. Rollback DIAMBIL→READY OK.
  static bool lineTransitionOk(String? from, String? to) {
    final a = normalizeLine(from);
    final b = normalizeLine(to);
    if (a == b) return true;
    if (a == linePendingRo && b == lineReady) return true;
    if (a == lineReady && (b == linePendingRo || b == lineDiambil)) {
      return true;
    }
    if (a == lineDiambil && b == lineReady) return true;
    return false;
  }

  /// Mesin tracking board. DP tidak boleh SIAP_DIAMBIL / DIAMBIL.
  static bool trackingTransitionOk({
    required String? from,
    required String? to,
    required bool wasDp,
    required bool nowDp,
    String? pay,
  }) {
    if (isCancelled(from, pay) || isCancelled(to, pay)) return true;
    final a = normalizeTrack(from);
    final b = normalizeTrack(to);
    if (a == b) return true;

    if (nowDp) {
      return (a == trackPending && b == trackSiapPelunasan) ||
          (a == trackSiapPelunasan && b == trackPending);
    }

    if (wasDp && !nowDp) {
      return (a == trackSiapPelunasan &&
              (b == trackSiapDiambil || b == trackPending)) ||
          (a == trackPending && b == trackPending);
    }

    if (a == trackPending && b == trackSiapDiambil) return true;
    if (a == trackSiapDiambil && b == trackPending) return true;
    if (a == trackSiapDiambil && b == trackDiambil) return true;
    if (a == trackDiambil && b == trackSiapDiambil) return true;
    if (a == trackSiapPelunasan && b == trackSiapDiambil) return true;
    return false;
  }

  static bool paymentTransitionOk(String? from, String? to) {
    final a = normalizePay(from);
    final b = normalizePay(to);
    if (a == b) return true;
    if (b == 'BATAL' || a == 'BATAL') return true;
    if (a == payDp && b == payLunas) return true;
    return false;
  }

  /// QR DP hanya di SIAP_PELUNASAN. QR LUNAS hanya lunas + SIAP_DIAMBIL.
  static bool qrPhaseOk({
    required String phase,
    required bool isDp,
    required String? tracking,
    required bool diambil,
  }) {
    final t = (tracking ?? '').trim().toUpperCase();
    switch (phase.toUpperCase()) {
      case 'DP':
        return isDp && t == trackSiapPelunasan;
      case 'LUNAS':
        return !isDp &&
            !diambil &&
            (t == trackSiapDiambil || t == trackClearAlias);
      case 'CLAIM':
        return diambil;
      default:
        return false;
    }
  }
}
