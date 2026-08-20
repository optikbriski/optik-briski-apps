import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../finance/gl_report_service.dart';
import '../brand/brand_service.dart';

class GlReportPdfService {
  GlReportPdfService._();

  static const _navy = PdfColor.fromInt(0xFF0F172A);
  static const _gold = PdfColor.fromInt(0xFFC9A84C);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _zebra = PdfColor.fromInt(0xFFF8FAFC);
  static const _ink = PdfColor.fromInt(0xFF0F172A);

  static final _rp = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  static String _fmt(int v) => _rp.format(v);

  static Future<void> shareTrialBalance({
    required String title,
    required String subtitle,
    required List<GlAccountBalance> rows,
  }) async {
    final bytes = await _build(
      title: title,
      subtitle: subtitle,
      headers: const ['Kode', 'Akun', 'Debit', 'Kredit', 'Saldo'],
      data: rows
          .map((r) => [
                r.kode,
                r.nama,
                _fmt(r.debit),
                _fmt(r.kredit),
                _fmt(r.saldo),
              ])
          .toList(),
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'OptikBRiski_NeracaSaldo_${DateFormat('yyyyMM').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> shareIncomeStatement({
    required String title,
    required String subtitle,
    required List<GlAccountBalance> rows,
    required int labaBersih,
  }) async {
    final data = rows
        .map((r) => [
              r.kode,
              r.nama,
              r.tipe,
              _fmt(r.tipe == 'REVENUE' ? (r.kredit - r.debit) : (r.debit - r.kredit)),
            ])
        .toList();
    data.add(['', 'Laba bersih', '', _fmt(labaBersih)]);
    final bytes = await _build(
      title: title,
      subtitle: subtitle,
      headers: const ['Kode', 'Akun', 'Tipe', 'Nominal'],
      data: data,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'OptikBRiski_LabaRugi_${DateFormat('yyyyMM').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> shareBalanceSheet({
    required String title,
    required String subtitle,
    required List<GlAccountBalance> rows,
    required int labaBerjalan,
  }) async {
    final data = rows
        .map((r) => [
              r.kode,
              r.nama,
              r.tipe,
              _fmt(r.saldo),
            ])
        .toList();
    data.add(['', 'Laba berjalan', 'EQUITY', _fmt(labaBerjalan)]);
    final bytes = await _build(
      title: title,
      subtitle: subtitle,
      headers: const ['Kode', 'Akun', 'Tipe', 'Saldo'],
      data: data,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'OptikBRiski_Neraca_${DateFormat('yyyyMM').format(DateTime.now())}.pdf',
    );
  }

  static Future<Uint8List> _build({
    required String title,
    required String subtitle,
    required List<String> headers,
    required List<List<String>> data,
  }) async {
    final doc = pw.Document(title: title, author: '${BrandService.name}');
    final generated =
        DateFormat('d MMM yyyy HH:mm', 'id_ID').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text('OPTIK B. RISKI',
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy)),
            pw.SizedBox(height: 2),
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy)),
            pw.Text(subtitle,
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
            pw.SizedBox(height: 6),
            pw.Container(height: 1.2, color: _navy),
            pw.Container(height: 1.5, color: _gold),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (ctx) => pw.Column(children: [
          pw.SizedBox(height: 8),
          pw.Container(height: 0.6, color: _border),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Dibuat $generated',
                  style: const pw.TextStyle(fontSize: 7, color: _muted)),
              pw.Text('Halaman ${ctx.pageNumber}/${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7, color: _muted)),
            ],
          ),
        ]),
        build: (_) => [
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.4),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _navy),
                children: headers
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(h,
                              style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white),
                              textAlign: pw.TextAlign.center),
                        ))
                    .toList(),
              ),
              for (var i = 0; i < data.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : _zebra),
                  children: data[i]
                      .map((c) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(c,
                                style: const pw.TextStyle(
                                    fontSize: 8, color: _ink)),
                          ))
                      .toList(),
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}
