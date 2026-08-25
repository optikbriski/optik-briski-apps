import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/invoice/invoice_qr_opener.dart';
import '../../shared/qr/obr_codes.dart';
import '../../shared/theme.dart';
import 'karyawan_claim_page.dart';
import 'karyawan_pickup_page.dart';

/// Karyawan invoice opener:
/// - QR **LUNAS** → serah terima di HP (wajib shift OPEN)
/// - QR **CLAIM** → klaim garansi di HP (wajib shift OPEN)
/// - DP / view-only → snack petunjuk
void registerKaryawanInvoiceOpener() {
  InvoiceQrOpener.open = (
    context, {
    required noInvoice,
    rawScan,
    profile,
    required viewOnly,
    required fromAdminHidScanner,
  }) async {
    final raw = (rawScan ?? '').trim();
    final phase = ObrInvoice.parse(raw)?.phase;
    final prof = profile ?? const <String, dynamic>{};

    if (!viewOnly && raw.isNotEmpty && phase == 'LUNAS') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => KaryawanPickupPage(
            noInvoice: noInvoice,
            rawScan: raw,
            profile: prof,
          ),
        ),
      );
      return;
    }

    if (!viewOnly && raw.isNotEmpty && phase == 'CLAIM') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => KaryawanClaimPage(
            noInvoice: noInvoice,
            rawScan: raw,
            profile: prof,
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final msg = switch (phase) {
      'DP' => 'antrian_invoice_dp_hint'.tr(namedArgs: {'invoice': noInvoice}),
      'CLAIM' =>
        'antrian_invoice_claim_hint'.tr(namedArgs: {'invoice': noInvoice}),
      _ => 'antrian_invoice_view_hint'.tr(namedArgs: {'invoice': noInvoice}),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: OptikAdminTokens.navy,
      ),
    );
  };
}
