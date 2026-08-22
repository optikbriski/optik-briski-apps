/// Aturan Delivery Order — UI/tes.
/// RLS + trigger + RPC 000027 yang menahan celah saat toko jalan.
abstract final class DoLifecycleRules {
  static const moveQueued = 'QUEUED';
  static const movePreparing = 'PREPARING';
  static const moveWaiting = 'WAITING';
  static const moveTransit = 'TRANSIT';
  static const movePending = 'PENDING';
  static const moveSuccess = 'SUCCESS';
  static const moveBatal = 'BATAL';
  static const moveRejected = 'REJECTED';

  static const tipeDelivery = 'DELIVERY';
  static const tipeRequest = 'REQUEST';
  static const tipeRetur = 'RETUR';

  static String norm(String? raw) => (raw ?? '').trim().toUpperCase();

  static bool isPusatWarehouse(String? toko) {
    final t = norm(toko);
    return t == 'PUSAT' || t == 'CABANG-PUSAT';
  }

  static bool deliveryOriginOk(String? dari) => isPusatWarehouse(dari);

  static bool returDestinationOk(String? ke) => isPusatWarehouse(ke);

  static bool isPreparing(String? status) {
    final s = norm(status);
    return s == movePreparing || s == moveWaiting || s == moveQueued;
  }

  static bool isReceiveReady(String? status) {
    final s = norm(status);
    return s == moveTransit || s == movePending;
  }

  static bool isTerminal(String? status) {
    final s = norm(status);
    return s == moveSuccess || s == moveBatal || s == moveRejected;
  }

  /// PREPARING/WAITING → TRANSIT → SUCCESS.
  /// PENDING legacy/retur → SUCCESS.
  /// BATAL hanya sebelum kirim. Tidak boleh PREPARING → PENDING.
  static bool moveTransitionOk(String? from, String? to) {
    final a = norm(from);
    final b = norm(to);
    if (a == b) return true;
    if (b == moveBatal || b == moveRejected) {
      return isPreparing(a);
    }
    if (isTerminal(a)) return false;
    if (a == moveQueued && (b == movePreparing || b == moveWaiting)) {
      return true;
    }
    if (a == moveWaiting && b == movePreparing) {
      return true;
    }
    if ((a == movePreparing || a == moveWaiting) && b == moveTransit) {
      return true;
    }
    if ((a == moveTransit || a == movePending) && b == moveSuccess) {
      return true;
    }
    return false;
  }

  static bool canCancelMove(String? status) => isPreparing(status);

  static bool canInsertStatus(String? tipe, String? status) {
    final t = norm(tipe);
    final s = norm(status);
    if (s == moveTransit || s == moveSuccess) return false;
    if (s == movePending) return t == tipeRetur;
    return s == movePreparing || s == moveWaiting || s == moveQueued;
  }
}
