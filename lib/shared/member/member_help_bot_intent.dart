// Pure helpers for Member help-bot routing / escalate rules (no Flutter deps).
// Used by client chip/fallback path and unit tests.

enum MemberHelpChipId {
  orderStatus,
  pointsGrade,
  storeInfo,
  labQueue,
  stok,
  careWarranty,
  contactWa,
}

enum MemberHelpIntent {
  orderStatus,
  pointsGrade,
  storeInfo,
  labQueue,
  stok,
  careWarranty,
  contactWa,
  faqGeneral,
  escalateLive,
  unknown,
}

/// Max SKUs fetched from [search_member_toko_stock] for chat product lists.
const int kMemberHelpStockFetchLimit = 30;

/// First page of tappable stock products under an OBRA bubble.
const int kMemberHelpStockUiInitial = 15;

/// Extra rows revealed by “tampilkan lebih”.
const int kMemberHelpStockUiPage = 15;

class MemberHelpBotReply {
  const MemberHelpBotReply({
    required this.reply,
    this.escalateWa = false,
    this.intent,
    this.suggestedChips = const [],
    this.errorCode,
    this.stockProducts = const [],
    this.stockTotalInStock = 0,
  });

  final String reply;
  final bool escalateWa;
  final MemberHelpIntent? intent;
  final List<MemberHelpChipId> suggestedChips;

  /// Edge `error_code` when Gemini fell back (e.g. gemini_rate_limited).
  final String? errorCode;

  /// Tappable SKUs for stock replies (client UI). Prefer available_qty > 0.
  final List<MemberHelpStockMatch> stockProducts;

  /// Branch-wide SKU count with available qty > 0 (may exceed [stockProducts]).
  final int stockTotalInStock;

  bool get isSoftGeminiFailure {
    final c = (errorCode ?? '').trim();
    return c == 'gemini_unavailable' ||
        c == 'gemini_rate_limited' ||
        c == 'client_rate_limited';
  }

  Map<String, dynamic> toJson() => {
        'reply': reply,
        'escalate_wa': escalateWa,
        if (intent != null) 'intent': intent!.name,
        if (suggestedChips.isNotEmpty)
          'suggested_chips':
              suggestedChips.map((e) => e.name).toList(growable: false),
        if (errorCode != null && errorCode!.isNotEmpty) 'error_code': errorCode,
        if (stockProducts.isNotEmpty)
          'stock_products': stockProducts
              .map(
                (m) => {
                  'sku': m.sku,
                  'nama': m.nama,
                  if (m.kategori != null) 'kategori': m.kategori,
                  if (m.warna != null) 'warna': m.warna,
                  'available_qty': m.availableQty,
                  'in_stock': m.inStock,
                },
              )
              .toList(growable: false),
        if (stockTotalInStock > 0) 'stock_total_in_stock': stockTotalInStock,
      };
}

/// Aggregates from [get_toko_lab_queue_counts] (no PII).
class MemberHelpLabQueueCounts {
  const MemberHelpLabQueueCounts({
    required this.tokoId,
    required this.waiting,
    required this.inProgress,
    required this.ready,
    this.ok = true,
  });

  final String tokoId;
  final int waiting;
  final int inProgress;
  final int ready;
  final bool ok;

  factory MemberHelpLabQueueCounts.fromJson(Map<String, dynamic> raw) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return MemberHelpLabQueueCounts(
      tokoId: (raw['toko_id'] ?? '').toString().trim().toUpperCase(),
      waiting: asInt(raw['waiting']),
      inProgress: asInt(raw['in_progress']),
      ready: asInt(raw['ready']),
      ok: raw['ok'] != false,
    );
  }
}

/// One SKU row from [search_member_toko_stock] (no PII / no modal).
class MemberHelpStockMatch {
  const MemberHelpStockMatch({
    required this.sku,
    required this.nama,
    this.kategori,
    this.warna,
    required this.availableQty,
    required this.inStock,
  });

  final String sku;
  final String nama;
  final String? kategori;
  final String? warna;
  final int availableQty;
  final bool inStock;

  factory MemberHelpStockMatch.fromJson(Map<String, dynamic> raw) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final qty = memberHelpClampNonNegQty(asInt(raw['available_qty']));
    return MemberHelpStockMatch(
      sku: (raw['sku'] ?? '').toString().trim(),
      nama: (raw['nama'] ?? '').toString().trim(),
      kategori: () {
        final s = (raw['kategori'] ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }(),
      warna: () {
        final s = (raw['warna'] ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }(),
      availableQty: qty,
      inStock: raw['in_stock'] == true || qty > 0,
    );
  }
}

/// Display/parse guard: available qty must never show as negative nonsense.
int memberHelpClampNonNegQty(int value) => value < 0 ? 0 : value;

class MemberHelpStockCategory {
  const MemberHelpStockCategory({
    required this.kategori,
    required this.skusInStock,
    required this.totalAvailable,
  });

  final String kategori;
  final int skusInStock;
  final int totalAvailable;

  factory MemberHelpStockCategory.fromJson(Map<String, dynamic> raw) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return MemberHelpStockCategory(
      kategori: (raw['kategori'] ?? 'Lainnya').toString().trim(),
      skusInStock: memberHelpClampNonNegQty(asInt(raw['skus_in_stock'])),
      totalAvailable: memberHelpClampNonNegQty(asInt(raw['total_available'])),
    );
  }
}

/// Result from [search_member_toko_stock] (no PII).
class MemberHelpStockResult {
  const MemberHelpStockResult({
    required this.tokoId,
    required this.mode,
    this.query,
    required this.skusInStock,
    this.byKategori = const [],
    this.matches = const [],
    this.ok = true,
    this.error,
  });

  final String tokoId;
  final String mode; // summary | search
  final String? query;
  final int skusInStock;
  final List<MemberHelpStockCategory> byKategori;
  final List<MemberHelpStockMatch> matches;
  final bool ok;
  final String? error;

  factory MemberHelpStockResult.fromJson(Map<String, dynamic> raw) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    List<Map<String, dynamic>> asMapList(Object? v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }

    final q = (raw['query'] ?? '').toString().trim();
    return MemberHelpStockResult(
      tokoId: (raw['toko_id'] ?? '').toString().trim().toUpperCase(),
      mode: (raw['mode'] ?? 'summary').toString().trim().toLowerCase(),
      query: q.isEmpty ? null : q,
      skusInStock: asInt(raw['skus_in_stock']),
      byKategori: asMapList(raw['by_kategori'])
          .map(MemberHelpStockCategory.fromJson)
          .toList(growable: false),
      matches: asMapList(raw['matches'])
          .map(MemberHelpStockMatch.fromJson)
          .toList(growable: false),
      ok: raw['ok'] != false,
      error: () {
        final e = (raw['error'] ?? '').toString().trim();
        return e.isEmpty ? null : e;
      }(),
    );
  }
}

/// True lobby / physical-shelf confirm / nego / physical / today's hours — WA.
/// System stock keywords are handled by [memberHelpNeedsStok].
bool memberHelpNeedsLiveEscalation(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return false;

  const phrases = <String>[
    'nego',
    'negoisasi',
    'tawar',
    'bargain',
    // Physical shelf confirmation — not the same as system available_qty.
    'stok rak',
    'stok di rak',
    'ada di rak',
    'di rak sekarang',
    'fisik',
    'retak',
    'patah',
    'baret',
    'scratch',
    'komplain',
    'complaint',
    'keluhan',
    'rusak',
    'hari ini buka',
    'masih buka',
    'masih tutup',
    'jam berapa tutup',
    'jam tutup hari ini',
    'berapa orang',
    'orang di toko',
    'orang di lobby',
    'antrean lobby',
    'antrian lobby',
    'lobby queue',
  ];
  for (final p in phrases) {
    if (t.contains(p)) return true;
  }
  return false;
}

/// Production / lab / RO pipeline load (invoice-based), not lobby foot traffic.
bool memberHelpNeedsLabQueue(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return false;

  // Multi-word / longer phrases — substring OK.
  const phrases = <String>[
    'lagi full',
    'berapa lama',
    'lama pengerjaan',
    'lama dikerjakan',
    'beban lab',
    'beban pengerjaan',
    'antrean lab',
    'antrian lab',
    'lab queue',
    'pengerjaan lab',
    'pengerjaan kacamata',
    'sedang dikerjakan',
    'belum dikerjakan',
    'menunggu dikerjakan',
    'job lab',
    'antrian',
    'antrean',
  ];
  for (final p in phrases) {
    if (t.contains(p)) return true;
  }
  // Short tokens — word boundary only ("rame" must not match "frame"/"rayban").
  const bounded = <String>['antre', 'queue', 'rame', 'sepi'];
  for (final w in bounded) {
    if (RegExp('(^|[^a-z])$w([^a-z]|\$)').hasMatch(t)) return true;
  }
  return false;
}

/// System stock / availability from catalog+branch qty (not physical shelf audit).
bool memberHelpNeedsStok(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return false;

  const phrases = <String>[
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
    // Colloquial "what's ready / available" (system stock, not shelf audit).
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
  ];
  for (final p in phrases) {
    if (t.contains(p)) return true;
  }
  // Standalone "stok" / "stock" (avoid matching inside other words).
  if (RegExp(r'(^|[^a-z])stok([^a-z]|$)').hasMatch(t)) return true;
  if (RegExp(r'(^|[^a-z])stock([^a-z]|$)').hasMatch(t)) return true;
  // "ada/ready/tersedia + frame|lensa|…" → system availability (not WA).
  final hasProduct = RegExp(
    r'(^|[^a-z])(frame|lensa|kacamata|barang|sku|produk)([^a-z]|$)',
  ).hasMatch(t);
  final hasAvail = RegExp(
    r'(^|[^a-z])(ready|tersedia|available|sisa|ada)([^a-z]|$)',
  ).hasMatch(t);
  if (hasProduct && hasAvail) return true;
  return false;
}

/// Strip stock/filler tokens so remaining text can be used as product search.
///
/// [stripNamedToko] — leftover cabang tokens (e.g. "singaparna" from
/// "stok di Singaparna") must not become a product query; pass the output of
/// [memberHelpExtractNamedTokoQuery] so those tokens are removed too.
String memberHelpExtractStockQuery(String raw, {String? stripNamedToko}) {
  var t = raw.toLowerCase().trim();
  if (t.isEmpty) return '';

  // Longer phrases first so colloquial summary asks collapse to empty query.
  const dropPhrases = <String>[
    'cek stok',
    'cek stock',
    'stok frame',
    'stok lensa',
    'stock frame',
    'stock lensa',
    'ada stok',
    'ada stock',
    'stok ada',
    'stock ada',
    'ada apa aja',
    'apa aja',
    'ada apa',
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
    'optik b. riski',
    'optik b riski',
  ];
  for (final p in dropPhrases) {
    t = t.replaceAll(p, ' ');
  }

  const dropWords = <String>{
    'stok',
    'stock',
    'cek',
    'ada',
    'apakah',
    'apa',
    'aja',
    'ajah',
    'ajahh',
    'sih',
    'nih',
    'deh',
    'lah',
    'kah',
    'dong',
    'ya',
    'yuk',
    'tolong',
    'minta',
    'lihat',
    'cari',
    'berapa',
    'sisa',
    'ready',
    'available',
    'availability',
    'barang',
    'yang',
    'di',
    'untuk',
    'cabang',
    'toko',
    'masih',
    'tersedia',
    'sistem',
    'app',
    'aplikasi',
    'kak',
    'min',
    'bang',
    'bro',
    'sis',
    'mas',
    'mbak',
    'gak',
    'ga',
    'nggak',
    'ngga',
    'please',
    'the',
    'a',
    'an',
    'is',
    'are',
    'any',
    'have',
    'has',
    'do',
    'does',
    'you',
    'what',
  };
  final namedDrop = <String>{};
  final named = (stripNamedToko ?? '').toLowerCase().trim();
  if (named.isNotEmpty) {
    for (final w in named.split(RegExp(r'\s+'))) {
      if (w.length >= 2) namedDrop.add(w);
    }
  }
  final parts = t
      .replaceAll(RegExp(r'[^\w\s\-+/]'), ' ')
      .split(RegExp(r'\s+'))
      .where(
        (w) =>
            w.isNotEmpty && !dropWords.contains(w) && !namedDrop.contains(w),
      )
      .toList(growable: false);
  return parts.join(' ').trim();
}

/// Free-text asking for branch WA / contact — escalate to nearest store, never
/// dump a directory of phone numbers.
bool memberHelpWantsWhatsAppContact(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return false;

  const phrases = <String>[
    'nomor wa',
    'nomer wa',
    'no wa',
    'no. wa',
    'no.wa',
    'nomor whatsapp',
    'nomer whatsapp',
    'whatsapp',
    'whats app',
    'bagi nomor',
    'minta nomor',
    'bagi wa',
    'minta wa',
    'kasih nomor',
    'kasih wa',
    'share nomor',
    'hubungi cabang',
    'hubungi toko',
    'chat toko',
    'chat cabang',
    'chat wa',
    'wa toko',
    'wa cabang',
    'kontak wa',
    'kontak cabang',
    'contact wa',
    'contact branch',
    'customer service',
    'hubungi cs',
    'nomor cs',
    'admin wa',
  ];
  for (final p in phrases) {
    if (t.contains(p)) return true;
  }
  // Standalone "cs" / "admin" as contact intent (avoid matching inside words).
  if (RegExp(r'(^|[^a-z])cs([^a-z]|$)').hasMatch(t)) return true;
  if (RegExp(r'(^|[^a-z])admin([^a-z]|$)').hasMatch(t)) return true;
  return false;
}

bool _memberHelpLooksLikeOwnOrder(String t) {
  const keys = <String>[
    'status pesanan',
    'cek pesanan',
    'pesanan saya',
    'order status',
    'invoice',
    'nota',
    'lacak',
    'tracking',
  ];
  return keys.any(t.contains);
}

MemberHelpIntent memberHelpDetectIntent(String raw) {
  final t = raw.toLowerCase().trim();
  if (t.isEmpty) return MemberHelpIntent.unknown;
  // Lobby / physical shelf / nego / physical / today's hours → WA (before stok).
  if (memberHelpNeedsLiveEscalation(t)) return MemberHelpIntent.escalateLive;
  // Before storeInfo ("cabang") so "hubungi cabang" / "bagi nomor wa" escalate.
  if (memberHelpWantsWhatsAppContact(t)) return MemberHelpIntent.contactWa;

  bool any(List<String> keys) => keys.any(t.contains);

  // Own-order phrases win over generic "berapa lama".
  if (_memberHelpLooksLikeOwnOrder(t)) {
    return MemberHelpIntent.orderStatus;
  }
  if (memberHelpNeedsLabQueue(t)) {
    return MemberHelpIntent.labQueue;
  }
  if (memberHelpNeedsStok(t)) {
    return MemberHelpIntent.stok;
  }
  if (any([
    'siap diambil',
  ])) {
    return MemberHelpIntent.orderStatus;
  }
  if (any([
    'poin',
    'point',
    'grade',
    'tier',
    'silver',
    'gold',
    'platinum',
    'diamond',
    'basic',
  ])) {
    return MemberHelpIntent.pointsGrade;
  }
  if (any([
    'jam buka',
    'jam operasional',
    'alamat',
    'cabang',
    'lokasi toko',
    'store hours',
    'address',
    'dimana toko',
    'di mana toko',
  ])) {
    return MemberHelpIntent.storeInfo;
  }
  if (any([
    'perawatan',
    'garansi',
    'membersihkan',
    'bersih',
    'warranty',
    'care',
    'lap microfiber',
    'klaim',
  ])) {
    return MemberHelpIntent.careWarranty;
  }
  return MemberHelpIntent.unknown;
}

/// Format honest production-queue reply (aggregates only).
String memberHelpFormatLabQueueReply({
  required String locale,
  required String tokoId,
  required int waiting,
  required int inProgress,
  required int ready,
  String? shopName,
}) {
  final en = locale.toLowerCase().startsWith('en');
  final tid = tokoId.trim().toUpperCase();
  final name = (shopName ?? '').trim();
  final label = name.isNotEmpty ? '$tid ($name)' : tid;

  if (en) {
    return 'Estimated lab/production load at $label from system data '
        '(invoice pipeline — not people standing in the lobby):\n'
        '• Waiting to be worked: $waiting invoice(s)\n'
        '• In progress: $inProgress invoice(s)\n'
        '• Ready for pickup: $ready invoice(s)\n\n'
        'This is the branch work queue from invoices/lab jobs, not lobby wait minutes. '
        'For physical shelf confirmation right now, negotiation, or physical complaints — WhatsApp the branch. '
        'For app/system stock by SKU or category, use the stock chip or ask “cek stok …”.';
  }
  return 'Estimasi beban pengerjaan lab di cabang $label dari data sistem '
      '(pipeline invoice — bukan jumlah orang di lobby):\n'
      '• Menunggu dikerjakan: $waiting invoice\n'
      '• Sedang dikerjakan: $inProgress invoice\n'
      '• Siap diambil: $ready invoice\n\n'
      'Ini antrean pengerjaan/lab dari invoice, bukan antrean orang di toko. '
      'Estimasi menit tunggu di lobby tidak tersedia. '
      'Untuk konfirmasi rak fisik sekarang, nego, atau keluhan fisik — WhatsApp cabang. '
      'Untuk stok sistem (SKU/kategori) pakai chip stok atau tanya “cek stok …”.';
}

String _stockDisclaimer({required bool en, bool offerWa = false}) {
  if (en) {
    final base =
        'This is app/system availability (stock − reserved), not a physical shelf audit.';
    if (!offerWa) return base;
    return '$base For a live shelf check, chat the branch on WhatsApp.';
  }
  final base =
      'Ini stok sistem aplikasi (stock − reserved), bukan audit rak fisik.';
  if (!offerWa) return base;
  return '$base Untuk cek rak langsung, chat cabang via WhatsApp.';
}

/// Pick SKUs for the tappable stock list (prefer in-stock; cap [max]).
List<MemberHelpStockMatch> memberHelpPickStockProductsForUi(
  MemberHelpStockResult result, {
  int max = kMemberHelpStockFetchLimit,
}) {
  final cap = max < 1 ? 1 : max;
  final ranked = List<MemberHelpStockMatch>.from(result.matches);
  int cmp(MemberHelpStockMatch a, MemberHelpStockMatch b) {
    final ka = (a.kategori ?? '').toLowerCase();
    final kb = (b.kategori ?? '').toLowerCase();
    final c = ka.compareTo(kb);
    if (c != 0) return c;
    return a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
  }

  final inStock = ranked
      .where(
        (m) =>
            m.sku.trim().isNotEmpty &&
            m.inStock &&
            memberHelpClampNonNegQty(m.availableQty) > 0,
      )
      .toList(growable: false)
    ..sort(cmp);
  if (inStock.isNotEmpty) {
    return inStock.take(cap).toList(growable: false);
  }
  // Search may return OOS-only matches — still expose for honesty / detail tap.
  final any = ranked.where((m) => m.sku.trim().isNotEmpty).toList(growable: false)
    ..sort(cmp);
  return any.take(cap).toList(growable: false);
}

/// Format honest system-stock reply (summary and/or SKU matches).
///
/// When [interactiveProducts] is true and matches exist, SKU bullets are omitted
/// (client renders a tappable list). Category one-liners stay for summary.
String memberHelpFormatStokReply({
  required String locale,
  required MemberHelpStockResult result,
  String? shopName,
  bool interactiveProducts = false,
}) {
  final en = locale.toLowerCase().startsWith('en');
  final tid = result.tokoId.trim().toUpperCase();
  final name = (shopName ?? '').trim();
  final label = name.isNotEmpty ? '$tid ($name)' : tid;
  final uiProducts = interactiveProducts
      ? memberHelpPickStockProductsForUi(result)
      : const <MemberHelpStockMatch>[];
  final hasUiList = uiProducts.isNotEmpty;
  final buf = StringBuffer();

  var offerWaNote = false;
  if (result.mode == 'search') {
    final q = (result.query ?? '').trim();
    if (result.matches.isEmpty) {
      offerWaNote = true;
      if (en) {
        buf.writeln(
          'No matching SKU in system stock at $label'
          '${q.isEmpty ? '' : ' for “$q”'}.',
        );
        buf.writeln(
          'Try a clearer product name/SKU, or ask the branch for a shelf check.',
        );
      } else {
        buf.writeln(
          'Tidak ketemu SKU cocok di stok sistem cabang $label'
          '${q.isEmpty ? '' : ' untuk “$q”'}.',
        );
        buf.writeln(
          'Coba nama/SKU lebih spesifik, atau tanya cabang untuk cek rak.',
        );
      }
    } else if (hasUiList) {
      if (en) {
        buf.writeln(
          'Ready / system stock at $label'
          '${q.isEmpty ? '' : ' for “$q”'} — tap a product for details:',
        );
      } else {
        buf.writeln(
          'Ready / stok sistem di $label'
          '${q.isEmpty ? '' : ' untuk “$q”'} — ketuk produk untuk detail:',
        );
      }
    } else {
      if (en) {
        buf.writeln(
          'System stock at $label'
          '${q.isEmpty ? '' : ' for “$q”'}:',
        );
      } else {
        buf.writeln(
          'Stok sistem di cabang $label'
          '${q.isEmpty ? '' : ' untuk “$q”'}:',
        );
      }
      for (final m in result.matches) {
        final kat = (m.kategori ?? '').trim();
        final warna = (m.warna ?? '').trim();
        final meta = [
          if (kat.isNotEmpty) kat,
          if (warna.isNotEmpty) warna,
        ].join(' · ');
        final avail = memberHelpClampNonNegQty(m.availableQty);
        final status = en
            ? (avail > 0 ? 'available: $avail' : 'out of stock (0)')
            : (avail > 0 ? 'tersedia: $avail' : 'habis (0)');
        final title = m.sku.isNotEmpty ? '${m.sku} — ${m.nama}' : m.nama;
        buf.writeln(
          meta.isEmpty ? '• $title — $status' : '• $title ($meta) — $status',
        );
      }
    }
  } else {
    if (en) {
      buf.writeln(
        'System stock summary at $label '
        '(${result.skusInStock} SKU(s) with available qty > 0):',
      );
    } else {
      buf.writeln(
        'Ringkasan stok sistem cabang $label '
        '(${result.skusInStock} SKU tersedia):',
      );
    }
    final cats = result.byKategori
        .where((c) {
          final skus = memberHelpClampNonNegQty(c.skusInStock);
          final tot = memberHelpClampNonNegQty(c.totalAvailable);
          return skus > 0 || tot > 0;
        })
        .toList(growable: false);
    if (cats.isEmpty || result.skusInStock <= 0) {
      offerWaNote = true;
      buf.writeln(
        en
            ? '• No sellable SKUs with available qty right now in the system.'
            : '• Belum ada SKU sellable dengan qty tersedia di sistem saat ini.',
      );
    } else {
      for (final c in cats) {
        final skus = memberHelpClampNonNegQty(c.skusInStock);
        final tot = memberHelpClampNonNegQty(c.totalAvailable);
        if (en) {
          buf.writeln(
            '• ${c.kategori}: $skus SKU in stock '
            '(total available qty ~$tot)',
          );
        } else {
          buf.writeln(
            '• ${c.kategori}: $skus SKU tersedia '
            '(total qty ~$tot)',
          );
        }
      }
    }
    if (hasUiList) {
      buf.writeln(
        en
            ? '\nProducts in stock — tap for details:'
            : '\nProduk tersedia — ketuk untuk detail:',
      );
    } else {
      buf.writeln(
        en
            ? '\nAsk with a product name/SKU (e.g. “cek stok Rayban hitam”) for SKU-level qty.'
            : '\nTanya dengan nama/SKU produk (mis. “cek stok Rayban hitam”) untuk qty per SKU.',
      );
    }
  }

  buf.writeln();
  buf.write(_stockDisclaimer(en: en, offerWa: offerWaNote));
  return buf.toString().trim();
}

/// Keyword fallback when Gemini is unavailable (local or Edge).
MemberHelpBotReply memberHelpKeywordFallback({
  required String message,
  required String locale,
}) {
  final intent = memberHelpDetectIntent(message);
  final id = locale.toLowerCase().startsWith('en');

  switch (intent) {
    case MemberHelpIntent.escalateLive:
      return MemberHelpBotReply(
        reply: id
            ? 'Live lobby info (how many people in-store), physical shelf confirmation right now, negotiation, physical complaints, or whether hours changed today isn’t readable from the app. Please ask the branch on WhatsApp. For app/system stock, ask “cek stok …” or use the stock chip. For lab/production queue, ask “antrean lab” or use the lab-queue chip.'
            : 'Info live lobby (berapa orang di toko), konfirmasi stok rak fisik sekarang, nego, keluhan fisik, atau jam buka hari ini berubah tidak bisa dibaca dari app. Silakan tanya cabang via WhatsApp. Untuk stok sistem aplikasi, tanya “cek stok …” atau pakai chip stok. Untuk beban antrean lab dari invoice, tanya “antrean lab” atau pakai chip antrean lab.',
        escalateWa: true,
        intent: intent,
        suggestedChips: const [
          MemberHelpChipId.contactWa,
          MemberHelpChipId.stok,
          MemberHelpChipId.labQueue,
          MemberHelpChipId.orderStatus,
        ],
      );
    case MemberHelpIntent.labQueue:
      return MemberHelpBotReply(
        reply: id
            ? 'Tap “Lab / work queue” for estimated production load at a branch (waiting / in progress / ready) from system invoice data — not lobby foot traffic.'
            : 'Ketuk chip “Antrean lab / pengerjaan” untuk estimasi beban pengerjaan cabang (menunggu / dikerjakan / siap diambil) dari data invoice sistem — bukan jumlah orang di lobby.',
        escalateWa: false,
        intent: intent,
        suggestedChips: const [
          MemberHelpChipId.labQueue,
          MemberHelpChipId.contactWa,
        ],
      );
    case MemberHelpIntent.stok:
      return MemberHelpBotReply(
        reply: id
            ? 'Tap “Stock / availability” for system stock at a branch (category summary or SKU search). This is app availability (stock − reserved), not a physical shelf audit.'
            : 'Ketuk chip “Stok / ketersediaan” untuk stok sistem cabang (ringkasan kategori atau cari SKU). Ini stok aplikasi (stock − reserved), bukan audit rak fisik.',
        escalateWa: false,
        intent: intent,
        suggestedChips: const [
          MemberHelpChipId.stok,
          MemberHelpChipId.contactWa,
        ],
      );
    case MemberHelpIntent.orderStatus:
      return MemberHelpBotReply(
        reply: id
            ? 'Tap “Check order status” for your latest invoices, or ask on WhatsApp for a live update.'
            : 'Ketuk chip “Cek status pesanan” untuk lihat nota terbaru, atau hubungi cabang via WA untuk update live.',
        escalateWa: false,
        intent: intent,
        suggestedChips: const [
          MemberHelpChipId.orderStatus,
          MemberHelpChipId.contactWa,
        ],
      );
    case MemberHelpIntent.pointsGrade:
      return MemberHelpBotReply(
        reply: id
            ? 'Tap “Points & grade” to see your balance from the app data.'
            : 'Ketuk chip “Poin & grade” untuk lihat saldo dari data akun Anda.',
        escalateWa: false,
        intent: intent,
        suggestedChips: const [MemberHelpChipId.pointsGrade],
      );
    case MemberHelpIntent.storeInfo:
      return MemberHelpBotReply(
        reply: id
            ? 'Tap “Store hours / address” for branch contacts from our directory (typical hours 09:00–21:00). Lobby foot traffic isn’t in the app — use WhatsApp. Lab/work queue and system stock are on their chips.'
            : 'Ketuk chip “Jam / alamat cabang” untuk kontak dari data cabang (jam umum 09:00–21:00). Jumlah orang di lobby tidak ada di app — pakai WhatsApp. Antrean lab dan stok sistem tersedia lewat chip masing-masing.',
        escalateWa: false,
        intent: intent,
        suggestedChips: const [
          MemberHelpChipId.storeInfo,
          MemberHelpChipId.stok,
          MemberHelpChipId.labQueue,
          MemberHelpChipId.contactWa,
        ],
      );
    case MemberHelpIntent.careWarranty:
      return MemberHelpBotReply(
        reply: id
            ? 'Tap “Care / warranty FAQ” for care tips and warranty exclusions.'
            : 'Ketuk chip “Perawatan / garansi” untuk tips perawatan dan batas garansi.',
        escalateWa: false,
        intent: intent,
        suggestedChips: const [MemberHelpChipId.careWarranty],
      );
    case MemberHelpIntent.contactWa:
      // Client owns XOR UX (GPS open OR ask area OR named-branch chips).
      // Keep escalate_wa for older clients; modern UI auto-resolves without CTA.
      return MemberHelpBotReply(
        reply: id
            ? 'Connecting you to WhatsApp…'
            : 'Menghubungkan ke WhatsApp…',
        escalateWa: true,
        intent: intent,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    case MemberHelpIntent.faqGeneral:
    case MemberHelpIntent.unknown:
      return MemberHelpBotReply(
        reply: id
            ? 'AI help is temporarily unavailable. Try a quick-action chip, or chat with the store on WhatsApp.'
            : 'Bantuan AI sedang tidak tersedia. Coba chip cepat di bawah, atau hubungi cabang via WhatsApp.',
        escalateWa: true,
        intent: MemberHelpIntent.unknown,
        suggestedChips: const [
          MemberHelpChipId.orderStatus,
          MemberHelpChipId.pointsGrade,
          MemberHelpChipId.storeInfo,
          MemberHelpChipId.labQueue,
          MemberHelpChipId.stok,
          MemberHelpChipId.careWarranty,
          MemberHelpChipId.contactWa,
        ],
      );
  }
}

/// Max free-text length accepted by client + Edge.
const int kMemberHelpMaxMessageLength = 500;
