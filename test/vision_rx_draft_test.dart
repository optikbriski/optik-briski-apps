import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/ocr/vision_rx_draft.dart';

void main() {
  test('parses OD/OS doctor pad', () {
    const text = '''
OD SPH -2.00 CYL -0.50 AXIS 180
OS SPH -1.75 CYL -0.25 AXIS 175
PD 62
ADD +2.00
''';
    final d = VisionRxDraft.parse(text);
    expect(d.structured, isNotNull);
    expect(d.structured, contains('R: SPH -2.00'));
    expect(d.structured, contains('L: SPH -1.75'));
    expect(d.structured, contains('PD Pasien: 62 mm'));
  });

  test('keeps raw when no eye labels', () {
    const text = 'Catatan: ganti frame hitam';
    final d = VisionRxDraft.parse(text);
    expect(d.structured, isNull);
    expect(d.displayText, text);
  });
}
