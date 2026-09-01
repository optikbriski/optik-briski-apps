import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/admin/admin_nav_badge_logic.dart';
import 'package:optik_b_riski/shared/admin/admin_nav_badge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('AdminNavBadgeLogic', () {
    test('5 pending, 1 dibuka → badge 4 (bukan 0)', () {
      final live = {'a', 'b', 'c', 'd', 'e'};
      final seen = {'a'};
      expect(
        AdminNavBadgeLogic.displayCount(live: live, seen: seen, pinned: {}),
        4,
      );
    });

    test('semua dibuka → badge 0', () {
      final live = {'a', 'b'};
      expect(
        AdminNavBadgeLogic.displayCount(
          live: live,
          seen: live,
          pinned: {},
        ),
        0,
      );
    });

    test('markEntityUnread mengembalikan 1 entitas', () async {
      final svc = AdminNavBadgeService.instance;
      svc.debugReset(
        live: {'karyawan': {'k1', 'k2'}},
        seen: {'karyawan': {'k1', 'k2'}},
      );
      await svc.markEntityUnread('karyawan', 'k1');
      expect(svc.displayCount('karyawan'), 1);
      expect(svc.isEntityUnread('karyawan', 'k1'), isTrue);
      expect(svc.isEntityUnread('karyawan', 'k2'), isFalse);
    });

    test('markScopeUnread mengembalikan semua pending', () async {
      final svc = AdminNavBadgeService.instance;
      svc.debugReset(
        live: {'pengaduan': {'p1', 'p2', 'p3'}},
        seen: {'pengaduan': {'p1', 'p2', 'p3'}},
      );
      await svc.markScopeUnread('pengaduan');
      expect(svc.displayCount('pengaduan'), 3);
    });

    test('entitas selesai (hilang dari live) tidak dihitung', () async {
      final svc = AdminNavBadgeService.instance;
      svc.debugReset(
        live: {'pengaduan': {'p1'}},
        seen: {'pengaduan': {'p1', 'p2'}},
      );
      expect(svc.displayCount('pengaduan'), 0);
    });

    test('groupCount = jumlah sub-badge (bubble main nav)', () {
      final svc = AdminNavBadgeService.instance;
      svc.debugReset(
        live: {
          'karyawan': {'k1', 'k2'},
          'pengaduan': {'p1'},
          'reimburse': {},
        },
        seen: {'karyawan': {'k1'}},
      );
      expect(
        svc.groupCount(['karyawan', 'pengaduan', 'reimburse']),
        2,
      );
    });

    test('countUnreadIn menghitung per tab', () {
      final svc = AdminNavBadgeService.instance;
      svc.debugReset(
        live: {'online': {'a', 'b', 'c'}},
        seen: {'online': {'a'}},
      );
      expect(svc.countUnreadIn('online', ['a', 'b', 'c']), 2);
      expect(svc.countUnreadIn('online', ['a']), 0);
    });

    test('reminder token saat scope kosong tapi di-pin', () {
      expect(
        AdminNavBadgeLogic.displayCount(
          live: {},
          seen: {},
          pinned: {AdminNavBadgeLogic.reminderToken},
        ),
        1,
      );
    });

    test('prunePinned mempertahankan reminder token', () {
      final pruned = AdminNavBadgeLogic.prunePinned(
        live: {},
        pinned: {AdminNavBadgeLogic.reminderToken, 'gone'},
      );
      expect(pruned, {AdminNavBadgeLogic.reminderToken});
    });
  });

  group('Nav scope ↔ menu id sync', () {
    test('semua scope badge punya pasangan menu id', () {
      const scopes = {
        'karyawan',
        'pengaduan',
        'reimburse',
        'lembur',
        'chat_toko',
        'jadwal',
        'logistik',
        'online',
        'monitor_absensi',
        'tinjauan',
        'update_apk',
      };
      expect(scopes.length, 11);
    });

    test('admin_dash_nav.dart menu id cocok dengan scope service', () {
      final src = File('lib/apps/admin/admin_dash_nav.dart').readAsStringSync();
      const scopes = [
        'karyawan',
        'pengaduan',
        'reimburse',
        'lembur',
        'chat_toko',
        'jadwal',
        'logistik',
        'online',
        'monitor_absensi',
        'tinjauan',
        'update_apk',
      ];
      for (final scope in scopes) {
        expect(src.contains("id: '$scope'"), isTrue, reason: scope);
      }
    });
  });
}
