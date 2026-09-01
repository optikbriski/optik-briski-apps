import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/admin/admin_force_sync.dart';
import 'package:optik_b_riski/shared/logistics/stock_leak_rules.dart';
import 'package:optik_b_riski/shared/sync/client_force_sync.dart';

void main() {
  test('AdminForceSync is a dedicated client-sync entry (not stock leak)', () {
    expect(AdminForceSync.run, isA<Function>());
  });

  test('originId is usable on web-safe Random range', () {
    expect(ClientForceSync.originId, isNotEmpty);
    expect(ClientForceSync.originId.contains(' '), isFalse);
  });

  test('pingStockChannels accepts parallel time-budget args', () {
    expect(ClientForceSync.pingStockChannels, isA<Function>());
    expect(ClientForceSync.isAllBranchesToko('*'), isTrue);
    expect(ClientForceSync.isAllBranchesToko('CABANG-DEPOK'), isFalse);
  });

  test('ClientForceSync scopes events to cabang toko_id', () {
    final tid = '00000000-0000-0000-0000-000000000001';
    expect(
      ClientForceSync.topicForTenant(tid),
      'obr-force-sync-00000000-0000-0000-0000-000000000001',
    );

    final depok = ClientForceSync.parsePayload({
      'tenant_id': tid,
      'toko_id': 'CABANG-DEPOK',
      'origin_id': 'other-device',
      'source': 'admin_web',
      'ts': '2026-01-01T00:00:00Z',
    });
    expect(depok, isNotNull);
    expect(depok!.tokoId, 'CABANG-DEPOK');

    expect(
      ClientForceSync.appliesToLocalToko(
        depok,
        localTokoId: 'CABANG-DEPOK',
      ),
      isTrue,
    );
    expect(
      ClientForceSync.appliesToLocalToko(
        depok,
        localTokoId: 'CABANG-CIMAHI',
      ),
      isFalse,
    );

    final all = ClientForceSync.parsePayload({
      'tenant_id': tid,
      'toko_id': '*',
      'origin_id': 'pusat',
      'source': 'admin_pusat',
      'ts': 'x',
    });
    expect(ClientForceSync.isAllBranchesToko(all!.tokoId), isTrue);
    expect(
      ClientForceSync.appliesToLocalToko(all, localTokoId: 'CABANG-CIMAHI'),
      isTrue,
    );
    expect(
      ClientForceSync.appliesToLocalToko(all, localTokoId: 'PUSAT'),
      isTrue,
    );

    final pusat = ClientForceSync.parsePayload({
      'payload': {
        'tenant_id': tid,
        'toko_id': 'PUSAT',
        'origin_id': 'other',
        'source': 'admin',
        'ts': 'x',
      },
    });
    expect(
      ClientForceSync.appliesToLocalToko(
        pusat!,
        localTokoId: 'CABANG-PUSAT',
      ),
      isTrue,
    );
  });

  test('own origin_id is identifiable so bind can ignore self-broadcast', () {
    final tid = '00000000-0000-0000-0000-000000000001';
    final self = ClientForceSync.parsePayload({
      'tenant_id': tid,
      'toko_id': 'CABANG-DEPOK',
      'origin_id': ClientForceSync.originId,
      'source': 'admin',
      'ts': 'x',
    });
    expect(self, isNotNull);
    expect(self!.originId, ClientForceSync.originId);
    // bind() callback drops when ev.originId == originId (loop guard).
    expect(self.originId == ClientForceSync.originId, isTrue);

    final other = ClientForceSync.parsePayload({
      'tenant_id': tid,
      'toko_id': 'CABANG-DEPOK',
      'origin_id': 'different-device',
      'source': 'admin',
      'ts': 'x',
    });
    expect(other!.originId == ClientForceSync.originId, isFalse);
  });

  test('client_force_sync source does not import stock leak/integrity', () {
    final src = File('lib/shared/sync/client_force_sync.dart').readAsStringSync();
    expect(src.contains('stock_integrity'), isFalse);
    expect(src.contains('recognizeVariance'), isFalse);
    expect(src.contains('reviseTo'), isFalse);
    expect(src.contains('StockLeak'), isFalse);
  });

  test('leak recognize vs bug-fix stay conceptually separate', () {
    expect(
      StockLeakRules.stokTetap(stockBefore: 10, stockAfter: 10),
      isTrue,
    );
    expect(
      StockLeakRules.stokTetap(stockBefore: 10, stockAfter: 8),
      isFalse,
    );
  });

  test('i18n keys mention cabang sync and keep leak paths separate', () {
    final id = _readJson('assets/translations/id.json');
    expect(id['admin_force_sync_busy'], contains('{toko}'));
    expect(id['admin_force_sync_ok'], contains('{toko}'));
    expect(id['admin_force_sync_busy_pusat'], contains('SEMUA'));
    expect(id['admin_force_sync_ok_pusat'], contains('{count}'));
    expect(id['admin_force_sync_busy_pusat'], contains('reload'));
    expect(id['admin_force_sync_busy'], contains('kebocoran'));
    expect(
      (id['leak_action_recognize'] as String).toLowerCase(),
      isNot(contains('bug')),
    );
    expect(
      (id['leak_action_fix_bug'] as String).toLowerCase(),
      contains('bug'),
    );
  });
}

Map<String, dynamic> _readJson(String path) {
  final raw = File(path).readAsStringSync();
  return Map<String, dynamic>.from(jsonDecode(raw) as Map);
}
