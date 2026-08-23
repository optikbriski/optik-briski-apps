import 'package:supabase_flutter/supabase_flutter.dart';

import 'logistics_tracking_service.dart';
import 'stock_leak_rules.dart';

class StockIntegrityIssue {
  StockIntegrityIssue({
    required this.sku,
    required this.tokoId,
    required this.stock,
    required this.ledgerSum,
    required this.delta,
    this.productId,
    this.nama,
    this.ledgerByReason = const {},
  });

  final String sku;
  final String tokoId;
  final int stock;
  final int ledgerSum;

  /// stock - ledgerSum. Positif = stok lebih dari jejak (masuk tanpa ledger).
  /// Negatif = stok kurang dari jejak (keluar tanpa ledger).
  final int delta;
  final String? productId;
  final String? nama;

  /// Jumlah qty_delta per reason ledger (SALE, TRANSFER_IN, …).
  final Map<String, int> ledgerByReason;

  String get diagnosis {
    if (delta > 0) {
      return 'Stok sistem +$delta lebih banyak dari jejak ledger '
          '(ada penambahan tanpa alasan tercatat).';
    }
    if (delta < 0) {
      return 'Stok sistem $delta lebih sedikit dari jejak ledger '
          '(ada pengurangan tanpa alasan tercatat).';
    }
    return 'Sinkron.';
  }

  /// Label ringkas breakdown jejak, mis. "SALE −12 · TRANSFER_IN +20".
  String get ledgerTrailLabel {
    if (ledgerByReason.isEmpty) return 'Belum ada jejak ledger';
    const order = [
      'OPENING',
      'TRANSFER_IN',
      'TRANSFER_OUT',
      'SALE',
      'RETURN_IN',
      'RETURN_OUT',
      'WRITE_OFF',
      'ADJUST',
    ];
    final keys = <String>[
      ...order.where(ledgerByReason.containsKey),
      ...ledgerByReason.keys.where((k) => !order.contains(k)),
    ];
    return keys.map((k) {
      final v = ledgerByReason[k] ?? 0;
      final sign = v > 0 ? '+' : '';
      return '$k $sign$v';
    }).join(' · ');
  }
}

/// Satu paket/DO/RO yang masih terbuka (disiapkan / transit).
class StockOpenTransitItem {
  const StockOpenTransitItem({
    required this.id,
    required this.resi,
    required this.fromToko,
    required this.toToko,
    required this.status,
    required this.qty,
    this.createdAt,
    this.tipe = '',
  });

  final String id;
  final String resi;
  final String fromToko;
  final String toToko;
  final String status;
  final int qty;
  final String? createdAt;
  final String tipe;

  String get statusLabel => LogisticsTrackingService.statusLabel(status);

  String get kindLabel {
    final t = tipe.toUpperCase();
    final r = resi.toUpperCase();
    if (t == 'REQUEST' || r.startsWith('RO-')) return 'RO';
    if (t == 'RETUR' || r.startsWith('RET-')) return 'Retur';
    if (t == 'DELIVERY' || r.startsWith('DO-')) return 'DO';
    return t.isEmpty ? 'Mutasi' : t;
  }
}

/// Baris SKU untuk drill-down stok / penjualan.
class StockSkuQtyLine {
  const StockSkuQtyLine({
    required this.sku,
    required this.nama,
    required this.qty,
  });

  final String sku;
  final String nama;
  final int qty;
}

class StockLeakReport {
  StockLeakReport({
    required this.checkedProducts,
    required this.mismatches,
    required this.missingSkuCount,
    required this.openTransitQty,
    required this.generatedAt,
    this.stockByToko = const {},
    this.stockLinesByToko = const {},
    this.transitByStatus = const {},
    this.transitByTujuan = const {},
    this.openTransitItems = const [],
    this.soldByToko30d = const {},
    this.soldLinesByToko30d = const {},
    this.ledgerByReason = const {},
    this.writeOffQty = 0,
  });

  final int checkedProducts;
  final List<StockIntegrityIssue> mismatches;
  final int missingSkuCount;

  /// Qty masih di perjalanan (Real sudah keluar / booking aktif) — normal, bukan bocor.
  final int openTransitQty;
  final DateTime generatedAt;

  final Map<String, int> stockByToko;
  final Map<String, List<StockSkuQtyLine>> stockLinesByToko;
  final Map<String, int> transitByStatus;
  final Map<String, int> transitByTujuan;
  final List<StockOpenTransitItem> openTransitItems;
  final Map<String, int> soldByToko30d;
  final Map<String, List<StockSkuQtyLine>> soldLinesByToko30d;
  final Map<String, int> ledgerByReason;

  /// Pcs WRITE_OFF tercatat (stok rusak). Bukan bocor — sudah ada jejak.
  final int writeOffQty;

  bool get isClean => mismatches.isEmpty && missingSkuCount == 0;

  int get totalStockOnHand =>
      stockByToko.values.fold<int>(0, (s, v) => s + v);

  int get totalSold30d =>
      soldByToko30d.values.fold<int>(0, (s, v) => s + v);

  int get cabangCount =>
      stockByToko.keys.where((k) => k != 'PUSAT').length;

  String get verdict {
    if (isClean) {
      return 'Aman — tidak ditemukan kebocoran stok pada pengecekan ini.';
    }
    final parts = <String>[];
    if (mismatches.isNotEmpty) {
      parts.add('${mismatches.length} selisih stok vs ledger');
    }
    if (missingSkuCount > 0) {
      parts.add('$missingSkuCount produk SKU lemah/NOSKU');
    }
    return 'Ada indikasi bocor — ${parts.join(', ')}.';
  }
}

/// Progress realtime saat scan kebocoran (untuk UI persen).
class StockLeakProgress {
  const StockLeakProgress({
    required this.percent,
    required this.phase,
    this.checked = 0,
    this.total = 0,
    this.currentLabel,
    this.foundLeaks = 0,
  });

  /// 0.0 – 1.0
  final double percent;
  final String phase;
  final int checked;
  final int total;
  final String? currentLabel;
  final int foundLeaks;

  int get percentInt => (percent.clamp(0.0, 1.0) * 100).round();
}

typedef StockLeakProgressCallback = void Function(StockLeakProgress progress);

/// Deteksi kebocoran: setiap pcs stok harus punya jejak di `product_stock_ledger`.
///
/// Rumus per (SKU, toko):
///   products.stock  ==  SUM(ledger.qty_delta)
class StockIntegrityService {
  StockIntegrityService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static String _key(String sku, String toko) =>
      '${sku.trim().toUpperCase()}|${StockLeakRules.tokoKey(toko)}';

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }

  /// Full scan dengan callback progress (persen nyata).
  Future<StockLeakReport> runLeakCheck({
    int pageSize = 500,
    StockLeakProgressCallback? onProgress,
    List<String>? tokoIds,
  }) async {
    void emit(StockLeakProgress p) => onProgress?.call(p);

    emit(const StockLeakProgress(
      percent: 0.02,
      phase: 'Menyiapkan daftar produk…',
    ));

    final scopedToko = tokoIds == null || tokoIds.isEmpty
        ? null
        : StockLeakRules.tokoKey(tokoIds.first);
    try {
      final raw = await _client.rpc(
        'stock_leak_scan',
        params: {'p_toko': scopedToko},
      );
      final fromRpc = _reportFromScanRpc(raw);
      if (fromRpc != null) {
        emit(const StockLeakProgress(
          percent: 0.90,
          phase: 'Merinci paket perjalanan…',
        ));
        final transit = await _openTransitBreakdown();
        emit(StockLeakProgress(
          percent: 1.0,
          phase: 'Pengecekan selesai',
          foundLeaks: fromRpc.mismatches.length,
        ));
        return StockLeakReport(
          checkedProducts: fromRpc.checkedProducts,
          mismatches: fromRpc.mismatches,
          missingSkuCount: fromRpc.missingSkuCount,
          openTransitQty: transit.total,
          stockByToko: fromRpc.stockByToko,
          stockLinesByToko: fromRpc.stockLinesByToko,
          transitByStatus: transit.byStatus,
          transitByTujuan: transit.byTujuan,
          openTransitItems: transit.items,
          soldByToko30d: fromRpc.soldByToko30d,
          soldLinesByToko30d: fromRpc.soldLinesByToko30d,
          ledgerByReason: fromRpc.ledgerByReason,
          writeOffQty: fromRpc.writeOffQty,
          generatedAt: DateTime.now(),
        );
      }
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) rethrow;
    }

    final allRows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      var pageQ = _client
          .from('products')
          .select('id, sku, toko_id, stock, nama');
      if (tokoIds != null && tokoIds.isNotEmpty) {
        pageQ = pageQ.inFilter('toko_id', tokoIds);
      }
      final page =
          await pageQ.order('sku').range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(page);
      if (rows.isEmpty) break;
      allRows.addAll(rows);
      emit(StockLeakProgress(
        percent: 0.03 + (0.07 * (allRows.length / (allRows.length + pageSize))),
        phase: 'Memuat katalog produk…',
        checked: allRows.length,
        total: allRows.length,
      ));
      if (rows.length < pageSize) break;
      offset += pageSize;
      if (offset > 20000) break;
    }

    final total = allRows.length;
    emit(StockLeakProgress(
      percent: 0.12,
      phase: total == 0
          ? 'Tidak ada produk'
          : 'Memuat jejak ledger (batch)…',
      checked: 0,
      total: total,
    ));

    // Batch ledger — hindari N+1 query per SKU (sangat lambat di dataset besar).
    final ledgerIndex = await _loadLedgerIndex(
      tokoIds: tokoIds,
      onProgress: (loaded, approx) {
        final pct = 0.12 + (0.48 * (approx.clamp(0.0, 1.0)));
        emit(StockLeakProgress(
          percent: pct,
          phase: 'Memuat jejak ledger…',
          checked: loaded,
          total: total > 0 ? total : loaded,
          currentLabel: '$loaded baris ledger',
        ));
      },
    );

    emit(StockLeakProgress(
      percent: 0.62,
      phase: 'Membandingkan stok vs ledger…',
      checked: 0,
      total: total,
    ));

    final mismatches = <StockIntegrityIssue>[];
    var checked = 0;
    var missingSku = 0;
    final stockByToko = <String, int>{};
    final stockLinesRaw = <String, List<StockSkuQtyLine>>{};

    for (final p in allRows) {
      checked++;
      final skuRaw = (p['sku'] ?? '').toString().trim();
      final toko = (p['toko_id'] ?? '').toString().trim().toUpperCase();
      final nama = (p['nama'] ?? skuRaw).toString();
      final stock = StockLeakRules.stockOf(p['stock']);
      final tokoKey = StockLeakRules.tokoKey(toko);

      if (tokoKey.isNotEmpty) {
        stockByToko[tokoKey] = (stockByToko[tokoKey] ?? 0) + stock;
        if (stock > 0 && skuRaw.isNotEmpty && !skuRaw.startsWith('NOSKU-')) {
          stockLinesRaw.putIfAbsent(tokoKey, () => []).add(StockSkuQtyLine(
                sku: skuRaw,
                nama: nama,
                qty: stock,
              ));
        }
      }

      if (skuRaw.isEmpty || skuRaw.startsWith('NOSKU-')) {
        missingSku++;
        final scanPct =
            total == 0 ? 0.88 : 0.62 + (0.26 * (checked / total));
        emit(StockLeakProgress(
          percent: scanPct,
          phase: 'Membandingkan stok vs ledger…',
          checked: checked,
          total: total,
          currentLabel: '$nama · $toko',
          foundLeaks: mismatches.length,
        ));
        continue;
      }

      if (tokoKey.isEmpty) {
        // Tanpa lokasi, rumus integrity tidak valid.
        final scanPct =
            total == 0 ? 0.88 : 0.62 + (0.26 * (checked / total));
        emit(StockLeakProgress(
          percent: scanPct,
          phase: 'Membandingkan stok vs ledger…',
          checked: checked,
          total: total,
          currentLabel: '$nama · (tanpa toko)',
          foundLeaks: mismatches.length,
        ));
        continue;
      }

      final agg = ledgerIndex[_key(skuRaw, tokoKey)] ??
          const _LedgerAgg(sum: 0, byReason: {});
      if (!StockLeakRules.sinkron(stock: stock, ledgerSum: agg.sum)) {
        mismatches.add(StockIntegrityIssue(
          sku: skuRaw,
          tokoId: tokoKey,
          stock: stock,
          ledgerSum: agg.sum,
          delta: stock - agg.sum,
          productId: p['id']?.toString(),
          nama: p['nama']?.toString(),
          ledgerByReason: agg.byReason,
        ));
      }

      final scanPct = total == 0 ? 0.88 : 0.62 + (0.26 * (checked / total));
      emit(StockLeakProgress(
        percent: scanPct,
        phase: 'Membandingkan stok vs ledger…',
        checked: checked,
        total: total,
        currentLabel: '$nama · $toko',
        foundLeaks: mismatches.length,
      ));
    }

    emit(StockLeakProgress(
      percent: 0.90,
      phase: 'Menghitung peta stok…',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));
    final stockLinesByToko = <String, List<StockSkuQtyLine>>{};
    for (final entry in stockLinesRaw.entries) {
      final lines = List<StockSkuQtyLine>.from(entry.value)
        ..sort((a, b) => b.qty.compareTo(a.qty));
      stockLinesByToko[entry.key] = lines.take(40).toList();
    }

    emit(StockLeakProgress(
      percent: 0.93,
      phase: 'Merinci paket perjalanan…',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));
    final transit = await _openTransitBreakdown();

    emit(StockLeakProgress(
      percent: 0.96,
      phase: 'Menghitung penjualan POS…',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));
    final sold = await _soldBreakdownLast30d(tokoIds: tokoIds);

    emit(StockLeakProgress(
      percent: 0.98,
      phase: 'Merangkum jejak ledger…',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));
    final ledgerByReason = <String, int>{};
    var writeOffQty = 0;
    for (final agg in ledgerIndex.values) {
      writeOffQty += StockLeakRules.writeOffPcsOf(agg.byReason);
      agg.byReason.forEach((k, v) {
        ledgerByReason[k] = (ledgerByReason[k] ?? 0) + v;
      });
    }

    emit(StockLeakProgress(
      percent: 1.0,
      phase: 'Pengecekan selesai',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));

    // Urutkan selisih terbesar dulu.
    mismatches.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

    return StockLeakReport(
      checkedProducts: checked,
      mismatches: mismatches,
      missingSkuCount: missingSku,
      openTransitQty: transit.total,
      stockByToko: stockByToko,
      stockLinesByToko: stockLinesByToko,
      transitByStatus: transit.byStatus,
      transitByTujuan: transit.byTujuan,
      openTransitItems: transit.items,
      soldByToko30d: sold.byToko,
      soldLinesByToko30d: sold.linesByToko,
      ledgerByReason: ledgerByReason,
      writeOffQty: writeOffQty,
      generatedAt: DateTime.now(),
    );
  }

  StockLeakReport? _reportFromScanRpc(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    if (!m.containsKey('checked') && !m.containsKey('mismatches')) {
      return null;
    }
    final mismatches = <StockIntegrityIssue>[];
    final rawIssues = m['mismatches'];
    if (rawIssues is List) {
      for (final row in rawIssues) {
        if (row is! Map) continue;
        final r = Map<String, dynamic>.from(row);
        final stock = StockLeakRules.stockOf(r['stock']);
        final ledger = StockLeakRules.deltaOf(r['ledger_sum']);
        mismatches.add(StockIntegrityIssue(
          sku: (r['sku'] ?? '').toString(),
          tokoId: StockLeakRules.tokoKey(r['toko_id']),
          stock: stock,
          ledgerSum: ledger,
          delta: StockLeakRules.deltaOf(r['delta'] ?? (stock - ledger)),
          productId: r['product_id']?.toString(),
          nama: r['nama']?.toString(),
          ledgerByReason: StockLeakRules.reasonMapOf(r['ledger_by_reason']),
        ));
      }
    }
    mismatches.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

    final stockByToko = StockLeakRules.reasonMapOf(m['stock_by_toko'])
        .map((k, v) => MapEntry(StockLeakRules.tokoKey(k), StockLeakRules.stockOf(v)));
    final soldByToko = StockLeakRules.reasonMapOf(m['sold_by_toko'])
        .map((k, v) => MapEntry(StockLeakRules.tokoKey(k), StockLeakRules.stockOf(v)));

    final stockLines = <String, List<StockSkuQtyLine>>{};
    final soldLines = <String, List<StockSkuQtyLine>>{};
    void takeLines(Object? rawLines, Map<String, List<StockSkuQtyLine>> dest) {
      if (rawLines is! List) return;
      for (final row in rawLines) {
        if (row is! Map) continue;
        final r = Map<String, dynamic>.from(row);
        final toko = StockLeakRules.tokoKey(r['toko_id']);
        final qty = StockLeakRules.stockOf(r['qty']);
        if (toko.isEmpty || qty <= 0) continue;
        dest.putIfAbsent(toko, () => []).add(StockSkuQtyLine(
              sku: (r['sku'] ?? '-').toString(),
              nama: (r['nama'] ?? r['sku'] ?? '-').toString(),
              qty: qty,
            ));
      }
    }

    takeLines(m['stock_lines'], stockLines);
    takeLines(m['sold_lines'], soldLines);

    final reasons = StockLeakRules.reasonMapOf(m['ledger_by_reason']);
    var writeOff = StockLeakRules.stockOf(m['write_off_qty']);
    if (writeOff <= 0) writeOff = StockLeakRules.writeOffPcsOf(reasons);

    return StockLeakReport(
      checkedProducts: StockLeakRules.stockOf(m['checked']),
      mismatches: mismatches,
      missingSkuCount: StockLeakRules.stockOf(m['missing_sku']),
      openTransitQty: 0,
      stockByToko: stockByToko,
      stockLinesByToko: stockLines,
      soldByToko30d: soldByToko,
      soldLinesByToko30d: soldLines,
      ledgerByReason: reasons,
      writeOffQty: writeOff,
      generatedAt: DateTime.now(),
    );
  }

  /// Muat seluruh ledger sekali, agregat di memori per SKU|toko.
  Future<Map<String, _LedgerAgg>> _loadLedgerIndex({
    required void Function(int loadedRows, double approx) onProgress,
    int pageSize = 1000,
    List<String>? tokoIds,
  }) async {
    final sums = <String, int>{};
    final byReason = <String, Map<String, int>>{};
    var offset = 0;
    var loaded = 0;

    while (true) {
      var pageQ = _client
          .from('product_stock_ledger')
          .select('sku, toko_id, qty_delta, reason');
      if (tokoIds != null && tokoIds.isNotEmpty) {
        pageQ = pageQ.inFilter('toko_id', tokoIds);
      }
      final page = await pageQ.range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(page);
      if (rows.isEmpty) break;

      for (final r in rows) {
        final sku = (r['sku'] ?? '').toString().trim();
        final toko = StockLeakRules.tokoKey(r['toko_id']);
        if (sku.isEmpty || toko.isEmpty) continue;
        final key = _key(sku, toko);
        final d = StockLeakRules.deltaOf(r['qty_delta']);
        final reason = (r['reason'] ?? 'UNKNOWN').toString().toUpperCase();
        sums[key] = (sums[key] ?? 0) + d;
        final reasonMap = byReason.putIfAbsent(key, () => {});
        reasonMap[reason] = (reasonMap[reason] ?? 0) + d;
      }

      loaded += rows.length;
      // Estimasi kasar: makin banyak page, makin dekat 1.0 (cap di 0.95 sampai break).
      final approx = (1 - (1 / (1 + loaded / 5000))).clamp(0.0, 0.95);
      onProgress(loaded, approx);

      if (rows.length < pageSize) break;
      offset += pageSize;
      if (offset > 120000) break;
    }

    onProgress(loaded, 1.0);

    final out = <String, _LedgerAgg>{};
    for (final e in sums.entries) {
      out[e.key] = _LedgerAgg(
        sum: e.value,
        byReason: Map<String, int>.from(byReason[e.key] ?? const {}),
      );
    }
    return out;
  }

  Future<_TransitAgg> _openTransitBreakdown() async {
    final rows = await _client
        .from('stock_move_history')
        .select(
          'id, product_name, dari_lokasi, ke_lokasi, jumlah, status, created_at, tipe',
        )
        .inFilter('status', ['PREPARING', 'TRANSIT', 'PENDING', 'WAITING'])
        .order('created_at', ascending: false)
        .limit(200);
    var total = 0;
    final byStatus = <String, int>{};
    final byTujuan = <String, int>{};
    final items = <StockOpenTransitItem>[];
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final qty = StockLeakRules.stockOf(r['jumlah']);
      final status = (r['status'] ?? 'UNKNOWN').toString().toUpperCase();
      final tujuan = (r['ke_lokasi'] ?? '-').toString().toUpperCase();
      final dari = (r['dari_lokasi'] ?? '-').toString().toUpperCase();
      total += qty;
      byStatus[status] = (byStatus[status] ?? 0) + qty;
      byTujuan[tujuan] = (byTujuan[tujuan] ?? 0) + qty;
      items.add(StockOpenTransitItem(
        id: r['id']?.toString() ?? '',
        resi: (r['product_name'] ?? '-').toString(),
        fromToko: dari,
        toToko: tujuan,
        status: status,
        qty: qty,
        createdAt: r['created_at']?.toString(),
        tipe: (r['tipe'] ?? '').toString(),
      ));
    }
    return _TransitAgg(
      total: total,
      byStatus: byStatus,
      byTujuan: byTujuan,
      items: items,
    );
  }

  Future<_SoldAgg> _soldBreakdownLast30d({
    int pageSize = 1000,
    List<String>? tokoIds,
  }) async {
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();
    final byToko = <String, int>{};
    final skuByToko = <String, Map<String, int>>{};
    var offset = 0;
    while (true) {
      var pageQ = _client
          .from('product_stock_ledger')
          .select('toko_id, qty_delta, sku')
          .eq('reason', 'SALE')
          .gte('created_at', since);
      if (tokoIds != null && tokoIds.isNotEmpty) {
        pageQ = pageQ.inFilter('toko_id', tokoIds);
      }
      final page = await pageQ.range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(page);
      if (rows.isEmpty) break;
      for (final r in rows) {
        final toko = StockLeakRules.tokoKey(r['toko_id']);
        if (toko.isEmpty) continue;
        final d = StockLeakRules.writeOffPcs(r['qty_delta']);
        final sku = (r['sku'] ?? '-').toString();
        byToko[toko] = (byToko[toko] ?? 0) + d;
        final skuMap = skuByToko.putIfAbsent(toko, () => {});
        skuMap[sku] = (skuMap[sku] ?? 0) + d;
      }
      if (rows.length < pageSize) break;
      offset += pageSize;
      if (offset > 50000) break;
    }

    final linesByToko = <String, List<StockSkuQtyLine>>{};
    for (final entry in skuByToko.entries) {
      final lines = entry.value.entries
          .map((e) => StockSkuQtyLine(sku: e.key, nama: e.key, qty: e.value))
          .toList()
        ..sort((a, b) => b.qty.compareTo(a.qty));
      linesByToko[entry.key] = lines.take(40).toList();
    }
    return _SoldAgg(byToko: byToko, linesByToko: linesByToko);
  }

  Future<Map<String, dynamic>> recognizeVariance({
    required StockIntegrityIssue issue,
    required String alasan,
    String? actorNama,
  }) async {
    if (!StockLeakRules.adaSelisih(issue.delta)) {
      return {'ok': true, 'changed': false};
    }
    if (!StockLeakRules.alasanCukup(alasan)) {
      throw 'Alasan terlalu singkat (min. ${StockLeakRules.minAlasanChars} karakter).';
    }
    try {
      final res = await _client.rpc('recognize_stock_variance', params: {
        'p_toko': issue.tokoId.trim().toUpperCase(),
        'p_sku': issue.sku.trim(),
        'p_alasan_text': alasan.trim(),
        'p_actor_id': _client.auth.currentUser?.id,
        'p_actor_nama': actorNama ?? _client.auth.currentUser?.email,
      });
      final map = Map<String, dynamic>.from(res as Map);
      final before = StockLeakRules.stockOf(map['stock_before'] ?? map['stock']);
      final after = StockLeakRules.stockOf(map['stock_after'] ?? map['stock']);
      if (!StockLeakRules.stokTetap(stockBefore: before, stockAfter: after)) {
        throw 'Rekognisi tidak boleh mengubah stok rak.';
      }
      return map;
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal catat selisih kebocoran.' : msg;
    }
  }

  @Deprecated('Gunakan runLeakCheck()')
  Future<Map<String, dynamic>> summary() async {
    final report = await runLeakCheck();
    return {
      'products_missing_sku': report.missingSkuCount,
      'stock_ledger_mismatches': report.mismatches.length,
      'open_transit_qty': report.openTransitQty,
      'checked': report.checkedProducts,
      'verdict': report.verdict,
      'stock_by_toko': report.stockByToko,
      'sold_by_toko_30d': report.soldByToko30d,
      'issues': report.mismatches
          .take(50)
          .map((e) => {
                'sku': e.sku,
                'toko': e.tokoId,
                'nama': e.nama,
                'stock': e.stock,
                'ledger_sum': e.ledgerSum,
                'delta': e.delta,
                'diagnosis': e.diagnosis,
                'ledger_by_reason': e.ledgerByReason,
              })
          .toList(),
    };
  }
}

class _LedgerAgg {
  const _LedgerAgg({required this.sum, required this.byReason});
  final int sum;
  final Map<String, int> byReason;
}

class _TransitAgg {
  const _TransitAgg({
    required this.total,
    required this.byStatus,
    required this.byTujuan,
    required this.items,
  });
  final int total;
  final Map<String, int> byStatus;
  final Map<String, int> byTujuan;
  final List<StockOpenTransitItem> items;
}

class _SoldAgg {
  const _SoldAgg({
    required this.byToko,
    required this.linesByToko,
  });
  final Map<String, int> byToko;
  final Map<String, List<StockSkuQtyLine>> linesByToko;
}
