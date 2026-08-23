import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/tenant/industry_catalog.dart';
import 'package:optik_b_riski/shared/tenant/store_catalog.dart';

Map<String, dynamic> _siteCatalog() {
  final raw = File('site/catalog.js').readAsStringSync();
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  final js = raw.substring(start, end + 1).replaceAllMapped(
        RegExp(r'([{\[,]\s*)([A-Za-z_][A-Za-z0-9_]*):'),
        (m) => '${m[1]}"${m[2]}":',
      );
  return jsonDecode(js) as Map<String, dynamic>;
}

void main() {
  test('situs publik paket bisa diklik dan fitur bisa di-toggle', () {
    final js = File('site/store.js').readAsStringSync();
    expect(js, contains('data-plan'));
    expect(js, contains('data-industry'));
    expect(js, contains('industry-chips'));
    expect(js, contains('industry-grid'));
    expect(js, contains('LIHAT PAKET'));
    expect(File('site/index.html').readAsStringSync(), contains('id="industry-grid"'));
    expect(File('site/paket.html').readAsStringSync(), contains('id="industry-grid"'));
    expect(File('site/paket.html').readAsStringSync(), contains('id="back-home"'));
    expect(File('site/paket.html').readAsStringSync(), contains('Halaman utama'));
    expect(
      File('lib/apps/admin/rekasa_store_page.dart').readAsStringSync(),
      contains('Halaman utama'),
    );
    expect(js, contains('PILIH FITUR'));
    expect(js, contains('plan-badge'));
    expect(js, contains('paket.html?plan='));
    expect(js, contains('data-page'));
    expect(js, contains('type = "checkbox"'));
    expect(js, contains('rekasa-midtrans-create'));
    expect(js, contains('snap.pay'));
    expect(File('site/index.html').readAsStringSync(), isNot(contains('checkout-form')));
    expect(File('site/paket.html').existsSync(), isTrue);
  });

  test('web dan APK pakai field checkout yang sama', () {
    final paket = File('site/paket.html').readAsStringSync();
    final dart = File('lib/apps/admin/rekasa_store_plan_page.dart').readAsStringSync();
    for (final field in [
      'Nama usaha / merek',
      'Kode usaha',
      'WA / HP',
      'Email (opsional)',
      'Nama penandatangan kontrak',
      'Bayar via Midtrans',
    ]) {
      expect(paket, contains(field), reason: 'web: $field');
      expect(dart, contains(field), reason: 'apk: $field');
    }
    expect(File('site/catalog.js').readAsStringSync(), contains('highlight: "Hemat"'));
    expect(File('site/catalog.js').readAsStringSync(), contains('highlight: "Tertinggi"'));
  });

  test('harga dan modul situs sama dengan etalase Flutter', () {
    final site = _siteCatalog();
    final plans = site['plans'] as Map<String, dynamic>;
    expect(plans['paket_c']['priceIdr'], 250000);
    expect(plans['paket_b']['priceIdr'], 450000);
    expect(plans['paket_a']['priceIdr'], 750000);
    expect(site['whiteLabelAddonIdr'], 200000);

    for (final industry in industryCatalog) {
      final cat = StoreCatalog.local(industry.key);
      final row = (site['industries'] as List).cast<Map<String, dynamic>>().singleWhere(
            (e) => e['key'] == industry.key,
          );
      final hide = (row['hide'] as List?)?.cast<String>() ?? const [];
      expect(
        cat.modules.map((m) => m.key).where((k) => !hide.contains(k)).toSet(),
        isNotEmpty,
      );
      for (final plan in cat.plans) {
        final siteKeys = (row['plans'][plan.planKey] as List).cast<String>()
          ..sort();
        final dartKeys = List<String>.from(plan.moduleKeys)..sort();
        expect(siteKeys, dartKeys, reason: '${industry.key} ${plan.planKey}');
        expect(plans[plan.planKey]['priceIdr'], plan.priceIdr);
      }
    }
  });
}
