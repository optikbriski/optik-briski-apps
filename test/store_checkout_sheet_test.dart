import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:optik_b_riski/apps/store/store_checkout_sheet.dart';
import 'package:optik_b_riski/shared/brand/rekasa_tokens.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('checkout sheet shows price and order action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRekasaStoreTheme(),
        home: const Scaffold(
          body: RekasaSheetScaffold(
            eyebrow: 'Checkout',
            title: 'Beli paket',
            price: 'Rp 750.000',
            primaryLabel: 'Pesan',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(find.text('Beli paket'), findsOneWidget);
    expect(find.text('Rp 750.000'), findsOneWidget);
    expect(find.text('Pesan'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
