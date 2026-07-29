/// Hasil pengiriman nota ke email / WhatsApp (untuk feedback UI admin).
class InvoiceDeliveryResult {
  const InvoiceDeliveryResult({
    required this.emailOk,
    required this.waOk,
    required this.emailSkipped,
    required this.waSkipped,
    this.emailError,
    this.waError,
    this.payload,
    this.phase,
    this.invoice,
  });

  final bool emailOk;
  final bool waOk;
  final bool emailSkipped;
  final bool waSkipped;
  final String? emailError;
  final String? waError;
  final String? payload;
  final String? phase;
  final String? invoice;

  bool get anyOk => emailOk || waOk;
  bool get allRequestedOk =>
      (emailSkipped || emailOk) && (waSkipped || waOk);

  /// Ringkas untuk SnackBar admin.
  String get summary {
    final inv = (invoice ?? '').trim();
    final head = inv.isEmpty ? 'Kirim nota' : 'Kirim $inv';
    final parts = <String>[];

    if (emailSkipped) {
      parts.add('email: tidak ada alamat');
    } else if (emailOk) {
      parts.add('email: OK');
    } else {
      parts.add('email: GAGAL${emailError != null ? ' ($emailError)' : ''}');
    }

    if (waSkipped) {
      parts.add('WA: tidak ada nomor');
    } else if (waOk) {
      parts.add('WA: OK');
    } else {
      parts.add('WA: GAGAL${waError != null ? ' ($waError)' : ''}');
    }

    parts.add('Member: update otomatis (notif/poll)');
    return '$head · ${parts.join(' · ')}';
  }
}
