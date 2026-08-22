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
    expect(js, contains('plan-body'));
    expect(js, contains('type = "checkbox"'));
    expect(js, contains('rekasa-midtrans-create'));
    expect(js, contains('snap.pay'));
    expect(File('site/index.html').readAsStringSync(), isNot(contains('id="fitur"')));
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
