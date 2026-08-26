import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/print/admin_label_print_service.dart';

void main() {
  test('printableSku strips OBRPROD to plain SKU', () {
    expect(
      AdminLabelPrintService.printableSku(
        'OBRPROD|v1|BC-123|440b835a-33fb-4c4f-ae14-0b1ee33101f1',
      ),
      'BC-123',
    );
    expect(AdminLabelPrintService.printableSku('BC-123'), 'BC-123');
  });

  test('buildPdf barcode and qr produce non-empty bytes', () async {
    final barcode = await AdminLabelPrintService.buildPdf(
      data: 'SKU-TEST',
      title: 'Frame Test',
      subtitle: 'SKU SKU-TEST',
      symbol: AdminLabelSymbol.barcode1d,
      size: AdminLabelSize.mm50x30,
      copies: 2,
    );
    expect(barcode.length, greaterThan(100));

    final qr = await AdminLabelPrintService.buildPdf(
      data: 'OBRPROD|v1|SKU-TEST',
      title: 'Frame Test',
      symbol: AdminLabelSymbol.qr,
      size: AdminLabelSize.mm40x30,
      copies: 1,
    );
    expect(qr.length, greaterThan(100));
  });

  test('buildPdf rejects empty data', () async {
    expect(
      () => AdminLabelPrintService.buildPdf(
        data: '  ',
        title: 'x',
        symbol: AdminLabelSymbol.qr,
        size: AdminLabelSize.mm50x30,
      ),
      throwsA(isA<String>()),
    );
  });
}
