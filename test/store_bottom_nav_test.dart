import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/apps/store/store_bottom_nav.dart';
import 'package:optik_b_riski/shared/brand/rekasa_tokens.dart';

void main() {
  testWidgets('storefront uses a phone-style bottom bar', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRekasaStoreTheme(),
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: StoreBottomNav(
            index: index,
            onChanged: (i) => index = i,
          ),
        ),
      ),
    );
    for (final label in StoreBottomNav.labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Akun'));
    await tester.pump();
    expect(index, 1);
  });
}
