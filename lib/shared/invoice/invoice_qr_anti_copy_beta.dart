/// Fitur beta: invalidasi QR pelanggan yang di-copy / di-screenshot.
///
/// Belum aktif — untuk sekarang pelanggan bertanggung jawab menjaga QR-nya.
/// Jangan panggil API di sini dari alur produksi.
class InvoiceQrAntiCopyBeta {
  InvoiceQrAntiCopyBeta._();

  /// Master switch. Harus `false` sampai fitur siap.
  static const bool enabled = false;

  static bool get isUsable => enabled;

  /// Placeholder: putar ulang token fase tanpa mengubah status transaksi.
  static Future<Never> rotateCustomerQr({
    required String saleId,
    required String phase,
  }) async {
    throw UnsupportedError(
      'Anti-copy QR pelanggan masih beta dan belum bisa dipakai.',
    );
  }
}
