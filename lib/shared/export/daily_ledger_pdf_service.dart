import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../brand/brand_service.dart';

/// Ringkasan laba-rugi harian + mutasi untuk ekspor dari Buku Besar Stage 3.
class DailyLedgerPdfData {
  const DailyLedgerPdfData({
    required this.tokoLabel,
    required this.tokoId,
    required this.dateStr,
    required this.omzet,
    required this.hpp,
    required this.dpp,
    required this.ppn,
    required this.pemasukanManual,
    required this.opex,
    required this.labaBersih,
    required this.paymentBreakdown,
    required this.itemsSold,
    required this.mutasi,
  });

  final String tokoLabel;
  final String tokoId;
  final String dateStr;
  final int omzet;
  final int hpp;
  final int dpp;
  final int ppn;
  final int pemasukanManual;
  final int opex;
  final int labaBersih;
  final Map<String, int> paymentBreakdown;
  final List<Map<String, dynamic>> itemsSold;
  final List<Map<String, dynamic>> mutasi;
}

/// PDF laporan ledger harian — branding selaras ekspor bulanan.
class DailyLedgerPdfService {
  DailyLedgerPdfService._();

  static const _navy = PdfColor.fromInt(0xFF0F172A);
  static const _gold = PdfColor.fromInt(0xFFC9A84C);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _slate = PdfColor.fromInt(0xFF334155);
  static const _border = PdfColor.fromInt(0xFFE2E8F0);
  static const _zebra = PdfColor.fromInt(0xFFF8FAFC);
  static const _ink = PdfColor.fromInt(0xFF0F172A);
  static const _green = PdfColor.fromInt(0xFF15803D);
  static const _red = PdfColor.fromInt(0xFFB91C1C);

  static final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  static String _rp(int v) => _rupiah.format(v);

  static String _tanggalIndo(String dateStr) {
    try {
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID')
          .format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  static String filenameFor({
    required String tokoId,
    required String dateStr,
  }) {
    final safeToko = tokoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeDate = dateStr.replaceAll('-', '');
    return 'OptikBRiski_LedgerHarian_${safeToko}_$safeDate.pdf';
  }

  static Future<Uint8List> buildPdf(DailyLedgerPdfData data) async {
    final doc = pw.Document(
      title: 'Ledger Harian ${data.tokoLabel} ${data.dateStr}',
      author: '${BrandService.name}',
    );

    final untungKotor = data.omzet - data.hpp;
    final generatedAt =
        DateFormat('d MMM yyyy HH:mm', 'id_ID').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        header: (ctx) => _header(data),
        footer: (ctx) => _footer(ctx, generatedAt),
        build: (ctx) => [
          pw.SizedBox(height: 8),
          _section('Ringkasan laba rugi'),
          pw.SizedBox(height: 8),
          _kvTable([
            ['Omzet bruto POS', _rp(data.omzet)],
            ['DPP (omzet netto)', _rp(data.dpp)],
            ['PPN keluaran 11%', _rp(data.ppn)],
            ['HPP / modal pokok', '- ${_rp(data.hpp)}'],
            ['Untung kotor produk', _rp(untungKotor)],
            ['Pemasukan kas manual', '+ ${_rp(data.pemasukanManual)}'],
            ['Beban operasional', '- ${_rp(data.opex)}'],
            ['Laba bersih harian', _rp(data.labaBersih)],
          ], emphasizeLast: true),
          pw.SizedBox(height: 16),
          _section('Kanal setoran'),
          pw.SizedBox(height: 8),
          _kvTable(
            data.paymentBreakdown.entries
                .map((e) => [e.key, _rp(e.value)])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          _section('Barang keluar'),
          pw.SizedBox(height: 8),
          if (data.itemsSold.isEmpty)
            pw.Text(
              'Tidak ada sirkulasi produk pada tanggal ini.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            )
          else
            _itemsTable(data.itemsSold),
          pw.SizedBox(height: 16),
          _section('Mutasi operasional'),
          pw.SizedBox(height: 8),
          if (data.mutasi.isEmpty)
            pw.Text(
              'Tidak ada mutasi operasional pada tanggal ini.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            )
          else
            _mutasiTable(data.mutasi),
        ],
      ),
    );

    return doc.save();
  }

  static Future<void> sharePdf(DailyLedgerPdfData data) async {
    final bytes = await buildPdf(data);
    await Printing.sharePdf(
      bytes: bytes,
      filename: filenameFor(tokoId: data.tokoId, dateStr: data.dateStr),
    );
  }

  static pw.Widget _header(DailyLedgerPdfData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'OPTIK B. RISKI',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Laporan ledger harian',
                    style: const pw.TextStyle(fontSize: 10, color: _slate),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  data.tokoLabel,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                  ),
                ),
                pw.Text(
                  _tanggalIndo(data.dateStr),
                  style: const pw.TextStyle(fontSize: 9, color: _muted),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.2, color: _navy),
        pw.Container(height: 1.5, color: _gold),
      ],
    );
  }

  static pw.Widget _footer(pw.Context context, String generatedAt) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 8),
        pw.Container(height: 0.6, color: _border),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Dibuat $generatedAt · Internal ${BrandService.name}',
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
            pw.Text(
              'Halaman ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _section(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: _navy,
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _kvTable(
    List<List<String>> rows, {
    bool emphasizeLast = false,
  }) {
    if (rows.isEmpty) {
      return pw.Text(
        'Tidak ada data.',
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.4),
      },
      children: [
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: emphasizeLast && i == rows.length - 1
                  ? const PdfColor.fromInt(0xFFEEF2FF)
                  : (i.isEven ? PdfColors.white : _zebra),
            ),
            children: [
              _cell(rows[i][0],
                  bold: emphasizeLast && i == rows.length - 1),
              _cell(
                rows[i][1],
                align: pw.TextAlign.right,
                bold: true,
                color: emphasizeLast && i == rows.length - 1 ? _navy : _ink,
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _itemsTable(List<Map<String, dynamic>> items) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.6),
        1: pw.FlexColumnWidth(0.5),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navy),
          children: [
            _th('Produk'),
            _th('Qty'),
            _th('Jual'),
            _th('Modal'),
            _th('Margin'),
          ],
        ),
        for (var i = 0; i < items.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : _zebra,
            ),
            children: [
              _cell(
                '${items[i]['nama_produk'] ?? '-'}\n'
                '${items[i]['no_invoice'] ?? ''} · '
                '${items[i]['nama_pelanggan'] ?? ''}',
                size: 7.5,
              ),
              _cell('${items[i]['qty'] ?? 0}',
                  align: pw.TextAlign.center),
              _cell(_rp(int.tryParse('${items[i]['subtotal'] ?? 0}') ?? 0),
                  align: pw.TextAlign.right),
              _cell(_rp(int.tryParse('${items[i]['total_hpp'] ?? 0}') ?? 0),
                  align: pw.TextAlign.right),
              _cell(_rp(int.tryParse('${items[i]['margin'] ?? 0}') ?? 0),
                  align: pw.TextAlign.right, color: _green),
            ],
          ),
      ],
    );
  }

  static pw.Widget _mutasiTable(List<Map<String, dynamic>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navy),
          children: [
            _th('Kategori'),
            _th('Keterangan'),
            _th('Status'),
            _th('Nominal'),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : _zebra,
            ),
            children: [
              _cell('${rows[i]['kategori'] ?? '-'}', size: 8),
              _cell('${rows[i]['deskripsi'] ?? '-'}', size: 7.5),
              _cell(
                _statusLabel(rows[i]),
                align: pw.TextAlign.center,
                size: 7.5,
              ),
              _cell(
                _signedNominal(rows[i]),
                align: pw.TextAlign.right,
                color: _isIncomeJenis(rows[i]) ? _green : _red,
                bold: true,
              ),
            ],
          ),
      ],
    );
  }

  static bool _isIncomeJenis(Map<String, dynamic> row) {
    final j = (row['jenis_transaksi'] ?? '').toString().toUpperCase();
    return j == 'PEMASUKAN' || j == 'PIUTANG';
  }

  static String _signedNominal(Map<String, dynamic> row) {
    final n = int.tryParse('${row['nominal'] ?? 0}') ?? 0;
    return '${_isIncomeJenis(row) ? '+' : '-'} ${_rp(n)}';
  }

  static String _statusLabel(Map<String, dynamic> row) {
    final st = (row['status_konfirmasi'] ?? '').toString().toUpperCase();
    if (st == 'APPROVED') return 'Disetujui';
    if (st == 'PENDING') return 'Menunggu';
    final ref = (row['referensi_id'] ?? '').toString();
    if (ref.isNotEmpty) return 'Sistem';
    return st.isEmpty ? '-' : st;
  }

  static pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    double size = 8.5,
    PdfColor color = _ink,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
      ),
    );
  }
}
