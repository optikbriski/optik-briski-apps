import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/kpi_fire_service.dart';
import 'package:optik_b_riski/shared/karyawan/streak_fire_level.dart';

void main() {
  // Target: 26×45=1170, 27×45=1215 (absen 20 + SOP penuh 25).
  const t26 = 1170;
  const t27 = 1215;

  group('targetFromWorkDays', () {
    test('fallback 26 hari → 1170', () {
      expect(KpiFireSnapshot.targetFromWorkDays(0), t26);
      expect(KpiFireSnapshot.monthlyPointTarget, t26);
      expect(KpiFireSnapshot.pointsPerLevel(t26), 234);
    });

    test('clamp 26–27', () {
      expect(KpiFireSnapshot.targetFromWorkDays(20), t26);
      expect(KpiFireSnapshot.targetFromWorkDays(26), t26);
      expect(KpiFireSnapshot.targetFromWorkDays(27), t27);
      expect(KpiFireSnapshot.targetFromWorkDays(30), t27);
      expect(KpiFireSnapshot.pointsPerLevel(t27), 243);
    });
  });

  group('level sync dengan poin', () {
    void expectBandMatchesLevel(int target) {
      for (var pts = -50; pts <= target + 40; pts++) {
        final p = KpiFireSnapshot.progressFromPoints(pts, target: target);
        final level = StreakFireLevel.forKpiProgress(p).level;
        final band = KpiFireSnapshot.pointBandForLevel(level, target);

        if (pts <= 0) {
          expect(level, 1, reason: 'pts=$pts harus L1');
          continue;
        }
        if (pts > target) {
          expect(level, 5, reason: 'pts=$pts > target harus L5');
          continue;
        }
        expect(
          pts >= band.lo && pts <= band.hi,
          isTrue,
          reason: 'pts=$pts lv=$level band=${band.lo}-${band.hi} target=$target',
        );
      }
    }

    test('setiap poin di target 1170 masuk band level yang benar', () {
      expectBandMatchesLevel(t26);
    });

    test('setiap poin di target 1215 masuk band level yang benar', () {
      expectBandMatchesLevel(t27);
    });

    test('batas naik level 1170', () {
      expect(StreakFireLevel.forKpiProgress(234 / t26).level, 1);
      expect(StreakFireLevel.forKpiProgress(235 / t26).level, 2);
      expect(StreakFireLevel.forKpiProgress(468 / t26).level, 2);
      expect(StreakFireLevel.forKpiProgress(469 / t26).level, 3);
      expect(StreakFireLevel.forKpiProgress(702 / t26).level, 3);
      expect(StreakFireLevel.forKpiProgress(703 / t26).level, 4);
      expect(StreakFireLevel.forKpiProgress(936 / t26).level, 4);
      expect(StreakFireLevel.forKpiProgress(937 / t26).level, 5);
      expect(StreakFireLevel.forKpiProgress(1.0).level, 5);
      expect(StreakFireLevel.forKpiProgress(0).level, 1);
    });

    test('syncedWithPoints menjaga target & sinkron fire', () {
      final base = KpiFireSnapshot.empty().syncedWithPoints(0);
      expect(base.fire.level, 1);
      expect(base.progress, 0);
      expect(base.totalPoin, 0);

      final mid = base.syncedWithPoints(469);
      expect(mid.pointTarget, base.pointTarget);
      expect(mid.totalPoin, 469);
      expect(mid.fire.level, 3);
      expect(mid.pointsToNextLevel(), 703 - 469);

      final maxed = mid.syncedWithPoints(2000);
      expect(maxed.progress, 1.0);
      expect(maxed.fire.level, 5);
      expect(maxed.pointsToNextLevel(), 0);
    });

    test('pointsToNextLevel dari 0', () {
      final s = KpiFireSnapshot.empty();
      expect(s.pointsToNextLevel(), 235);
    });
  });

  group('pointBandForLevel', () {
    test('rentang 1170', () {
      expect(KpiFireSnapshot.pointBandForLevel(1, t26), (lo: 0, hi: 234));
      expect(KpiFireSnapshot.pointBandForLevel(2, t26), (lo: 235, hi: 468));
      expect(KpiFireSnapshot.pointBandForLevel(3, t26), (lo: 469, hi: 702));
      expect(KpiFireSnapshot.pointBandForLevel(4, t26), (lo: 703, hi: 936));
      expect(KpiFireSnapshot.pointBandForLevel(5, t26), (lo: 937, hi: t26));
    });

    test('rentang 1215', () {
      expect(KpiFireSnapshot.pointBandForLevel(1, t27), (lo: 0, hi: 243));
      expect(KpiFireSnapshot.pointBandForLevel(2, t27), (lo: 244, hi: 486));
      expect(KpiFireSnapshot.pointBandForLevel(3, t27), (lo: 487, hi: 729));
      expect(KpiFireSnapshot.pointBandForLevel(4, t27), (lo: 730, hi: 972));
      expect(KpiFireSnapshot.pointBandForLevel(5, t27), (lo: 973, hi: t27));
    });
  });
}
