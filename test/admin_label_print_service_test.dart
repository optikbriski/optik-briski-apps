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

  test('symbolAreaFor fits inside each selected label size', () {
    for (final size in AdminLabelSize.values) {
      final area = AdminLabelPrintService.symbolAreaFor(
        size: size,
        hasSubtitle: true,
      );
      final page = AdminLabelPrintService.formatOf(size);
      expect(area.width, lessThanOrEqualTo(page.availableWidth + 0.01));
      expect(area.height, lessThan(page.availableHeight));
      expect(area.height, greaterThan(10));
      // QR side harus muat di kotak sisa.
      final qrSide = area.width < area.height ? area.width : area.height;
      expect(qrSide, lessThanOrEqualTo(area.width + 0.01));
      expect(qrSide, lessThanOrEqualTo(area.height + 0.01));
    }
  });

  test('buildPdf barcode and qr produce non-empty bytes', () async {
    for (final size in AdminLabelSize.values) {
      final barcode = await AdminLabelPrintService.buildPdf(
        data: 'BC-1784688575572',
        title: 'Aviator - Dark Chiaroscuro',
        subtitle: 'SKU BC-1784688575572',
        symbol: AdminLabelSymbol.barcode1d,
        size: size,
      );
      expect(barcode.length, greaterThan(100), reason: 'barcode $size');

      final qr = await AdminLabelPrintService.buildPdf(
        data: 'BC-1784688575572',
        title: 'Aviator - Dark Chiaroscuro',
        subtitle: 'SKU BC-1784688575572',
        symbol: AdminLabelSymbol.qr,
        size: size,
      );
      expect(qr.length, greaterThan(100), reason: 'qr $size');
    }
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
