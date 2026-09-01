import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/sop_story_resolve.dart';

void main() {
  group('SopStoryResolve', () {
    test('tanpa akun IG → honor', () {
      final r = SopStoryResolve.pick(
        hasAccount: false,
        honorCount: 3,
      );
      expect(r.count, 3);
      expect(r.live, isFalse);
      expect(r.fromIg, isFalse);
    });

    test('IG sukses 0 → 0 (fatal sah)', () {
      final r = SopStoryResolve.pick(
        hasAccount: true,
        igCount: 0,
        honorCount: 8,
      );
      expect(r.count, 0);
      expect(r.live, isTrue);
      expect(r.fromIg, isTrue);
    });

    test('IG gagal tanpa cache → honor, bukan 0', () {
      final r = SopStoryResolve.pick(
        hasAccount: true,
        honorCount: 5,
      );
      expect(r.count, 5);
      expect(r.live, isFalse);
      expect(r.fromIg, isFalse);
    });

    test('IG gagal + cache → pakai cache', () {
      final r = SopStoryResolve.pick(
        hasAccount: true,
        cacheCount: 7,
        honorCount: 1,
      );
      expect(r.count, 7);
      expect(r.live, isTrue);
      expect(r.fromIg, isTrue);
    });

    test('IG sukses mengalahkan cache & honor', () {
      final r = SopStoryResolve.pick(
        hasAccount: true,
        igCount: 8,
        cacheCount: 2,
        honorCount: 1,
      );
      expect(r.count, 8);
      expect(r.live, isTrue);
    });
  });
}
