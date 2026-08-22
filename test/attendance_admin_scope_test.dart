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
  });

  group('monitor write + banner', () {
    test('requireTokoId rejects empty', () {
      expect(() => AttendanceAdminScope.requireTokoId(''), throwsStateError);
      expect(AttendanceAdminScope.requireTokoId('CABANG-X'), 'CABANG-X');
    });

    test('banner is store-specific for admin_toko', () {
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
}
