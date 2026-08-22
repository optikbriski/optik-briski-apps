import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/tenant_modules.dart';

void main() {
  setUp(TenantModules.instance.debugReset);

  test('modules fail-closed before load — no menus without entitlements', () {
    expect(TenantModules.instance.loaded, isFalse);
    expect(TenantModules.instance.allows('finance'), isFalse);
    expect(TenantModules.instance.allows('online_orders'), isFalse);
    expect(TenantModules.instance.allows('pos'), isFalse);
  });

  test('after bind, only purchased modules stay on', () {
    TenantModules.instance.debugApplyEnabled({'pos', 'attendance'});
    expect(TenantModules.instance.allows('pos'), isTrue);
    expect(TenantModules.instance.allows('attendance'), isTrue);
    expect(TenantModules.instance.allows('online_orders'), isFalse);
    expect(TenantModules.instance.allows('finance'), isFalse);
  });

  test('storefront seal never shows POS menus', () {
    TenantModules.instance.debugApplyEnabled({'pos', 'finance'});
    TenantModules.instance.sealStorefront();
    expect(TenantModules.instance.allows('pos'), isFalse);
    expect(TenantModules.instance.allows('finance'), isFalse);
    expect(TenantModules.instance.shell, 'rekasa_store');
  });

  test('shared shell hint names the kode usaha', () {
    TenantModules.instance.debugApplyEntitlements({
      'plan_key': 'paket_b',
      'industry_key': 'fnb',
      'slug': 'warung-sari',
      'white_label': false,
      'shell': 'rekasa_shared',
      'modules': [
        {'module_key': 'pos', 'enabled': true},
        {'module_key': 'finance', 'enabled': false},
      ],
    });
    expect(TenantModules.instance.allows('pos'), isTrue);
    expect(TenantModules.instance.allows('finance'), isFalse);
    expect(TenantModules.instance.shellHint, contains('warung-sari'));
    expect(TenantModules.instance.planLabel, contains('Paket B'));
  });

  test('install hint separates store APK from client APK', () {
    final shared = TenantModules.installHint(
      whiteLabel: false,
      slug: 'toko-maju',
    );
    final branded = TenantModules.installHint(
      whiteLabel: true,
      slug: 'toko-maju',
    );
    expect(shared, contains('bukan APK etalase'));
    expect(shared, contains('toko-maju'));
    expect(branded, contains('merek sendiri'));
    expect(branded, contains('toko-maju'));
  });
}
