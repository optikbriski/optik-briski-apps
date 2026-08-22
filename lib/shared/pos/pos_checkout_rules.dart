/// Aturan kasir — UI/tes. RLS + trigger 000024 yang menahan celah.
abstract final class PosCheckoutRules {
  static const minQty = 1;
  static const maxQty = 99;
  static const invoicePoin = 5;
  static const invoiceSumber = 'INVOICE';

  static int clampQty(int n) {
    if (n < minQty) return minQty;
    if (n > maxQty) return maxQty;
    return n;
  }

  static bool isGatewayMethod(String? raw) {
    final m = (raw ?? '').trim().toLowerCase();
    return m == 'qris' ||
        m == 'transfer' ||
        m == 'debit' ||
        m == 'midtrans';
  }

  static bool isCashMethod(String? raw) {
    final m = (raw ?? '').trim().toLowerCase();
    return m == 'tunai' || m == 'cash';
  }

  /// Diskon header hanya dari voucher. Ketik manual tanpa kode = 0.
  static int headerDiscount({
    required String? voucherCode,
    required int voucherNominal,
  }) {
    if ((voucherCode ?? '').trim().isEmpty) return 0;
    return voucherNominal < 0 ? 0 : voucherNominal;
  }

  static int totalAkhir({
    required int subtotal,
    required String? voucherCode,
    required int voucherNominal,
  }) {
    final total = subtotal - headerDiscount(
      voucherCode: voucherCode,
      voucherNominal: voucherNominal,
    );
    return total < 0 ? 0 : total;
  }
}
