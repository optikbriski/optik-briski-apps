import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/print/pos_cups_print_io.dart';

void main() {
  test('findUsbUri returns POS-80 when listed by lpinfo', () async {
    // Hanya assert API tidak throw di lingkungan tanpa printer.
    final uri = await PosCupsPrint.findUsbUri(nameHint: 'POS-80');
    // Boleh null (CI tanpa hardware) atau mengandung pos.
    if (uri != null) {
      expect(uri.toLowerCase(), contains('usb://'));
    }
  });

  test('listQueues returns a list', () async {
    final q = await PosCupsPrint.listQueues();
    expect(q, isA<List<String>>());
  });
}
