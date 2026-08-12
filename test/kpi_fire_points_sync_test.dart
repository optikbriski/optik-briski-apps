import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/kpi_fire_service.dart';
import 'package:optik_b_riski/shared/karyawan/streak_fire_level.dart';

void main() {
  group('targetFromWorkDays', () {
    test('fallback 26 hari → 1040', () {
      expect(KpiFireSnapshot.targetFromWorkDays(0), 1040);
      expect(KpiFireSnapshot.monthlyPointTarget, 1040);
      expect(KpiFireSnapshot.pointsPerLevel(1040), 208);
    });

    test('clamp 26–27', () {
      expect(KpiFireSnapshot.targetFromWorkDays(20), 1040); // naik ke min 26
      expect(KpiFireSnapshot.targetFromWorkDays(26), 1040);
      expect(KpiFireSnapshot.targetFromWorkDays(27), 1080);
      expect(KpiFireSnapshot.targetFromWorkDays(30), 1080); // turun ke max 27
      expect(KpiFireSnapshot.pointsPerLevel(1080), 216);
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

    test('setiap poin di target 1040 masuk band level yang benar', () {
      expectBandMatchesLevel(1040);
    });

    test('setiap poin di target 1080 masuk band level yang benar', () {
      expectBandMatchesLevel(1080);
    });

    test('batas naik level 1040', () {
      expect(StreakFireLevel.forKpiProgress(208 / 1040).level, 1);
      expect(StreakFireLevel.forKpiProgress(209 / 1040).level, 2);
      expect(StreakFireLevel.forKpiProgress(416 / 1040).level, 2);
      expect(StreakFireLevel.forKpiProgress(417 / 1040).level, 3);
      expect(StreakFireLevel.forKpiProgress(624 / 1040).level, 3);
      expect(StreakFireLevel.forKpiProgress(625 / 1040).level, 4);
      expect(StreakFireLevel.forKpiProgress(832 / 1040).level, 4);
      expect(StreakFireLevel.forKpiProgress(833 / 1040).level, 5);
      expect(StreakFireLevel.forKpiProgress(1.0).level, 5);
      expect(StreakFireLevel.forKpiProgress(0).level, 1);
    });

    test('syncedWithPoints menjaga target & sinkron fire', () {
      final base = KpiFireSnapshot.empty().syncedWithPoints(0);
      expect(base.fire.level, 1);
      expect(base.progress, 0);
      expect(base.totalPoin, 0);

      final mid = base.syncedWithPoints(417);
      expect(mid.pointTarget, base.pointTarget);
      expect(mid.totalPoin, 417);
      // 417/1040 = 0.401 → ceil(2.005)=3
      expect(mid.fire.level, 3);
      expect(mid.pointsToNextLevel(), 625 - 417);

      final maxed = mid.syncedWithPoints(2000);
      expect(maxed.progress, 1.0);
      expect(maxed.fire.level, 5);
      expect(maxed.pointsToNextLevel(), 0);
    });

    test('pointsToNextLevel dari 0', () {
      final s = KpiFireSnapshot.empty();
      expect(s.pointsToNextLevel(), 209); // L2 mulai 209 di target 1040
    });
  });

  group('pointBandForLevel', () {
    test('rentang 1040', () {
      expect(KpiFireSnapshot.pointBandForLevel(1, 1040), (lo: 0, hi: 208));
      expect(KpiFireSnapshot.pointBandForLevel(2, 1040), (lo: 209, hi: 416));
      expect(KpiFireSnapshot.pointBandForLevel(3, 1040), (lo: 417, hi: 624));
      expect(KpiFireSnapshot.pointBandForLevel(4, 1040), (lo: 625, hi: 832));
      expect(KpiFireSnapshot.pointBandForLevel(5, 1040), (lo: 833, hi: 1040));
    });

    test('rentang 1080', () {
      expect(KpiFireSnapshot.pointBandForLevel(1, 1080), (lo: 0, hi: 216));
      expect(KpiFireSnapshot.pointBandForLevel(2, 1080), (lo: 217, hi: 432));
      expect(KpiFireSnapshot.pointBandForLevel(3, 1080), (lo: 433, hi: 648));
      expect(KpiFireSnapshot.pointBandForLevel(4, 1080), (lo: 649, hi: 864));
      expect(KpiFireSnapshot.pointBandForLevel(5, 1080), (lo: 865, hi: 1080));
    });
  });
}
