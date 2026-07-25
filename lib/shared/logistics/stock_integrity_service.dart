import 'package:supabase_flutter/supabase_flutter.dart';

class StockIntegrityIssue {
  StockIntegrityIssue({
    required this.sku,
    required this.tokoId,
    required this.stock,
    required this.ledgerSum,
    required this.delta,
    this.productId,
    this.nama,
  });

  final String sku;
  final String tokoId;
  final int stock;
  final int ledgerSum;

  /// stock - ledgerSum. Positif = stok lebih dari jejak (ada yang masuk tanpa ledger).
  /// Negatif = stok kurang dari jejak (ada yang keluar tanpa ledger / stok dipotong liar).
  final int delta;
  final String? productId;
  final String? nama;

  String get diagnosis {
    if (delta > 0) {
      return 'Stok di sistem +$delta lebih banyak dari jejak ledger '
          '(ada penambahan tanpa alasan tercatat).';
    }
    if (delta < 0) {
      return 'Stok di sistem $delta lebih sedikit dari jejak ledger '
          '(ada pengurangan tanpa alasan tercatat).';
    }
    return 'Sinkron.';
  }
}

class StockLeakReport {
  StockLeakReport({
    required this.checkedProducts,
    required this.mismatches,
    required this.missingSkuCount,
    required this.openTransitQty,
    required this.generatedAt,
  });

  final int checkedProducts;
  final List<StockIntegrityIssue> mismatches;
  final int missingSkuCount;

  /// Qty masih di perjalanan (TRANSFER_OUT sudah, belum TRANSFER_IN) — ini normal, bukan bocor.
  final int openTransitQty;
  final DateTime generatedAt;

  bool get isClean => mismatches.isEmpty && missingSkuCount == 0;

  String get verdict {
    if (isClean) {
      return 'AMAN — tidak ditemukan kebocoran stok pada pengecekan ini.';
    }
    final parts = <String>[];
    if (mismatches.isNotEmpty) {
      parts.add('${mismatches.length} selisih stok vs ledger');
    }
    if (missingSkuCount > 0) {
      parts.add('$missingSkuCount produk SKU lemah/NOSKU');
    }
    return 'ADA INDIKASI BOCOR — ${parts.join(', ')}.';
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

  /// Full scan dengan callback progress (persen nyata per baris produk).
  Future<StockLeakReport> runLeakCheck({
    int pageSize = 500,
    StockLeakProgressCallback? onProgress,
  }) async {
    void emit(StockLeakProgress p) => onProgress?.call(p);

    emit(const StockLeakProgress(
      percent: 0.02,
      phase: 'Menyiapkan daftar produk…',
    ));

    final allRows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('products')
          .select('id, sku, toko_id, stock, nama')
          .order('sku')
          .range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(page);
      if (rows.isEmpty) break;
      allRows.addAll(rows);
      emit(StockLeakProgress(
        percent: 0.04 + (0.06 * (allRows.length / (allRows.length + pageSize))),
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
      percent: 0.10,
      phase: total == 0 ? 'Tidak ada produk' : 'Memindai $total baris produk…',
      checked: 0,
      total: total,
    ));

    final mismatches = <StockIntegrityIssue>[];
    var checked = 0;
    var missingSku = 0;

    for (final p in allRows) {
      checked++;
      final sku = (p['sku'] ?? '').toString().trim();
      final toko = (p['toko_id'] ?? '').toString().toUpperCase();
      final nama = (p['nama'] ?? sku).toString();

      if (sku.isEmpty || sku.startsWith('NOSKU-')) {
        missingSku++;
      }

      if (sku.isNotEmpty) {
        final stock = int.tryParse(p['stock']?.toString() ?? '0') ?? 0;
        final ledgerSum = await _sumLedger(sku: sku, tokoId: toko);
        if (ledgerSum != stock) {
          mismatches.add(StockIntegrityIssue(
            sku: sku,
            tokoId: toko,
            stock: stock,
            ledgerSum: ledgerSum,
            delta: stock - ledgerSum,
            productId: p['id']?.toString(),
            nama: p['nama']?.toString(),
          ));
        }
      }

      // 10% → 90% untuk pemindaian baris
      final scanPct = total == 0 ? 0.9 : 0.10 + (0.80 * (checked / total));
      emit(StockLeakProgress(
        percent: scanPct,
        phase: 'Memverifikasi jejak ledger…',
        checked: checked,
        total: total,
        currentLabel: '$nama · $toko',
        foundLeaks: mismatches.length,
      ));
    }

    emit(StockLeakProgress(
      percent: 0.92,
      phase: 'Menghitung paket transit…',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));

    final openTransit = await _openTransitQty();

    emit(StockLeakProgress(
      percent: 1.0,
      phase: 'Pengecekan selesai',
      checked: checked,
      total: total,
      foundLeaks: mismatches.length,
    ));

    return StockLeakReport(
      checkedProducts: checked,
      mismatches: mismatches,
      missingSkuCount: missingSku,
      openTransitQty: openTransit,
      generatedAt: DateTime.now(),
    );
  }

  Future<int> _sumLedger({required String sku, required String tokoId}) async {
    final ledger = await _client
        .from('product_stock_ledger')
        .select('qty_delta')
        .eq('sku', sku)
        .eq('toko_id', tokoId);
    var sum = 0;
    for (final l in List<Map<String, dynamic>>.from(ledger)) {
      sum += int.tryParse(l['qty_delta']?.toString() ?? '0') ?? 0;
    }
    return sum;
  }

  Future<int> _openTransitQty() async {
    final rows = await _client
        .from('stock_move_history')
        .select('jumlah, status')
        .inFilter('status', ['PREPARING', 'TRANSIT', 'PENDING', 'WAITING']);
    var total = 0;
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      total += int.tryParse(r['jumlah']?.toString() ?? '0') ?? 0;
    }
    return total;
  }

  Future<Map<String, dynamic>> recognizeVariance({
    required StockIntegrityIssue issue,
    required String alasan,
    String? actorNama,
  }) async {
    if (issue.delta == 0) {
      return {'ok': true, 'changed': false};
    }
    if (alasan.trim().isEmpty) {
      throw 'Alasan wajib diisi.';
    }
    final res = await _client.rpc('recognize_stock_variance', params: {
      'p_toko': issue.tokoId,
      'p_sku': issue.sku,
      'p_alasan_text': alasan.trim(),
      'p_actor_id': _client.auth.currentUser?.id,
      'p_actor_nama': actorNama ?? _client.auth.currentUser?.email,
    });
    return Map<String, dynamic>.from(res as Map);
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
              })
          .toList(),
    };
  }
}
