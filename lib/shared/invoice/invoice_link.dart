import '../qr/obr_codes.dart';

/// Deep link / QR payload untuk hub invoice.
///
/// **Sumber kebenaran tunggal:** token di baris `sales` (`qr_dp_token` /
/// `qr_lunas_token` / `qr_claim_token`). Email, WhatsApp, APK Member, dan PDF
/// POS harus memakai [encodeFromSale] / [InvoiceLifecycleService.customerQrPayload]
/// agar scan di cabang pembuat nota (mis. CIMAHI) selalu cocok.
///
/// **QR pelanggan (lifecycle, sekali pakai per fase):**
///   `OBRINV|v1|<no_invoice>|<DP|LUNAS|CLAIM>|<token>|<ONLINE|OFFLINE>`
/// **QR toko (lihat detail saja):**
///   `OBRTXN|v1|<no_invoice>|<ONLINE|OFFLINE>`
/// Field channel di akhir; QR lama tanpa field = OFFLINE (beli di toko).
/// HTTPS (share / rating HP — bukan lifecycle):
///   https://optik-briski-apps.vercel.app/i/{no_invoice}
class InvoiceLink {
  static const String httpsBase = 'https://optik-briski-apps.vercel.app/i';
  static const String appScheme = 'optikbriski';
  static const String rekasaAppScheme = 'rekasa';
  static const String appHost = 'invoice';

  /// QR cetak untuk pelanggan — wajib [token] untuk aksi lifecycle.
  static String encode(
    String noInvoice, {
    String? paymentStatus,
    String? token,
    String channel = ObrSaleChannel.offline,
  }) {
    final st = ObrInvoice.normalizePhase(paymentStatus);
    final t = (token ?? '').trim();
    if (st != null && t.length >= 8) {
      return ObrInvoice.encodeCustomer(
        noInvoice,
        paymentStatus: st,
        token: t,
        channel: channel,
      );
    }
    // Tanpa token → bukan QR pelanggan lifecycle; fallback QR toko.
    return ObrTxn.encode(noInvoice, channel: channel);
  }

  /// Encode dari baris `sales` (pakai token fase yang masih aktif).
  ///
  /// QR customer hanya setelah admin "Barang Ready":
  /// - DP → QR pelunasan (token + SIAP_PELUNASAN)
  /// - Lunas pending → QR pengambilan (SIAP_DIAMBIL)
  /// - Lunas + stok ready di kasir → langsung QR LUNAS
  ///
  /// Channel dari `sales.channel` (`member_online` → ONLINE di payload).
  static String encodeFromSale(Map<String, dynamic> sale) {
    final no = (sale['no_invoice'] ?? '').toString().trim();
    if (no.isEmpty) return '';
    final channel = ObrSaleChannel.fromSaleChannel(sale['channel']?.toString());
    final tracking =
        (sale['tracking_status']?.toString() ?? '').trim().toUpperCase();
    final diambil =
        sale['diambil_at'] != null || tracking == 'DIAMBIL';
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = pay == 'DP' || sisa > 0;
    final lunasReady = tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';

    if (isDp) {
      // QR DP hanya di SIAP_PELUNASAN + token aktif (setelah admin Barang Ready).
      final t = (sale['qr_dp_token'] ?? '').toString().trim();
      if (tracking != 'SIAP_PELUNASAN' ||
          t.length < 8 ||
          sale['qr_dp_used_at'] != null) {
        return ObrTxn.encode(no, channel: channel);
      }
      return encode(no, paymentStatus: 'DP', token: t, channel: channel);
    }

    final claimT = (sale['qr_claim_token'] ?? '').toString().trim();
    final claimReady =
        claimT.length >= 8 && sale['qr_claim_used_at'] == null;

    if (!diambil) {
      // LUNAS ready (termasuk partial: READY + masih ada RO).
      if (lunasReady) {
        final t = (sale['qr_lunas_token'] ?? '').toString().trim();
        if (t.length >= 8 && sale['qr_lunas_used_at'] == null) {
          return encode(no, paymentStatus: 'LUNAS', token: t, channel: channel);
        }
      }
      // Partial handover: invoice belum DIAMBIL penuh, tapi CLAIM batch aktif.
      if (claimReady && sale['qr_lunas_used_at'] != null) {
        return encode(
          no,
          paymentStatus: 'CLAIM',
          token: claimT,
          channel: channel,
        );
      }
      return ObrTxn.encode(no, channel: channel);
    }

    if (!claimReady) {
      return ObrTxn.encode(no, channel: channel);
    }
    return encode(no, paymentStatus: 'CLAIM', token: claimT, channel: channel);
  }

  /// QR internal toko — hanya lihat detail transaksi.
  static String encodeStoreView(
    String noInvoice, {
    String channel = ObrSaleChannel.offline,
    Map<String, dynamic>? sale,
  }) {
    final ch = sale != null
        ? ObrSaleChannel.fromSaleChannel(sale['channel']?.toString())
        : ObrSaleChannel.normalize(channel);
    return ObrTxn.encode(noInvoice, channel: ch);
  }

  /// Channel dari raw scan QR (`online` | `offline`). Default offline.
  static String channelFromRaw(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ObrSaleChannel.offline;
    final inv = ObrInvoice.parse(raw);
    if (inv != null) return inv.channel;
    final txn = ObrTxn.parseData(raw);
    if (txn != null) return txn.channel;
    return ObrSaleChannel.offline;
  }

  /// Encode HTTPS untuk share / scan kamera HP pelanggan.
  static String encodeHttps(String noInvoice) {
    final n = noInvoice.trim();
    if (n.isEmpty) return httpsBase;
    return '$httpsBase/${Uri.encodeComponent(n)}';
  }

  static String encodeApp(String noInvoice) {
    final n = noInvoice.trim();
    return '$appScheme://$appHost/${Uri.encodeComponent(n)}';
  }

  /// True jika raw adalah QR pelanggan yang boleh memicu aksi lifecycle.
  static bool isCustomerLifecycleQr(String? raw) =>
      ObrInvoice.isCustomerLifecycle(raw);

  /// Ambil no_invoice dari QR/raw scan.
  static String? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    final txn = ObrTxn.parse(s);
    if (txn != null) return txn;

    final obr = ObrInvoice.parse(s);
    if (obr != null) return obr.noInvoice;

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

    final appUri = Uri.tryParse(s);
    if (appUri != null &&
        (appUri.scheme == appScheme || appUri.scheme == rekasaAppScheme) &&
        (appUri.host == appHost || appUri.pathSegments.contains(appHost))) {
      final segs = appUri.pathSegments.where((e) => e.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        return Uri.decodeComponent(segs.last).trim();
      }
      if (appUri.path.isNotEmpty) {
        return Uri.decodeComponent(appUri.path.replaceFirst('/', '')).trim();
      }
    }

    if (_looksLikeInvoice(s)) return s;

    return null;
  }

  static bool _looksLikeInvoice(String s) {
    if (s.contains('://')) return false;
    if (s.startsWith('OBR')) return false;
    if (s.startsWith('BC-') || s.startsWith('LNS-')) return false;
    if (s.startsWith('DO-') || s.startsWith('RO-') || s.startsWith('RET-')) {
      return false;
    }
    if (!s.toUpperCase().startsWith('INV-') &&
        !s.toUpperCase().startsWith('ON-')) {
      return false;
    }
    if (s.length < 4 || s.length > 64) return false;
    return RegExp(r'^(INV|ON)-[A-Za-z0-9\-_]+$', caseSensitive: false)
        .hasMatch(s);
  }

  static bool isInvoicePayload(String? raw) => parse(raw) != null;
}
