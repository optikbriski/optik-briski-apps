// ignore_for_file: use_build_context_synchronously
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../apps/karyawan/absensi_page.dart';
import '../../apps/member/pages/member_invoice_hub_page.dart';
import '../../apps/member/pages/member_product_detail_sheet.dart';
import '../invoice/invoice_qr_opener.dart';
import '../member/member_session.dart';
import '../scanner_penerimaan_page.dart';
import 'qr_route.dart';
import 'universal_qr_scan_page.dart';
import '../theme.dart';

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
      hintKey: callerRole == UniversalQrCallerRole.member
          ? 'member_scan_qr_sub'
          : 'universal_qr_scan_hint',
    );
    if (result == null || !context.mounted) return;
    final toko = (cabangKaryawan ?? profile?['toko_id'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final nik = (karyawanId ?? profile?['nik'] ?? profile?['id'] ?? '')
        .toString()
        .trim();
    final nama = (karyawanNama ?? profile?['nama'] ?? 'Admin').toString().trim();
    // Kamera HP / Scan QR — bukan scanner HID web admin → lifecycle view-only.
    await dispatch(
      context,
      result,
      profile: profile,
      callerRole: callerRole,
      cabangKaryawan: toko.isEmpty ? cabangKaryawan : toko,
      karyawanId: nik.isEmpty ? karyawanId : nik,
      karyawanNama: nama.isEmpty ? karyawanNama : nama,
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
        if ((result.invoiceNo ?? '').trim().isEmpty) return false;
        // Guest Member → snack + login route, bukan push hub.
        if (callerRole == UniversalQrCallerRole.member) {
          return MemberSession.instance.isLoggedIn;
        }
        return true;
      case QrPayloadType.attendance:
        return callerRole == UniversalQrCallerRole.karyawan;
      case QrPayloadType.receiveStock:
        if (callerRole != UniversalQrCallerRole.karyawan &&
            callerRole != UniversalQrCallerRole.admin) {
          return false;
        }
        return (cabangKaryawan ?? '').trim().isNotEmpty;
      case QrPayloadType.product:
        return callerRole == UniversalQrCallerRole.member &&
            (result.productSku ?? '').trim().isNotEmpty;
      case QrPayloadType.customer:
      case QrPayloadType.karyawan:
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
          snack('universal_qr_unknown'.tr(), color: OptikAdminTokens.warning);
          return;
        }
        if (callerRole == UniversalQrCallerRole.member) {
          if (!MemberSession.instance.isLoggedIn) {
            snack(
              'universal_qr_login_for_invoice'.tr(),
              color: OptikAdminTokens.navy,
            );
            await Navigator.of(context).pushNamed('/login');
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemberInvoiceHubPage(noInvoice: inv),
            ),
          );
          return;
        }
        // Bawa raw scan utuh ke hub. Panel tindakan aktif hanya jika payload
        // OBRINV bertoken lolos validasi (lihat InvoiceHubPage._load).
        final openInvoice = InvoiceQrOpener.open;
        if (openInvoice == null) {
          snack('universal_qr_unknown'.tr(), color: OptikAdminTokens.warning);
          return;
        }
        final isStaff = callerRole == UniversalQrCallerRole.admin ||
            callerRole == UniversalQrCallerRole.karyawan;
        final looksLifecycle = isStaff &&
            result.invoiceCustomerLifecycle &&
            !result.invoiceViewOnly;
        await openInvoice(
          context,
          noInvoice: inv,
          rawScan: result.raw,
          profile: profile,
          viewOnly: !looksLifecycle,
          fromAdminHidScanner: looksLifecycle || fromAdminHidScanner,
        );
        return;

      case QrPayloadType.attendance:
        if (callerRole == UniversalQrCallerRole.member) {
          snack('universal_qr_attendance_member'.tr(), color: OptikAdminTokens.navy);
          return;
        }
        if (callerRole == UniversalQrCallerRole.admin) {
          snack('universal_qr_attendance_admin'.tr(), color: OptikAdminTokens.navy);
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
          snack('universal_qr_receive_not_member'.tr(), color: OptikAdminTokens.warning);
          return;
        }
        // Karyawan + admin (dengan cabang) boleh scan DO/RO.
        if (callerRole != UniversalQrCallerRole.karyawan &&
            callerRole != UniversalQrCallerRole.admin) {
          snack('universal_qr_receive_staff_only'.tr(), color: OptikAdminTokens.warning);
          return;
        }
        final cabang = (cabangKaryawan ?? '').trim();
        if (cabang.isEmpty) {
          snack('universal_qr_receive_no_cabang'.tr(), color: OptikAdminTokens.warning);
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
        if (callerRole == UniversalQrCallerRole.member) {
          final sku = (result.productSku ?? '').trim();
          if (sku.isEmpty) {
            snack('universal_qr_unknown'.tr(), color: OptikAdminTokens.warning);
            return;
          }
          await openMemberProductDetailBySku(context, sku: sku);
          return;
        }
        snack('universal_qr_product_staff'.tr(), color: OptikAdminTokens.navy);
        return;

      case QrPayloadType.customer:
        if (callerRole == UniversalQrCallerRole.member) {
          snack('universal_qr_customer_member'.tr(), color: OptikAdminTokens.navy);
          return;
        }
        snack('universal_qr_customer_staff'.tr(), color: OptikAdminTokens.navy);
        return;

      case QrPayloadType.karyawan:
        if (callerRole == UniversalQrCallerRole.member) {
          snack('universal_qr_karyawan_member'.tr(), color: OptikAdminTokens.navy);
          return;
        }
        snack('universal_qr_karyawan_staff'.tr(), color: OptikAdminTokens.navy);
        return;

      case QrPayloadType.unknown:
        snack('universal_qr_unknown'.tr(), color: OptikAdminTokens.warning);
    }
  }
}
