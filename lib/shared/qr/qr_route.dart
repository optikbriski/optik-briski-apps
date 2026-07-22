import 'dart:convert';

import '../invoice/invoice_link.dart';
import 'obr_codes.dart';
import 'product_code.dart';

/// Jenis payload yang dikenali scanner universal.
enum QrPayloadType {
  invoice,
  attendance,
  receiveStock,
  product,
  customer,
  unknown,
}

/// Hasil klasifikasi string mentah hasil scan QR.
class QrRouteResult {
  const QrRouteResult({
    required this.type,
    required this.raw,
    this.invoiceNo,
    this.invoicePaymentStatus,
    this.invoiceCustomerLifecycle = false,
    this.invoiceViewOnly = false,
    this.attendanceTokoId,
    this.attendanceToken,
    this.receiveResi,
    this.receiveTujuan,
    this.productSku,
    this.productId,
    this.customerNama,
    this.customerPhone,
    this.customerEmail,
  });

  final QrPayloadType type;
  final String raw;
  final String? invoiceNo;
  final String? invoicePaymentStatus;
  /// QR pelanggan `OBRINV|…|DP/LUNAS/CLAIM|<token>` — aksi lifecycle sekali pakai.
  final bool invoiceCustomerLifecycle;
  /// QR toko `OBRTXN` / buka nomor saja — hanya lihat detail.
  final bool invoiceViewOnly;
  final String? attendanceTokoId;
  final String? attendanceToken;
  final String? receiveResi;
  final String? receiveTujuan;
  final String? productSku;
  final String? productId;
  final String? customerNama;
  final String? customerPhone;
  final String? customerEmail;

  bool get isKnown => type != QrPayloadType.unknown;
}

/// Parser payload absensi: `OBRATT|v1|<toko_id>|<token>`.
class AttendanceQrPayload {
  static const String prefix = 'OBRATT';
  static const String version = 'v1';

  static bool looksLike(String? raw) => parse(raw) != null;

  static ({String tokoId, String token})? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split('|');
    if (parts.length < 4) return null;
    if (parts[0] != prefix || parts[1] != version) return null;
    final tokoId = parts[2].trim();
    final token = parts[3].trim();
    if (tokoId.isEmpty || token.length < 16) return null;
    return (tokoId: tokoId, token: token);
  }
}

/// Klasifikasi QR → aksi fitur.
///
/// Urutan: OBRATT → OBRPROD → OBRCUS → OBRINV → OBRDO/OBRRO →
/// HTTPS invoice → JSON receive lama → InvoiceLink (INV- only) → unknown.
class QrRouter {
  const QrRouter._();

  static QrRouteResult classify(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) {
      return const QrRouteResult(type: QrPayloadType.unknown, raw: '');
    }

    final att = AttendanceQrPayload.parse(s);
    if (att != null) {
      return QrRouteResult(
        type: QrPayloadType.attendance,
        raw: s,
        attendanceTokoId: att.tokoId,
        attendanceToken: att.token,
      );
    }

    final prod = ProductCode.parse(s);
    if (prod != null) {
      return QrRouteResult(
        type: QrPayloadType.product,
        raw: s,
        productSku: prod.sku,
        productId: prod.productId,
      );
    }

    final cus = ObrCustomer.parse(s);
    if (cus != null) {
      return QrRouteResult(
        type: QrPayloadType.customer,
        raw: s,
        customerNama: cus.nama,
        customerPhone: cus.phone,
        customerEmail: cus.email,
      );
    }

    // QR toko: lihat detail saja
    final txn = ObrTxn.parse(s);
    if (txn != null) {
      return QrRouteResult(
        type: QrPayloadType.invoice,
        raw: s,
        invoiceNo: txn,
        invoiceViewOnly: true,
      );
    }

    // QR pelanggan: DP / LUNAS lifecycle
    final obrInv = ObrInvoice.parse(s);
    if (obrInv != null) {
      return QrRouteResult(
        type: QrPayloadType.invoice,
        raw: s,
        invoiceNo: obrInv.noInvoice,
        invoicePaymentStatus: obrInv.paymentStatus,
        invoiceCustomerLifecycle: obrInv.customerLifecycle,
        invoiceViewOnly: !obrInv.customerLifecycle,
      );
    }

    final logi = parseObrLogistics(s);
    if (logi != null) {
      return QrRouteResult(
        type: QrPayloadType.receiveStock,
        raw: s,
        receiveResi: logi.resi,
        receiveTujuan: logi.tujuan,
      );
    }

    // Link HTTPS / skema app invoice → lihat detail (bukan lifecycle pelanggan)
    if (_isExplicitInvoiceLink(s)) {
      final inv = InvoiceLink.parse(s);
      if (inv != null && inv.isNotEmpty) {
        return QrRouteResult(
          type: QrPayloadType.invoice,
          raw: s,
          invoiceNo: inv,
          invoiceViewOnly: true,
        );
      }
    }

    final receive = _parseReceiveJson(s);
    if (receive != null) {
      return QrRouteResult(
        type: QrPayloadType.receiveStock,
        raw: s,
        receiveResi: receive.resi,
        receiveTujuan: receive.tujuan,
      );
    }

    final inv = InvoiceLink.parse(s);
    if (inv != null && inv.isNotEmpty) {
      return QrRouteResult(
        type: QrPayloadType.invoice,
        raw: s,
        invoiceNo: inv,
        invoiceViewOnly: true,
      );
    }

    return QrRouteResult(type: QrPayloadType.unknown, raw: s);
  }

  static bool _isExplicitInvoiceLink(String s) {
    if (s.startsWith(InvoiceLink.httpsBase) ||
        s.startsWith('http://optik-briski-apps.vercel.app/i/')) {
      return true;
    }
    final uri = Uri.tryParse(s);
    return uri != null &&
        uri.scheme == InvoiceLink.appScheme &&
        (uri.host == InvoiceLink.appHost ||
            uri.pathSegments.contains(InvoiceLink.appHost));
  }

  /// JSON surat jalan lama: `{"resi":"DO-…","tujuan":"…"}`.
  static ({String resi, String? tujuan})? _parseReceiveJson(String s) {
    if (!s.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final resi =
          (map['resi'] ?? map['product_name'] ?? '').toString().trim();
      if (resi.isEmpty) return null;
      final tujuan = (map['tujuan'] ?? '').toString().trim();
      return (resi: resi, tujuan: tujuan.isEmpty ? null : tujuan);
    } catch (_) {
      return null;
    }
  }
}
