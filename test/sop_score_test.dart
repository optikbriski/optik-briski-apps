import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/shift_auto_assign.dart';
import 'package:optik_b_riski/shared/karyawan/sop_score.dart';

SopScoreResult score({
  required OfficeLayer layer,
  required bool pagi,
  int story = 8,
  int displayDone = 3,
  int displayRequired = 3,
  bool stok = true,
  bool sapu = true,
  bool aktif = true,
  bool libur = false,
}) {
  return SopScore.compute(
    SopScoreInput(
      layer: layer,
      isPagi: pagi,
      isAktif: aktif,
      isLibur: libur,
      storyCount: story,
      displayDone: displayDone,
      displayRequired: displayRequired,
      stokDone: stok,
      sapuDone: sapu,
    ),
  );
}

void main() {
  group('SopScore balancing table', () {
    test('semua beres → +25', () {
      expect(score(layer: OfficeLayer.front, pagi: true).poin, 25);
      expect(score(layer: OfficeLayer.back, pagi: true).poin, 25);
      expect(score(layer: OfficeLayer.front, pagi: false).poin, 25);
      expect(score(layer: OfficeLayer.back, pagi: false).poin, 25);
    });

    test('0 story fatal → −25', () {
      for (final layer in OfficeLayer.values) {
        for (final pagi in [true, false]) {
          final r = score(layer: layer, pagi: pagi, story: 0);
          expect(r.poin, -25);
          expect(r.fatalStory, isTrue);
        }
      }
    });

    test('story 4/8 + core+sapu → +13', () {
      expect(score(layer: OfficeLayer.front, pagi: true, story: 4).poin, 13);
      expect(score(layer: OfficeLayer.back, pagi: true, story: 4).poin, 13);
      expect(score(layer: OfficeLayer.front, pagi: false, story: 4).poin, 13);
      expect(score(layer: OfficeLayer.back, pagi: false, story: 4).poin, 13);
    });

    test('story 8, core gagal, sapu OK → pagi +8 / siang 0', () {
      // 0.50*1 + 0.35*0 + 0.15*1 = 0.65 → round(25*0.30)=8
      expect(
        score(
          layer: OfficeLayer.front,
          pagi: true,
          displayDone: 0,
          sapu: true,
        ).poin,
        8,
      );
      expect(
        score(
          layer: OfficeLayer.back,
          pagi: true,
          stok: false,
          sapu: true,
        ).poin,
        8,
      );
      expect(
        score(layer: OfficeLayer.front, pagi: false, displayDone: 0).poin,
        0,
      );
      expect(
        score(layer: OfficeLayer.back, pagi: false, stok: false).poin,
        0,
      );
    });

    test('story 8, core OK, sapu gagal pagi → +18', () {
      expect(
        score(layer: OfficeLayer.front, pagi: true, sapu: false).poin,
        18,
      );
      expect(
        score(layer: OfficeLayer.back, pagi: true, sapu: false).poin,
        18,
      );
    });

    test('story 8, setengah core (0.5), sapu OK → pagi +16 / siang +13', () {
      expect(
        score(
          layer: OfficeLayer.front,
          pagi: true,
          displayDone: 1,
          displayRequired: 2,
        ).poin,
        16,
      );
      expect(
        score(
          layer: OfficeLayer.front,
          pagi: false,
          displayDone: 1,
          displayRequired: 2,
        ).poin,
        13,
      );
    });

    test('libur / tidak aktif → 0', () {
      expect(score(layer: OfficeLayer.front, pagi: true, libur: true).poin, 0);
      expect(score(layer: OfficeLayer.front, pagi: true, aktif: false).poin, 0);
    });
  });

  test('isPagiShift', () {
    expect(SopScore.isPagiShift(jamMasuk: '09:00'), isTrue);
    expect(SopScore.isPagiShift(jamMasuk: '14:00'), isFalse);
    expect(SopScore.isPagiShift(shiftLabel: 'Siang'), isFalse);
    expect(SopScore.isPagiShift(shiftLabel: 'Pagi'), isTrue);
  });
}
