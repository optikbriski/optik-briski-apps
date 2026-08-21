import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/industry_catalog.dart';
import 'package:optik_b_riski/shared/tenant/module_catalog.dart';
import 'package:optik_b_riski/shared/tenant/store_catalog.dart';

void main() {
  test('local without industry is pick-bidang', () {
    final cat = StoreCatalog.local();
    expect(cat.plans, isEmpty);
    expect(cat.industries, isNotEmpty);
  });

  test('optik industry copy does not name the sample tenant', () {
    final optik = industryCatalog.singleWhere((i) => i.key == 'optik');
    expect(optik.blurb.toLowerCase(), isNot(contains('optik b. riski')));
    expect(optik.blurb.toLowerCase(), isNot(contains('contoh tenant')));
  });

  test('optik A includes every optik catalog module', () {
    final cat = StoreCatalog.local('optik');
    final a = cat.plans.singleWhere((p) => p.planKey == 'paket_a');
    for (final m in cat.modules) {
      expect(a.includes(m.key), isTrue, reason: m.key);
    }
    expect(a.whiteLabel, isTrue);
  });

  test('fnb packages are not optical POS', () {
    final cat = StoreCatalog.local('fnb');
    final a = cat.plans.singleWhere((p) => p.planKey == 'paket_a');
    expect(a.includes('pos'), isTrue);
    expect(a.includes('warranty'), isFalse);
    expect(cat.module('pos')?.label.toLowerCase(), contains('meja'));
  });

  test('quote adds add-on only for extras', () {
    final cat = StoreCatalog.local('optik');
    final c = cat.plans.singleWhere((p) => p.planKey == 'paket_c');
    final enabled = {for (final m in cat.modules) m.key: c.includes(m.key)};
    final base = cat.quote(plan: c, enabled: enabled, whiteLabel: false);
    expect(base.amountIdr, c.priceIdr);
    expect(base.addOnIdr, 0);

    enabled['finance'] = true;
    final extra = cat.quote(plan: c, enabled: enabled, whiteLabel: false);
    expect(extra.addOnIdr, cat.module('finance')!.addOnPriceIdr);
    expect(extra.amountIdr, c.priceIdr + extra.addOnIdr);

    final wl = cat.quote(plan: c, enabled: enabled, whiteLabel: true);
    expect(wl.whiteLabelIdr, cat.whiteLabelAddonIdr);
    expect(wl.amountIdr, extra.amountIdr + cat.whiteLabelAddonIdr);
  });

  test('quote fromRpc prefers server amount', () {
    final local = StoreCatalog.local('optik').quote(
      plan: StoreCatalog.local('optik').plans.first,
      enabled: const {},
      whiteLabel: false,
    );
    final remote = StoreQuote.fromRpc({
      'ok': true,
      'base_idr': 250000,
      'add_on_idr': 75000,
      'white_label_idr': 0,
      'amount_idr': 325000,
      'white_label': false,
    }, fallback: local);
    expect(remote.fromServer, isTrue);
    expect(remote.amountIdr, 325000);
    expect(remote.addOnIdr, 75000);
    expect(StoreQuote.fromRpc(null, fallback: local).fromServer, isFalse);
  });

  test('youtube id from watch and youtu.be', () {
    expect(
      StoreVideo.youtubeId('https://www.youtube.com/watch?v=dQw4w9wgGcQ'),
      'dQw4w9wgGcQ',
    );
    expect(StoreVideo.youtubeId('https://youtu.be/dQw4w9wgGcQ'), 'dQw4w9wgGcQ');
    expect(
      StoreVideo.embedUrl('https://youtu.be/dQw4w9wgGcQ'),
      contains('youtube-nocookie.com/embed/dQw4w9wgGcQ'),
    );
    expect(StoreVideo.youtubeId('https://example.com/x'), isNull);
  });

  test('moduleCatalog still exposes key and label for tenant admin', () {
    expect(moduleCatalog.map((m) => m.key).toSet(), containsAll(['pos', 'finance']));
    expect(moduleCatalog.first.label, isNotEmpty);
  });
}
