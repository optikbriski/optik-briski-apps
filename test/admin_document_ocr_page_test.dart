import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/apps/admin/admin_document_ocr_page.dart';
import 'package:optik_b_riski/shared/theme.dart';

void main() {
  testWidgets('konfirmasi jumlah kolom tidak crash — judul + tabel muncul',
      (tester) async {
    await _pumpOcrPage(tester);

    expect(find.byType(AdminDocumentOcrPage), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-result-table')), findsNothing);
    expect(find.byKey(const ValueKey('ocr-title-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ocr-confirm-cols')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('ocr-title-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-title-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-result-table')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-cell-0-0')), findsOneWidget);
  });

  testWidgets('ganti 2 lalu 8 kolom, judul, layar penuh tanpa exception',
      (tester) async {
    await _pumpOcrPage(tester);

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ocr-confirm-cols')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('ocr-title-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-title-2')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('ocr-title-0')), 'Nama');
    await tester.enterText(find.byKey(const ValueKey('ocr-title-1')), 'Telp');
    await tester.pump();
    expect(find.text('Nama'), findsWidgets);

    await tester.ensureVisible(find.byKey(const ValueKey('ocr-fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr-fullscreen')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('ocr-result-table')), findsOneWidget);

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ocr-result-table')), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('ocr-title-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ocr-confirm-cols')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('ocr-title-7')));
    expect(find.byKey(const ValueKey('ocr-title-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-cell-0-7')), findsOneWidget);
  });

  testWidgets('mode teks biasa tidak memasang tabel', (tester) async {
    await _pumpOcrPage(tester);

    await tester.tap(find.byIcon(Icons.notes_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ocr-confirm-cols')), findsNothing);

    await tester.tap(find.byIcon(Icons.table_chart_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr-confirm-cols')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ocr-result-table')), findsOneWidget);
  });
}

Future<void> _pumpOcrPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: const AdminDocumentOcrPage(),
    ),
  );
  await tester.pump();
}
