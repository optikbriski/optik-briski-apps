import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/invoice/invoice_qr_opener.dart';
import '../../shared/qr/obr_codes.dart';
import '../../shared/theme.dart';
import 'karyawan_pickup_page.dart';

/// Karyawan invoice opener:
/// - QR **LUNAS** lifecycle → serah terima di HP
/// - DP / CLAIM / view-only → snack (tipe QR lain tetap di-route UniversalQrNav)
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

    final isLunasPickup = !viewOnly && raw.isNotEmpty && phase == 'LUNAS';

    if (isLunasPickup) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => KaryawanPickupPage(
            noInvoice: noInvoice,
            rawScan: raw,
            profile: profile ?? const {},
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
