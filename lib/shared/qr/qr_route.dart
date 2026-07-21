import 'dart:convert';

import '../invoice/invoice_link.dart';

/// Jenis payload yang dikenali scanner universal.
enum QrPayloadType {
  invoice,
  attendance,
  receiveStock,
  unknown,
}

/// Hasil klasifikasi string mentah hasil scan QR.
class QrRouteResult {
  const QrRouteResult({
    required this.type,
    required this.raw,
    this.invoiceNo,
    this.attendanceTokoId,
    this.attendanceToken,
    this.receiveResi,
  });

  final QrPayloadType type;
  final String raw;
  final String? invoiceNo;
  final String? attendanceTokoId;
  final String? attendanceToken;
  final String? receiveResi;

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

/// Klasifikasi QR → aksi fitur (invoice / absensi / penerimaan / unknown).
class QrRouter {
  const QrRouter._();

  /// Urutan: absensi (eksplisit) → invoice link → JSON surat jalan → unknown.
  /// Plain INV diprioritaskan lewat [InvoiceLink]; DO plain tidak di-claim di sini.
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

    // Link HTTPS / skema app invoice (bukan plain heuristic dulu)
    if (_isExplicitInvoiceLink(s)) {
      final inv = InvoiceLink.parse(s);
      if (inv != null && inv.isNotEmpty) {
        return QrRouteResult(
          type: QrPayloadType.invoice,
          raw: s,
          invoiceNo: inv,
        );
      }
    }

    final receive = _parseReceive(s);
    if (receive != null) {
      return QrRouteResult(
        type: QrPayloadType.receiveStock,
        raw: s,
        receiveResi: receive,
      );
    }

    final inv = InvoiceLink.parse(s);
    if (inv != null && inv.isNotEmpty) {
      return QrRouteResult(
        type: QrPayloadType.invoice,
        raw: s,
        invoiceNo: inv,
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

  /// JSON surat jalan: `{"resi":"DO-…","tujuan":"…"}`.
  static String? _parseReceive(String s) {
    if (!s.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final resi =
          (map['resi'] ?? map['product_name'] ?? '').toString().trim();
      if (resi.isEmpty) return null;
      return resi;
    } catch (_) {
      return null;
    }
  }
}
