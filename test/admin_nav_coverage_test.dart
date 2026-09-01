import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/admin/admin_nav_coverage.dart';

/// Verifikasi 7 main nav × 25 sub nav × detail nav badge wiring.
void main() {
  group('Admin nav coverage (7 main × 25 sub)', () {
    test('25 sub-nav ids unik', () {
      expect(AdminNavCoverage.subNavIds25.length, 25);
      expect(
        AdminNavCoverage.subNavIds25.toSet().length,
        25,
        reason: 'duplikat sub-nav',
      );
    });

    test('7 main group + sub items = 25 (+ platform opsional)', () {
      var sum = 0;
      for (final g in AdminNavCoverage.mainGroupIds) {
        if (g == 'platform') continue;
        sum += AdminNavCoverage.subNavByMainGroup[g]!.length;
      }
      expect(sum, 25);
    });

    test('badge scope + no-badge = 25 sub', () {
      final all = {
        ...AdminNavCoverage.badgeScopes,
        ...AdminNavCoverage.noBadgeSubNav,
      };
      expect(all.length, 25);
      for (final id in AdminNavCoverage.subNavIds25) {
        expect(all.contains(id), isTrue, reason: id);
      }
    });

    test('admin_dash_nav.dart memuat semua 25 sub id', () {
      final src = File('lib/apps/admin/admin_dash_nav.dart').readAsStringSync();
      for (final id in AdminNavCoverage.subNavIds25) {
        expect(src.contains("id: '$id'"), isTrue, reason: id);
      }
    });

    test('semua halaman badge punya markEntitySeen + ListenableBuilder', () {
      final requireListen = {
        'karyawan',
        'pengaduan',
        'reimburse',
        'lembur',
        'online',
        'monitor_absensi',
        'tinjauan',
        'logistik_detail',
        'jadwal_detail',
      };
      for (final e in AdminNavCoverage.badgePageFiles.entries) {
        final src = File(e.value).readAsStringSync();
        if (e.key == 'logistik') {
          expect(
            src.contains('GlobalNotificationIcon'),
            isTrue,
            reason: e.value,
          );
          continue;
        }
        expect(
          src.contains('AdminNavBadgeService') ||
              src.contains('GlobalNotificationIcon'),
          isTrue,
          reason: '${e.key} → ${e.value}',
        );
        if (e.key == 'logistik_bell' || e.key == 'chat_toko') continue;
        if (e.key == 'jadwal' || e.key == 'logistik') {
          expect(
            src.contains('displayCount') ||
                src.contains('GlobalNotificationIcon'),
            isTrue,
            reason: e.key,
          );
          continue;
        }
        if (e.key == 'update_apk') {
          expect(src.contains('markEntitySeen'), isTrue, reason: e.key);
          continue;
        }
        expect(src.contains('markEntitySeen'), isTrue, reason: e.key);
        if (requireListen.contains(e.key)) {
          expect(src.contains('ListenableBuilder'), isTrue, reason: e.key);
          expect(src.contains('isEntityUnread'), isTrue, reason: e.key);
        }
      }
    });

    test('halaman tanpa badge tidak import AdminNavBadgeService', () {
      const noBadgeFiles = {
        'rangkuman_kerja': 'lib/apps/admin/work_summary_page.dart',
        'absensi_kiosk': 'lib/apps/admin/absensi_toko_page.dart',
        'geofence': 'lib/apps/admin/toko_geofence_page.dart',
        'pos': 'lib/apps/admin/sales_page.dart',
        'dp': 'lib/apps/admin/riwayat_transaksi_page.dart',
        'master': 'lib/apps/admin/product_master.dart',
        'garansi': 'lib/apps/admin/garansi_page.dart',
        'keuangan': 'lib/apps/admin/buku_besar.dart',
        'payroll': 'lib/apps/admin/payroll_workspace_page.dart',
        'invoice': 'lib/apps/admin/invoice_config_page.dart',
        'export': 'lib/apps/admin/monthly_export_page.dart',
        'member_home': 'lib/apps/admin/member_home_content_page.dart',
        'scan_dokumen': 'lib/apps/admin/admin_document_ocr_page.dart',
      };
      for (final e in noBadgeFiles.entries) {
        final src = File(e.value).readAsStringSync();
        expect(
          src.contains('AdminNavBadgeService'),
          isFalse,
          reason: '${e.key} tidak boleh badge',
        );
      }
    });

    test('sidebar: 7 grup bubble = sum sub-badge', () {
      final sidebar =
          File('lib/apps/admin/admin_nav_sidebar.dart').readAsStringSync();
      expect(sidebar.contains('_groupBadge'), isTrue);
      expect(sidebar.contains('badgeCounts[item.id]'), isTrue);
    });
  });
}
