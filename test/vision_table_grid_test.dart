import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/ocr/vision_table_grid.dart';

void main() {
  test('3 kolom: kiri / tengah / kanan jadi 2 baris', () {
    const tokens = [
      VisionOcrToken(text: 'Nasi', cx: 0.12, cy: 0.20, x0: 0.08, x1: 0.18, y0: 0.17, y1: 0.23),
      VisionOcrToken(text: '2', cx: 0.50, cy: 0.20, x0: 0.46, x1: 0.54, y0: 0.17, y1: 0.23),
      VisionOcrToken(text: '12000', cx: 0.88, cy: 0.20, x0: 0.80, x1: 0.95, y0: 0.17, y1: 0.23),
      VisionOcrToken(text: 'Teh', cx: 0.12, cy: 0.40, x0: 0.08, x1: 0.18, y0: 0.37, y1: 0.43),
      VisionOcrToken(text: '1', cx: 0.50, cy: 0.40, x0: 0.46, x1: 0.54, y0: 0.37, y1: 0.43),
      VisionOcrToken(text: '5000', cx: 0.88, cy: 0.40, x0: 0.80, x1: 0.95, y0: 0.37, y1: 0.43),
    ];
    final grid = VisionTableGrid.fromTokens(tokens: tokens, columns: 3);
    expect(grid, [
      ['Nasi', '2', '12000'],
      ['Teh', '1', '5000'],
    ]);
  });

  test('kata di sel yang sama digabung', () {
    const tokens = [
      VisionOcrToken(text: 'Nasi', cx: 0.10, cy: 0.2, x0: 0.05, x1: 0.16, y0: 0.17, y1: 0.23),
      VisionOcrToken(text: 'goreng', cx: 0.22, cy: 0.2, x0: 0.17, x1: 0.30, y0: 0.17, y1: 0.23),
      VisionOcrToken(text: '1', cx: 0.55, cy: 0.2, x0: 0.50, x1: 0.60, y0: 0.17, y1: 0.23),
      VisionOcrToken(text: '15.000', cx: 0.88, cy: 0.2, x0: 0.80, x1: 0.96, y0: 0.17, y1: 0.23),
    ];
    final grid = VisionTableGrid.fromTokens(tokens: tokens, columns: 3);
    expect(grid.single, ['Nasi goreng', '1', '15.000']);
  });

  test('skip baris judul pada 1 baris saja tetap ada 1 baris kosong', () {
    const tokens = [
      VisionOcrToken(text: 'Item', cx: 0.2, cy: 0.2, x0: 0.1, x1: 0.3, y0: 0.15, y1: 0.25),
      VisionOcrToken(text: 'Qty', cx: 0.8, cy: 0.2, x0: 0.7, x1: 0.9, y0: 0.15, y1: 0.25),
    ];
    final grid = VisionTableGrid.fromTokens(
      tokens: tokens,
      columns: 2,
      skipFirstRow: true,
    );
    expect(grid, [
      ['', ''],
    ]);
  });

  test('2 dan 8 kolom tidak melewati batas', () {
    const tokens = [
      VisionOcrToken(text: 'A', cx: 0.05, cy: 0.2, x0: 0.0, x1: 0.1, y0: 0.15, y1: 0.25),
      VisionOcrToken(text: 'H', cx: 0.95, cy: 0.2, x0: 0.9, x1: 1.0, y0: 0.15, y1: 0.25),
    ];
    expect(VisionTableGrid.fromTokens(tokens: tokens, columns: 2).single.length, 2);
    expect(VisionTableGrid.fromTokens(tokens: tokens, columns: 8).single.length, 8);
    expect(VisionTableGrid.fromTokens(tokens: tokens, columns: 99).single.length, 8);
    expect(VisionTableGrid.fromTokens(tokens: tokens, columns: 1).single.length, 2);
  });

  test('skip baris judul', () {
    const tokens = [
      VisionOcrToken(text: 'Item', cx: 0.15, cy: 0.10, x0: 0.1, x1: 0.2, y0: 0.08, y1: 0.12),
      VisionOcrToken(text: 'Qty', cx: 0.50, cy: 0.10, x0: 0.45, x1: 0.55, y0: 0.08, y1: 0.12),
      VisionOcrToken(text: 'Harga', cx: 0.85, cy: 0.10, x0: 0.78, x1: 0.95, y0: 0.08, y1: 0.12),
      VisionOcrToken(text: 'Kopi', cx: 0.15, cy: 0.30, x0: 0.1, x1: 0.2, y0: 0.27, y1: 0.33),
      VisionOcrToken(text: '1', cx: 0.50, cy: 0.30, x0: 0.45, x1: 0.55, y0: 0.27, y1: 0.33),
      VisionOcrToken(text: '8.000', cx: 0.85, cy: 0.30, x0: 0.78, x1: 0.95, y0: 0.27, y1: 0.33),
    ];
    final grid = VisionTableGrid.fromTokens(
      tokens: tokens,
      columns: 3,
      skipFirstRow: true,
    );
    expect(grid, [
      ['Kopi', '1', '8.000'],
    ]);
  });

  test('token kosong → satu baris kosong', () {
    final grid = VisionTableGrid.fromTokens(tokens: const [], columns: 3);
    expect(grid, [
      ['', '', ''],
    ]);
  });

  test('toTsv pakai header user', () {
    final tsv = VisionTableGrid.toTsv(
      ['Item', 'Qty', 'Harga'],
      [
        ['Nasi', '2', '12000'],
      ],
    );
    expect(tsv, 'Item\tQty\tHarga\nNasi\t2\t12000');
  });

  test('parseList dari JSON Vision', () {
    final tokens = VisionOcrToken.parseList([
      {'text': 'A', 'cx': 0.1, 'cy': 0.2, 'x0': 0.05, 'x1': 0.15, 'y0': 0.1, 'y1': 0.3},
      {'text': '  ', 'cx': 0.5, 'cy': 0.2},
    ]);
    expect(tokens.length, 1);
    expect(tokens.single.text, 'A');
    expect(tokens.single.cx, 0.1);
  });

  test('fromPlainText pecah spasi ganda ke kolom', () {
    final grid = VisionTableGrid.fromPlainText(
      'Nasi goreng  2  12000\nTeh  1  5000',
      3,
    );
    expect(grid, [
      ['Nasi goreng', '2', '12000'],
      ['Teh', '1', '5000'],
    ]);
  });
}
