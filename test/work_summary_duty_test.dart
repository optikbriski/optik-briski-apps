import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/work_summary_service.dart';

void main() {
  group('workDutyStatus', () {
    test('tanpa jadwal → noJadwal', () {
      expect(
        workDutyStatus(
          hasJadwal: false,
          isLibur: false,
          hasOpenShift: false,
          hasMasuk: false,
          hasPulang: false,
        ),
        WorkDutyStatus.noJadwal,
      );
    });

    test('libur tanpa absen → libur', () {
      expect(
        workDutyStatus(
          hasJadwal: true,
          isLibur: true,
          hasOpenShift: false,
          hasMasuk: false,
          hasPulang: false,
        ),
        WorkDutyStatus.libur,
      );
    });

    test('jadwal kerja, belum absen → belumMasuk', () {
      expect(
        workDutyStatus(
          hasJadwal: true,
          isLibur: false,
          hasOpenShift: false,
          hasMasuk: false,
          hasPulang: false,
        ),
        WorkDutyStatus.belumMasuk,
      );
    });

    test('shift OPEN → bertugas (meski jadwal libur)', () {
      expect(
        workDutyStatus(
          hasJadwal: true,
          isLibur: true,
          hasOpenShift: true,
          hasMasuk: true,
          hasPulang: false,
        ),
        WorkDutyStatus.bertugas,
      );
    });

    test('sudah masuk, belom pulang → bertugas', () {
      expect(
        workDutyStatus(
          hasJadwal: true,
          isLibur: false,
          hasOpenShift: false,
          hasMasuk: true,
          hasPulang: false,
        ),
        WorkDutyStatus.bertugas,
      );
    });

    test('sudah pulang, shift OPEN → bertugas', () {
      expect(
        workDutyStatus(
          hasJadwal: true,
          isLibur: false,
          hasOpenShift: true,
          hasMasuk: true,
          hasPulang: true,
        ),
        WorkDutyStatus.bertugas,
      );
    });
  });
}
