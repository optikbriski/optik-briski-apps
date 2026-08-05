// Unified Optik B. Riski QR / SKU payloads (pipe-separated, one scanner).
//
// OBRPROD|v1|<sku>|<product_id>       → product_code.dart
// OBRATT|v1|<toko_id>|<token>         → qr_route.dart AttendanceQrPayload
// OBRINV|v1|<no>|<DP|LUNAS|CLAIM>|<token>|<ONLINE|OFFLINE>
//   → QR PELANGGAN (sekali pakai per fase); channel opsional, default OFFLINE
// OBRTXN|v1|<no_invoice>|<ONLINE|OFFLINE>   → QR TOKO (lihat detail saja)
// OBRPREP|v1|<resi>|<tujuan>   → klaim tim preparing (QUEUED → PREPARING)
// OBRDO|v1|<resi>|<tujuan>     → QR jalan (driver → TRANSIT, cabang → SUCCESS)
// OBRRO|v1|<resi>|<tujuan>
// OBRCUS|v1|<nama>|<phone>|<email>
// OBRKARY|v1|<karyawan_id>|<nama>|<toko_id>
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
    this.channel = ObrSaleChannel.offline,
  });

  final String noInvoice;
  /// `DP` | `LUNAS` | `CLAIM` pada QR pelanggan.
  final String? phase;
  /// Token sekali pakai (wajib untuk aksi lifecycle).
  final String? token;
  /// True hanya untuk QR pelanggan bertoken (`OBRINV|…|DP/LUNAS/CLAIM|<token>`).
  final bool customerLifecycle;
  /// `online` (APK Member) | `offline` (beli di toko). Default offline (QR lama).
  final String channel;

  /// Alias kompatibilitas.
  String? get paymentStatus => phase;

  bool get isOnline => channel == ObrSaleChannel.online;
}

/// Channel belanja di payload QR invoice.
class ObrSaleChannel {
  ObrSaleChannel._();

  static const online = 'online';
  static const offline = 'offline';

  /// Normalisasi field QR → `online` | `offline` (default offline).
  static String normalize(String? raw) {
    final s = (raw ?? '').trim().toUpperCase();
    if (s == 'ONLINE' || s == 'MEMBER' || s == 'MEMBER_ONLINE' || s == 'APK') {
      return online;
    }
    return offline;
  }

  /// Dari kolom `sales.channel` → nilai QR.
  static String fromSaleChannel(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'member_online' || s == 'online' || s == 'member') {
      return online;
    }
    return offline;
  }

  /// Encode ke field payload (`ONLINE` | `OFFLINE`).
  static String encodeField(String? channel) =>
      normalize(channel) == online ? 'ONLINE' : 'OFFLINE';
}

class ObrInvoice {
  ObrInvoice._();

  static const prefix = 'OBRINV';
  static const version = 'v1';

  /// QR pelanggan: `OBRINV|v1|<no>|<fase>|<token>|<ONLINE|OFFLINE>`.
  static String encodeCustomer(
    String noInvoice, {
    required String paymentStatus,
    required String token,
    String channel = ObrSaleChannel.offline,
  }) {
    final n = _clean(noInvoice);
    final st = normalizePhase(paymentStatus);
    final t = _clean(token).replaceAll(' ', '');
    if (n.isEmpty || st == null || t.length < 8) return '';
    final ch = ObrSaleChannel.encodeField(channel);
    return '$prefix|$version|$n|$st|$t|$ch';
  }

  @Deprecated('Gunakan encodeCustomer(+token) untuk QR pelanggan')
  static String encode(
    String noInvoice, {
    String? paymentStatus,
    String? token,
    String channel = ObrSaleChannel.offline,
  }) {
    final st = normalizePhase(paymentStatus);
    final t = (token ?? '').trim();
    if (st != null && t.length >= 8) {
      return encodeCustomer(
        noInvoice,
        paymentStatus: st,
        token: t,
        channel: channel,
      );
    }
    return ObrTxn.encode(noInvoice, channel: channel);
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
    // Field channel di akhir; QR lama tanpa field → offline.
    final channel = parts.length >= 6
        ? ObrSaleChannel.normalize(parts[5])
        : ObrSaleChannel.offline;
    return ObrInvoiceData(
      noInvoice: no,
      phase: st,
      token: hasToken ? token : null,
      // Legacy tanpa token: dikenali sebagai invoice, tapi BUKAN lifecycle aktif.
      customerLifecycle:
          hasToken && (st == 'DP' || st == 'LUNAS' || st == 'CLAIM'),
      channel: channel,
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

class ObrTxnData {
  const ObrTxnData({
    required this.noInvoice,
    this.channel = ObrSaleChannel.offline,
  });

  final String noInvoice;
  final String channel;

  bool get isOnline => channel == ObrSaleChannel.online;
}

/// QR internal toko — hanya buka detail transaksi (bukan aksi DP/garansi/klaim).
class ObrTxn {
  ObrTxn._();

  static const prefix = 'OBRTXN';
  static const version = 'v1';

  /// `OBRTXN|v1|<no>` atau `OBRTXN|v1|<no>|<ONLINE|OFFLINE>`.
  static String encode(
    String noInvoice, {
    String channel = ObrSaleChannel.offline,
  }) {
    final n = _clean(noInvoice);
    if (n.isEmpty) return '';
    final ch = ObrSaleChannel.encodeField(channel);
    return '$prefix|$version|$n|$ch';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  /// No invoice saja (kompatibel pemanggil lama).
  static String? parse(String? raw) => parseData(raw)?.noInvoice;

  static ObrTxnData? parseData(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 3) return null;
    final no = parts[2].trim();
    if (no.isEmpty) return null;
    final channel = parts.length >= 4
        ? ObrSaleChannel.normalize(parts[3])
        : ObrSaleChannel.offline;
    return ObrTxnData(noInvoice: no, channel: channel);
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

  /// `DO`, `RO`, or `PREP`
  final String kind;
  final String resi;
  final String? tujuan;
}

/// QR untuk tim preparing: scan → status PREPARING + buka daftar siapkan.
class ObrPrep {
  ObrPrep._();

  static const prefix = 'OBRPREP';
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
      kind: 'PREP',
      resi: resi,
      tujuan: tujuan.isEmpty ? null : tujuan,
    );
  }
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

/// Parse DO / RO / PREP logistics payload.
ObrLogisticsData? parseObrLogistics(String? raw) =>
    ObrPrep.parse(raw) ?? ObrDo.parse(raw) ?? ObrRo.parse(raw);

/// Parse travel QR only (driver / cabang) — bukan klaim preparing.
ObrLogisticsData? parseObrTravel(String? raw) =>
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

// -----------------------------------------------------------------------------
// Karyawan identity (verifikasi actor login Admin / revisi stok)
// -----------------------------------------------------------------------------

class ObrKaryawanData {
  const ObrKaryawanData({
    required this.karyawanId,
    required this.nama,
    this.tokoId,
  });

  final String karyawanId;
  final String nama;
  final String? tokoId;
}

class ObrKaryawan {
  ObrKaryawan._();

  static const prefix = 'OBRKARY';
  static const version = 'v1';

  static String encode({
    required String karyawanId,
    required String nama,
    String? tokoId,
  }) {
    final id = _clean(karyawanId).replaceAll(' ', '');
    final n = _clean(nama);
    if (id.isEmpty || n.isEmpty) return '';
    final t = _clean(tokoId);
    return '$prefix|$version|$id|$n|$t';
  }

  static bool looksLike(String? raw) => parse(raw) != null;

  static ObrKaryawanData? parse(String? raw) {
    final parts = _parts(raw, prefix);
    if (parts == null || parts.length < 4) return null;
    final id = parts[2].trim();
    final nama = parts[3].trim();
    if (id.isEmpty || nama.isEmpty) return null;
    final toko = parts.length >= 5 ? parts[4].trim() : '';
    return ObrKaryawanData(
      karyawanId: id,
      nama: nama,
      tokoId: toko.isEmpty ? null : toko,
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
