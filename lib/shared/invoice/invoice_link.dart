/// Deep link / QR payload untuk hub invoice multi-fungsi.
///
/// Format utama (HTTPS, cocok dipindai kamera HP):
///   https://optik-briski-apps.vercel.app/i/{no_invoice}
/// Format app:
///   optikbriski://invoice/{no_invoice}
/// Backward compatible: string plain `no_invoice` tetap diterima.
class InvoiceLink {
  static const String httpsBase = 'https://optik-briski-apps.vercel.app/i';
  static const String appScheme = 'optikbriski';
  static const String appHost = 'invoice';

  /// Encode nomor invoice ke URL QR.
  static String encode(String noInvoice) {
    final n = noInvoice.trim();
    if (n.isEmpty) return httpsBase;
    return '$httpsBase/${Uri.encodeComponent(n)}';
  }

  /// Encode skema app (opsional).
  static String encodeApp(String noInvoice) {
    final n = noInvoice.trim();
    return '$appScheme://$appHost/${Uri.encodeComponent(n)}';
  }

  /// Ambil no_invoice dari QR/raw scan. Null jika bukan invoice link & bukan pola invoice.
  static String? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    // HTTPS hub
    final httpsPrefix = '$httpsBase/';
    if (s.startsWith(httpsPrefix) ||
        s.startsWith('http://optik-briski-apps.vercel.app/i/')) {
      final uri = Uri.tryParse(s);
      if (uri != null && uri.pathSegments.length >= 2) {
        final i = uri.pathSegments.indexOf('i');
        if (i >= 0 && i + 1 < uri.pathSegments.length) {
          return Uri.decodeComponent(uri.pathSegments[i + 1]).trim();
        }
      }
      final rest = s.split('/i/').last;
      return Uri.decodeComponent(rest.split('?').first).trim();
    }

    // App scheme
    final appUri = Uri.tryParse(s);
    if (appUri != null &&
        appUri.scheme == appScheme &&
        (appUri.host == appHost || appUri.pathSegments.contains(appHost))) {
      final segs = appUri.pathSegments.where((e) => e.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        return Uri.decodeComponent(segs.last).trim();
      }
      if (appUri.path.isNotEmpty) {
        return Uri.decodeComponent(appUri.path.replaceFirst('/', '')).trim();
      }
    }

    // Plain invoice (legacy QR) — pola umum INV-… / huruf-angka
    if (_looksLikeInvoice(s)) return s;

    return null;
  }

  static bool _looksLikeInvoice(String s) {
    if (s.contains('://')) return false;
    if (s.length < 4 || s.length > 64) return false;
    // Hindari SKU produk pendek murni angka panjang barcode EAN
    if (RegExp(r'^\d{8,14}$').hasMatch(s)) return false;
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_/]+$').hasMatch(s);
  }

  static bool isInvoicePayload(String? raw) => parse(raw) != null;
}
