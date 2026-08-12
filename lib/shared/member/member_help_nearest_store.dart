import 'dart:math' as math;

/// Pure haversine distance in meters (for unit tests + GPS ranking).
double memberHelpHaversineMeters(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadiusM = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

double _rad(double deg) => deg * math.pi / 180.0;

/// True when [raw] looks like a dialable store phone (not empty / placeholder).
bool memberHelpHasValidStorePhone(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty || t == '-') return false;
  final digits = t.replaceAll(RegExp(r'[^\d]'), '');
  return digits.length >= 8;
}

/// Picks the nearest store that has coordinates + a valid phone.
///
/// Returns null if none qualify. Does not mutate [stores].
Map<String, dynamic>? pickNearestStoreWithPhone({
  required double userLat,
  required double userLng,
  required List<Map<String, dynamic>> stores,
  double Function(double lat1, double lng1, double lat2, double lng2)?
      distanceMeters,
}) {
  final distFn = distanceMeters ?? memberHelpHaversineMeters;
  Map<String, dynamic>? best;
  var bestM = double.infinity;
  for (final s in stores) {
    if (!memberHelpHasValidStorePhone(s['phone']?.toString())) continue;
    final slat = (s['latitude'] as num?)?.toDouble();
    final slng = (s['longitude'] as num?)?.toDouble();
    if (slat == null || slng == null) continue;
    final d = distFn(userLat, userLng, slat, slng);
    if (d < bestM) {
      bestM = d;
      best = s;
    }
  }
  return best;
}

/// One ranked text match against store directory fields.
class MemberHelpStoreTextMatch {
  const MemberHelpStoreTextMatch({
    required this.store,
    required this.score,
  });

  final Map<String, dynamic> store;
  final int score;

  String get tokoId => (store['toko_id'] ?? '').toString().trim();
  String get shopName => (store['shop_name'] ?? '').toString().trim();
}

String _memberHelpNormText(String? raw) {
  return (raw ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _memberHelpTokens(String normalized) {
  if (normalized.isEmpty) return const [];
  return normalized
      .split(' ')
      .where((t) => t.length >= 2)
      .toList(growable: false);
}

/// Score how well [query] matches [store] (toko_id / shop_name / address /
/// optional city|kota|area). Higher is better; 0 = no match.
int scoreStoreStatedLocationMatch(
  String query,
  Map<String, dynamic> store,
) {
  final q = _memberHelpNormText(query);
  if (q.isEmpty) return 0;

  final id = _memberHelpNormText(store['toko_id']?.toString());
  final name = _memberHelpNormText(store['shop_name']?.toString());
  final addr = _memberHelpNormText(store['address']?.toString());
  final city = _memberHelpNormText(
    (store['city'] ?? store['kota'] ?? store['area'] ?? '').toString(),
  );
  final haystack = '$id $name $addr $city'.trim();
  if (haystack.isEmpty) return 0;

  // Exact toko_id always wins over city/address phrase stacking.
  if (id.isNotEmpty && id == q) return 2000;

  var score = 0;

  // Exact / contains on primary fields (full query phrase).
  if (id.isNotEmpty && (id.contains(q) || q.contains(id))) {
    score += 500;
  }
  if (name.isNotEmpty && name.contains(q)) score += 400;
  if (city.isNotEmpty && city.contains(q)) score += 380;
  if (addr.isNotEmpty && addr.contains(q)) score += 350;
  if (haystack.contains(q) && score == 0) score += 200;

  // Token overlap (e.g. "cikarang selatan" vs address with "cikarang").
  final qTokens = _memberHelpTokens(q);
  if (qTokens.isEmpty) return score;

  var hit = 0;
  for (final t in qTokens) {
    if (id.contains(t)) {
      hit++;
      score += 80;
    } else if (city.contains(t)) {
      hit++;
      score += 70;
    } else if (name.contains(t)) {
      hit++;
      score += 60;
    } else if (addr.contains(t)) {
      hit++;
      score += 50;
    }
  }
  if (hit == qTokens.length && qTokens.length > 1) {
    score += 40; // all tokens covered
  }
  if (hit == 0 && score == 0) return 0;
  return score;
}

/// Rank stores by stated-location text match. Best first; skips score 0.
///
/// When [requirePhone] is true, only dialable stores are returned.
List<MemberHelpStoreTextMatch> matchStoresByStatedLocation(
  String query,
  List<Map<String, dynamic>> stores, {
  int maxResults = 5,
  bool requirePhone = true,
}) {
  final ranked = <MemberHelpStoreTextMatch>[];
  for (final s in stores) {
    if (requirePhone && !memberHelpHasValidStorePhone(s['phone']?.toString())) {
      continue;
    }
    final score = scoreStoreStatedLocationMatch(query, s);
    if (score <= 0) continue;
    ranked.add(MemberHelpStoreTextMatch(store: s, score: score));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.tokoId.compareTo(b.tokoId);
  });
  if (ranked.length <= maxResults) return ranked;
  return ranked.sublist(0, maxResults);
}

/// Clear single pick when one match dominates (or only one exists).
MemberHelpStoreTextMatch? pickBestStatedLocationMatch(
  List<MemberHelpStoreTextMatch> matches, {
  int minScore = 50,
  int dominateGap = 80,
}) {
  if (matches.isEmpty) return null;
  final best = matches.first;
  if (best.score < minScore) return null;
  if (matches.length == 1) return best;
  final second = matches[1];
  if (best.score >= second.score + dominateGap) return best;
  // Same-ish scores → let UI show chips.
  return null;
}

/// First [limit] stores that have a valid WhatsApp/phone (directory order).
List<Map<String, dynamic>> topStoresWithPhone(
  List<Map<String, dynamic>> stores, {
  int limit = 4,
}) {
  final out = <Map<String, dynamic>>[];
  for (final s in stores) {
    if (!memberHelpHasValidStorePhone(s['phone']?.toString())) continue;
    out.add(s);
    if (out.length >= limit) break;
  }
  return out;
}

/// How the help-bot WA number was chosen (client-side).
enum MemberHelpWaSource {
  /// Store picked on the OBRA gate (primary path).
  selectedToko,
  nearestGps,
  statedLocation,
  preferredToko,
  adminFallback,
}

/// Find a directory row by [tokoId] (case-insensitive). Null if missing/empty.
Map<String, dynamic>? findStoreByTokoId(
  String? tokoId,
  List<Map<String, dynamic>> stores,
) {
  final want = (tokoId ?? '').trim().toUpperCase();
  if (want.isEmpty) return null;
  for (final s in stores) {
    final id = (s['toko_id'] ?? '').toString().trim().toUpperCase();
    if (id == want) return s;
  }
  return null;
}

/// Filler stripped before treating leftover tokens as an explicit cabang name.
///
/// Stock / lab / WA words must not override the OBRA-selected store.
const List<String> kMemberHelpNamedTokoDropPhrases = [
  'cek stok',
  'cek stock',
  'stok frame',
  'stok lensa',
  'stock frame',
  'stock lensa',
  'ada stok',
  'ada stock',
  'sisa stok',
  'sisa stock',
  'stok cabang',
  'stok toko',
  'stock cabang',
  'stock toko',
  'stok tersedia',
  'stock tersedia',
  'berapa stok',
  'berapa stock',
  'masih ada stok',
  'masih ada stock',
  'ready stock',
  'ready stok',
  'stock ready',
  'stok ready',
  'yang ready',
  'ready apa',
  'apa yang ready',
  'frame ready',
  'ready frame',
  'lensa ready',
  'ready lensa',
  'barang ready',
  'ready barang',
  'yang tersedia',
  'barang di toko',
  'available stock',
  'availability',
  'in stock',
  'antrean lab',
  'antrian lab',
  'lab queue',
  'beban lab',
  'beban pengerjaan',
  'pengerjaan lab',
  'pengerjaan kacamata',
  'lama pengerjaan',
  'lama dikerjakan',
  'sedang dikerjakan',
  'belum dikerjakan',
  'menunggu dikerjakan',
  'berapa lama',
  'lagi full',
  'job lab',
  'optik b. riski',
  'optik b riski',
];

const Set<String> kMemberHelpNamedTokoStopwords = {
  ...kMemberHelpWaAreaStopwords,
  'stok',
  'stock',
  'cek',
  'apakah',
  'apa',
  'lihat',
  'cari',
  'berapa',
  'sisa',
  'ready',
  'available',
  'availability',
  'barang',
  'frame',
  'lensa',
  'kacamata',
  'sku',
  'produk',
  'sistem',
  'aplikasi',
  'antre',
  'antrean',
  'antrian',
  'queue',
  'rame',
  'sepi',
  'full',
  'lab',
  'pengerjaan',
  'dikerjakan',
  'menunggu',
  'sedang',
  'belum',
  'lama',
  'job',
  'beban',
  'estimasi',
  'info',
  'alamat',
  'jam',
  'buka',
  'tutup',
  'is',
  'are',
  'any',
  'have',
  'has',
  'do',
  'does',
  'you',
  'what',
  'which',
};

/// Leftover tokens after stripping stock/lab/filler — candidate cabang name.
///
/// Examples:
/// - "stock apa yang ready?" → ""
/// - "stok di Singaparna" → "singaparna"
/// - "antrean lab Wonosobo" → "wonosobo"
String memberHelpExtractNamedTokoQuery(String raw) {
  var t = _memberHelpNormText(raw);
  if (t.isEmpty) return '';

  final phrases = List<String>.from(kMemberHelpNamedTokoDropPhrases)
    ..addAll(kMemberHelpWaContactPhrases)
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final p in phrases) {
    t = t.replaceAll(p, ' ');
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';

  final kept = t
      .split(' ')
      .where(
        (tok) =>
            tok.length >= 2 && !kMemberHelpNamedTokoStopwords.contains(tok),
      )
      .toList(growable: false);
  return kept.join(' ');
}

/// Resolve store for stock / lab queue / store-info in an OBRA chat session.
///
/// When [selectedTokoId] is set, it is kept for the whole session unless
/// [message] **explicitly names** a different cabang (clear directory match
/// after stripping stock/lab filler). Words like "stock", "ready", "frame"
/// never change toko. Does **not** fall back to the first directory row while
/// a selected id is present.
Map<String, dynamic>? resolveMemberHelpSessionStore({
  required List<Map<String, dynamic>> stores,
  String? selectedTokoId,
  String? message,
}) {
  final selected = (selectedTokoId ?? '').trim().toUpperCase();
  final selectedStore = findStoreByTokoId(selected, stores);

  final hint = memberHelpExtractNamedTokoQuery(message ?? '');
  Map<String, dynamic>? named;
  if (hint.isNotEmpty) {
    final matches = matchStoresByStatedLocation(
      hint,
      stores,
      requirePhone: false,
    );
    // Higher bar than WA chips — only clear cabang names override selection.
    final best = pickBestStatedLocationMatch(matches, minScore: 70);
    if (best != null) named = best.store;
  }

  if (selectedStore != null) {
    if (named != null) {
      final namedId =
          (named['toko_id'] ?? '').toString().trim().toUpperCase();
      if (namedId.isNotEmpty && namedId != selected) {
        return named;
      }
    }
    return selectedStore;
  }

  // No valid picker selection — named cabang only (never silent first-store).
  return named;
}

/// Selected-store WA when the row has a dialable phone; else null (GPS / ask).
Map<String, dynamic>? pickSelectedStoreWithPhone({
  required String? selectedTokoId,
  required List<Map<String, dynamic>> stores,
}) {
  final store = findStoreByTokoId(selectedTokoId, stores);
  if (store == null) return null;
  if (!memberHelpHasValidStorePhone(store['phone']?.toString())) return null;
  return store;
}

class MemberHelpWaTarget {
  const MemberHelpWaTarget({
    required this.waDigits,
    required this.source,
    this.tokoId,
    this.shopName,
    this.locationUnavailable = false,
  });

  final String waDigits;
  final MemberHelpWaSource source;
  final String? tokoId;
  final String? shopName;

  /// True when GPS was attempted but denied/unavailable/timed out.
  final bool locationUnavailable;
}

/// Result of preparing WA escalation (GPS soft attempt).
enum MemberHelpWaPrepareKind {
  /// GPS (or forced toko) resolved — open WA now.
  ready,

  /// GPS failed — ask user for city/area in chat before opening WA.
  askLocation,
}

class MemberHelpWaPrepareResult {
  const MemberHelpWaPrepareResult.ready(this.target)
      : kind = MemberHelpWaPrepareKind.ready;

  const MemberHelpWaPrepareResult.askLocation()
      : kind = MemberHelpWaPrepareKind.askLocation,
        target = null;

  final MemberHelpWaPrepareKind kind;
  final MemberHelpWaTarget? target;
}

/// Outcome of matching a typed area to the store directory.
class MemberHelpStatedLocationResult {
  const MemberHelpStatedLocationResult({
    this.target,
    this.candidates = const [],
    this.noTextMatch = false,
  });

  /// Clear single match — open WA.
  final MemberHelpWaTarget? target;

  /// Multiple matches or fallback chips to tap.
  final List<Map<String, dynamic>> candidates;

  /// No directory text hit (candidates may still list top phone stores).
  final bool noTextMatch;
}

/// WA / contact filler phrases stripped before area matching (longest first).
const List<String> kMemberHelpWaContactPhrases = [
  'nomor whatsapp',
  'nomer whatsapp',
  'customer service',
  'contact branch',
  'hubungi cabang',
  'hubungi toko',
  'kontak cabang',
  'kontak wa',
  'contact wa',
  'hubungi cs',
  'nomor cs',
  'admin wa',
  'chat cabang',
  'chat toko',
  'chat wa',
  'wa cabang',
  'wa toko',
  'nomor wa',
  'nomer wa',
  'no. wa',
  'no.wa',
  'bagi nomor',
  'minta nomor',
  'kasih nomor',
  'share nomor',
  'bagi wa',
  'minta wa',
  'kasih wa',
  'whats app',
  'whatsapp',
  'no wa',
];

/// Tokens that are never treated as city / branch area hints.
const Set<String> kMemberHelpWaAreaStopwords = {
  'dong',
  'ya',
  'yuk',
  'please',
  'tolong',
  'bang',
  'kak',
  'bro',
  'sis',
  'minta',
  'bagi',
  'kasih',
  'share',
  'kirim',
  'nomor',
  'nomer',
  'nomornya',
  'nomernya',
  'no',
  'hp',
  'telepon',
  'telp',
  'wa',
  'wanya',
  'whatsapp',
  'whats',
  'app',
  'chat',
  'hubungi',
  'kontak',
  'contact',
  'customer',
  'service',
  'cs',
  'admin',
  'cabang',
  'toko',
  'branch',
  'store',
  'outlet',
  'ke',
  'di',
  'sama',
  'dengan',
  'yang',
  'untuk',
  'nya',
  'the',
  'a',
  'an',
  'to',
  'me',
  'my',
  'of',
  'and',
  'atau',
  'lah',
  'sih',
  'aja',
  'ajah',
  'nih',
  'deh',
};

/// Strip WA-contact filler from [raw]; leftover tokens are area/branch hints.
///
/// Examples:
/// - "bagi wa dong" → ""
/// - "bagi wa cabang banyuwangi" → "banyuwangi"
/// - "wa cikarang" → "cikarang"
String memberHelpExtractAreaQuery(String raw) {
  var t = _memberHelpNormText(raw);
  if (t.isEmpty) return '';

  final phrases = List<String>.from(kMemberHelpWaContactPhrases)
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final p in phrases) {
    t = t.replaceAll(p, ' ');
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';

  final kept = t
      .split(' ')
      .where((tok) => tok.length >= 2 && !kMemberHelpWaAreaStopwords.contains(tok))
      .toList(growable: false);
  return kept.join(' ');
}

/// True when free-text WA request also names a city / cabang (overrides GPS).
bool memberHelpHasExplicitAreaHint(String raw) {
  return memberHelpExtractAreaQuery(raw).isNotEmpty;
}

/// XOR: auto-resolving contact-WA must not also show the escalate CTA bubble.
bool memberHelpShouldShowWaEscalateCta({
  required bool escalateWaFlag,
  required bool autoResolvingContactWa,
}) {
  if (!escalateWaFlag) return false;
  if (autoResolvingContactWa) return false;
  return true;
}
