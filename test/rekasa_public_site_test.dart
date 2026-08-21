import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('situs publik Rekasa siap kolom link Midtrans', () {
    final html = File('site/index.html').readAsStringSync();
    expect(html, contains('REKASA KARYA INDONESIA'));
    expect(html, contains('Perseroan Perorangan'));
    expect(html, contains('AHU-A011645.AH.01.31.Tahun 2026'));
    expect(html, contains('Paket C'));
    expect(html, contains('perangkat lunak'));
    expect(html, isNot(contains('PT Biasa')));
    expect(File('site/syarat.html').existsSync(), isTrue);
    expect(File('site/kebijakan.html').existsSync(), isTrue);
    expect(File('site/kontak.html').existsSync(), isTrue);
  });
}
