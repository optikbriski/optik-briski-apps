import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/tenant_modules.dart';

void main() {
  test('modules fail-open before load so Optik tetap jalan pra-migrasi', () {
    expect(TenantModules.instance.loaded, isFalse);
    expect(TenantModules.instance.allows('finance'), isTrue);
    expect(TenantModules.instance.allows('online_orders'), isTrue);
  });
}
