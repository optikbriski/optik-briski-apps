import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optik_b_riski/shared/training/training_curriculum.dart';
import 'package:optik_b_riski/shared/training/training_http_client.dart';
import 'package:optik_b_riski/shared/training/training_mode.dart';
import 'package:optik_b_riski/shared/training/training_ops_sync.dart';
import 'package:optik_b_riski/shared/training/training_sandbox_store.dart';

class _FailIfCalledClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    fail('Network must not be called: ${request.method} ${request.url}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await TrainingMode.instance.debugDeactivateForTest();
  });

  test('POS checkout syncs History + Finance + Warranty + stock', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'CIMAHI');
    await TrainingCurriculum.seedFreshWorld(
      tokoId: 'CIMAHI',
      profile: {
        'id': 'admin_tr',
        'toko_id': 'CIMAHI',
        'role': 'admin_toko',
        'nama': 'Admin Latihan',
      },
    );

    final frame = (await TrainingSandboxStore.instance.select('products'))
        .firstWhere(
          (p) => p['toko_id'] == 'CIMAHI' && p['sku'] == 'TR-FR-001',
        );
    final stockBefore = int.parse('${frame['stock']}');

    final report = await TrainingOpsSync.runSimulatedCheckout(
      tokoId: 'CIMAHI',
      productId: frame['id'].toString(),
      qty: 2,
      harga: int.parse('${frame['harga']}'),
      namaPelanggan: 'Budi Latihan',
    );

    expect(report.allOk, isTrue, reason: report.errors.join('; '));
    expect(report.historyOk, isTrue);
    expect(report.financeOk, isTrue);
    expect(report.warrantyOk, isTrue);
    expect(report.warrantyCards, greaterThanOrEqualTo(1));
    expect(report.stockOk, isTrue);

    final frameAfter = await TrainingSandboxStore.instance.selectOne(
      'products',
      where: {'id': frame['id']},
    );
    expect(int.parse('${frameAfter!['stock']}'), stockBefore - 2);

    final sales = await TrainingSandboxStore.instance
        .select('sales', where: {'toko_id': 'CIMAHI'});
    expect(sales.any((s) => s['nama_pelanggan'] == 'Budi Latihan'), isTrue);

    final finance = await TrainingSandboxStore.instance
        .select('finance_transactions', where: {'toko_id': 'CIMAHI'});
    expect(
      finance.any((f) => (f['deskripsi']?.toString() ?? '').contains('Budi')),
      isTrue,
    );

    final kartu = await TrainingSandboxStore.instance.select('garansi_kartu');
    expect(kartu.any((k) => k['jenis_garansi'] == 'frame'), isTrue);
  });

  test('HTTP GET history/finance/garansi never hits network after sale',
      () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'CIMAHI');
    await TrainingCurriculum.seedFreshWorld(
      tokoId: 'CIMAHI',
      profile: {'id': 'a', 'toko_id': 'CIMAHI', 'role': 'admin_toko'},
    );
    final frame = (await TrainingSandboxStore.instance.select('products'))
        .firstWhere(
          (p) => p['toko_id'] == 'CIMAHI' && p['sku'] == 'TR-FR-001',
        );
    await TrainingOpsSync.runSimulatedCheckout(
      tokoId: 'CIMAHI',
      productId: frame['id'].toString(),
      qty: 1,
      harga: 350000,
    );

    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    Future<List> getTable(String table, {String? query}) async {
      final uri = Uri.parse(
        'https://example.supabase.co/rest/v1/$table${query ?? ''}',
      );
      final req = http.Request('GET', uri);
      final streamed = await client.send(req);
      final resp = await http.Response.fromStream(streamed);
      expect(resp.statusCode, 200);
      return jsonDecode(resp.body) as List;
    }

    final sales = await getTable(
      'sales',
      query: '?toko_id=eq.CIMAHI&order=created_at.desc',
    );
    expect(sales, isNotEmpty);

    final finance = await getTable(
      'finance_transactions',
      query: '?toko_id=eq.CIMAHI&order=tanggal_transaksi.desc',
    );
    expect(finance, isNotEmpty);

    final garansi = await getTable(
      'garansi_kartu',
      query: '?toko_id=eq.CIMAHI&order=created_at.desc',
    );
    expect(garansi, isNotEmpty);

    final products = await getTable(
      'products',
      query: '?toko_id=eq.CIMAHI',
    );
    expect(products, isNotEmpty);

    expect(inner.calls, 0);
  });

  test('upsert on_conflict merges garansi_kartu without network', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'CIMAHI');
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    Future<void> upsert(Map<String, dynamic> row) async {
      final req = http.Request(
        'POST',
        Uri.parse(
          'https://example.supabase.co/rest/v1/garansi_kartu?on_conflict=sale_item_id',
        ),
      );
      req.headers['Content-Type'] = 'application/json';
      req.headers['Prefer'] = 'resolution=merge-duplicates,return=representation';
      req.body = jsonEncode(row);
      final streamed = await client.send(req);
      final resp = await http.Response.fromStream(streamed);
      expect(resp.statusCode, anyOf(200, 201));
    }

    await upsert({
      'sale_item_id': 'si_1',
      'sale_id': 'sale_1',
      'toko_id': 'CIMAHI',
      'no_invoice': 'INV-1',
      'nama_produk': 'Frame A',
      'jenis_garansi': 'frame',
      'status': 'menunggu_ambil',
    });
    await upsert({
      'sale_item_id': 'si_1',
      'sale_id': 'sale_1',
      'toko_id': 'CIMAHI',
      'no_invoice': 'INV-1',
      'nama_produk': 'Frame A Updated',
      'jenis_garansi': 'frame',
      'status': 'menunggu_ambil',
    });

    final rows = await TrainingSandboxStore.instance.select('garansi_kartu');
    expect(rows.length, 1);
    expect(rows.first['nama_produk'], 'Frame A Updated');
    expect(inner.calls, 0);
  });

  test('re-enter training starts from zero (wipe then seed)', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'CIMAHI');
    await TrainingCurriculum.seedFreshWorld(
      tokoId: 'CIMAHI',
      profile: {'id': 'a', 'toko_id': 'CIMAHI', 'role': 'admin_toko'},
    );
    final frame = (await TrainingSandboxStore.instance.select('products'))
        .firstWhere(
          (p) => p['toko_id'] == 'CIMAHI' && p['sku'] == 'TR-FR-001',
        );
    await TrainingOpsSync.runSimulatedCheckout(
      tokoId: 'CIMAHI',
      productId: frame['id'].toString(),
      qty: 1,
      harga: 350000,
    );
    expect(
      await TrainingSandboxStore.instance.select('sales'),
      isNotEmpty,
    );

    await TrainingMode.instance.debugDeactivateForTest();
    await TrainingMode.instance.debugActivateForTest(tokoId: 'CIMAHI');
    await TrainingCurriculum.seedFreshWorld(
      tokoId: 'CIMAHI',
      profile: {'id': 'a', 'toko_id': 'CIMAHI', 'role': 'admin_toko'},
    );

    expect(await TrainingSandboxStore.instance.select('sales'), isEmpty);
    expect(
      await TrainingSandboxStore.instance.select('finance_transactions'),
      isEmpty,
    );
    expect(
      await TrainingSandboxStore.instance.select('garansi_kartu'),
      isEmpty,
    );
    final seeded = await TrainingSandboxStore.instance.select('products');
    expect(seeded, isNotEmpty);
  });
}
