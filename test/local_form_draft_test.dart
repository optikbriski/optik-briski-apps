import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optik_b_riski/shared/connectivity/connectivity_reload.dart';
import 'package:optik_b_riski/shared/local_form_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('LocalFormDraft round-trip preserves payload without mutating input', () async {
    const key = 'test_draft';
    final input = <String, dynamic>{
      'cart': [
        {'sku': 'A1', 'qty': 2, 'needs_fulfillment': true},
      ],
      'no_invoice': 'INV-TEST-1',
    };

    await LocalFormDraft.save(key, input);
    expect(input.containsKey('saved_at'), isFalse);

    final read = await LocalFormDraft.read(key);
    expect(read, isNotNull);
    expect(read!['no_invoice'], 'INV-TEST-1');
    expect((read['cart'] as List).length, 1);
    expect(read['saved_at'], isNotEmpty);

    await LocalFormDraft.clear(key);
    expect(await LocalFormDraft.read(key), isNull);
  });

  test('bytesToB64 enforces photo size limit', () {
    final small = Uint8List(1024);
    final huge = Uint8List(LocalFormDraft.maxDraftPhotoBytes + 1);
    expect(LocalFormDraft.bytesToB64(small), isNotNull);
    expect(LocalFormDraft.bytesToB64(huge), isNull);
    expect(LocalFormDraft.bytesFromB64(''), isNull);
    expect(LocalFormDraft.bytesFromB64('not-b64'), isNull);
  });

  test('clearSessionDrafts removes user and toko keys', () async {
    await LocalFormDraft.save('pengaduan_compose_draft_karyawan_u1', {'x': 1});
    await LocalFormDraft.save('pos_draft_transaksi_CABANG-A', {'y': 2});
    await LocalFormDraft.save('do_compose_draft_CABANG-A', {'z': 3});

    await LocalFormDraft.clearSessionDrafts(
      userId: 'u1',
      tokoId: 'CABANG-A',
    );

    expect(await LocalFormDraft.read('pengaduan_compose_draft_karyawan_u1'), isNull);
    expect(await LocalFormDraft.read('pos_draft_transaksi_CABANG-A'), isNull);
    expect(await LocalFormDraft.read('do_compose_draft_CABANG-A'), isNull);
  });

  test('ConnectivityReload runs all handlers and isolates failures', () async {
    final log = <String>[];
    final a = Object();
    final b = Object();
    ConnectivityReload.bind(a, () async => log.add('a'));
    ConnectivityReload.bind(b, () async {
      log.add('b');
      throw StateError('fail');
    });

    await ConnectivityReload.runAll();
    expect(log, ['a', 'b']);

    ConnectivityReload.unbind(a);
    ConnectivityReload.unbind(b);
    log.clear();
    await ConnectivityReload.runAll();
    expect(log, isEmpty);
  });

  test('DebouncedFormSave coalesces rapid schedules', () async {
    var count = 0;
    final debouncer = DebouncedFormSave(delay: const Duration(milliseconds: 40));
    debouncer.schedule(() async => count++);
    debouncer.schedule(() async => count++);
    debouncer.schedule(() async => count++);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(count, 1);
    debouncer.dispose();
  });
}
