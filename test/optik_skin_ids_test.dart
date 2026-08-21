import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Optik B. Riski remains a skin with locked applicationIds', () {
    final map = jsonDecode(
      File('brands/optik-briski.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(map['slug'], 'optik-briski');
    expect(map['displayName'], 'Optik B. Riski');
    expect(map['pinTenant'], isTrue);
    expect(map['memberApplicationId'], 'com.optikbriski.member');
    expect(map['adminApplicationId'], 'com.optikbriski.admin');
    expect(map['karyawanApplicationId'], 'com.example.toko_kacamata_natan');
  });

  test('Rekasa is the shared shell, not a pinned Optik fork', () {
    final map = jsonDecode(File('brands/rekasa.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(map['slug'], 'rekasa');
    expect(map['pinTenant'], isFalse);
    expect(map['storefrontApplicationId'], 'com.rekasa.store');
  });
}
