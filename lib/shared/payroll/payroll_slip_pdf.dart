import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../brand/brand_service.dart';
import 'payroll_compute_engine.dart';

/// Slip gaji Karyawan — PDF dari line terkunci (tanpa angka hardcode).
abstract final class PayrollSlipPdf {
  static const _navy = PdfColor.fromInt(0xFF0F172A);
  static const _gold = PdfColor.fromInt(0xFFC9A84C);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _zebra = PdfColor.fromInt(0xFFF8FAFC);

  static final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  static String _rp(dynamic v) => _rupiah.format(PayrollComputeEngine.asInt(v));

  static Future<void> shareSlip(Map<String, dynamic> slip) async {
    final bytes = await buildPdf(slip);
    final ym = (slip['periode_ym'] ?? 'slip').toString().replaceAll('-', '');
    final nama = (slip['nama'] ?? 'karyawan')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'slip_${ym}_$nama.pdf',
    );
  }

  static Future<Uint8List> buildPdf(Map<String, dynamic> slip) async {
    final doc = pw.Document();
    final comps = PayrollComputeEngine.asMapList(
      slip['components'] ?? slip['payroll_line_components'],
    );
    final periode = (slip['periode_ym'] ?? '-').toString();
    final status = (slip['status'] ?? '-').toString();
    final nama = (slip['nama'] ?? '-').toString();
    final jabatan = (slip['jabatan'] ?? '-').toString();
    final toko = (slip['toko_id'] ?? '-').toString();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              BrandService.name,
              style: pw.TextStyle(
                color: _navy,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Container(height: 3, color: _gold),
            pw.SizedBox(height: 12),
            pw.Text(
              'Slip gaji',
              style: pw.TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Periode $periode · $status',
              style: const pw.TextStyle(color: _muted, fontSize: 10),
            ),
            pw.SizedBox(height: 12),
            pw.Text(nama,
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
            pw.Text('$jabatan · $toko',
                style: const pw.TextStyle(color: _muted, fontSize: 10)),
            pw.SizedBox(height: 14),
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(color: _border, width: 0.4),
              ),
              children: [
                for (var i = 0; i < comps.length; i++)
                  pw.TableRow(
                    decoration: i.isOdd
                        ? const pw.BoxDecoration(color: _zebra)
                        : null,
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                        child: pw.Text(
                          (comps[i]['label'] ?? comps[i]['key'] ?? '-')
                              .toString(),
                          style: const pw.TextStyle(fontSize: 9, color: _navy),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(
                            _rp(comps[i]['amount']),
                            style: const pw.TextStyle(fontSize: 9, color: _navy),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Nett diterima',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text(
                  _rp(slip['nett']),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                    color: _navy,
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              'Dokumen ini sinkron dari payroll Admin yang sudah dikunci.',
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
