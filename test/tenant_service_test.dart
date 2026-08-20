import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/tenant_service.dart';

void main() {
  tearDown(() {
    TenantService.instance.debugUnbind();
    TenantService.instance.slug = TenantService.defaultSlug;
  });

  test('withTenant refuses unbound tenant', () {
    TenantService.instance.debugUnbind();
    expect(
      () => withTenant({'p_phone': '0812'}),
      throwsA(isA<StateError>()),
    );
  });

  test('boundId refuses Optik fallback when unbound', () {
    TenantService.instance.debugUnbind();
    expect(() => TenantService.instance.boundId, throwsA(isA<StateError>()));
    expect(TenantService.instance.isBound, isFalse);
  });

  test('boundId returns the resolved tenant, not a silent default', () {
    const other = '11111111-1111-1111-1111-111111111111';
    TenantService.instance.debugBind(other, slug: 'optik-maju');
    expect(TenantService.instance.boundId, other);
    expect(withTenant({})['p_tenant_id'], other);
  });
}
