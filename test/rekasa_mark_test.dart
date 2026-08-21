import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:optik_b_riski/shared/brand/rekasa_tokens.dart';
import 'package:optik_b_riski/shared/widgets/rekasa_mark.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('logo ink is cobalt sky, not Optik navy', () {
    expect(RekasaTokens.ink, const Color(0xFF0047AB));
    expect(RekasaTokens.inkSoft, const Color(0xFF2B6BC4));
    expect(RekasaTokens.sky, const Color(0xFF8BB4E8));
    expect(RekasaTokens.inkDeep, const Color(0xFF001F4D));
    expect(RekasaTokens.paper, const Color(0xFFFFFFFF));
    expect(RekasaTokens.ink, isNot(const Color(0xFF000080)));
    expect(RekasaTokens.ink, isNot(const Color(0xFF0B3D8C)));
  });

  testWidgets('mark shows R badge and Rekasa wordmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RekasaMark()),
      ),
    );
    expect(find.text('R'), findsOneWidget);
    expect(find.text('Rekasa'), findsOneWidget);
  });
}
