import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../invoice/invoice_hub_service.dart';
import '../whatsapp_launcher.dart';
import 'member_help_bot_intent.dart';
import 'member_help_nearest_store.dart';
import 'member_points_grade.dart';
import 'member_repository.dart';
import 'member_session.dart';

/// Client API for Member help bot: chips (DB/FAQ) + free-text Edge (Gemini).
class MemberHelpBotService {
  MemberHelpBotService({
    MemberRepository? repo,
    SupabaseClient? client,
  })  : _repo = repo ?? MemberRepository(client: client),
        _db = client ?? Supabase.instance.client;

  final MemberRepository _repo;
  final SupabaseClient _db;

  static const careFaqId = '''
Perawatan kacamata:
• Cuci dengan air bersih dan sabun lembut khusus lensa.
• Keringkan dengan lap microfiber — hindari baju/tisu kasar.
• Lepas kacamata saat olahraga kontak atau berenang.
• Kontrol ukuran jika pandangan mulai tidak nyaman.

Garansi:
• Aktif 7 hari sejak barang diambil di toko (hari diambil sampai hari ke-7).
• Lebih dari 7 hari sejak diambil → garansi mati, tidak bisa klaim.
• Klaim wajib datang ke toko membawa barang; keputusan setelah cek fisik.
• Maksimal 1× klaim per transaksi.
• Batal jika: benturan / terjatuh / disengaja, modifikasi di luar Optik B. Riski, atau kehilangan (bukan tanggung jawab toko).

Jam operasional umum: 09:00–21:00 (bisa beda per cabang / hari libur). Untuk jam hari ini, konfirmasi via WhatsApp cabang.
''';

  static const careFaqEn = '''
Eyewear care:
• Rinse with clean water and a mild lens-safe soap.
• Dry with a microfiber cloth — avoid clothing or rough tissues.
• Remove glasses for contact sports or swimming.
• Book a check if vision feels uncomfortable.

Warranty:
• Active for 7 days from in-store pickup (pickup day through day 7).
• After more than 7 days from pickup → warranty is dead; claims are not allowed.
• Claims require visiting the store with the item; decision after physical check.
• Maximum 1 claim per purchase.
• Voided by: impact / drop / intentional damage, self-modification outside Optik B. Riski, or lost glasses (not the store’s responsibility).

Typical hours: 09:00–21:00 (may vary by branch / holidays). Confirm today’s hours via store WhatsApp.
''';

  Future<MemberHelpBotReply> handleChip(
    MemberHelpChipId chip, {
    String? locale,
    String? preferredTokoId,
  }) async {
    final loc = (locale ?? MemberSession.instance.locale).toLowerCase();
    final en = loc.startsWith('en');
    switch (chip) {
      case MemberHelpChipId.orderStatus:
        return _chipOrderStatus(en: en);
      case MemberHelpChipId.pointsGrade:
        return _chipPoints(en: en);
      case MemberHelpChipId.storeInfo:
        return _chipStore(
          en: en,
          preferredTokoId: preferredTokoId,
        );
      case MemberHelpChipId.labQueue:
        return _chipLabQueue(locale: loc, preferredTokoId: preferredTokoId);
      case MemberHelpChipId.stok:
        return _chipStok(locale: loc, preferredTokoId: preferredTokoId);
      case MemberHelpChipId.careWarranty:
        return MemberHelpBotReply(
          reply: en ? careFaqEn.trim() : careFaqId.trim(),
          escalateWa: false,
          intent: MemberHelpIntent.careWarranty,
        );
      case MemberHelpChipId.contactWa:
        // Client auto-resolves (selected store / GPS / ask area) — no dual-path copy.
        return MemberHelpBotReply(
          reply: en
              ? 'Connecting you to WhatsApp…'
              : 'Menghubungkan ke WhatsApp…',
          escalateWa: true,
          intent: MemberHelpIntent.contactWa,
        );
    }
  }

  /// Public store directory for the OBRA store picker gate.
  Future<List<Map<String, dynamic>>> loadStoreDirectory() =>
      _loadStoreDirectoryLite();

  /// Production/lab queue aggregates for preferred (or nearest named) toko.
  Future<MemberHelpBotReply> answerLabQueue({
    String? locale,
    String? preferredTokoId,
    String? messageForNamedToko,
  }) {
    final loc = (locale ?? MemberSession.instance.locale).toLowerCase();
    return _resolveAndFetchLabQueue(
      locale: loc,
      preferredTokoId: preferredTokoId,
      messageForNamedToko: messageForNamedToko,
    );
  }

  /// System stock summary / SKU search for preferred (or nearest named) toko.
  Future<MemberHelpBotReply> answerStok({
    String? locale,
    String? preferredTokoId,
    String? messageForNamedToko,
    String? productQuery,
  }) {
    final loc = (locale ?? MemberSession.instance.locale).toLowerCase();
    final msg = (messageForNamedToko ?? '').trim();
    final namedHint =
        msg.isEmpty ? '' : memberHelpExtractNamedTokoQuery(msg);
    final q = (productQuery ??
            (msg.isEmpty
                ? ''
                : memberHelpExtractStockQuery(
                    msg,
                    stripNamedToko: namedHint,
                  )))
        .trim();
    return _resolveAndFetchStok(
      locale: loc,
      preferredTokoId: preferredTokoId,
      messageForNamedToko: messageForNamedToko,
      productQuery: q.isEmpty ? null : q,
    );
  }

  Future<MemberHelpBotReply> _chipLabQueue({
    required String locale,
    String? preferredTokoId,
  }) {
    return _resolveAndFetchLabQueue(
      locale: locale,
      preferredTokoId: preferredTokoId,
    );
  }

  Future<MemberHelpBotReply> _chipStok({
    required String locale,
    String? preferredTokoId,
  }) {
    return _resolveAndFetchStok(
      locale: locale,
      preferredTokoId: preferredTokoId,
    );
  }

  Future<MemberHelpBotReply> _resolveAndFetchLabQueue({
    required String locale,
    String? preferredTokoId,
    String? messageForNamedToko,
  }) async {
    final en = locale.toLowerCase().startsWith('en');
    try {
      final stores = await _loadStoreDirectoryLite();
      if (stores.isEmpty) {
        return MemberHelpBotReply(
          reply: en
              ? 'Branch directory is unavailable right now. Please ask on WhatsApp.'
              : 'Data cabang sedang tidak tersedia. Silakan tanya via WhatsApp.',
          escalateWa: true,
          intent: MemberHelpIntent.labQueue,
          suggestedChips: const [MemberHelpChipId.contactWa],
        );
      }

      final preferred = (preferredTokoId ??
              MemberSession.instance.preferredTokoId ??
              '')
          .trim()
          .toUpperCase();
      final focus = resolveMemberHelpSessionStore(
        stores: stores,
        selectedTokoId: preferred,
        message: messageForNamedToko,
      );

      final tokoId = (focus?['toko_id'] ?? '').toString().trim().toUpperCase();
      if (focus == null || tokoId.isEmpty) {
        return MemberHelpBotReply(
          reply: en
              ? 'Could not determine a branch. Name a branch (e.g. Depok) or set a preferred store, then try again.'
              : 'Belum bisa menentukan cabang. Sebut nama cabang (mis. Depok) atau set cabang pilihan, lalu coba lagi.',
          escalateWa: false,
          intent: MemberHelpIntent.labQueue,
          suggestedChips: const [
            MemberHelpChipId.storeInfo,
            MemberHelpChipId.contactWa,
          ],
        );
      }

      final counts = await fetchTokoLabQueueCounts(tokoId);
      if (counts == null || !counts.ok) {
        return MemberHelpBotReply(
          reply: en
              ? 'Could not load lab/work queue for $tokoId right now. Try again shortly, or ask on WhatsApp.'
              : 'Gagal memuat antrean lab/pengerjaan cabang $tokoId saat ini. Coba sebentar lagi, atau tanya via WhatsApp.',
          escalateWa: true,
          intent: MemberHelpIntent.labQueue,
          suggestedChips: const [
            MemberHelpChipId.labQueue,
            MemberHelpChipId.contactWa,
          ],
        );
      }

      final shop = (focus['shop_name'] ?? '').toString().trim();
      return MemberHelpBotReply(
        reply: memberHelpFormatLabQueueReply(
          locale: locale,
          tokoId: counts.tokoId.isNotEmpty ? counts.tokoId : tokoId,
          waiting: counts.waiting,
          inProgress: counts.inProgress,
          ready: counts.ready,
          shopName: shop.isEmpty ? null : shop,
        ),
        escalateWa: false,
        intent: MemberHelpIntent.labQueue,
        suggestedChips: const [
          MemberHelpChipId.orderStatus,
          MemberHelpChipId.contactWa,
        ],
      );
    } catch (e) {
      debugPrint('member help lab queue: $e');
      return MemberHelpBotReply(
        reply: en
            ? 'Could not load lab/work queue. Please try WhatsApp.'
            : 'Gagal memuat antrean lab/pengerjaan. Silakan coba via WhatsApp.',
        escalateWa: true,
        intent: MemberHelpIntent.labQueue,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    }
  }

  /// Member-safe RPC: aggregates only (no invoice/PII rows).
  Future<MemberHelpLabQueueCounts?> fetchTokoLabQueueCounts(String tokoId) async {
    final tid = tokoId.trim().toUpperCase();
    if (tid.isEmpty) return null;
    try {
      final raw = await _db.rpc(
        'get_toko_lab_queue_counts',
        params: {'p_toko_id': tid},
      );
      if (raw is Map) {
        return MemberHelpLabQueueCounts.fromJson(
          Map<String, dynamic>.from(raw),
        );
      }
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        return MemberHelpLabQueueCounts.fromJson(
          Map<String, dynamic>.from(raw.first as Map),
        );
      }
    } catch (e) {
      debugPrint('get_toko_lab_queue_counts: $e');
    }
    return null;
  }

  Future<MemberHelpBotReply> _resolveAndFetchStok({
    required String locale,
    String? preferredTokoId,
    String? messageForNamedToko,
    String? productQuery,
  }) async {
    final en = locale.toLowerCase().startsWith('en');
    try {
      final stores = await _loadStoreDirectoryLite();
      if (stores.isEmpty) {
        return MemberHelpBotReply(
          reply: en
              ? 'Branch directory is unavailable right now. Please ask on WhatsApp.'
              : 'Data cabang sedang tidak tersedia. Silakan tanya via WhatsApp.',
          escalateWa: true,
          intent: MemberHelpIntent.stok,
          suggestedChips: const [MemberHelpChipId.contactWa],
        );
      }

      final preferred = (preferredTokoId ??
              MemberSession.instance.preferredTokoId ??
              '')
          .trim()
          .toUpperCase();
      final focus = resolveMemberHelpSessionStore(
        stores: stores,
        selectedTokoId: preferred,
        message: messageForNamedToko,
      );

      final tokoId = (focus?['toko_id'] ?? '').toString().trim().toUpperCase();
      if (focus == null || tokoId.isEmpty) {
        return MemberHelpBotReply(
          reply: en
              ? 'Could not determine a branch. Name a branch (e.g. Depok) or set a preferred store, then try again.'
              : 'Belum bisa menentukan cabang. Sebut nama cabang (mis. Depok) atau set cabang pilihan, lalu coba lagi.',
          escalateWa: false,
          intent: MemberHelpIntent.stok,
          suggestedChips: const [
            MemberHelpChipId.storeInfo,
            MemberHelpChipId.contactWa,
          ],
        );
      }

      final result = await fetchTokoStock(
        tokoId,
        query: productQuery,
      );
      if (result == null || !result.ok) {
        return MemberHelpBotReply(
          reply: en
              ? 'Could not load system stock for $tokoId right now. Try again shortly, or ask on WhatsApp.'
              : 'Gagal memuat stok sistem cabang $tokoId saat ini. Coba sebentar lagi, atau tanya via WhatsApp.',
          escalateWa: true,
          intent: MemberHelpIntent.stok,
          suggestedChips: const [
            MemberHelpChipId.stok,
            MemberHelpChipId.contactWa,
          ],
        );
      }

      final shop = (focus['shop_name'] ?? '').toString().trim();
      final q = (productQuery ?? '').trim();
      final noMatch = q.isNotEmpty &&
          result.mode == 'search' &&
          result.matches.isEmpty;
      final ambiguous = q.isNotEmpty &&
          result.matches.length > 1 &&
          result.matches.every((m) => !m.inStock);
      // True empty branch (summary with 0 in-stock SKUs) → WA. Successful
      // summary/search with matches → no WA CTA.
      final emptyBranch =
          result.mode == 'summary' && result.skusInStock <= 0;
      final escalate = noMatch || ambiguous || emptyBranch;
      final products = memberHelpPickStockProductsForUi(result);
      return MemberHelpBotReply(
        reply: memberHelpFormatStokReply(
          locale: locale,
          result: result,
          shopName: shop.isEmpty ? null : shop,
          interactiveProducts: products.isNotEmpty,
        ),
        escalateWa: escalate,
        intent: MemberHelpIntent.stok,
        suggestedChips: escalate
            ? const [
                MemberHelpChipId.stok,
                MemberHelpChipId.contactWa,
              ]
            : const [MemberHelpChipId.stok],
        stockProducts: products,
        stockTotalInStock: memberHelpClampNonNegQty(result.skusInStock),
      );
    } catch (e) {
      debugPrint('member help stok: $e');
      return MemberHelpBotReply(
        reply: en
            ? 'Could not load system stock. Please try WhatsApp.'
            : 'Gagal memuat stok sistem. Silakan coba via WhatsApp.',
        escalateWa: true,
        intent: MemberHelpIntent.stok,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    }
  }

  /// Member-safe RPC: system available_qty summary / SKU matches (no PII).
  Future<MemberHelpStockResult?> fetchTokoStock(
    String tokoId, {
    String? query,
    int limit = kMemberHelpStockFetchLimit,
  }) async {
    final tid = tokoId.trim().toUpperCase();
    if (tid.isEmpty) return null;
    final lim = limit < 1
        ? kMemberHelpStockFetchLimit
        : (limit > kMemberHelpStockFetchLimit
            ? kMemberHelpStockFetchLimit
            : limit);
    try {
      final raw = await _db.rpc(
        'search_member_toko_stock',
        params: {
          'p_toko_id': tid,
          'p_q': (query ?? '').trim().isEmpty ? null : query!.trim(),
          'p_limit': lim,
        },
      );
      if (raw is Map) {
        return MemberHelpStockResult.fromJson(Map<String, dynamic>.from(raw));
      }
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        return MemberHelpStockResult.fromJson(
          Map<String, dynamic>.from(raw.first as Map),
        );
      }
    } catch (e) {
      debugPrint('search_member_toko_stock: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadStoreDirectoryLite() async {
    // Prefer SECURITY DEFINER RPC — invoice_settings RLS is authenticated-only
    // while Member uses anon + custom session.
    try {
      final raw = await _db.rpc('list_member_help_stores');
      final list = _parseStoreDirectoryRpc(raw);
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('list_member_help_stores: $e');
    }

    // Legacy direct select (works only with authenticated / service role).
    try {
      final rows = await _db
          .from('invoice_settings')
          .select('toko_id, shop_name, address, phone')
          .order('toko_id');
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((s) => (s['toko_id'] ?? '').toString().trim().isNotEmpty)
          .where((s) {
            final id =
                (s['toko_id'] ?? '').toString().trim().toUpperCase();
            return id.isNotEmpty && id != 'PUSAT' && id != 'CABANG-PUSAT';
          })
          .toList(growable: false);
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('member help store directory: $e');
    }

    // Last resort: toko_id ids so picker is never hard-empty.
    try {
      final rows = await _db.from('toko_id').select('id').order('id');
      return (rows as List)
          .map((e) {
            final id = (e is Map ? e['id'] : null)?.toString().trim() ?? '';
            return <String, dynamic>{
              'toko_id': id,
              'shop_name': 'Optik B. Riski',
              'address': '',
              'phone': '',
            };
          })
          .where((s) {
            final id =
                (s['toko_id'] ?? '').toString().trim().toUpperCase();
            return id.isNotEmpty && id != 'PUSAT' && id != 'CABANG-PUSAT';
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('member help toko_id fallback: $e');
      return const [];
    }
  }

  List<Map<String, dynamic>> _parseStoreDirectoryRpc(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) => (s['toko_id'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<MemberHelpBotReply> _chipOrderStatus({required bool en}) async {
    final session = MemberSession.instance;
    if (!session.isLoggedIn) {
      return MemberHelpBotReply(
        reply: en
            ? 'Sign in to see your order status in the app, or ask the store on WhatsApp with your invoice number.'
            : 'Masuk akun dulu untuk melihat status pesanan di app, atau tanya cabang via WA dengan nomor nota.',
        escalateWa: true,
        intent: MemberHelpIntent.orderStatus,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    }
    final phone = session.phoneForQuery;
    final sales = await _repo.listSales(phone);
    if (sales.isEmpty) {
      return MemberHelpBotReply(
        reply: en
            ? 'No invoices found for this account yet. If you just ordered in-store, ask the branch on WhatsApp with your name/phone.'
            : 'Belum ada nota terhubung ke akun ini. Jika baru pesan di toko, tanya cabang via WA dengan nama/HP Anda.',
        escalateWa: true,
        intent: MemberHelpIntent.orderStatus,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    }

    final buf = StringBuffer(
      en
          ? 'Latest orders from your account:\n'
          : 'Pesanan terbaru dari akun Anda:\n',
    );
    for (final s in sales.take(5)) {
      final inv = (s['no_invoice'] ?? '-').toString();
      final toko = (s['toko_id'] ?? '-').toString();
      final label = InvoiceHubService.statusLabel(s);
      final pay = (s['status_pembayaran'] ?? '').toString();
      buf.writeln(
        '• $inv · $toko · $label${pay.isEmpty ? '' : ' · $pay'}',
      );
    }
    buf.writeln(
      en
          ? '\nThis is your order status — not lobby foot traffic. For branch lab/work queue load (waiting / in progress / ready), use the lab-queue chip.'
          : '\nIni status pesanan Anda — bukan jumlah orang di lobby. Untuk beban antrean lab/pengerjaan cabang (menunggu / dikerjakan / siap diambil), pakai chip antrean lab.',
    );
    return MemberHelpBotReply(
      reply: buf.toString().trim(),
      escalateWa: false,
      intent: MemberHelpIntent.orderStatus,
      suggestedChips: const [MemberHelpChipId.contactWa],
    );
  }

  Future<MemberHelpBotReply> _chipPoints({required bool en}) async {
    final session = MemberSession.instance;
    final id = session.memberId;
    if (!session.isLoggedIn || id == null || id.isEmpty) {
      return MemberHelpBotReply(
        reply: en
            ? 'Sign in to see points and grade tied to your member account.'
            : 'Masuk akun dulu untuk melihat poin dan grade Member Anda.',
        escalateWa: false,
        intent: MemberHelpIntent.pointsGrade,
      );
    }
    final snap = await _repo.pointsSummary(id);
    final grade = snap.palette.label;
    final next = MemberGradeThresholds.nextGrade(snap.grade);
    final toNext = MemberGradeThresholds.pointsToNext(snap.statusPoints);
    final rewardFmt = formatMemberPoints(snap.rewardPoints);
    final statusFmt = formatMemberPoints(snap.statusPoints);
    final toNextFmt = formatMemberPoints(toNext);
    final nextLine = next == null
        ? (en ? 'You are at the top grade.' : 'Anda di grade tertinggi.')
        : (en
            ? 'Next: ${MemberGradePalette.of(next).label} · $toNextFmt status points to go.'
            : 'Berikutnya: ${MemberGradePalette.of(next).label} · kurang $toNextFmt Status Poin.');

    return MemberHelpBotReply(
      reply: en
          ? 'Reward points: $rewardFmt\n'
              'Status points (grade): $statusFmt\n'
              'Grade: $grade\n'
              '$nextLine'
          : 'Poin Reward: $rewardFmt\n'
              'Status Poin (grade): $statusFmt\n'
              'Grade: $grade\n'
              '$nextLine',
      escalateWa: false,
      intent: MemberHelpIntent.pointsGrade,
    );
  }

  Future<MemberHelpBotReply> _chipStore({
    required bool en,
    String? preferredTokoId,
    String? messageForNamedToko,
  }) async {
    final preferred = (preferredTokoId ??
            MemberSession.instance.preferredTokoId ??
            '')
        .trim()
        .toUpperCase();
    try {
      final list = await _loadStoreDirectoryLite();
      if (list.isEmpty) {
        return MemberHelpBotReply(
          reply: en
              ? 'Branch directory is unavailable right now. Please ask on WhatsApp.'
              : 'Data cabang sedang tidak tersedia. Silakan tanya via WhatsApp.',
          escalateWa: true,
          intent: MemberHelpIntent.storeInfo,
          suggestedChips: const [MemberHelpChipId.contactWa],
        );
      }

      final focus = resolveMemberHelpSessionStore(
        stores: list,
        selectedTokoId: preferred,
        message: messageForNamedToko,
      );
      if (focus == null) {
        return MemberHelpBotReply(
          reply: en
              ? 'Could not determine a branch. Pick a store first, or name a branch.'
              : 'Belum bisa menentukan cabang. Pilih toko dulu, atau sebut nama cabang.',
          escalateWa: false,
          intent: MemberHelpIntent.storeInfo,
          suggestedChips: const [MemberHelpChipId.contactWa],
        );
      }

      final buf = StringBuffer(
        en ? 'Branch info (directory):\n' : 'Info cabang (dari data toko):\n',
      );
      final id = (focus['toko_id'] ?? '-').toString();
      final name = (focus['shop_name'] ?? 'Optik B. Riski').toString();
      final addrRaw = (focus['address'] ?? '').toString().trim();
      final phoneRaw = (focus['phone'] ?? '').toString().trim();
      final addrMissing = addrRaw.isEmpty || addrRaw == '-';
      final phoneMissing = phoneRaw.isEmpty ||
          phoneRaw == '-' ||
          !memberHelpHasValidStorePhone(phoneRaw);
      final addr = addrMissing
          ? (en
              ? 'Not listed in directory — ask via WhatsApp'
              : 'Belum terisi di data cabang — tanya via WhatsApp')
          : addrRaw;
      final phone = phoneMissing
          ? (en
              ? 'Not listed — use “Contact branch (WA)”'
              : 'Belum terisi — pakai chip “Hubungi cabang (WA)”')
          : phoneRaw;
      buf.writeln('• $id — $name');
      buf.writeln('  ${en ? 'Address' : 'Alamat'}: $addr');
      buf.writeln('  WA/HP: $phone');
      if (list.length > 1) {
        buf.writeln(
          en
              ? '\nOther branches: open the Cabang tab for the full list.'
              : '\nCabang lain: buka tab Cabang untuk daftar lengkap.',
        );
      }
      buf.writeln(
        en
            ? '\nTypical hours 09:00–21:00 (may vary by branch/holiday). Lobby foot traffic & physical shelf confirmation aren’t in the app → WhatsApp. Lab/work queue and system stock are on their chips.'
            : '\nJam umum 09:00–21:00 (bisa beda per cabang/libur). Jumlah orang di lobby & konfirmasi rak fisik tidak ada di app → WhatsApp. Antrean lab dan stok sistem ada di chip masing-masing.',
      );

      return MemberHelpBotReply(
        reply: buf.toString().trim(),
        escalateWa: false,
        intent: MemberHelpIntent.storeInfo,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    } catch (e) {
      debugPrint('member help store chip: $e');
      return MemberHelpBotReply(
        reply: en
            ? 'Could not load branch data. Please contact WhatsApp.'
            : 'Gagal memuat data cabang. Silakan hubungi via WhatsApp.',
        escalateWa: true,
        intent: MemberHelpIntent.storeInfo,
        suggestedChips: const [MemberHelpChipId.contactWa],
      );
    }
  }

  /// Free-text → Edge Function (Gemini Flash) with local/keyword fallback.
  Future<MemberHelpBotReply> askFreeText(
    String message, {
    String? locale,
    String? preferredTokoId,
    Map<String, dynamic>? clientContext,
  }) async {
    final trimmed = message.trim();
    final loc = (locale ?? MemberSession.instance.locale).toLowerCase();
    if (trimmed.isEmpty) {
      return memberHelpKeywordFallback(message: trimmed, locale: loc);
    }
    if (trimmed.length > kMemberHelpMaxMessageLength) {
      final en = loc.startsWith('en');
      return MemberHelpBotReply(
        reply: en
            ? 'Message is too long (max $kMemberHelpMaxMessageLength characters).'
            : 'Pesan terlalu panjang (maks $kMemberHelpMaxMessageLength karakter).',
        escalateWa: false,
      );
    }

    // Lobby / physical shelf / nego / physical / today's hours → WA (not invent).
    if (memberHelpNeedsLiveEscalation(trimmed)) {
      return memberHelpKeywordFallback(message: trimmed, locale: loc);
    }
    // Production/lab queue from aggregates — local RPC, skip Gemini.
    if (memberHelpDetectIntent(trimmed) == MemberHelpIntent.labQueue) {
      return answerLabQueue(
        locale: loc,
        preferredTokoId: preferredTokoId,
        messageForNamedToko: trimmed,
      );
    }
    // System stock summary / SKU search — local RPC, skip Gemini.
    if (memberHelpDetectIntent(trimmed) == MemberHelpIntent.stok) {
      return answerStok(
        locale: loc,
        preferredTokoId: preferredTokoId,
        messageForNamedToko: trimmed,
      );
    }
    // Hours / address for selected (or named) store — local, skip Gemini WA push.
    if (memberHelpDetectIntent(trimmed) == MemberHelpIntent.storeInfo) {
      return _chipStore(
        en: loc.startsWith('en'),
        preferredTokoId: preferredTokoId,
        messageForNamedToko: trimmed,
      );
    }
    // Care / warranty FAQ — local static copy.
    if (memberHelpDetectIntent(trimmed) == MemberHelpIntent.careWarranty) {
      return handleChip(
        MemberHelpChipId.careWarranty,
        locale: loc,
        preferredTokoId: preferredTokoId,
      );
    }
    // WA contact free-text → escalate locally (selected store / GPS / ask).
    // Never send to Gemini (it may dump the whole store phone directory).
    if (memberHelpWantsWhatsAppContact(trimmed)) {
      return memberHelpKeywordFallback(message: trimmed, locale: loc);
    }

    final session = MemberSession.instance;
    final tokoForEdge = (preferredTokoId ?? session.preferredTokoId ?? '')
        .trim()
        .toUpperCase();
    final body = <String, dynamic>{
      'message': trimmed,
      'locale': loc,
      if (session.memberId != null) 'member_id': session.memberId,
      if (session.phoneForQuery.isNotEmpty) 'phone': session.phoneForQuery,
      if (tokoForEdge.isNotEmpty) 'toko_id': tokoForEdge,
      if (session.nama != null && session.nama!.isNotEmpty)
        'member_name': session.nama,
      if (clientContext != null) 'context': clientContext,
    };

    // One soft retry after a short pause — free-tier Gemini RPM / empty
    // thinking-budget replies are intermittent under burst traffic.
    MemberHelpBotReply? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
      last = await _invokeHelpBot(body, fallbackMessage: trimmed, locale: loc);
      if (last != null && !last.isSoftGeminiFailure) return last;
    }
    return last ?? memberHelpKeywordFallback(message: trimmed, locale: loc);
  }

  Future<MemberHelpBotReply?> _invokeHelpBot(
    Map<String, dynamic> body, {
    required String fallbackMessage,
    required String locale,
  }) async {
    try {
      final res = await _db.functions.invoke('member-help-bot', body: body);
      if (res.data is Map) {
        return _parseEdgeReply(
          Map<String, dynamic>.from(res.data as Map),
          fallbackMessage: fallbackMessage,
          locale: locale,
        );
      }
      if (res.status >= 400) {
        debugPrint('member-help-bot HTTP ${res.status}: ${res.data}');
      }
    } on FunctionException catch (e) {
      debugPrint(
        'member-help-bot FunctionException status=${e.status} details=${e.details}',
      );
      final details = e.details;
      if (details is Map) {
        final map = Map<String, dynamic>.from(details);
        final reply = (map['reply'] ?? '').toString().trim();
        if (reply.isNotEmpty) {
          return _parseEdgeReply(
            map,
            fallbackMessage: fallbackMessage,
            locale: locale,
          );
        }
      }
    } catch (e) {
      debugPrint('member-help-bot invoke: $e');
    }
    return null;
  }

  MemberHelpBotReply _parseEdgeReply(
    Map<String, dynamic> raw, {
    required String fallbackMessage,
    required String locale,
  }) {
    final reply = (raw['reply'] ?? '').toString().trim();
    final errorCode = (raw['error_code'] ?? '').toString().trim();
    if (reply.isEmpty) {
      return memberHelpKeywordFallback(
        message: fallbackMessage,
        locale: locale,
      );
    }
    final escalate = raw['escalate_wa'] == true;
    MemberHelpIntent? intent;
    final intentRaw = (raw['intent'] ?? '').toString().trim();
    if (intentRaw.isNotEmpty) {
      for (final v in MemberHelpIntent.values) {
        if (v.name == intentRaw) {
          intent = v;
          break;
        }
      }
    }
    final chips = <MemberHelpChipId>[];
    final sug = raw['suggested_chips'];
    if (sug is List) {
      for (final c in sug) {
        final name = c.toString();
        for (final v in MemberHelpChipId.values) {
          if (v.name == name) {
            chips.add(v);
            break;
          }
        }
      }
    }
    // Never treat a configured/unavailable reply as "unconfigured" locally —
    // trust the Edge error_code + message when present.
    return MemberHelpBotReply(
      reply: reply,
      escalateWa: escalate,
      intent: intent,
      suggestedChips: chips,
      errorCode: errorCode.isEmpty ? null : errorCode,
    );
  }

  /// Resolve WA for escalation.
  ///
  /// Primary: [selectedTokoId] store phone when dialable.
  /// Fallback: soft GPS nearest, else [askLocation]
  /// (do **not** silently jump to preferred/PUSAT — chat asks for area first).
  Future<MemberHelpWaPrepareResult> prepareEscalationWhatsApp({
    String? selectedTokoId,
  }) async {
    final stores = await _loadStoresWithGeoAndPhone();

    final selected = pickSelectedStoreWithPhone(
      selectedTokoId: selectedTokoId,
      stores: stores,
    );
    if (selected != null) {
      return MemberHelpWaPrepareResult.ready(
        _targetFromStore(selected, MemberHelpWaSource.selectedToko),
      );
    }

    // Selected store missing phone (or no selection) → GPS soft, else ask.
    final pos = await _tryCurrentPositionSoft();
    if (pos != null) {
      final nearest = pickNearestStoreWithPhone(
        userLat: pos.latitude,
        userLng: pos.longitude,
        stores: stores,
        distanceMeters: Geolocator.distanceBetween,
      );
      if (nearest != null) {
        return MemberHelpWaPrepareResult.ready(
          _targetFromStore(nearest, MemberHelpWaSource.nearestGps),
        );
      }
    }
    // GPS denied/timeout/unavailable or no geo+phone rows → ask in chat.
    return const MemberHelpWaPrepareResult.askLocation();
  }

  /// Match typed city/area to store directory (V1: text contains / tokens).
  Future<MemberHelpStatedLocationResult> resolveFromStatedLocation(
    String query,
  ) async {
    final stores = await _loadStoresWithGeoAndPhone();
    final matches = matchStoresByStatedLocation(query, stores);
    final best = pickBestStatedLocationMatch(matches);
    if (best != null) {
      return MemberHelpStatedLocationResult(
        target: _targetFromStore(
          best.store,
          MemberHelpWaSource.statedLocation,
          locationUnavailable: true,
        ),
      );
    }
    if (matches.isNotEmpty) {
      return MemberHelpStatedLocationResult(
        candidates: matches.map((m) => m.store).toList(growable: false),
      );
    }
    return MemberHelpStatedLocationResult(
      noTextMatch: true,
      candidates: topStoresWithPhone(stores),
    );
  }

  /// Last resort after user cannot/won't give a usable area.
  Future<MemberHelpWaTarget> resolveFallbackWhatsAppTarget({
    String? preferredTokoId,
  }) async {
    final preferred = (preferredTokoId ??
            MemberSession.instance.preferredTokoId ??
            '')
        .trim()
        .toUpperCase();
    final stores = await _loadStoresWithGeoAndPhone();

    if (preferred.isNotEmpty) {
      for (final s in stores) {
        final tid = (s['toko_id'] ?? '').toString().trim().toUpperCase();
        if (tid != preferred) continue;
        if (!memberHelpHasValidStorePhone(s['phone']?.toString())) break;
        return _targetFromStore(
          s,
          MemberHelpWaSource.preferredToko,
          locationUnavailable: true,
        );
      }
      final wa = await resolveAdminWhatsApp(client: _db, tokoId: preferred);
      if (wa != defaultAdminWhatsApp) {
        return MemberHelpWaTarget(
          waDigits: wa,
          source: MemberHelpWaSource.preferredToko,
          tokoId: preferred,
          locationUnavailable: true,
        );
      }
    }

    final wa = await resolveAdminWhatsApp(client: _db, tokoId: 'PUSAT');
    return MemberHelpWaTarget(
      waDigits: wa,
      source: MemberHelpWaSource.adminFallback,
      tokoId: 'PUSAT',
      locationUnavailable: true,
    );
  }

  /// Build WA target from a store row already chosen (chip tap).
  MemberHelpWaTarget targetFromStoreMap(
    Map<String, dynamic> store, {
    MemberHelpWaSource source = MemberHelpWaSource.statedLocation,
  }) {
    return _targetFromStore(store, source, locationUnavailable: true);
  }

  MemberHelpWaTarget _targetFromStore(
    Map<String, dynamic> store,
    MemberHelpWaSource source, {
    bool locationUnavailable = false,
  }) {
    final phone = normalizeWaNumber((store['phone'] ?? '').toString());
    final tid = (store['toko_id'] ?? '').toString().trim();
    final shop = (store['shop_name'] ?? '').toString().trim();
    return MemberHelpWaTarget(
      waDigits: phone,
      source: source,
      tokoId: tid.isEmpty ? null : tid,
      shopName: shop.isEmpty ? null : shop,
      locationUnavailable: locationUnavailable,
    );
  }

  Future<List<Map<String, dynamic>>> _loadStoresWithGeoAndPhone() async {
    // RPC already includes lat/lng when available.
    final fromRpc = await _loadStoreDirectoryLite();
    if (fromRpc.isNotEmpty) {
      final hasAnyPhone =
          fromRpc.any((s) => memberHelpHasValidStorePhone(s['phone']?.toString()));
      if (hasAnyPhone) return fromRpc;
    }

    final geoById = <String, Map<String, dynamic>>{};
    try {
      final geoRows =
          await _db.from('toko_id').select('id, latitude, longitude').order('id');
      for (final raw in (geoRows as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id'] ?? '').toString().trim().toUpperCase();
        if (id.isNotEmpty) geoById[id] = m;
      }
    } catch (e) {
      debugPrint('member help WA geo load: $e');
    }

    final list = <Map<String, dynamic>>[];
    for (final s0 in fromRpc) {
      final s = Map<String, dynamic>.from(s0);
      final id = (s['toko_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      if (s['latitude'] == null || s['longitude'] == null) {
        final geo = geoById[id.toUpperCase()];
        s['latitude'] = geo?['latitude'];
        s['longitude'] = geo?['longitude'];
      }
      list.add(s);
    }
    return list;
  }

  /// Soft GPS: request permission if needed; never hang the WA CTA.
  Future<Position?> _tryCurrentPositionSoft() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('member help WA GPS soft: $e');
      return null;
    }
  }

  /// Prefill WA with member context + last question; opens [target] WA.
  Future<MemberHelpWaTarget> openWhatsAppForTarget(
    MemberHelpWaTarget target, {
    String? lastQuestion,
  }) async {
    final session = MemberSession.instance;
    final name = (session.nama ?? '').trim();
    final phone = session.phoneForQuery;
    final q = (lastQuestion ?? '').trim();
    final tokoLabel = (target.tokoId ?? '').trim();

    final buf = StringBuffer('Halo Optik B. Riski, saya dari aplikasi Member.');
    if (name.isNotEmpty) buf.write('\nNama: $name');
    if (phone.isNotEmpty) buf.write('\nHP: $phone');
    if (tokoLabel.isNotEmpty) buf.write('\nCabang: $tokoLabel');
    if (q.isNotEmpty) buf.write('\nPertanyaan: $q');

    final uri = Uri.parse(
      'https://wa.me/${target.waDigits}?text=${Uri.encodeComponent(buf.toString())}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw 'Tidak bisa membuka WhatsApp. Pastikan aplikasi terpasang.';
    }
    return target;
  }

  /// Selected-store WA (primary), else GPS soft / ask location.
  ///
  /// Does not fall back to preferred/PUSAT; use [resolveFallbackWhatsAppTarget]
  /// only after the user cannot match an area.
  Future<MemberHelpWaPrepareResult> tryOpenEscalationWhatsApp({
    String? lastQuestion,
    String? selectedTokoId,
  }) async {
    final prepared = await prepareEscalationWhatsApp(
      selectedTokoId: selectedTokoId,
    );
    if (prepared.kind == MemberHelpWaPrepareKind.ready &&
        prepared.target != null) {
      await openWhatsAppForTarget(
        prepared.target!,
        lastQuestion: lastQuestion,
      );
    }
    return prepared;
  }
}
