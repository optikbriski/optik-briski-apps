import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/apps/admin/global_notification.dart';
import 'package:optik_b_riski/shared/admin/admin_nav_badge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AdminNavBadgeService.instance.debugReset();
  });

  testWidgets('GlobalNotificationIcon sinkron dengan scope logistik', (tester) async {
    AdminNavBadgeService.instance.debugReset(
      live: {'logistik': {'do-1', 'do-2', 'do-3'}},
      seen: {'logistik': {'do-1'}},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlobalNotificationIcon(
            profile: const {
              'role': 'admin_toko',
              'toko_id': 'TOKO1',
            },
          ),
        ),
      ),
    );

    // 3 live − 1 seen = 2 unread
    expect(find.text('2'), findsOneWidget);

    await AdminNavBadgeService.instance.markEntitySeen('logistik', 'do-2');
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('GlobalNotificationIcon hidden tanpa hak antrean', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlobalNotificationIcon(
            profile: const {'role': 'kasir', 'toko_id': 'TOKO1'},
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
  });
}
