import 'package:flutter/material.dart';

import 'invoice_hub_page.dart';
import 'invoice_qr_opener.dart';

/// Admin / full hub (lifecycle + detail + print paths).
void registerInvoiceHubOpener() {
  InvoiceQrOpener.open = (
    context, {
    required noInvoice,
    rawScan,
    profile,
    required viewOnly,
    required fromAdminHidScanner,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceHubPage(
          noInvoice: noInvoice,
          rawScan: rawScan,
          profile: profile,
          viewOnly: viewOnly,
          fromAdminHidScanner: fromAdminHidScanner,
        ),
      ),
    );
  };
}
