import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/invoice/invoice_qr_opener.dart';
import '../../shared/qr/obr_codes.dart';
import '../../shared/theme.dart';
import 'karyawan_claim_page.dart';
import 'karyawan_pickup_page.dart';

/// Keputusan routing QR invoice di APK Karyawan (uji unit tanpa Navigator).
enum KaryawanInvoiceQrDest {
  pickupLunas,
  claim,
  snackDp,
  snackClaim,
  snackView,
}

KaryawanInvoiceQrDest resolveKaryawanInvoiceQrDest({
  required bool viewOnly,
  required String? phase,
  required String rawScan,
}) {
  final raw = rawScan.trim();
  if (!viewOnly && raw.isNotEmpty && phase == 'LUNAS') {
    return KaryawanInvoiceQrDest.pickupLunas;
  }
  if (!viewOnly && raw.isNotEmpty && phase == 'CLAIM') {
    return KaryawanInvoiceQrDest.claim;
  }
  return switch (phase) {
    'DP' => KaryawanInvoiceQrDest.snackDp,
    'CLAIM' => KaryawanInvoiceQrDest.snackClaim,
    _ => KaryawanInvoiceQrDest.snackView,
  };
}

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
    final dest = resolveKaryawanInvoiceQrDest(
      viewOnly: viewOnly,
      phase: phase,
      rawScan: raw,
    );

    if (dest == KaryawanInvoiceQrDest.pickupLunas) {
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

    if (dest == KaryawanInvoiceQrDest.claim) {
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
    final msg = switch (dest) {
      KaryawanInvoiceQrDest.snackDp =>
        'antrian_invoice_dp_hint'.tr(namedArgs: {'invoice': noInvoice}),
      KaryawanInvoiceQrDest.snackClaim =>
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
