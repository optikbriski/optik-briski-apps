import 'package:flutter/material.dart';

/// Opens invoice UI after a universal QR classify.
///
/// Registered per flavor so Karyawan does not pull Admin POS/PDF/print
/// into the AOT tree via [InvoiceHubPage].
typedef InvoiceQrOpenFn = Future<void> Function(
  BuildContext context, {
  required String noInvoice,
  String? rawScan,
  Map<String, dynamic>? profile,
  required bool viewOnly,
  required bool fromAdminHidScanner,
});

abstract final class InvoiceQrOpener {
  static InvoiceQrOpenFn? open;
}
