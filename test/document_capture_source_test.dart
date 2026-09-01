import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/ocr/deskew_document_capture.dart';
import 'package:optik_b_riski/shared/theme.dart';

void main() {
  test('PDF magic bytes terdeteksi', () {
    final pdf = Uint8List.fromList('%PDF-1.4'.codeUnits);
    expect(documentBytesLookLikePdf(pdf), isTrue);
    expect(
      documentBytesLookLikePdf(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
      isFalse,
    );
  });

  testWidgets('sheet sumber: kamera, galeri, unggah file', (tester) async {
    DocumentCaptureSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAdminTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  picked = await pickDocumentCaptureSource(context);
                },
                child: const Text('open-source'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-source'));
    await tester.pumpAndSettle();

    expect(find.text('ocr_source_camera'), findsOneWidget);
    expect(find.text('ocr_source_gallery'), findsOneWidget);
    expect(find.text('ocr_source_file'), findsOneWidget);

    await tester.tap(find.text('ocr_source_gallery'));
    await tester.pumpAndSettle();
    expect(picked, DocumentCaptureSource.gallery);
  });

  testWidgets('sheet sumber: pilih kamera', (tester) async {
    DocumentCaptureSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAdminTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  picked = await pickDocumentCaptureSource(context);
                },
                child: const Text('open-source'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ocr_source_camera'));
    await tester.pumpAndSettle();
    expect(picked, DocumentCaptureSource.camera);
  });

  testWidgets('sheet sumber: pilih unggah file', (tester) async {
    DocumentCaptureSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAdminTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  picked = await pickDocumentCaptureSource(context);
                },
                child: const Text('open-source'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ocr_source_file'));
    await tester.pumpAndSettle();
    expect(picked, DocumentCaptureSource.file);
  });
}
