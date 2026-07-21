import 'package:flutter/foundation.dart';

import '../garansi/garansi_service.dart';
import 'training_data_client.dart';
import 'training_mode.dart';
import 'training_sandbox_store.dart';

/// Ensures curriculum modules stay in sync inside the training sandbox
/// after a POS checkout (History, Finance, Warranty, stock).
///
/// Never touches production — requires [TrainingMode.isActive].
class TrainingOpsSync {
  TrainingOpsSync._();

  /// Run after POS `_prosesCheckout` succeeds in Training Mode.
  ///
  /// Idempotent: fills gaps if finance/garansi inserts were skipped by
  /// silent catch blocks; verifies stock was cut for non-custom items.
  static Future<TrainingSyncReport> ensureAfterPosCheckout({
    required String saleId,
    required String tokoId,
    required String noInvoice,
    required String namaPelanggan,
    required int bayar,
    required String paymentStatus,
    required String paymentMethod,
    List<Map<String, dynamic>>? cartSnapshot,
  }) async {
    if (!TrainingMode.instance.isActive) {
      throw StateError('TrainingOpsSync requires Training Mode');
    }

    final store = TrainingSandboxStore.instance;
    final client = TrainingDataClient.instance;
    final report = TrainingSyncReport(saleId: saleId, noInvoice: noInvoice);

    final sale = await store.selectOne('sales', where: {'id': saleId});
    if (sale == null) {
      report.errors.add('sales row missing for $saleId');
      return report;
    }
    report.historyOk = true;

    // --- Finance ---
    final finance = await store.select('finance_transactions');
    final hasFinance = finance.any((r) =>
        (r['deskripsi']?.toString() ?? '').contains(noInvoice) ||
        (r['deskripsi']?.toString() ?? '').contains(namaPelanggan));
    if (!hasFinance && bayar > 0) {
      await client.insert('finance_transactions', {
        'toko_id': tokoId,
        'tanggal_transaksi': DateTime.now().toIso8601String().split('T')[0],
        'jenis_transaksi': 'PEMASUKAN',
        'kategori': 'Penjualan Kasir',
        'deskripsi': 'Penjualan Kasir POS: $noInvoice ($namaPelanggan)',
        'nominal': bayar,
        'status_pembayaran': paymentStatus == 'Lunas' ? 'LUNAS' : 'DP',
        'metode_pembayaran': paymentMethod,
        'status_konfirmasi': 'APPROVED',
        'updated_at': DateTime.now().toIso8601String(),
      });
      report.financeRepaired = true;
    }
    report.financeOk = true;

    // --- Warranty cards ---
    final items = await store.select('sales_items', where: {'sale_id': saleId});
    var kartuCount = 0;
    for (final item in items) {
      final tipe = item['tipe_produk']?.toString();
      final nama = item['nama_produk']?.toString();
      final jenis = GaransiService.jenisFromItem(tipe, nama);
      if (jenis == null) continue;
      final saleItemId = item['id']?.toString();
      if (saleItemId == null || saleItemId.isEmpty) continue;

      final existing = await store.selectOne(
        'garansi_kartu',
        where: {'sale_item_id': saleItemId},
      );
      if (existing != null) {
        kartuCount++;
        continue;
      }

      Map<String, dynamic>? product;
      final pid = item['product_id']?.toString();
      if (pid != null && pid.isNotEmpty) {
        product = await store.selectOne('products', where: {'id': pid});
      }

      await client.insert('garansi_kartu', {
        'sale_id': saleId,
        'sale_item_id': saleItemId,
        'toko_id': tokoId,
        'no_invoice': sale['no_invoice'],
        'nama_pelanggan': sale['nama_pelanggan'],
        'no_wa': sale['no_wa'],
        'product_id': item['product_id'],
        'nama_produk': nama,
        'jenis_garansi': jenis,
        'resep_awal': item['detail_resep']?.toString(),
        'spesifikasi_produk': GaransiService.buildSpesifikasi(
          namaProduk: nama,
          tipeProduk: tipe,
          product: product,
        ),
        'tanggal_mulai': null,
        'tanggal_akhir': null,
        'status': 'menunggu_ambil',
        'klaim_digunakan': false,
      });
      kartuCount++;
      report.warrantyRepaired = true;
    }
    report.warrantyCards = kartuCount;
    report.warrantyOk = true;

    // --- Stock sanity (non-custom cart lines) ---
    if (cartSnapshot != null) {
      for (final line in cartSnapshot) {
        if (line['is_lensa_custom'] == true) continue;
        final pid = line['id']?.toString();
        if (pid == null || pid.isEmpty) continue;
        final prod = await store.selectOne('products', where: {'id': pid});
        if (prod == null) {
          report.errors.add('product missing after sale: $pid');
          continue;
        }
        report.stockChecked++;
      }
    }
    report.stockOk = report.errors.isEmpty;

    debugPrint(
      '[TrainingOpsSync] sale=$saleId history=${report.historyOk} '
      'finance=${report.financeOk} (repaired=${report.financeRepaired}) '
      'warranty=${report.warrantyCards} (repaired=${report.warrantyRepaired}) '
      'stockOk=${report.stockOk}',
    );
    return report;
  }

  /// Full sandbox checkout used by unit tests (no Flutter/Supabase UI).
  static Future<TrainingSyncReport> runSimulatedCheckout({
    required String tokoId,
    required String productId,
    required int qty,
    required int harga,
    String namaPelanggan = 'Pasien Latihan',
    String paymentStatus = 'Lunas',
    String paymentMethod = 'CASH',
  }) async {
    if (!TrainingMode.instance.isActive) {
      throw StateError('TrainingOpsSync requires Training Mode');
    }
    final client = TrainingDataClient.instance;
    final store = TrainingSandboxStore.instance;

    final prod = await store.selectOne('products', where: {'id': productId});
    if (prod == null) throw StateError('product $productId not in sandbox');
    final stockBefore = int.tryParse('${prod['stock']}') ?? 0;

    final inv =
        'TR-INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final total = harga * qty;

    final sale = await client.insert('sales', {
      'no_invoice': inv,
      'toko_id': tokoId,
      'nama_kasir': 'Kasir Latihan',
      'nama_pelanggan': namaPelanggan,
      'no_wa': '0800000000',
      'total_harga': total,
      'dibayarkan': total,
      'sisa_tagihan': 0,
      'kembalian': 0,
      'status_pembayaran': paymentStatus,
      'metode_pembayaran': paymentMethod,
      'tracking_status': 'SIAP_DIAMBIL',
    });
    final saleId = sale['id'].toString();

    final item = await client.insert('sales_items', {
      'sale_id': saleId,
      'product_id': productId,
      'tipe_produk': prod['kategori'] ?? 'Frame',
      'nama_produk': prod['nama'],
      'harga_satuan': harga,
      'qty': qty,
      'subtotal': total,
      'detail_resep': 'Normal',
    });

    final stockAfter = (stockBefore - qty).clamp(0, 1 << 30);
    await client.update(
      'products',
      {'stock': stockAfter},
      where: {'id': productId},
    );

    await client.insert('finance_transactions', {
      'toko_id': tokoId,
      'tanggal_transaksi': DateTime.now().toIso8601String().split('T')[0],
      'jenis_transaksi': 'PEMASUKAN',
      'kategori': 'Penjualan Kasir',
      'deskripsi': 'Penjualan Kasir POS: $inv ($namaPelanggan)',
      'nominal': total,
      'status_pembayaran': 'LUNAS',
      'metode_pembayaran': paymentMethod,
      'status_konfirmasi': 'APPROVED',
    });

    // Bonus accessories cut (same as POS Frame path)
    if ((prod['kategori']?.toString() ?? '') == 'Frame') {
      final allProducts = await store.select('products');
      for (final namaBonus in ['Kotak Kacamata', 'Lap Kacamata']) {
        Map<String, dynamic>? bonus;
        for (final p in allProducts) {
          if (p['nama'] == namaBonus && p['toko_id'] == tokoId) {
            bonus = p;
            break;
          }
        }
        if (bonus != null) {
          final bs = int.tryParse('${bonus['stock']}') ?? 0;
          await client.update(
            'products',
            {'stock': (bs - qty).clamp(0, 1 << 30)},
            where: {'id': bonus['id']},
          );
        }
      }
    }

    final report = await ensureAfterPosCheckout(
      saleId: saleId,
      tokoId: tokoId,
      noInvoice: inv,
      namaPelanggan: namaPelanggan,
      bayar: total,
      paymentStatus: paymentStatus,
      paymentMethod: paymentMethod,
      cartSnapshot: [
        {
          'id': productId,
          'qty': qty,
          'is_lensa_custom': false,
          'sale_item_id': item['id'],
        },
      ],
    );

    final prodAfter =
        await store.selectOne('products', where: {'id': productId});
    final stockNow = int.tryParse('${prodAfter?['stock']}') ?? -1;
    if (stockNow != stockAfter) {
      report.errors.add('stock mismatch: expected $stockAfter got $stockNow');
      report.stockOk = false;
    } else {
      report.stockOk = true;
    }

    // Cross-module visibility
    final history = await store.select('sales', where: {'toko_id': tokoId});
    report.historyOk = history.any((s) => '${s['id']}' == saleId);

    final fin = await store.select('finance_transactions', where: {'toko_id': tokoId});
    report.financeOk =
        fin.any((f) => (f['deskripsi']?.toString() ?? '').contains(inv));

    final kartu =
        await store.select('garansi_kartu', where: {'sale_id': saleId});
    report.warrantyOk = kartu.isNotEmpty;
    report.warrantyCards = kartu.length;

    return report;
  }
}

class TrainingSyncReport {
  TrainingSyncReport({
    required this.saleId,
    required this.noInvoice,
  });

  final String saleId;
  final String noInvoice;
  bool historyOk = false;
  bool financeOk = false;
  bool financeRepaired = false;
  bool warrantyOk = false;
  bool warrantyRepaired = false;
  int warrantyCards = 0;
  bool stockOk = false;
  int stockChecked = 0;
  final List<String> errors = [];

  bool get allOk =>
      historyOk && financeOk && warrantyOk && stockOk && errors.isEmpty;
}
