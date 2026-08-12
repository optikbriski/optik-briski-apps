import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../formatters.dart';
import '../theme.dart';
import 'invoice_layout.dart';
import 'invoice_link.dart';
import 'invoice_settings_service.dart';
import 'invoice_status_footer.dart';

/// Model nota siap render — satu sumber untuk UI / PDF / thermal.
class InvoiceDocumentModel {
  const InvoiceDocumentModel({
    required this.settings,
    required this.meta,
    required this.lines,
    required this.footerText,
    required this.footerTextPdf,
    required this.totalFormatted,
    required this.paidLabel,
    required this.paidFormatted,
    required this.remainingFormatted,
    required this.hasRemainingDebt,
    required this.totalHarga,
    required this.dibayarkan,
    required this.sisaTagihan,
    required this.hasLensa,
    required this.detailResep,
    required this.qrPayload,
    required this.showQr,
    this.logoImage,
  });

  final InvoiceSettings settings;
  final InvoiceDocMeta meta;
  final List<InvoiceDocLine> lines;
  final String footerText;
  final String footerTextPdf;
  final String totalFormatted;
  final String paidLabel;
  final String paidFormatted;
  final String remainingFormatted;
  final bool hasRemainingDebt;
  final int totalHarga;
  final int dibayarkan;
  final int sisaTagihan;
  final bool hasLensa;
  final String detailResep;
  final String qrPayload;
  final bool showQr;
  final pw.ImageProvider? logoImage;
}

/// Builder bersama — Adjust Invoice / POS / PDF / thermal / Member Hub.
abstract final class InvoiceDocumentBuilder {
  InvoiceDocumentBuilder._();

  static Future<InvoiceDocumentModel> fromSale({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    bool loadLogoForPdf = false,
  }) async {
    final map = Map<String, dynamic>.from(sale);
    final itemMaps = items
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);

    final toko = InvoiceSettingsService.normalizeTokoId(
      map['toko_id']?.toString(),
    );
    final settings = await InvoiceSettingsService().fetchForToko(toko);

    final totalHarga =
        int.tryParse(map['total_harga']?.toString() ?? '0') ?? 0;
    final dibayarkan =
        int.tryParse(map['dibayarkan']?.toString() ?? '0') ?? 0;
    final sisaTagihan =
        int.tryParse(map['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = sisaTagihan > 0 ||
        (map['status_pembayaran'] ?? '').toString().toUpperCase() == 'DP';

    final hasLensa = itemMaps.any((item) {
      final tipe = item['tipe_produk']?.toString().toLowerCase() ?? '';
      final nama = item['nama_produk']?.toString().toLowerCase() ?? '';
      return tipe.contains('lensa') ||
          nama.contains('lensa') ||
          nama.contains('progresif');
    });

    var detailResep = '';
    for (final item in itemMaps) {
      final r = item['detail_resep']?.toString() ?? '';
      if (r.isNotEmpty && r != 'Normal' && r.contains('|')) {
        detailResep = r;
        break;
      }
    }

    final lines = <InvoiceDocLine>[
      for (final item in itemMaps)
        InvoiceDocLine(
          label: _itemLabel(item),
          amount: formatRupiah(
            int.tryParse(item['subtotal']?.toString() ?? '0') ?? 0,
          ),
          group: InvoiceLayout.groupOfProduct(
            tipe: item['tipe_produk']?.toString() ??
                item['kategori']?.toString(),
            nama: item['nama_produk']?.toString(),
          ),
        ),
    ];

    final board = InvoiceStatusFooter.statusOf(map);
    final footer = InvoiceStatusFooter.forSale(
      map,
      footers: settings.statusFooters,
    );
    final footerPdf = InvoiceStatusFooter.forSale(
      map,
      footers: settings.statusFooters,
      forPdf: true,
    );

    var qrPayload = '';
    try {
      qrPayload = InvoiceLink.encodeFromSale(map);
    } catch (_) {
      qrPayload = map['no_invoice']?.toString() ?? '';
    }
    final showQr = settings.showQrInvoice &&
        (qrPayload.isNotEmpty) &&
        (InvoiceLink.isCustomerLifecycleQr(qrPayload) ||
            qrPayload.startsWith('OBR') ||
            (map['no_invoice']?.toString().isNotEmpty ?? false));

    pw.ImageProvider? logoImage;
    if (loadLogoForPdf && settings.hasLogo) {
      try {
        logoImage = await networkImage(settings.logoUrl);
      } catch (_) {}
    }

    final created = map['created_at'];
    final dateOnly = created?.toString().split('T').first ?? '';

    return InvoiceDocumentModel(
      settings: settings,
      meta: InvoiceDocMeta(
        noInvoice: map['no_invoice']?.toString() ?? '-',
        customerName: (map['nama_pelanggan'] ?? '-').toString(),
        whatsapp: map['no_wa']?.toString(),
        address: (map['alamat']?.toString().trim().isNotEmpty ?? false)
            ? map['alamat'].toString()
            : null,
        email: (map['email_pelanggan']?.toString().trim().isNotEmpty ?? false)
            ? map['email_pelanggan'].toString()
            : null,
        cashier: map['nama_kasir']?.toString() ?? 'Staff',
        dateLabel: dateOnly.isEmpty ? null : 'Masuk: $dateOnly',
        createdAtLabel: InvoiceLayout.formatInvoiceCreatedAt(created),
        method: map['metode_pembayaran']?.toString(),
        status: isDp ? 'DP' : 'LUNAS',
        boardStatus: board,
      ),
      lines: lines,
      footerText: footer,
      footerTextPdf: footerPdf,
      totalFormatted: formatRupiah(totalHarga),
      paidLabel: isDp ? 'Uang muka (DP)' : 'Dibayar',
      paidFormatted: formatRupiah(dibayarkan),
      remainingFormatted: formatRupiah(sisaTagihan),
      hasRemainingDebt: sisaTagihan > 0,
      totalHarga: totalHarga,
      dibayarkan: dibayarkan,
      sisaTagihan: sisaTagihan,
      hasLensa: hasLensa,
      detailResep: detailResep,
      qrPayload: qrPayload,
      showQr: showQr && settings.showQrInvoice,
      logoImage: logoImage,
    );
  }

  static String _itemLabel(Map<String, dynamic> item) {
    var rawName = item['nama_produk']?.toString() ?? '-';
    if (rawName.toUpperCase().contains('LENSA') ||
        rawName.toUpperCase().contains('PROGRESIF')) {
      rawName = rawName
          .replaceAll(
            RegExp(r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
            '',
          )
          .trim();
    }
    return '$rawName  ×${item['qty'] ?? 1}';
  }

  static String parseResep(String raw, String eye, String param) {
    if (raw.isEmpty || raw.toLowerCase() == 'normal') {
      return param == 'PD' ? '-' : '0.00';
    }
    try {
      final parts = raw.split('|').map((e) => e.trim()).toList();
      if (param == 'PD') {
        for (final part in parts) {
          if (part.toUpperCase().contains('PD PASIEN:')) {
            final split = part.split(RegExp(r'PD Pasien:\s*', caseSensitive: false));
            if (split.length > 1) return split.last.trim();
          }
        }
        if (raw.contains('PD Pasien:')) {
          return raw.split('PD Pasien:')[1].trim();
        }
        return '-';
      }
      final wantR = eye == 'OD' || eye == 'R';
      var sideStr = '';
      for (final part in parts) {
        final u = part.toUpperCase();
        if (wantR && (u.startsWith('R:') || u.startsWith('OD'))) {
          sideStr = part;
          break;
        }
        if (!wantR && (u.startsWith('L:') || u.startsWith('OS'))) {
          sideStr = part;
          break;
        }
      }
      if (sideStr.isEmpty) {
        sideStr = wantR
            ? (parts.isNotEmpty ? parts[0] : '')
            : (parts.length > 1 ? parts[1] : '');
      }
      final match =
          RegExp('$param\\s+([^/|\\s°]+)', caseSensitive: false).firstMatch(sideStr);
      return match?.group(1) ?? '0.00';
    } catch (_) {
      return param == 'PD' ? '-' : '0.00';
    }
  }

  static Widget lensTableUi(String detailResep) {
    if (detailResep.trim().isEmpty) return const SizedBox.shrink();
    String axis(String eye) {
      final a = parseResep(detailResep, eye, 'AXIS');
      return a.endsWith('°') ? a : '$a°';
    }

    Widget cell(String txt, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            txt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: header ? 8 : 9,
              fontWeight: header ? FontWeight.bold : FontWeight.w500,
              color: OptikAdminTokens.navy,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: OptikAdminTokens.lineStrong),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            border: TableBorder.all(color: OptikAdminTokens.line),
            columnWidths: const {
              0: FlexColumnWidth(1.8),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
              4: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: OptikAdminTokens.bgMid),
                children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                    .map((t) => cell(t, header: true))
                    .toList(),
              ),
              TableRow(
                children: [
                  'OD (Kanan)',
                  parseResep(detailResep, 'OD', 'SPH'),
                  parseResep(detailResep, 'OD', 'CYL'),
                  axis('OD'),
                  parseResep(detailResep, 'OD', 'ADD'),
                ].map(cell).toList(),
              ),
              TableRow(
                children: [
                  'OS (Kiri)',
                  parseResep(detailResep, 'OS', 'SPH'),
                  parseResep(detailResep, 'OS', 'CYL'),
                  axis('OS'),
                  parseResep(detailResep, 'OS', 'ADD'),
                ].map(cell).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'PD Pasien (R/L): ${parseResep(detailResep, 'OD', 'PD')}',
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static pw.Widget? lensTablePdf(String detailResep) {
    if (detailResep.trim().isEmpty) return null;
    String axis(String eye) {
      final a = parseResep(detailResep, eye, 'AXIS');
      return a.endsWith('°') ? a : '$a°';
    }

    pw.Widget cell(String txt, {bool header = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Text(
            txt,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: header ? 8 : 9,
              fontWeight:
                  header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: header
                  ? const PdfColor.fromInt(0xFF6D8196)
                  : const PdfColor.fromInt(0xFF000080),
            ),
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: const PdfColor.fromInt(0x4D6D8196)),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Table(
            border: pw.TableBorder.all(
                color: const PdfColor.fromInt(0x336D8196)),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF7FBFC)),
                children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                    .map((t) => cell(t, header: true))
                    .toList(),
              ),
              pw.TableRow(
                children: [
                  'OD (Kanan)',
                  parseResep(detailResep, 'OD', 'SPH'),
                  parseResep(detailResep, 'OD', 'CYL'),
                  axis('OD'),
                  parseResep(detailResep, 'OD', 'ADD'),
                ].map(cell).toList(),
              ),
              pw.TableRow(
                children: [
                  'OS (Kiri)',
                  parseResep(detailResep, 'OS', 'SPH'),
                  parseResep(detailResep, 'OS', 'CYL'),
                  axis('OS'),
                  parseResep(detailResep, 'OS', 'ADD'),
                ].map(cell).toList(),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'PD Pasien (R/L): ${parseResep(detailResep, 'OD', 'PD')}',
          style: pw.TextStyle(
            color: const PdfColor.fromInt(0xFF000080),
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Widget UI nota (Adjust / Member / Detail).
  static Widget buildUi(
    InvoiceDocumentModel doc, {
    double? width,
    String? qrOverride,
  }) {
    final qrData = (qrOverride ?? doc.qrPayload).trim();
    final showQr = doc.settings.showQrInvoice && qrData.isNotEmpty;
    return InvoiceLayout.paper(
      width: width,
      child: InvoiceLayout.documentBody(
        settings: doc.settings,
        footerText: doc.footerText,
        meta: doc.meta,
        lines: doc.lines,
        totalFormatted: doc.totalFormatted,
        paidLabel: doc.paidLabel,
        paidFormatted: doc.paidFormatted,
        remainingFormatted: doc.remainingFormatted,
        hasRemainingDebt: doc.hasRemainingDebt,
        extras: doc.hasLensa ? lensTableUi(doc.detailResep) : null,
        qrChild: showQr
            ? SizedBox(
                height: 52,
                width: 52,
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  gapless: true,
                  padding: EdgeInsets.zero,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: OptikAdminTokens.navy,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: OptikAdminTokens.navy,
                  ),
                ),
              )
            : null,
        itemsTitle: 'Rincian item pesanan',
      ),
    );
  }

  /// PDF A5 — Print / Share / Delivery.
  static Future<Uint8List> buildPdfBytes(
    InvoiceDocumentModel doc, {
    String? qrOverride,
  }) async {
    final pdf = pw.Document();
    final qrData = (qrOverride ?? doc.qrPayload).trim();
    final showQr = doc.settings.showQrInvoice && qrData.isNotEmpty;
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => InvoiceLayout.documentBodyPdf(
          settings: doc.settings,
          footerText: doc.footerTextPdf,
          logoImage: doc.logoImage,
          meta: doc.meta,
          lines: doc.lines,
          totalFormatted: doc.totalFormatted,
          paidLabel: doc.paidLabel,
          paidFormatted: doc.paidFormatted,
          remainingFormatted: doc.remainingFormatted,
          hasRemainingDebt: doc.hasRemainingDebt,
          extras: doc.hasLensa ? lensTablePdf(doc.detailResep) : null,
          qrChild: showQr
              ? pw.Container(
                  height: 44,
                  width: 44,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrData,
                    padding: pw.EdgeInsets.zero,
                  ),
                )
              : null,
          itemsTitle: 'RINCIAN ITEM PESANAN',
        ),
      ),
    );
    return pdf.save();
  }
}
