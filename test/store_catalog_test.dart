import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/module_catalog.dart';
import 'package:optik_b_riski/shared/tenant/store_catalog.dart';

void main() {
  test('local without industry is pick-bidang', () {
    final cat = StoreCatalog.local();
    expect(cat.plans, isEmpty);
    expect(cat.industries, isNotEmpty);
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
