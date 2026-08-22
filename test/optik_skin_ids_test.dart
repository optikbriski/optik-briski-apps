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

  test('Rekasa debug launchers stay unpinned', () {
    final raw = jsonDecode(File('.vscode/launch.json').readAsStringSync())
        as Map<String, dynamic>;
    final configs = (raw['configurations'] as List).cast<Map<String, dynamic>>();
    for (final name in ['Admin Rekasa', 'Karyawan Rekasa', 'Member Rekasa']) {
      final cfg = configs.firstWhere((c) => c['name'] == name);
      final args = (cfg['toolArgs'] as List).cast<String>();
      expect(args.join(' '), isNot(contains('optik-briski')));
      expect(
        args.any((a) => a.contains('PIN_TENANT=true') || a.contains('PIN_STORE_TENANT=true')),
        isFalse,
        reason: name,
      );
    }
    final optik = configs.firstWhere(
      (c) => c['name'] == 'Optik Member (kulit pelanggan)',
    );
    expect((optik['toolArgs'] as List).join(' '), contains('optik-briski'));
  });
}
