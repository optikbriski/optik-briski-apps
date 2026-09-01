import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/apps/admin/admin_nav_sidebar.dart';
import 'package:optik_b_riski/apps/admin/admin_dash_nav.dart';
import 'package:optik_b_riski/shared/admin/admin_nav_badge_service.dart';
import 'package:optik_b_riski/shared/theme.dart';
import 'package:optik_b_riski/shared/widgets/admin/admin_nav_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminNavBadge widget', () {
    testWidgets('count 0 → tidak render badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminNavBadge(count: 0))),
      );
      expect(find.byType(AdminNavBadge), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('count 3 → tampil angka 3', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminNavBadge(count: 3))),
      );
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('count 150 → cap 99+', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminNavBadge(count: 150))),
      );
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('Sidebar bubble hierarchy (live)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AdminNavBadgeService.instance.debugReset();
    });

    testWidgets('grup Tim badge = jumlah sub-item unread', (tester) async {
      AdminNavBadgeService.instance.debugReset(
        live: {
          'karyawan': {'k1', 'k2'},
          'pengaduan': {'p1'},
        },
        seen: {'karyawan': {'k1'}},
      );
      final badges = AdminNavBadgeService.instance.counts;

      final groups = [
        AdminDashNavGroup(
          id: 'tim',
          label: 'Tim',
          icon: Icons.groups_rounded,
          items: const [
            AdminDashNavItem(
              id: 'karyawan',
              title: 'Karyawan',
              icon: Icons.person,
              color: Colors.blue,
            ),
            AdminDashNavItem(
              id: 'pengaduan',
              title: 'Pengaduan',
              icon: Icons.report,
              color: Colors.orange,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminNavSidebar(
              groups: groups,
              openGroupId: 'tim',
              expanded: true,
              onSelectGroup: (_) {},
              badgeCounts: badges,
              onMarkItemUnread: (_) {},
            ),
          ),
        ),
      );

      // karyawan: 1 unread + pengaduan: 1 unread → grup total 2
      expect(find.text('2'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('buka 1 entitas → sidebar count turun 1 (simulasi)', (tester) async {
      AdminNavBadgeService.instance.debugReset(
        live: {'karyawan': {'k1', 'k2', 'k3'}},
      );
      expect(AdminNavBadgeService.instance.displayCount('karyawan'), 3);

      await AdminNavBadgeService.instance.markEntitySeen('karyawan', 'k1');
      expect(AdminNavBadgeService.instance.displayCount('karyawan'), 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminNavBadge(
              count: AdminNavBadgeService.instance.displayCount('karyawan'),
            ),
          ),
        ),
      );
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('i18n mark unread', () {
    test('admin_nav_mark_unread ada di id.json dan en.json', () {
      final root = Directory.current;
      final id = jsonDecode(
        File('${root.path}/assets/translations/id.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final en = jsonDecode(
        File('${root.path}/assets/translations/en.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(id['admin_nav_mark_unread'], 'Tandai belum dibaca');
      expect(en['admin_nav_mark_unread'], 'Mark as unread');
    });
  });
}
