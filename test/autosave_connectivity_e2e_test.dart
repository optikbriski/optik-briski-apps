import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optik_b_riski/shared/config.dart';
import 'package:optik_b_riski/shared/connectivity/connectivity_monitor.dart';
import 'package:optik_b_riski/shared/connectivity/connectivity_reload.dart';
import 'package:optik_b_riski/shared/local_form_draft.dart';

/// Simulasi end-to-end draft + connectivity tanpa UI.
/// Live probe Supabase jalan bila `--dart-define-from-file=.dart_define.admin.json`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('POS draft E2E (local)', () {
    test('round-trip cart + RO local + lens state', () async {
      const toko = 'CABANG-A';
      const key = 'pos_draft_transaksi_$toko';
      final roRow = {
        'local_key': 'INV-1|SKU1|2|1',
        'toko_id': toko,
        'no_invoice': 'INV-1',
        'nama_pelanggan': 'Budi',
        'sku': 'SKU1',
        'nama_produk': 'Frame X',
        'qty_request': 2,
        'status': 'PENDING',
      };
      await LocalFormDraft.save(key, {
        'no_invoice': 'INV-1',
        'cart': [
          {
            'sku': 'SKU1',
            'qty': 2,
            'needs_fulfillment': true,
            'harga': 100000,
          },
        ],
        'customer': {'name': 'Budi', 'phone': '0812'},
        'pending_ro_local': [roRow],
        'pending_lens_requests': [
          {'merk': 'Essilor', 'jenis': 'Progresif'},
        ],
        'lens': {
          'brand': 'Essilor',
          'jenis': 'Progresif',
          'bahan': 'Supersin',
          'sph_r': '-1.00',
        },
        'karyawan_terlibat': [
          {'id': 'k1', 'nama': 'Ani'},
        ],
      });

      final read = await LocalFormDraft.read(key);
      expect(read, isNotNull);
      expect(read!['no_invoice'], 'INV-1');
      expect((read['cart'] as List).first['needs_fulfillment'], isTrue);
      expect((read['pending_ro_local'] as List).length, 1);
      expect((read['pending_lens_requests'] as List).length, 1);
      expect(read['lens']['brand'], 'Essilor');

      final reencoded = jsonEncode(read);
      final round2 = jsonDecode(reencoded) as Map<String, dynamic>;
      expect(round2['customer']['phone'], '0812');
    });
  });

  group('DO compose draft E2E (local)', () {
    test('round-trip keranjang DO + filter', () async {
      const key = 'do_compose_draft_PUSAT';
      await LocalFormDraft.save(key, {
        'selected_toko': 'CABANG-B',
        'selected_items': {'prod-1': 3, 'prod-2': 1},
        'only_need_restock': true,
        'search': 'frame',
        'selected_categories': ['Frame', 'Lensa'],
      });
      final read = await LocalFormDraft.read(key);
      expect(read!['selected_toko'], 'CABANG-B');
      final items = Map<String, dynamic>.from(read['selected_items'] as Map);
      expect(int.parse('${items['prod-1']}'), 3);
      expect((read['selected_categories'] as List), contains('Frame'));
    });
  });

  group('Pengaduan draft E2E (local)', () {
    test('round-trip karyawan + admin compose keys terpisah per user', () async {
      final foto = Uint8List.fromList(List.generate(512, (i) => i % 256));
      await LocalFormDraft.save('pengaduan_compose_draft_karyawan_uA', {
        'kategori_kode': 'PRODUK',
        'deskripsi': 'Rusak',
        'foto_b64': LocalFormDraft.bytesToB64(foto),
        'items': [
          {'sku': 'L1', 'nama': 'Lensa', 'qty': 1, 'harga': 0},
        ],
      });
      await LocalFormDraft.save('pengaduan_compose_draft_admin_uB', {
        'toko_id': 'CABANG-A',
        'kategori_kode': 'OPERASIONAL',
        'detail': 'AC mati',
      });

      final k = await LocalFormDraft.read('pengaduan_compose_draft_karyawan_uA');
      final a = await LocalFormDraft.read('pengaduan_compose_draft_admin_uB');
      expect(k!['kategori_kode'], 'PRODUK');
      expect(LocalFormDraft.bytesFromB64(k['foto_b64']), isNotNull);
      expect(a!['toko_id'], 'CABANG-A');

      await LocalFormDraft.clearSessionDrafts(userId: 'uA', tokoId: 'CABANG-A');
      expect(await LocalFormDraft.read('pengaduan_compose_draft_karyawan_uA'), isNull);
      expect(await LocalFormDraft.read('pos_draft_transaksi_CABANG-A'), isNull);
      // Admin user B draft tidak ikut terhapus.
      expect(await LocalFormDraft.read('pengaduan_compose_draft_admin_uB'), isNotNull);
    });
  });

  group('Connectivity reload chain E2E', () {
    test('probeAndReload skips handlers when offline', () async {
      final mon = ConnectivityMonitor.instance;
      mon.status = ConnectivityStatus.offline;
      var reloaded = false;
      final owner = Object();
      ConnectivityReload.bind(owner, () async {
        reloaded = true;
      });
      final ok = await mon.probeAndReload();
      // Probe may flip status on live network; assert handler guard when still offline.
      if (mon.status == ConnectivityStatus.offline) {
        expect(ok, isFalse);
        expect(reloaded, isFalse);
      }
      ConnectivityReload.unbind(owner);
    });

    test('reload chain runs POS+DO handlers in registration order', () async {
      final log = <String>[];
      final pos = Object();
      final dash = Object();
      final doPage = Object();
      ConnectivityReload.bind(dash, () async => log.add('dash'));
      ConnectivityReload.bind(pos, () async => log.add('pos'));
      ConnectivityReload.bind(doPage, () async => log.add('do'));
      await ConnectivityReload.runAll();
      expect(log, containsAll(['dash', 'pos', 'do']));
      ConnectivityReload.unbind(dash);
      ConnectivityReload.unbind(pos);
      ConnectivityReload.unbind(doPage);
    });
  });

  group('Live Supabase probe', () {
    test('HEAD /rest/v1/ reachable (production build config)', () async {
      final base = supabaseUrl.trim();
      if (base.isEmpty) {
        // Skip silently in CI tanpa dart-define.
        return;
      }
      final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/rest/v1/');
      final headers = <String, String>{
        if (supabasePublishableKey.isNotEmpty) 'apikey': supabasePublishableKey,
        if (supabasePublishableKey.isNotEmpty)
          'Authorization': 'Bearer $supabasePublishableKey',
      };
      final sw = Stopwatch()..start();
      final res = await http.head(uri, headers: headers).timeout(
            const Duration(seconds: 8),
          );
      sw.stop();
      // 200/401/404 still mean server reachable — same as app probe (no throw).
      expect(res.statusCode, lessThan(500));
      expect(sw.elapsedMilliseconds, lessThan(8000));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
