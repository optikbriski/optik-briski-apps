import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Audit statis end-to-end — jalankan ulang kapan saja sebelum deploy toko.
void main() {
  group('Admin nav badge E2E audit (static)', () {
    late String dashOpen;
    late String serviceSrc;
    late String globalNotif;

    setUpAll(() {
      dashOpen = File('lib/apps/admin/dashboard_page.dart').readAsStringSync();
      serviceSrc =
          File('lib/shared/admin/admin_nav_badge_service.dart').readAsStringSync();
      globalNotif =
          File('lib/apps/admin/global_notification.dart').readAsStringSync();
    });

    test('dashboard: buka menu TIDAK panggil markEntitySeen/markRead', () {
      expect(dashOpen.contains('markEntitySeen'), isFalse);
      expect(dashOpen.contains('markRead('), isFalse);
      expect(dashOpen.contains('markScopeUnread'), isTrue);
    });

    test('global_notification: tidak ada polling 30 detik', () {
      expect(globalNotif.contains('Timer.periodic'), isFalse);
      expect(globalNotif.contains('AdminNavBadgeService'), isTrue);
      expect(globalNotif.contains("displayCount('logistik')"), isTrue);
    });

    test('service: 11 scope loader + realtime tables', () {
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
      for (final s in scopes) {
        expect(serviceSrc.contains("'$s'"), isTrue, reason: 'scope $s');
      }
      expect(serviceSrc.contains('onPostgresChanges'), isTrue);
      expect(serviceSrc.contains('_prefChatBaselinedKey'), isTrue);
    });

    test('markEntitySeen wired di semua halaman isi', () {
      final wiring = <String, String>{
        'karyawan': 'lib/shared/admin_approval_page.dart',
        'pengaduan': 'lib/apps/admin/pengaduan_inbox_page.dart',
        'reimburse': 'lib/apps/admin/reimburse_inbox_page.dart',
        'lembur': 'lib/apps/admin/lembur_inbox_page.dart',
        'chat_toko': 'lib/apps/karyawan/toko_chat_page.dart',
        'jadwal': 'lib/apps/admin/jadwal_pengajuan_approval_page.dart',
        'logistik': 'lib/apps/admin/verifikasi_terima.dart',
        'online': 'lib/apps/admin/online_orders_page.dart',
        'monitor_absensi': 'lib/apps/admin/attendance_monitor_page.dart',
        'tinjauan': 'lib/apps/admin/tinjauan_mencurigakan_page.dart',
        'update_apk': 'lib/shared/app_update/app_software_update_page.dart',
      };
      for (final e in wiring.entries) {
        final src = File(e.value).readAsStringSync();
        expect(
          src.contains("markEntitySeen('${e.key}'") ||
              src.contains('markEntitySeen(\n        \'${e.key}\'') ||
              src.contains("markEntitySeen(\n        '${e.key}'"),
          isTrue,
          reason: '${e.key} → ${e.value}',
        );
      }
    });

    test('sidebar: long-press mark unread + context menu', () {
      final sidebar =
          File('lib/apps/admin/admin_nav_sidebar.dart').readAsStringSync();
      expect(sidebar.contains('admin_nav_mark_unread'), isTrue);
      expect(sidebar.contains('onMarkItemUnread'), isTrue);
      expect(sidebar.contains('onLongPress'), isTrue);
    });

    test('i18n mark unread ada di semua locale', () {
      for (final loc in ['id', 'en', 'ja', 'ms', 'zh']) {
        final raw =
            File('assets/translations/$loc.json').readAsStringSync();
        expect(raw.contains('admin_nav_mark_unread'), isTrue, reason: loc);
      }
    });

    test('detail nav: ListenableBuilder + isEntityUnread di semua inbox', () {
      const detailPages = [
        'lib/shared/admin_approval_page.dart',
        'lib/apps/admin/pengaduan_inbox_page.dart',
        'lib/apps/admin/reimburse_inbox_page.dart',
        'lib/apps/admin/lembur_inbox_page.dart',
        'lib/apps/admin/online_orders_page.dart',
        'lib/apps/admin/attendance_monitor_page.dart',
        'lib/apps/admin/tinjauan_mencurigakan_page.dart',
        'lib/apps/admin/verifikasi_terima.dart',
        'lib/apps/admin/jadwal_pengajuan_approval_page.dart',
      ];
      for (final path in detailPages) {
        final src = File(path).readAsStringSync();
        expect(src.contains('ListenableBuilder'), isTrue, reason: path);
        expect(src.contains('isEntityUnread'), isTrue, reason: path);
      }
    });

    test('detail nav badge: tab verifikasi + filter OPEN pengaduan', () {
      final appr =
          File('lib/shared/admin_approval_page.dart').readAsStringSync();
      final peng =
          File('lib/apps/admin/pengaduan_inbox_page.dart').readAsStringSync();
      final jadwal =
          File('lib/apps/admin/jadwal_kerja_page.dart').readAsStringSync();
      expect(appr.contains("displayCount('karyawan')"), isTrue);
      expect(peng.contains("displayCount('pengaduan')"), isTrue);
      expect(jadwal.contains("displayCount('jadwal')"), isTrue);
    });
  });
}
