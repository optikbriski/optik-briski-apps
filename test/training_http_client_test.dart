import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optik_b_riski/shared/training/training_approval_simulator.dart';
import 'package:optik_b_riski/shared/training/training_curriculum.dart';
import 'package:optik_b_riski/shared/training/training_data_client.dart';
import 'package:optik_b_riski/shared/training/training_http_client.dart';
import 'package:optik_b_riski/shared/training/training_mode.dart';
import 'package:optik_b_riski/shared/training/training_rpc_stubs.dart';
import 'package:optik_b_riski/shared/training/training_sandbox_store.dart';

/// Inner client that fails if any request reaches the network.
class _FailIfCalledClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    fail('Network must not be called during training mutation: '
        '${request.method} ${request.url}');
  }
}

/// Inner client that records calls and returns empty JSON lists for GETs.
class _RecordingClient extends http.BaseClient {
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add('${request.method} ${request.url.path}');
    if (request.method.toUpperCase() == 'GET') {
      final body = utf8.encode('[]');
      return http.StreamedResponse(
        Stream.value(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    fail('Unexpected non-GET reached network: ${request.method}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await TrainingMode.instance.debugDeactivateForTest();
  });

  test('REST POST while training never hits network and stores locally',
      () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    final req = http.Request(
      'POST',
      Uri.parse('https://example.supabase.co/rest/v1/pengaduan'),
    );
    req.headers['Content-Type'] = 'application/json';
    req.headers['Prefer'] = 'return=representation';
    req.body = jsonEncode({
      'toko_id': 'T1',
      'isi': 'latihan',
      'status': 'OPEN',
    });

    final before = TrainingHttpClient.debugBlockedMutations;
    final streamed = await client.send(req);
    final resp = await http.Response.fromStream(streamed);

    expect(inner.calls, 0);
    expect(TrainingHttpClient.debugBlockedMutations, greaterThan(before));
    expect(resp.statusCode, anyOf(200, 201));
    final rows = await TrainingSandboxStore.instance.select('pengaduan');
    expect(rows, isNotEmpty);
    expect(rows.last['isi'], 'latihan');
  });

  test('Storage upload while training never hits network', () async {
    await TrainingMode.instance.debugActivateForTest();
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    final req = http.Request(
      'POST',
      Uri.parse(
        'https://example.supabase.co/storage/v1/object/pengaduan_photos/a/b.jpg',
      ),
    );
    req.bodyBytes = utf8.encode('fake-image');

    final streamed = await client.send(req);
    final resp = await http.Response.fromStream(streamed);

    expect(inner.calls, 0);
    expect(resp.statusCode, 200);
    final map = jsonDecode(resp.body) as Map;
    expect(map['Key'], contains('pengaduan_photos'));
    final bytes = await TrainingSandboxStore.instance
        .readFile('pengaduan_photos/a/b.jpg');
    expect(bytes, isNotNull);
  });

  test('RPC mutating stub never hits network', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T9');
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    final req = http.Request(
      'POST',
      Uri.parse(
        'https://example.supabase.co/rest/v1/rpc/issue_attendance_qr_token',
      ),
    );
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode({'p_toko_id': 'T9', 'p_ttl_seconds': 60});

    final streamed = await client.send(req);
    final resp = await http.Response.fromStream(streamed);
    expect(inner.calls, 0);
    expect(resp.statusCode, 200);
    final map = jsonDecode(resp.body) as Map;
    expect(map['payload'], isNotEmpty);
    expect(map['toko_id'], 'T9');
  });

  test('edge function POST while training never hits network', () async {
    await TrainingMode.instance.debugActivateForTest();
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    final req = http.Request(
      'POST',
      Uri.parse('https://example.supabase.co/functions/v1/face-match'),
    );
    req.body = '{}';

    final streamed = await client.send(req);
    final resp = await http.Response.fromStream(streamed);
    expect(inner.calls, 0);
    expect(resp.statusCode, 200);
    final map = jsonDecode(resp.body) as Map;
    expect(map['training'], isTrue);
  });

  test('PATCH/PUT/DELETE while training never hit network', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    // Seed a row locally first.
    final seeded = await TrainingSandboxStore.instance.insert('pengaduan', {
      'toko_id': 'T1',
      'isi': 'seed',
      'status': 'OPEN',
    });

    for (final method in ['PATCH', 'PUT', 'DELETE']) {
      final req = http.Request(
        method,
        Uri.parse(
          'https://example.supabase.co/rest/v1/pengaduan?id=eq.${seeded['id']}',
        ),
      );
      req.headers['Content-Type'] = 'application/json';
      if (method != 'DELETE') {
        req.body = jsonEncode({'status': 'DONE'});
      }
      final streamed = await client.send(req);
      await http.Response.fromStream(streamed);
    }
    expect(inner.calls, 0);
  });

  test('unknown-host mutating request fails closed (no network)', () async {
    await TrainingMode.instance.debugActivateForTest();
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);

    // When supabaseUrl is empty, all hosts are treated as Supabase scope
    // (stricter). Either way mutations must never reach [_inner].
    final req = http.Request(
      'POST',
      Uri.parse('https://evil.example.com/api/write'),
    );
    req.body = '{}';

    await expectLater(client.send(req), throwsA(isA<StateError>()));
    expect(inner.calls, 0);
  });

  test('approval simulator updates sandbox only (never network)', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    final inner = _FailIfCalledClient();
    // Interceptor present but simulator must not need it — sandbox only.
    final client = TrainingHttpClient(inner: inner);
    expect(client, isNotNull);

    final row = await TrainingDataClient.instance.insert('pengaduan', {
      'toko_id': 'T1',
      'isi': 'sim',
      'status': 'OPEN',
    });

    await TrainingApprovalSimulator.applySandboxOutcome(
      table: 'pengaduan',
      id: row['id'],
      outcome: TrainingApprovalOutcome.approved,
      statusFor: TrainingApprovalSimulator.pengaduanStatus,
    );

    final updated = await TrainingSandboxStore.instance.selectOne(
      'pengaduan',
      where: {'id': row['id']},
    );
    expect(updated?['status'], 'DONE');
    expect(inner.calls, 0);

    await TrainingApprovalSimulator.applySandboxOutcome(
      table: 'jadwal_pengajuan',
      id: 'sb_jadwal_1',
      outcome: TrainingApprovalOutcome.rejected,
      statusFor: TrainingApprovalSimulator.jadwalPengajuanStatus,
      note: 'kurang dokumen',
    );
    final jadwal = await TrainingSandboxStore.instance.selectOne(
      'jadwal_pengajuan',
      where: {'id': 'sb_jadwal_1'},
    );
    expect(jadwal?['status'], 'REJECTED');
    expect(jadwal?['reviewer_note'], 'kurang dokumen');
    expect(inner.calls, 0);
  });

  test('applySandboxOutcome throws when training inactive', () async {
    expect(
      () => TrainingApprovalSimulator.applySandboxOutcome(
        table: 'pengaduan',
        id: 'x',
        outcome: TrainingApprovalOutcome.pending,
        statusFor: TrainingApprovalSimulator.pengaduanStatus,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('coa / stock_move status mappers + statusColumn update', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    final coa = await TrainingDataClient.instance.insert('finance_transactions', {
      'toko_id': 'T1',
      'status_konfirmasi': 'PENDING',
    });
    await TrainingApprovalSimulator.applySandboxOutcome(
      table: 'finance_transactions',
      id: coa['id'],
      outcome: TrainingApprovalOutcome.approved,
      statusFor: TrainingApprovalSimulator.coaStatus,
      statusColumn: 'status_konfirmasi',
    );
    final coaRow = await TrainingSandboxStore.instance.selectOne(
      'finance_transactions',
      where: {'id': coa['id']},
    );
    expect(coaRow?['status_konfirmasi'], 'APPROVED');

    final move = await TrainingDataClient.instance.insert('stock_move_history', {
      'toko_id': 'T1',
      'status': 'PENDING',
      'tipe': 'RETUR',
    });
    await TrainingApprovalSimulator.applySandboxOutcome(
      table: 'stock_move_history',
      id: move['id'],
      outcome: TrainingApprovalOutcome.approved,
      statusFor: TrainingApprovalSimulator.stockMoveStatus,
    );
    final moveRow = await TrainingSandboxStore.instance.selectOne(
      'stock_move_history',
      where: {'id': move['id']},
    );
    expect(moveRow?['status'], 'SUCCESS');
  });

  test('allocate_export_salinan stub returns int', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    final raw = await TrainingRpcStubs.handle('allocate_export_salinan', null);
    expect(raw, 1);
  });

  test('REST GET while training never hits network (sandbox only)', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    await TrainingSandboxStore.instance.insert('products', {
      'toko_id': 'T1',
      'sku': 'X1',
      'nama': 'Local Only',
      'stock': 3,
    });
    final inner = _FailIfCalledClient();
    final client = TrainingHttpClient(inner: inner);
    final req = http.Request(
      'GET',
      Uri.parse('https://example.supabase.co/rest/v1/products'),
    );
    final streamed = await client.send(req);
    final resp = await http.Response.fromStream(streamed);
    expect(inner.calls, 0);
    expect(resp.statusCode, 200);
    final list = jsonDecode(resp.body) as List;
    expect(list.any((e) => e['sku'] == 'X1'), isTrue);
  });

  test('curriculum seed creates kasir + products for toko', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'CIMAHI');
    await TrainingCurriculum.seedFreshWorld(
      tokoId: 'CIMAHI',
      profile: {'id': 'admin1', 'toko_id': 'CIMAHI', 'role': 'admin_toko'},
    );
    final kasir = await TrainingSandboxStore.instance.selectOne(
      'karyawan',
      where: {'nik': 'TRAINING01'},
    );
    expect(kasir?['nama'], 'Kasir Latihan');
    final products = await TrainingSandboxStore.instance.select('products');
    expect(products.where((p) => p['toko_id'] == 'CIMAHI'), isNotEmpty);
    expect(TrainingCurriculum.allows('master_data'), isTrue);
    expect(TrainingCurriculum.allows('pos'), isTrue);
  });

  test('exit keeps isActive until sandbox wiped', () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    await TrainingSandboxStore.instance.insert('pengaduan', {
      'toko_id': 'T1',
      'isi': 'wipe-me',
      'status': 'OPEN',
    });
    expect(TrainingMode.instance.isActive, isTrue);
    expect(
      await TrainingSandboxStore.instance.select('pengaduan'),
      isNotEmpty,
    );

    // Mimic production exit: wipe while still active, then deactivate.
    // debugDeactivateForTest wipes then clears — assert postconditions.
    await TrainingMode.instance.debugDeactivateForTest();
    expect(TrainingMode.instance.isActive, isFalse);
    expect(TrainingSandboxStore.instance.isReady, isFalse);
  });

  test('exit() wipes sandbox before deactivating (no prod write window)',
      () async {
    await TrainingMode.instance.debugActivateForTest(tokoId: 'T1');
    await TrainingSandboxStore.instance.insert('pengaduan', {
      'toko_id': 'T1',
      'isi': 'must-wipe',
      'status': 'OPEN',
    });

    // Call real exit() — it must wipe while fail-closed still on, then clear.
    await TrainingMode.instance.exit();

    expect(TrainingMode.instance.isActive, isFalse);
    expect(TrainingSandboxStore.instance.isReady, isFalse);

    // After exit, a mutation via interceptor must NOT be treated as training
    // (would pass through). Prove isActive is false first.
    final inner = _RecordingClient();
    final client = TrainingHttpClient(inner: inner);
    final req = http.Request(
      'POST',
      Uri.parse('https://example.supabase.co/rest/v1/pengaduan'),
    );
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode({'isi': 'after-exit'});
    // Inactive → pass-through; recording client fails on non-GET.
    await expectLater(client.send(req), throwsA(isA<TestFailure>()));
    expect(inner.calls, isNotEmpty);
  });

  test('inactive training passes through to inner client', () async {
    final inner = _RecordingClient();
    final client = TrainingHttpClient(inner: inner);
    final req = http.Request(
      'GET',
      Uri.parse('https://example.supabase.co/rest/v1/karyawan?select=*'),
    );
    final streamed = await client.send(req);
    await http.Response.fromStream(streamed);
    expect(inner.calls, isNotEmpty);
  });
}
