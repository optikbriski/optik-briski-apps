import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/ocr/vision_receipt_draft.dart';

void main() {
  test('SPBU total with Indonesian thousands', () {
    const text = '''
SPBU PERTAMINA 34.12345
Jl. Veteran
PERTALITE
TOTAL
Rp 125.000
Kembalian Rp 5.000
''';
    final d = VisionReceiptDraft.parse(text);
    expect(d.amountRp, 125000);
    expect(d.merchant, 'SPBU PERTAMINA 34.12345');
    expect(d.suggestedKategori, VisionReceiptDraft.kategoriBensin);
    expect(d.catatanDraft, contains('SPBU'));
  });

  test('parkir receipt', () {
    const text = '''
Parkir Mall
Tiket 12
Rp 5.000
''';
    final d = VisionReceiptDraft.parse(text);
    expect(d.amountRp, 5000);
    expect(d.suggestedKategori, VisionReceiptDraft.kategoriParkir);
  });

  test('plain total without Rp prefix', () {
    const text = '''
TOKO SUKA MAJU
Jumlah 48.000
''';
    final d = VisionReceiptDraft.parse(text);
    expect(d.amountRp, 48000);
    expect(d.suggestedKategori, VisionReceiptDraft.kategoriLainnya);
  });

  test('ignores empty and noise', () {
    final d = VisionReceiptDraft.parse('   \n\n  ');
    expect(d.amountRp, isNull);
    expect(d.catatanDraft, isEmpty);
  });

  test('parseIdrAmount formats', () {
    expect(VisionReceiptDraft.parseIdrAmount('Rp 1.250.000'), 1250000);
    expect(VisionReceiptDraft.parseIdrAmount('1,250,000'), 1250000);
    expect(VisionReceiptDraft.parseIdrAmount('75000'), 75000);
  });

  test('skips subtotal/ppn in favor of total', () {
    const text = '''
Warung Kopi
Subtotal Rp 18.000
PPN Rp 1.800
TOTAL Rp 19.800
''';
    final d = VisionReceiptDraft.parse(text);
    expect(d.amountRp, 19800);
  });
}
