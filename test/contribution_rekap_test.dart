import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/contribution_rekap.dart';

void main() {
  test('fair share and ±10pp badges', () {
    final rekap = ContributionRekap.build(
      layerLabel: 'Front',
      unitsById: {
        'a': 60,
        'b': 40,
      },
      namaById: {'a': 'A', 'b': 'B'},
      jabatanById: {'a': 'Kasir', 'b': 'Kasir'},
      hariKerjaById: {'a': 26, 'b': 26},
      targetHari: 26,
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 31),
    );

    expect(rekap.fairShare, 0.5);
    expect(rekap.unitTim, 100);
    expect(rekap.peers.first.karyawanId, 'a');
    expect(rekap.peers.first.aktualPct, 0.6);
    expect(rekap.peers.first.deltaPp, closeTo(10, 0.01));
    expect(rekap.peers.first.isAboveFair, isFalse); // exactly +10 not >
    expect(rekap.peers.first.poin, 300);

    final below = rekap.peers.firstWhere((p) => p.karyawanId == 'b');
    expect(below.deltaPp, closeTo(-10, 0.01));
    expect(below.isBelowFair, isFalse);
  });

  test('above/below flags and schedule imbalance', () {
    final rekap = ContributionRekap.build(
      layerLabel: 'Back',
      unitsById: {'a': 80, 'b': 20},
      namaById: {'a': 'A', 'b': 'B'},
      jabatanById: {'a': 'Backliner', 'b': 'Backliner'},
      hariKerjaById: {'a': 26, 'b': 12},
      targetHari: 26,
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 31),
    );
    final a = rekap.peers.firstWhere((p) => p.karyawanId == 'a');
    final b = rekap.peers.firstWhere((p) => p.karyawanId == 'b');
    expect(a.isAboveFair, isTrue);
    expect(b.isBelowFair, isTrue);
    expect(b.scheduleImbalance, isTrue);
    expect(rekap.hasScheduleImbalance, isTrue);
  });
}
