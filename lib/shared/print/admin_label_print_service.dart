import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import '../widgets/admin/admin_picker.dart';
import 'admin_label_download_stub.dart'
    if (dart.library.html) 'admin_label_download_web.dart' as label_dl;

/// Jenis simbol di label.
enum AdminLabelSymbol { barcode1d, qr }

/// Ukuran kertas/label umum (mm) — cocok printer sistem / label Niimbot via PDF.
enum AdminLabelSize {
  mm40x30(40, 30, '40 × 30 mm'),
  mm50x30(50, 30, '50 × 30 mm'),
  mm60x40(60, 40, '60 × 40 mm'),
  mm80x50(80, 50, '80 × 50 mm');

  const AdminLabelSize(this.widthMm, this.heightMm, this.label);
  final double widthMm;
  final double heightMm;
  final String label;
}

/// Cetak barcode/QR universal dari web Admin (PDF → dialog print sistem).
/// Jalan di Mac / Windows / Android / iOS / Chrome / Safari — tanpa driver khusus.
class AdminLabelPrintService {
  AdminLabelPrintService._();

  static PdfPageFormat formatOf(AdminLabelSize size) => PdfPageFormat(
        size.widthMm * PdfPageFormat.mm,
        size.heightMm * PdfPageFormat.mm,
        marginAll: 2 * PdfPageFormat.mm,
      );

  static Future<Uint8List> buildPdf({
    required String data,
    required String title,
    required AdminLabelSymbol symbol,
    required AdminLabelSize size,
    int copies = 1,
    String? subtitle,
  }) async {
    final payload = data.trim();
    if (payload.isEmpty) throw 'Data label kosong.';
    final n = copies.clamp(1, 50);
    final pageFormat = formatOf(size);
    final doc = pw.Document();

    for (var i = 0; i < n; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (ctx) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  title.trim().isEmpty ? 'LABEL' : title.trim(),
                  maxLines: 2,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: size.heightMm < 35 ? 7 : 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if ((subtitle ?? '').trim().isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    subtitle!.trim(),
                    maxLines: 1,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 6),
                  ),
                ],
                pw.SizedBox(height: 3),
                if (symbol == AdminLabelSymbol.barcode1d)
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: payload,
                    width: pageFormat.availableWidth,
                    height: pageFormat.availableHeight * 0.42,
                    drawText: false,
                  )
                else
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: payload,
                    width: pageFormat.availableHeight * 0.55,
                    height: pageFormat.availableHeight * 0.55,
                  ),
                pw.SizedBox(height: 2),
                pw.Text(
                  payload,
                  maxLines: 2,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: size.heightMm < 35 ? 5 : 6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Dialog print sistem (universal).
  static Future<void> printPdf({
    required String data,
    required String title,
    required AdminLabelSymbol symbol,
    required AdminLabelSize size,
    int copies = 1,
    String? subtitle,
  }) async {
    final bytes = await buildPdf(
      data: data,
      title: title,
      symbol: symbol,
      size: size,
      copies: copies,
      subtitle: subtitle,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _safeFileName(title, symbol),
      format: formatOf(size),
    );
  }

  static Future<void> sharePdf({
    required String data,
    required String title,
    required AdminLabelSymbol symbol,
    required AdminLabelSize size,
    int copies = 1,
    String? subtitle,
  }) async {
    final bytes = await buildPdf(
      data: data,
      title: title,
      symbol: symbol,
      size: size,
      copies: copies,
      subtitle: subtitle,
    );
    final name = '${_safeFileName(title, symbol)}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  /// PNG halaman pertama — untuk tempel ke app Niimbot / printer lain.
  static Future<Uint8List> buildPng({
    required String data,
    required String title,
    required AdminLabelSymbol symbol,
    required AdminLabelSize size,
    String? subtitle,
  }) async {
    final pdf = await buildPdf(
      data: data,
      title: title,
      symbol: symbol,
      size: size,
      copies: 1,
      subtitle: subtitle,
    );
    await for (final page in Printing.raster(pdf, pages: [0], dpi: 203)) {
      return page.toPng();
    }
    throw 'Gagal render PNG label.';
  }

  static Future<void> sharePng({
    required String data,
    required String title,
    required AdminLabelSymbol symbol,
    required AdminLabelSize size,
    String? subtitle,
  }) async {
    final png = await buildPng(
      data: data,
      title: title,
      symbol: symbol,
      size: size,
      subtitle: subtitle,
    );
    final name = '${_safeFileName(title, symbol)}.png';
    if (kIsWeb) {
      label_dl.downloadBytes(
        bytes: png,
        filename: name,
        mimeType: 'image/png',
      );
      return;
    }
    await Share.shareXFiles(
      [XFile.fromData(png, mimeType: 'image/png', name: name)],
      subject: title,
    );
  }

  static String _safeFileName(String title, AdminLabelSymbol symbol) {
    final base = title
        .trim()
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final kind = symbol == AdminLabelSymbol.qr ? 'qr' : 'barcode';
    final t = base.isEmpty ? 'label' : base;
    return '${t}_$kind'.toLowerCase();
  }
}

/// Sheet universal: pilih simbol, ukuran, salinan, lalu Print / Share PDF / PNG.
class AdminLabelPrintSheet {
  AdminLabelPrintSheet._();

  static Future<void> show(
    BuildContext context, {
    required String data,
    required String title,
    String? subtitle,
    AdminLabelSymbol initialSymbol = AdminLabelSymbol.barcode1d,
  }) async {
    final payload = data.trim();
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data barcode/QR kosong.')),
      );
      return;
    }

    var symbol = initialSymbol;
    var size = AdminLabelSize.mm50x30;
    var copies = 1;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OptikAdminTokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  16 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: OptikAdminTokens.line,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Cetak label barcode / QR',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: OptikAdminTokens.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Universal: print sistem di device mana pun '
                      '(Mac, Windows, HP). PNG untuk app Niimbot.',
                      style: TextStyle(
                        fontSize: 12,
                        color: OptikAdminTokens.slate.withOpacity(0.75),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: OptikAdminTokens.navy,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Simbol',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: OptikAdminTokens.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _chip(
                            selected: symbol == AdminLabelSymbol.barcode1d,
                            label: 'Barcode 1D',
                            onTap: () => setModal(
                              () => symbol = AdminLabelSymbol.barcode1d,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _chip(
                            selected: symbol == AdminLabelSymbol.qr,
                            label: 'QR 2D',
                            onTap: () => setModal(
                              () => symbol = AdminLabelSymbol.qr,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Ukuran label',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: OptikAdminTokens.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in AdminLabelSize.values)
                          _chip(
                            selected: size == s,
                            label: s.label,
                            onTap: () => setModal(() => size = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text(
                          'Salinan',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: OptikAdminTokens.navy,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: copies <= 1
                              ? null
                              : () => setModal(() => copies--),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$copies',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          onPressed: copies >= 50
                              ? null
                              : () => setModal(() => copies++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'print'),
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikAdminTokens.navy,
                        foregroundColor: OptikAdminTokens.bg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text(
                        'Print (dialog sistem)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'share_pdf'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Share / unduh PDF'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'share_png'),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        kIsWeb
                            ? 'Unduh PNG (untuk app Niimbot)'
                            : 'Share PNG (untuk app Niimbot)',
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Batal'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (action == null || !context.mounted) return;
    try {
      switch (action) {
        case 'print':
          await AdminLabelPrintService.printPdf(
            data: payload,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            size: size,
            copies: copies,
          );
        case 'share_pdf':
          await AdminLabelPrintService.sharePdf(
            data: payload,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            size: size,
            copies: copies,
          );
        case 'share_png':
          await AdminLabelPrintService.sharePng(
            data: payload,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            size: size,
          );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  /// Shortcut: pilih lewat AdminPicker lalu cetak (tanpa sheet ukuran).
  static Future<void> showQuickPrint(
    BuildContext context, {
    required String data,
    required String title,
    String? subtitle,
  }) async {
    final sel = await showAdminPicker<AdminLabelSymbol>(
      context: context,
      title: 'Cetak label',
      subtitle: title,
      headerIcon: Icons.qr_code_2_rounded,
      searchable: false,
      selected: null,
      options: const [
        AdminPickerOption(
          value: AdminLabelSymbol.barcode1d,
          label: 'Barcode 1D (Code128)',
          subtitle: 'Label rak / stiker produk',
          icon: Icons.view_week_rounded,
        ),
        AdminPickerOption(
          value: AdminLabelSymbol.qr,
          label: 'QR 2D',
          subtitle: 'Scan HP / POS',
          icon: Icons.qr_code_2_rounded,
        ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null || !context.mounted) {
      return;
    }
    await show(
      context,
      data: data,
      title: title,
      subtitle: subtitle,
      initialSymbol: sel.value!,
    );
  }

  static Widget _chip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? OptikAdminTokens.navy.withOpacity(0.12)
          : OptikAdminTokens.navy.withOpacity(0.03),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.line,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: OptikAdminTokens.navy,
            ),
          ),
        ),
      ),
    );
  }
}
