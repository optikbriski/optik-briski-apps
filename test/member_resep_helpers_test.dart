import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/invoice/invoice_document_builder.dart';
import 'package:optik_b_riski/shared/member/member_resep_helpers.dart';

void main() {
  group('MemberResepHelpers filter', () {
    test('rejects empty / Normal', () {
      expect(MemberResepHelpers.isMeaningfulResep(null), isFalse);
      expect(MemberResepHelpers.isMeaningfulResep(''), isFalse);
      expect(MemberResepHelpers.isMeaningfulResep('Normal'), isFalse);
      expect(MemberResepHelpers.isMeaningfulResep('  normal  '), isFalse);
    });

    test('accepts structured and custom notes', () {
      const structured =
          'R: SPH -1.00/CYL -0.50/AXIS 90/ADD 0.00 | '
          'L: SPH -1.25/CYL -0.25/AXIS 80/ADD 0.00 | '
          'PD Pasien: 32/32 mm';
      expect(MemberResepHelpers.isMeaningfulResep(structured), isTrue);
      expect(MemberResepHelpers.isStructuredResep(structured), isTrue);
      expect(
        MemberResepHelpers.isMeaningfulResep('Resep Kustom Terlampir'),
        isTrue,
      );
      expect(
        MemberResepHelpers.isStructuredResep('Resep Kustom Terlampir'),
        isFalse,
      );
    });
  });

  group('MemberResepHelpers validators', () {
    test('SPH / CYL / ADD step 0.25 and ranges', () {
      expect(MemberResepHelpers.isValidSph('-1.00'), isTrue);
      expect(MemberResepHelpers.isValidSph('+2.25'), isTrue);
      expect(MemberResepHelpers.isValidSph('-1.10'), isFalse);
      expect(MemberResepHelpers.isValidSph('-21.00'), isFalse);

      expect(MemberResepHelpers.isValidCyl('-0.50'), isTrue);
      expect(MemberResepHelpers.isValidCyl('-6.00'), isTrue);
      expect(MemberResepHelpers.isValidCyl('-6.25'), isFalse);

      expect(MemberResepHelpers.isValidAdd('1.50'), isTrue);
      expect(MemberResepHelpers.isValidAdd('0.00'), isTrue);
      expect(MemberResepHelpers.isValidAdd('-0.25'), isFalse);
      expect(MemberResepHelpers.isValidAdd('4.25'), isFalse);
    });

    test('AXIS depends on CYL', () {
      expect(MemberResepHelpers.isValidAxis('', cyl: '0.00'), isTrue);
      expect(MemberResepHelpers.isValidAxis('90', cyl: '-0.50'), isTrue);
      expect(MemberResepHelpers.isValidAxis('90°', cyl: '-0.50'), isTrue);
      expect(MemberResepHelpers.isValidAxis('181', cyl: '-0.50'), isFalse);
      expect(MemberResepHelpers.isValidAxis('', cyl: '-0.50'), isFalse);
    });
  });

  group('InvoiceDocumentBuilder.parseResep', () {
    const raw =
        'R: SPH -1.00/CYL -0.50/AXIS 90/ADD 1.50 | '
        'L: SPH -1.25/CYL -0.25/AXIS 80/ADD 1.50 | '
        'PD Pasien: 32/31 mm';

    test('reads OD/OS fields', () {
      expect(InvoiceDocumentBuilder.parseResep(raw, 'OD', 'SPH'), '-1.00');
      expect(InvoiceDocumentBuilder.parseResep(raw, 'OD', 'CYL'), '-0.50');
      expect(InvoiceDocumentBuilder.parseResep(raw, 'OD', 'AXIS'), '90');
      expect(InvoiceDocumentBuilder.parseResep(raw, 'OD', 'ADD'), '1.50');
      expect(InvoiceDocumentBuilder.parseResep(raw, 'OS', 'SPH'), '-1.25');
      expect(InvoiceDocumentBuilder.parseResep(raw, 'OS', 'AXIS'), '80');
      expect(
        InvoiceDocumentBuilder.parseResep(raw, 'OD', 'PD'),
        '32/31 mm',
      );
    });
  });
}
