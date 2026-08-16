import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/karyawan_jabatan.dart';
import 'package:optik_b_riski/shared/karyawan/shift_auto_assign.dart';
import 'package:optik_b_riski/shared/karyawan/streak_fire_level.dart';

/// Mirrors LabJobService.isBackOffice without constructing Supabase client.
bool isBackOffice(String? jabatan) =>
    officeLayerOf(jabatan) == OfficeLayer.back;

/// Mirrors main_karyawan.dart `_showLabQueue`.
bool showLabQueueFor({
  required String jabatan,
  required String absenStatus,
  bool hasOpenJobs = false,
  bool hasMineJobs = false,
}) {
  if (!isBackOffice(jabatan)) return false;
  return absenStatus == 'sedang_bekerja' || hasOpenJobs || hasMineJobs;
}

/// Mirrors main_karyawan.dart `_showChecklistBukaTutup`.
bool showChecklistBukaTutup(String jabatan) {
  final j = KaryawanJabatan.normalize(jabatan);
  return j == 'frontliner' ||
      j == 'backliner' ||
      j == 'kepala toko' ||
      j == 'kepala area' ||
      j == 'kasir';
}

void main() {
  group('officeLayerOf Front/Back mapping', () {
    test('Front path jabatan', () {
      expect(officeLayerOf('Frontliner'), OfficeLayer.front);
      expect(officeLayerOf('Kasir'), OfficeLayer.front);
      expect(officeLayerOf('RO'), OfficeLayer.front);
    });

    test('Back path jabatan', () {
      expect(officeLayerOf('Backliner'), OfficeLayer.back);
      expect(officeLayerOf('Kepala Toko'), OfficeLayer.back);
      expect(officeLayerOf('Kepala Area'), OfficeLayer.back);
      expect(officeLayerOf('Admin'), OfficeLayer.back);
      expect(officeLayerOf('Owner'), OfficeLayer.back);
    });
  });

  group('11.5 antrian lab hanya Back', () {
    test('Frontliner never sees lab queue', () {
      expect(
        showLabQueueFor(
          jabatan: 'Frontliner',
          absenStatus: 'sedang_bekerja',
          hasOpenJobs: true,
        ),
        isFalse,
      );
      expect(isBackOffice('Frontliner'), isFalse);
      expect(isBackOffice('Kasir'), isFalse);
    });

    test('Backliner sees lab when working or has jobs', () {
      expect(
        showLabQueueFor(jabatan: 'Backliner', absenStatus: 'sedang_bekerja'),
        isTrue,
      );
      expect(
        showLabQueueFor(
          jabatan: 'Backliner',
          absenStatus: 'belum_masuk',
          hasOpenJobs: true,
        ),
        isTrue,
      );
      expect(
        showLabQueueFor(jabatan: 'Backliner', absenStatus: 'belum_masuk'),
        isFalse,
      );
    });

    test('Admin/KT map Back so can see lab gate', () {
      expect(isBackOffice('Admin'), isTrue);
      expect(isBackOffice('Kepala Toko'), isTrue);
    });
  });

  group('11.6 checklist Front/Back/KT/KA/Kasir', () {
    test('allowed roles', () {
      for (final j in [
        'Frontliner',
        'Backliner',
        'Kepala Toko',
        'Kepala Area',
        'Kasir',
      ]) {
        expect(showChecklistBukaTutup(j), isTrue, reason: j);
      }
    });

    test('Admin/Owner excluded from home checklist card', () {
      expect(showChecklistBukaTutup('Admin'), isFalse);
      expect(showChecklistBukaTutup('Owner'), isFalse);
    });
  });

  group('11.9 Api KPI 0 pts = L1', () {
    test('forKpiProgress(0) → level 1', () {
      expect(StreakFireLevel.forKpiProgress(0).level, 1);
      expect(StreakFireLevel.forKpiProgress(0.0).level, 1);
    });
  });
}
