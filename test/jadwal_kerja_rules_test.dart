import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/jadwal_kerja_rules.dart';

void main() {
  group('pengajuan status machine', () {
    test('hanya PENDING yang bisa diputus atau dibatalkan', () {
      expect(JadwalKerjaRules.canDecide('PENDING'), isTrue);
      expect(JadwalKerjaRules.canCancel('pending'), isTrue);
      expect(JadwalKerjaRules.canDecide('APPROVED'), isFalse);
      expect(JadwalKerjaRules.canCancel('REJECTED'), isFalse);
      expect(JadwalKerjaRules.canDecide('CANCELLED'), isFalse);
      expect(JadwalKerjaRules.isTerminal('APPROVED'), isTrue);
      expect(JadwalKerjaRules.isTerminal('PENDING'), isFalse);
    });

    test('tipe hanya IJIN CUTI TUKAR', () {
      expect(JadwalKerjaRules.isAllowedTipe('ijin'), isTrue);
      expect(JadwalKerjaRules.isAllowedTipe('CUTI'), isTrue);
      expect(JadwalKerjaRules.isAllowedTipe('TUKAR'), isTrue);
      expect(JadwalKerjaRules.isAllowedTipe('LIBUR'), isFalse);
      expect(JadwalKerjaRules.isAllowedTipe(''), isFalse);
    });
  });

  group('jam dan kuota', () {
    test('jam HH:mm valid 00:00–23:59', () {
      expect(JadwalKerjaRules.isValidTime('08:30'), isTrue);
      expect(JadwalKerjaRules.isValidTime('13:00'), isTrue);
      expect(JadwalKerjaRules.isValidTime('23:59'), isTrue);
      expect(JadwalKerjaRules.isValidTime('24:00'), isFalse);
      expect(JadwalKerjaRules.isValidTime('8:30'), isFalse);
      expect(JadwalKerjaRules.isValidTime('08:30:00'), isFalse);
      expect(JadwalKerjaRules.isValidTime(''), isFalse);
    });

    test('kuota 0–40', () {
      expect(JadwalKerjaRules.clampKuota(-3), 0);
      expect(JadwalKerjaRules.clampKuota(3), 3);
      expect(JadwalKerjaRules.clampKuota(40), 40);
      expect(JadwalKerjaRules.clampKuota(99), 40);
    });
  });
}
