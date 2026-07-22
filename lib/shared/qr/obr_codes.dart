// Unified Optik B. Riski QR / SKU payloads (pipe-separated, one scanner).
//
// OBRPROD|v1|<sku>|<product_id>       → product_code.dart
// OBRATT|v1|<toko_id>|<token>         → qr_route.dart AttendanceQrPayload
// OBRINV|v1|<no>|<DP|LUNAS|CLAIM>|<token>  → QR PELANGGAN (sekali pakai per fase)
// OBRTXN|v1|<no_invoice>                    → QR TOKO (lihat detail saja)
// OBRDO|v1|<resi>|<tujuan>
// OBRRO|v1|<resi>|<tujuan>
// OBRCUS|v1|<nama>|<phone>|<email>
//
// Field values must not contain `|` (stripped on encode).

String _clean(String? v) =>
    (v ?? '').trim().replaceAll('|', ' ').replaceAll(RegExp(r'\s+'), ' ');

// -----------------------------------------------------------------------------
// Invoice
// -----------------------------------------------------------------------------

class ObrInvoiceData {
  const ObrInvoiceData({
    required this.noInvoice,
    this.phase,
    this.token,
    this.customerLifecycle = false,
  });

  final String noInvoice;
  /// `DP` | `LUNAS` | `CLAIM` pada QR pelanggan.
  final String? phase;
  /// Token sekali pakai (wajib untuk aksi lifecycle).
  final String? token;
  /// True hanya untuk QR pelanggan bertoken (`OBRINV|…|DP/LUNAS/CLAIM|<token>`).
  final bool customerLifecycle;

  /// Alias kompatibilitas.
  String? get paymentStatus => phase;
}

class ObrInvoice {
  ObrInvoice._();

  static const prefix = 'OBRINV';
  static const version = 'v1';

  /// QR pelanggan sekali pakai: `OBRINV|v1|<no>|<fase>|<token>`.
  static String encodeCustomer(
    String noInvoice, {
    required String paymentStatus,
    required String token,
  }) {
    final n = _clean(noInvoice);
    final st = normalizePhase(paymentStatus);
    final t = _clean(token).replaceAll(' ', '');
    if (n.isEmpty || st == null || t.length < 8) return '';
    return '$prefix|$version|$n|$st|$t';
  }

  @Deprecated('Gunakan encodeCustomer(+token) untuk QR pelanggan')
  static String encode(String noInvoice, {String? paymentStatus, String? token}) {
    final st = normalizePhase(paymentStatus);
    final t = (token ?? '').trim();
    if (st != null && t.length >= 8) {
      return encodeCustomer(noInvoice, paymentStatus: st, token: t);
    }
    return ObrTxn.encode(noInvoice);
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static bool isCustomerLifecycle(String? raw) {
    final p = parse(raw);
    return p != null && p.customerLifecycle;
  }

  static ObrInvoiceData? parse(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 3) return null;
    final no = parts[2].trim();
    if (no.isEmpty) return null;
    final st = parts.length >= 4 ? normalizePhase(parts[3]) : null;
    final token = parts.length >= 5 ? parts[4].trim() : '';
    final hasToken = token.length >= 8;
    return ObrInvoiceData(
      noInvoice: no,
      phase: st,
      token: hasToken ? token : null,
      // Legacy tanpa token: dikenali sebagai invoice, tapi BUKAN lifecycle aktif.
      customerLifecycle:
          hasToken && (st == 'DP' || st == 'LUNAS' || st == 'CLAIM'),
    );
  }

  /// Normalisasi fase QR / status bayar → `DP` | `LUNAS` | `CLAIM`.
  static String? normalizePhase(String? raw) {
    final s = (raw ?? '').trim().toUpperCase();
    if (s == 'DP') return 'DP';
    if (s == 'CLAIM' || s == 'KLAIM') return 'CLAIM';
    if (s == 'LUNAS' || s == 'PAID' || s == 'FULL') return 'LUNAS';
    return null;
  }

  /// Status pembayaran di DB → `DP` | `LUNAS` (bukan CLAIM).
  static String normalizePayStatus(String? raw) {
    final s = (raw ?? '').trim().toUpperCase();
    if (s == 'DP') return 'DP';
    return 'LUNAS';
  }
}

/// QR internal toko — hanya buka detail transaksi (bukan aksi DP/garansi/klaim).
class ObrTxn {
  ObrTxn._();

  static const prefix = 'OBRTXN';
  static const version = 'v1';

  static String encode(String noInvoice) {
    final n = _clean(noInvoice);
    if (n.isEmpty) return '';
    return '$prefix|$version|$n';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static String? parse(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 3) return null;
    final no = parts[2].trim();
    return no.isEmpty ? null : no;
  }
}

// -----------------------------------------------------------------------------
// Delivery / Request order (stock receive)
// -----------------------------------------------------------------------------

class ObrLogisticsData {
  const ObrLogisticsData({
    required this.kind,
    required this.resi,
    this.tujuan,
  });

  /// `DO` or `RO`
  final String kind;
  final String resi;
  final String? tujuan;
}

class ObrDo {
  ObrDo._();

  static const prefix = 'OBRDO';
  static const version = 'v1';

  static String encode({required String resi, String? tujuan}) {
    final r = _clean(resi);
    if (r.isEmpty) return '';
    final t = _clean(tujuan);
    if (t.isEmpty) return '$prefix|$version|$r';
    return '$prefix|$version|$r|$t';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static ObrLogisticsData? parse(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 3) return null;
    final resi = parts[2].trim();
    if (resi.isEmpty) return null;
    final tujuan = parts.length >= 4 ? parts[3].trim() : '';
    return ObrLogisticsData(
      kind: 'DO',
      resi: resi,
      tujuan: tujuan.isEmpty ? null : tujuan,
    );
  }
}

class ObrRo {
  ObrRo._();

  static const prefix = 'OBRRO';
  static const version = 'v1';

  static String encode({required String resi, String? tujuan}) {
    final r = _clean(resi);
    if (r.isEmpty) return '';
    final t = _clean(tujuan);
    if (t.isEmpty) return '$prefix|$version|$r';
    return '$prefix|$version|$r|$t';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static ObrLogisticsData? parse(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 3) return null;
    final resi = parts[2].trim();
    if (resi.isEmpty) return null;
    final tujuan = parts.length >= 4 ? parts[3].trim() : '';
    return ObrLogisticsData(
      kind: 'RO',
      resi: resi,
      tujuan: tujuan.isEmpty ? null : tujuan,
    );
  }
}

/// Parse either DO or RO logistics payload.
ObrLogisticsData? parseObrLogistics(String? raw) =>
    ObrDo.parse(raw) ?? ObrRo.parse(raw);

// -----------------------------------------------------------------------------
// POS customer fill
// -----------------------------------------------------------------------------

class ObrCustomerData {
  const ObrCustomerData({
    required this.nama,
    this.phone,
    this.email,
  });

  final String nama;
  final String? phone;
  final String? email;
}

class ObrCustomer {
  ObrCustomer._();

  static const prefix = 'OBRCUS';
  static const version = 'v1';

  static String encode({
    required String nama,
    String? phone,
    String? email,
  }) {
    final n = _clean(nama);
    if (n.isEmpty) return '';
    final p = _clean(phone);
    final e = _clean(email);
    return '$prefix|$version|$n|$p|$e';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static ObrCustomerData? parse(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 3) return null;
    final nama = parts[2].trim();
    if (nama.isEmpty) return null;
    final phone = parts.length >= 4 ? parts[3].trim() : '';
    final email = parts.length >= 5 ? parts[4].trim() : '';
    return ObrCustomerData(
      nama: nama,
      phone: phone.isEmpty ? null : phone,
      email: email.isEmpty ? null : email,
    );
  }
}

List<String>? _parts(String? raw, String prefix) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parts = s.split('|');
  if (parts.length < 3) return null;
  if (parts[0] != prefix || parts[1] != 'v1') return null;
  return parts;
}
