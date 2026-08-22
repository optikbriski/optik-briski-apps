import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/config.dart';
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

  test('storeMatchesApk is inert on Admin test flavor', () {
    TenantService.instance.debugBind('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(isBrandedStoreApk, isFalse);
    expect(TenantService.instance.storeMatchesApk('other-tenant'), isTrue);
  });

  test('sessionAllowsAccount rejects empty tenant on any shell', () {
    TenantService.instance.debugBind('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(TenantService.instance.sessionAllowsAccount(''), isFalse);
    expect(TenantService.instance.sessionAllowsAccount(null), isFalse);
    expect(
      TenantService.instance.sessionAllowsAccount(
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      ),
      isTrue,
    );
    expect(
      TenantService.instance.sessionAllowsAccount(
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      ),
      isFalse,
    );
  });

  test('platform default is Rekasa shell; Optik is a brand skin', () {
    expect(memberTenantSlug, isEmpty);
    expect(karyawanTenantSlug, isEmpty);
    expect(adminTenantSlug, isEmpty);
    expect(TenantService.defaultSlug, isEmpty);
    expect(TenantService.optikSlug, 'optik-briski');
    expect(pinAdminTenant, isFalse);
    expect(pinStoreTenant, isFalse);
    expect(isRekasaControlPlane, isTrue);
    expect(isRekasaStorefront, isFalse);
    expect(isBrandedStoreApk, isFalse);
  });

  test('fail-closed SQL exists after tenant isolation migrations', () {
    final sql = File(
      'supabase/migrations/20260820000015_tenant_fail_closed.sql',
    ).readAsStringSync();
    expect(sql, contains('raise exception'));
    expect(sql, contains('jangan memakai data usaha lain'));
    expect(sql, isNot(contains('return public.default_tenant_id()')));
    final noOracle = File(
      'supabase/migrations/20260820000016_no_anon_optik_oracle.sql',
    ).readAsStringSync();
    expect(noOracle, contains('where b.tenant_id = public.current_tenant_id()'));
    expect(
      noOracle,
      contains('revoke all on function public.default_tenant_id() from anon'),
    );
    expect(
      noOracle,
      isNot(contains('coalesce(public.current_tenant_id(), public.default_tenant_id())')),
    );
  });

  test('login identity SQL is global, not per-tenant', () {
    final sql = File(
      'supabase/migrations/20260820000017_login_identity_global.sql',
    ).readAsStringSync();
    expect(sql, contains('karyawan_email_global_uidx'));
    expect(sql, contains('members_email_global_uidx'));
    expect(sql, contains('members_phone_global_uidx'));
    expect(sql, contains('profiles_email_global_uidx'));
    expect(sql, contains('Email sudah dipakai akun merek lain'));
    expect(sql, contains('drop index if exists public.karyawan_email_tenant_uidx'));
  });

  test('loginIdentityTakenMessage maps unique-login errors', () {
    expect(
      loginIdentityTakenMessage('Email sudah dipakai akun merek lain'),
      contains('Tidak boleh sama antar merek'),
    );
    expect(loginIdentityTakenMessage('network timeout'), isNull);
  });

  test('requireResolved refuses empty slug on shared Rekasa shell', () async {
    TenantService.instance.debugUnbind();
    TenantService.instance.slug = '';
    expect(isBrandedStoreApk, isFalse);
    await expectLater(
      TenantService.instance.requireResolved(slug: ''),
      throwsA(isA<StateError>()),
    );
    expect(TenantService.instance.isBound, isFalse);
  });
}
