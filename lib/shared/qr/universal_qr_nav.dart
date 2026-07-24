// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../apps/karyawan/absensi_page.dart';
import '../../apps/member/member_rating_page.dart';
import '../invoice/invoice_qr_opener.dart';
import '../scanner_penerimaan_page.dart';
import 'qr_route.dart';
import 'universal_qr_scan_page.dart';

/// Peran pemanggil — mempengaruhi routing setelah scan.
enum UniversalQrCallerRole { admin, karyawan, member }

/// Entry point navigasi setelah scan universal.
class UniversalQrNav {
  const UniversalQrNav._();

  /// Buka scanner lalu buka fitur sesuai tipe QR.
  static Future<void> open(
    BuildContext context, {
    Map<String, dynamic>? profile,
    UniversalQrCallerRole callerRole = UniversalQrCallerRole.admin,
    Set<QrPayloadType>? allowedTypes,
    String? cabangKaryawan,
    String? karyawanId,
    String? karyawanNama,
  }) async {
    final result = await UniversalQrScanPage.scanRouted(
      context,
      allowedTypes: allowedTypes,
    );
    if (result == null || !context.mounted) return;
    // Kamera HP / Scan QR — bukan scanner HID web admin → lifecycle view-only.
    await dispatch(
      context,
      result,
      profile: profile,
      callerRole: callerRole,
      cabangKaryawan: cabangKaryawan,
      karyawanId: karyawanId,
      karyawanNama: karyawanNama,
      fromAdminHidScanner: false,
    );
  }

  /// True jika [dispatch] akan `Navigator.push` ke halaman lain (bukan snackbar saja).
  static bool wouldNavigate(
    QrRouteResult result, {
    UniversalQrCallerRole callerRole = UniversalQrCallerRole.admin,
    String? cabangKaryawan,
  }) {
    switch (result.type) {
      case QrPayloadType.invoice:
        return (result.invoiceNo ?? '').trim().isNotEmpty;
      case QrPayloadType.attendance:
        return callerRole == UniversalQrCallerRole.karyawan;
      case QrPayloadType.receiveStock:
        if (callerRole != UniversalQrCallerRole.karyawan) return false;
        return (cabangKaryawan ?? '').trim().isNotEmpty;
      case QrPayloadType.product:
      case QrPayloadType.customer:
      case QrPayloadType.unknown:
        return false;
    }
  }

  static Future<void> dispatch(
    BuildContext context,
    QrRouteResult result, {
    Map<String, dynamic>? profile,
    UniversalQrCallerRole callerRole = UniversalQrCallerRole.admin,
    String? cabangKaryawan,
    String? karyawanId,
    String? karyawanNama,
    /// True hanya dari USB/Bluetooth HID yang terhubung ke web admin.
    bool fromAdminHidScanner = false,
  }) async {
    void snack(String msg, {Color? color}) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color),
      );
    }

    switch (result.type) {
      case QrPayloadType.invoice:
        final inv = result.invoiceNo;
        if (inv == null || inv.isEmpty) {
          snack('universal_qr_unknown'.tr(), color: Colors.orange);
          return;
        }
        if (callerRole == UniversalQrCallerRole.member) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemberRatingPage(initialInvoice: inv),
            ),
          );
          return;
        }
        // Lifecycle (lunasi / serah terima / klaim) hanya scanner HID + role admin.
        final lifecycleOk = fromAdminHidScanner &&
            callerRole == UniversalQrCallerRole.admin &&
            result.invoiceCustomerLifecycle &&
            !result.invoiceViewOnly;
        final openInvoice = InvoiceQrOpener.open;
        if (openInvoice == null) {
          snack('universal_qr_unknown'.tr(), color: Colors.orange);
          return;
        }
        await openInvoice(
          context,
          noInvoice: inv,
          rawScan: result.raw,
          profile: profile,
          viewOnly: !lifecycleOk,
          fromAdminHidScanner: lifecycleOk,
        );
        return;

      case QrPayloadType.attendance:
        if (callerRole == UniversalQrCallerRole.member) {
          snack('universal_qr_attendance_member'.tr(), color: Colors.blueAccent);
          return;
        }
        if (callerRole == UniversalQrCallerRole.admin) {
          snack('universal_qr_attendance_admin'.tr(), color: Colors.blueAccent);
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AbsensiPage(initialAttendanceRaw: result.raw),
          ),
        );
        return;

      case QrPayloadType.receiveStock:
        if (callerRole == UniversalQrCallerRole.member) {
          snack('universal_qr_receive_not_member'.tr(), color: Colors.orange);
          return;
        }
        if (callerRole != UniversalQrCallerRole.karyawan) {
          snack('universal_qr_receive_staff_only'.tr(), color: Colors.orange);
          return;
        }
        final cabang = (cabangKaryawan ?? '').trim();
        if (cabang.isEmpty) {
          snack('universal_qr_receive_no_cabang'.tr(), color: Colors.orange);
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScannerPenerimaanPage(
              cabangKaryawan: cabang,
              karyawanId: karyawanId,
              karyawanNama: karyawanNama,
              initialQr: result.raw,
            ),
          ),
        );
        return;

      case QrPayloadType.product:
        snack('Scan produk di POS / cek stok inventori.', color: Colors.blueAccent);
        return;

      case QrPayloadType.customer:
        snack('Scan QR pelanggan di layar POS untuk mengisi data.',
            color: Colors.blueAccent);
        return;

      case QrPayloadType.unknown:
        snack('universal_qr_unknown'.tr(), color: Colors.orange);
    }
  }
}
