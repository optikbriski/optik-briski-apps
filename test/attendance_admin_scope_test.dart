import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/attendance_admin_scope.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  group('canViewAllStores', () {
    test('pusat operators only', () {
      expect(AttendanceAdminScope.canViewAllStores(p('owner', 'CABANG-X')),
          isTrue);
      expect(AttendanceAdminScope.canViewAllStores(p('admin_pusat', 'PUSAT')),
          isTrue);
      expect(AttendanceAdminScope.canViewAllStores(p('super_admin', '')),
          isTrue);
    });

    test('admin_toko never sees all stores, even at PUSAT', () {
      expect(AttendanceAdminScope.canViewAllStores(p('admin_toko', 'PUSAT')),
          isFalse);
      expect(
        AttendanceAdminScope.canViewAllStores(p('admin_toko', 'CABANG-X')),
        isFalse,
      );
    });
  });

  group('canOpenKaryawanManagement', () {
    test('admin_toko with store can open HR', () {
      expect(
        AttendanceAdminScope.canOpenKaryawanManagement(
            p('admin_toko', 'CABANG-ARCAMANIK')),
        isTrue,
      );
    });

    test('admin_toko without store cannot', () {
      expect(
        AttendanceAdminScope.canOpenKaryawanManagement(p('admin_toko', '')),
        isFalse,
      );
    });

    test('kasir cannot open HR even at PUSAT', () {
      expect(
        AttendanceAdminScope.canOpenKaryawanManagement(p('kasir', 'PUSAT')),
        isFalse,
      );
    });
  });

  group('monitor and geofence follow HR scope', () {
    test('admin_toko own store', () {
      final profile = p('admin_toko', 'CABANG-X');
      expect(AttendanceAdminScope.canOpenStoreMonitor(profile), isTrue);
      expect(AttendanceAdminScope.canManageGeofence(profile), isTrue);
      expect(AttendanceAdminScope.canManageJadwal(profile), isTrue);
      expect(
        AttendanceAdminScope.canEditTokoJadwal(profile, 'CABANG-X'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canEditTokoJadwal(profile, 'CABANG-Y'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canEditTokoJadwal(p('kasir', 'CABANG-X'), 'CABANG-X'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canEditTokoJadwal(p('admin_pusat', 'PUSAT'), 'PUSAT'),
        isTrue,
      );
      expect(AttendanceAdminScope.canOpenPos(profile), isTrue);
      expect(
        AttendanceAdminScope.canPosCheckoutToko(profile, 'CABANG-X'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canPosCheckoutToko(profile, 'CABANG-Y'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canOpenPos(p('owner', 'PUSAT')),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canPosCheckoutToko(p('kasir', 'CABANG-X'), 'CABANG-X'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canEditTokoGeofence(profile, 'CABANG-X'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canEditTokoGeofence(profile, 'CABANG-Y'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canEditTokoGeofence(p('kasir', 'CABANG-X'), 'CABANG-X'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canEditTokoGeofence(p('owner', 'PUSAT'), 'CABANG-Y'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.filterTokoForMonitor(
          ['PUSAT', 'CABANG-X', 'CABANG-Y'],
          profile,
        ),
        ['CABANG-X'],
      );
    });

    test('admin_toko cannot access other store attendance', () {
      final profile = p('admin_toko', 'CABANG-X');
      expect(
        AttendanceAdminScope.canAccessTokoAttendance(profile, 'CABANG-Y'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canAccessTokoAttendance(profile, 'CABANG-X'),
        isTrue,
      );
    });
  });

  group('tenant is the isolation unit, not skin', () {
    test('owner cannot access another brand row', () {
      final owner = {
        'role': 'owner',
        'toko_id': 'PUSAT',
        'tenant_id': '00000000-0000-0000-0000-000000000001',
      };
      expect(
        AttendanceAdminScope.canAccessTokoAttendance(
          owner,
          'CABANG-X',
          rowTenantId: '00000000-0000-0000-0000-000000000099',
        ),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canAccessTokoAttendance(
          owner,
          'CABANG-X',
          rowTenantId: '00000000-0000-0000-0000-000000000001',
        ),
        isTrue,
      );
    });

    test('missing tenant is fail-closed', () {
      expect(
        AttendanceAdminScope.sameTenant(
          {'role': 'owner', 'toko_id': 'PUSAT'},
          '00000000-0000-0000-0000-000000000001',
        ),
        isFalse,
      );
    });

    test('bound tenant mismatch rejects karyawan clock-in', () {
      expect(AttendanceAdminScope.matchesBoundTenant(null), isFalse);
      expect(AttendanceAdminScope.matchesBoundTenant(''), isFalse);
      expect(
        () => AttendanceAdminScope.assertKaryawanTenant({
          'id': 'k1',
          'toko_id': 'CABANG-X',
        }),
        returnsNormally,
      );
    });
  });

  test('PUSAT and CABANG-PUSAT are the same store', () {
    expect(AttendanceAdminScope.sameTokoId('PUSAT', 'CABANG-PUSAT'), isTrue);
    expect(AttendanceAdminScope.sameTokoId('CABANG-X', 'CABANG-Y'), isFalse);
    expect(
      AttendanceAdminScope.storeIdAliases('PUSAT'),
      ['PUSAT', 'CABANG-PUSAT'],
    );
    expect(AttendanceAdminScope.storeIdAliases('CABANG-X'), ['CABANG-X']);
    expect(
      AttendanceAdminScope.expandStoreIds(['PUSAT', 'CABANG-X']),
      containsAll(['PUSAT', 'CABANG-PUSAT', 'CABANG-X']),
    );
  });

  group('tinjauan status machine', () {
    test('curang only from mencurigakan', () {
      expect(AttendanceAdminScope.canFlagMencurigakan('pending_review'), isTrue);
      expect(AttendanceAdminScope.canFlagMencurigakan('mencurigakan'), isFalse);
      expect(AttendanceAdminScope.canResolveAman('pending_review'), isTrue);
      expect(AttendanceAdminScope.canResolveAman('mencurigakan'), isTrue);
      expect(AttendanceAdminScope.canResolveAman('aman'), isFalse);
      expect(AttendanceAdminScope.canResolveCurang('pending_review'), isFalse);
      expect(AttendanceAdminScope.canResolveCurang('mencurigakan'), isTrue);
      expect(AttendanceAdminScope.canResolveCurang('aman'), isFalse);
    });
  });

  group('monitor write + banner', () {
    test('requireTokoId rejects empty', () {
      expect(() => AttendanceAdminScope.requireTokoId(''), throwsStateError);
      expect(AttendanceAdminScope.requireTokoId('CABANG-X'), 'CABANG-X');
    });

    test('banner is store-specific for admin_toko', () {
      expect(
        AttendanceAdminScope.geofenceBannerHint(p('admin_pusat', 'PUSAT')),
        'Semua toko termasuk Pusat',
      );
      expect(
        AttendanceAdminScope.jadwalBannerHint(p('admin_pusat', 'PUSAT')),
        'Semua toko termasuk Pusat',
      );
      expect(
        AttendanceAdminScope.jadwalBannerHint(p('admin_toko', 'CABANG-X')),
        'Toko CABANG-X saja',
      );
      expect(
        AttendanceAdminScope.geofenceBannerHint(p('admin_toko', 'CABANG-X')),
        'Toko CABANG-X saja',
      );
      expect(
        AttendanceAdminScope.monitorBannerHint(p('admin_toko', 'CABANG-X')),
        'Toko CABANG-X saja',
      );
      expect(
        AttendanceAdminScope.monitorBannerHint(p('owner', 'PUSAT')),
        'Semua toko termasuk Pusat',
      );
      expect(
        AttendanceAdminScope.monitorBannerHint(p('admin_pusat', 'PUSAT')),
        'Cabang saja (tanpa absensi Pusat)',
      );
    });
  });

  group('canEditProductCatalog', () {
    test('admin_toko boleh edit katalog, kasir tidak', () {
      expect(
        AttendanceAdminScope.canEditProductCatalog(p('admin_toko', 'CABANG-X')),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canEditProductCatalog(p('kasir', 'CABANG-X')),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canEditProductCatalog(p('admin_pusat', 'PUSAT')),
        isTrue,
      );
    });
  });
}
