import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/karyawan/gaji_pokok.dart';
import 'package:optik_b_riski/shared/karyawan/register_conflict.dart';

void main() {
  test('parse gaji strips separators', () {
    expect(parseGajiPokokInput('1.500.000'), 1500000);
    expect(parseGajiPokokInput('Rp 2,000,000'), 2000000);
    expect(parseGajiPokokInput(''), 0);
    expect(parseGajiPokokInput('abc', fallback: 7), 7);
  });

  test('format empty when zero', () {
    expect(formatGajiPokokInput(0), '');
    expect(formatGajiPokokInput(null), '');
    expect(formatGajiPokokInput(1500000), '1500000');
  });

  test('register conflict tenant scope is fail-closed', () {
    expect(RegisterConflict.tenantScopeId(null), isNull);
    expect(RegisterConflict.tenantScopeId('  '), isNull);
    expect(
      RegisterConflict.tenantScopeId('00000000-0000-0000-0000-000000000001'),
      '00000000-0000-0000-0000-000000000001',
    );
  });
}
