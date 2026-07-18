import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Bagian alokasi satu cabang untuk satu SKU Pusat.
class StoreShare {
  const StoreShare({
    required this.tokoId,
    required this.sold30d,
    required this.stockCabang,
    required this.inboundQty,
    required this.needQty,
    required this.allocated,
  });

  final String tokoId;
  final int sold30d;
  final int stockCabang;

  /// RO/DO yang masih jalan (belum SUCCESS) untuk SKU ini.
  final int inboundQty;
  final int needQty;
  final int allocated;
}

/// Hint restock DO untuk cabang yang sedang dipilih.
///
/// Butuh kirim = max(0, laku30h − stok cabang − inbound RO/DO)
/// Contoh: laku 50, stok 30 → kirim 20 (melengkapi rata2 penjualan).
class RestockHint {
  const RestockHint({
    required this.stockPusat,
    required this.stockCabang,
    required this.inboundQty,
    required this.sold30d,
    required this.needQty,
    required this.suggestedQty,
    required this.totalNeedAll,
    required this.pusatEnough,
    required this.salesRank,
    required this.cabangCount,
    required this.shares,
  });

  final int stockPusat;
  final int stockCabang;
  final int inboundQty;
  final int sold30d;

  /// max(0, laku − stok − inbound).
  final int needQty;

  /// Qty setelah alokasi multi-cabang (prioritas yang lebih laku).
  final int suggestedQty;

  final int totalNeedAll;
  final bool pusatEnough;
  final int salesRank;
  final int cabangCount;
  final List<StoreShare> shares;

  /// Stok efektif di cabang (on-hand + yang sudah dipesan/dalam perjalanan).
  int get coveredQty => stockCabang + inboundQty;
}

/// Alokasi stok Pusat ke banyak cabang berdasarkan sisa kebutuhan
/// setelah stok toko (+ inbound) diperhitungkan.
class RestockSuggestService {
  RestockSuggestService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _openRoStatuses = [
    'SENT_TO_HQ',
    'APPROVED',
    'PREPARING',
    'SHIPPING',
  ];

  static const _openMoveStatuses = ['WAITING', 'TRANSIT', 'PENDING'];

  static String matchKey(Map<String, dynamic> p) {
    final sku = (p['sku'] ?? '').toString().trim().toLowerCase();
    if (sku.isNotEmpty) return 'sku:$sku';
    final barcode = (p['barcode'] ?? '').toString().trim().toLowerCase();
    if (barcode.isNotEmpty) return 'bc:$barcode';
    final nama = (p['nama'] ?? '').toString().trim().toLowerCase();
    return 'nama:$nama';
  }

  static String matchKeyFromFields({
    String? sku,
    String? barcode,
    String? nama,
  }) {
    final s = (sku ?? '').trim().toLowerCase();
    if (s.isNotEmpty) return 'sku:$s';
    final b = (barcode ?? '').trim().toLowerCase();
    if (b.isNotEmpty) return 'bc:$b';
    return 'nama:${(nama ?? '').trim().toLowerCase()}';
  }

  /// Bagi [stockPusat] ke cabang. Weight = sold30d; hanya yang need > 0.
  static Map<String, int> allocateBySalesPriority({
    required int stockPusat,
    required Map<String, int> soldByToko,
    required Map<String, int> needByToko,
  }) {
    final pusatStock = stockPusat < 0 ? 0 : stockPusat;
    final tokoIds = needByToko.keys
        .where((t) => (needByToko[t] ?? 0) > 0)
        .toList();

    final alloc = {for (final t in needByToko.keys) t: 0};
    if (pusatStock <= 0 || tokoIds.isEmpty) return alloc;

    final totalNeed =
        tokoIds.fold<int>(0, (s, t) => s + (needByToko[t] ?? 0));

    if (pusatStock >= totalNeed) {
      for (final t in tokoIds) {
        alloc[t] = needByToko[t] ?? 0;
      }
      return alloc;
    }

    var totalWeight = 0;
    final weights = <String, int>{};
    for (final t in tokoIds) {
      final w = soldByToko[t] ?? 0;
      weights[t] = w > 0 ? w : 1;
      totalWeight += weights[t]!;
    }

    var used = 0;
    for (final t in tokoIds) {
      final share = (pusatStock * weights[t]! / totalWeight).floor();
      final capped = share.clamp(0, needByToko[t] ?? 0);
      alloc[t] = capped;
      used += capped;
    }

    var remainder = pusatStock - used;
    final ranked = [...tokoIds]..sort((a, b) {
      final bySold = (soldByToko[b] ?? 0).compareTo(soldByToko[a] ?? 0);
      if (bySold != 0) return bySold;
      return (needByToko[b] ?? 0).compareTo(needByToko[a] ?? 0);
    });

    while (remainder > 0) {
      var given = false;
      for (final t in ranked) {
        if (remainder <= 0) break;
        final need = needByToko[t] ?? 0;
        final cur = alloc[t] ?? 0;
        if (cur < need) {
          alloc[t] = cur + 1;
          remainder--;
          given = true;
        }
      }
      if (!given) break;
    }

    return alloc;
  }

  void _addInbound(
    Map<String, Map<String, int>> inboundByKeyToko,
    String key,
    String toko,
    int qty,
  ) {
    if (key == 'nama:' || toko.isEmpty || qty <= 0) return;
    inboundByKeyToko.putIfAbsent(key, () => {});
    inboundByKeyToko[key]![toko] =
        (inboundByKeyToko[key]![toko] ?? 0) + qty;
  }

  /// Map keyed by pusat `products.id` untuk [tokoTujuan].
  Future<Map<String, RestockHint>> hintsForToko(String tokoTujuan) async {
    final dest = tokoTujuan.trim();
    if (dest.isEmpty) return {};

    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    final pusatRes = await _client
        .from('products')
        .select('id, sku, barcode, nama, stock')
        .eq('toko_id', 'PUSAT');

    final cabangRes = await _client
        .from('products')
        .select('id, sku, barcode, nama, stock, toko_id')
        .neq('toko_id', 'PUSAT');

    final salesRes = await _client
        .from('sales')
        .select('id, toko_id, sales_items(qty, product_id, nama_produk)')
        .neq('toko_id', 'PUSAT')
        .gte('created_at', since);

    // RO terbuka = barang yang sudah dipesan / akan datang (hindari double DO).
    final roRes = await _client
        .from('pending_requests')
        .select('toko_id, sku, nama_produk, qty_request, reserved_qty, status')
        .inFilter('status', _openRoStatuses);

    final moveRes = await _client
        .from('stock_move_history')
        .select('ke_lokasi, jumlah, keterangan, status, tipe')
        .inFilter('status', _openMoveStatuses);

    final List pusatList = pusatRes as List;
    final List cabangList = cabangRes as List;
    final List salesList = salesRes as List;
    final List roList = roRes as List;
    final List moveList = moveRes as List;

    final cabangById = <String, Map<String, dynamic>>{};
    final stockByKeyToko = <String, Map<String, int>>{};
    final tokoSet = <String>{};

    for (final raw in cabangList) {
      final p = Map<String, dynamic>.from(raw as Map);
      final id = p['id']?.toString() ?? '';
      final toko = (p['toko_id'] ?? '').toString();
      if (toko.isEmpty) continue;
      tokoSet.add(toko);
      if (id.isNotEmpty) cabangById[id] = p;
      final key = matchKey(p);
      stockByKeyToko.putIfAbsent(key, () => {});
      stockByKeyToko[key]![toko] =
          int.tryParse(p['stock']?.toString() ?? '0') ?? 0;
    }

    final soldByKeyToko = <String, Map<String, int>>{};
    for (final sale in salesList) {
      final toko = (sale['toko_id'] ?? '').toString();
      if (toko.isEmpty || toko.toUpperCase() == 'PUSAT') continue;
      tokoSet.add(toko);
      final items = sale['sales_items'];
      if (items is! List) continue;
      for (final it in items) {
        if (it is! Map) continue;
        final qty = int.tryParse(it['qty']?.toString() ?? '0') ?? 0;
        if (qty <= 0) continue;
        final pid = it['product_id']?.toString();
        String key;
        if (pid != null && cabangById.containsKey(pid)) {
          key = matchKey(cabangById[pid]!);
        } else {
          key = matchKeyFromFields(nama: it['nama_produk']?.toString());
        }
        if (key == 'nama:') continue;
        soldByKeyToko.putIfAbsent(key, () => {});
        soldByKeyToko[key]![toko] = (soldByKeyToko[key]![toko] ?? 0) + qty;
      }
    }

    // inbound: RO terbuka + stock_move in-transit
    final inboundByKeyToko = <String, Map<String, int>>{};
    for (final raw in roList) {
      final r = Map<String, dynamic>.from(raw as Map);
      final toko = (r['toko_id'] ?? '').toString();
      if (toko.isEmpty) continue;
      tokoSet.add(toko);
      final reserved = int.tryParse(r['reserved_qty']?.toString() ?? '') ?? 0;
      final reqQty = int.tryParse(r['qty_request']?.toString() ?? '') ?? 0;
      final qty = reserved > 0 ? reserved : reqQty;
      final key = matchKeyFromFields(
        sku: r['sku']?.toString(),
        nama: r['nama_produk']?.toString(),
      );
      _addInbound(inboundByKeyToko, key, toko, qty);
    }

    for (final raw in moveList) {
      final m = Map<String, dynamic>.from(raw as Map);
      final toko = (m['ke_lokasi'] ?? '').toString();
      if (toko.isEmpty || toko.toUpperCase() == 'PUSAT') continue;
      tokoSet.add(toko);
      final ket = (m['keterangan'] ?? '').toString();
      final flatQty = int.tryParse(m['jumlah']?.toString() ?? '0') ?? 0;

      if (ket.contains('[{')) {
        try {
          final jsonPart = ket.substring(ket.indexOf('[{'));
          final items = jsonDecode(jsonPart);
          if (items is List) {
            for (final it in items) {
              if (it is! Map) continue;
              final qty = int.tryParse(it['qty']?.toString() ?? '0') ?? 0;
              final key = matchKeyFromFields(
                sku: it['sku']?.toString(),
                barcode: it['barcode']?.toString(),
                nama: it['nama']?.toString(),
              );
              _addInbound(inboundByKeyToko, key, toko, qty);
            }
            continue;
          }
        } catch (_) {}
      }

      // Fallback 1-SKU move tanpa JSON detail
      if (flatQty > 0 && ket.contains('RequestOrder#')) {
        // tanpa nama jelas — skip daripada salah match
        continue;
      }
    }

    final allToko = tokoSet.toList()..sort();

    final out = <String, RestockHint>{};
    for (final raw in pusatList) {
      final p = Map<String, dynamic>.from(raw as Map);
      final id = p['id']?.toString();
      if (id == null || id.isEmpty) continue;

      final key = matchKey(p);
      final sp = (int.tryParse(p['stock']?.toString() ?? '0') ?? 0)
          .clamp(0, 1 << 30);

      final soldMap = soldByKeyToko[key] ?? {};
      final stockMap = stockByKeyToko[key] ?? {};
      final inboundMap = inboundByKeyToko[key] ?? {};

      final needByToko = <String, int>{};
      final soldByToko = <String, int>{};
      final inboundByToko = <String, int>{};

      for (final t in allToko) {
        final v = soldMap[t] ?? 0;
        final sc = stockMap[t] ?? 0;
        final inbound = inboundMap[t] ?? 0;
        soldByToko[t] = v;
        inboundByToko[t] = inbound;
        // Melengkapi rata2 penjualan: laku − stok on-hand − yang sudah dipesan/jalan.
        needByToko[t] = (v - sc - inbound).clamp(0, 1 << 30);
      }

      final alloc = allocateBySalesPriority(
        stockPusat: sp,
        soldByToko: soldByToko,
        needByToko: needByToko,
      );

      final totalNeed =
          needByToko.values.fold<int>(0, (s, n) => s + n);

      final shares = allToko
          .where((t) =>
              (needByToko[t] ?? 0) > 0 ||
              (soldByToko[t] ?? 0) > 0 ||
              (inboundByToko[t] ?? 0) > 0)
          .map((t) => StoreShare(
                tokoId: t,
                sold30d: soldByToko[t] ?? 0,
                stockCabang: stockMap[t] ?? 0,
                inboundQty: inboundByToko[t] ?? 0,
                needQty: needByToko[t] ?? 0,
                allocated: alloc[t] ?? 0,
              ))
          .toList()
        ..sort((a, b) => b.sold30d.compareTo(a.sold30d));

      final needing = shares.where((s) => s.needQty > 0).toList();
      var rank = 0;
      for (var i = 0; i < needing.length; i++) {
        if (needing[i].tokoId == dest) {
          rank = i + 1;
          break;
        }
      }

      out[id] = RestockHint(
        stockPusat: sp,
        stockCabang: stockMap[dest] ?? 0,
        inboundQty: inboundByToko[dest] ?? 0,
        sold30d: soldByToko[dest] ?? 0,
        needQty: needByToko[dest] ?? 0,
        suggestedQty: alloc[dest] ?? 0,
        totalNeedAll: totalNeed,
        pusatEnough: sp >= totalNeed,
        salesRank: rank,
        cabangCount: needing.length,
        shares: shares,
      );
    }

    return out;
  }
}
