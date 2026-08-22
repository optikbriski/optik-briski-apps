/// Aturan stok / logistik — UI/tes. RLS + trigger 000026 yang menahan celah.
abstract final class InventoryStockRules {
  static const movePreparing = 'PREPARING';
  static const moveWaiting = 'WAITING';
  static const moveTransit = 'TRANSIT';
  static const movePending = 'PENDING';
  static const moveSuccess = 'SUCCESS';
  static const moveBatal = 'BATAL';
  static const moveRejected = 'REJECTED';

  static const roPending = 'PENDING';
  static const roSent = 'SENT_TO_HQ';
  static const roApproved = 'APPROVED';
  static const roPreparing = 'PREPARING';
  static const roShipping = 'SHIPPING';
  static const roSuccess = 'SUCCESS';
  static const roRejected = 'REJECTED';

  static String normMove(String? raw) =>
      (raw ?? '').trim().toUpperCase();

  static String normRo(String? raw) => (raw ?? '').trim().toUpperCase();

  static bool isMoveOpen(String? status) {
    final s = normMove(status);
    return s == movePreparing ||
        s == moveWaiting ||
        s == moveTransit ||
        s == movePending;
  }

  static bool isMoveTerminal(String? status) {
    final s = normMove(status);
    return s == moveSuccess || s == moveBatal || s == moveRejected;
  }

  /// PREPARING/WAITING → TRANSIT → SUCCESS. PENDING legacy → SUCCESS.
  /// Tidak boleh SUCCESS → TRANSIT / PREPARING.
  static bool moveTransitionOk(String? from, String? to) {
    final a = normMove(from);
    final b = normMove(to);
    if (a == b) return true;
    if (b == moveBatal || b == moveRejected) {
      return !isMoveTerminal(a) || a == b;
    }
    if (isMoveTerminal(a)) return false;
    if ((a == movePreparing || a == moveWaiting) &&
        (b == moveTransit || b == movePending)) {
      return true;
    }
    if ((a == moveTransit || a == movePending) && b == moveSuccess) {
      return true;
    }
    if ((a == movePreparing || a == moveWaiting) && b == moveSuccess) {
      return false;
    }
    return false;
  }

  /// Cabang tujuan tidak boleh jemput (potong stok Pusat dini).
  static bool canMarkTransit({
    required String scannerToko,
    required String dari,
    required String ke,
  }) {
    final s = scannerToko.trim().toUpperCase();
    final d = dari.trim().toUpperCase();
    final k = ke.trim().toUpperCase();
    if (s.isEmpty) return false;
    if (k.isNotEmpty && s == k && s != d && s != 'PUSAT' && s != 'CABANG-PUSAT') {
      return false;
    }
    return true;
  }

  /// Terima hanya di toko tujuan, status TRANSIT/PENDING.
  static bool canReceiveMove({
    required String receiverToko,
    required String ke,
    required String? status,
  }) {
    final r = receiverToko.trim().toUpperCase();
    final k = ke.trim().toUpperCase();
    if (r.isEmpty || k.isEmpty) return false;
    if (r != k &&
        !(r == 'PUSAT' && k == 'CABANG-PUSAT') &&
        !(r == 'CABANG-PUSAT' && k == 'PUSAT')) {
      return false;
    }
    final s = normMove(status);
    return s == moveTransit || s == movePending;
  }

  /// RO: antrian cabang → HQ → disiapkan → jalan → selesai.
  static bool roTransitionOk(String? from, String? to) {
    final a = normRo(from);
    final b = normRo(to);
    if (a == b) return true;
    if (b == roRejected) {
      return a != roSuccess;
    }
    const forward = {
      roPending: [roSent, roPreparing, roApproved],
      roSent: [roPreparing, roApproved],
      roApproved: [roPreparing, roShipping],
      roPreparing: [roShipping],
      roShipping: [roSuccess],
    };
    return forward[a]?.contains(b) ?? false;
  }

  static bool qtyPositive(int? n) => n != null && n > 0;

  static int clampRequestQty(int n) {
    if (n < 1) return 1;
    if (n > 999) return 999;
    return n;
  }
}
