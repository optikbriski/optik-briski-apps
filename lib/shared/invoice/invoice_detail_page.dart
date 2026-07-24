// ignore_for_file: use_build_context_synchronously, deprecated_member_use, prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../bootstrap.dart';
import '../formatters.dart';
import '../pos_print_service.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets/admin/premium_app_bar.dart';
import '../widgets/admin/premium_scaffold.dart';
import 'invoice_hub_page.dart';
import 'invoice_lifecycle_service.dart';
import 'invoice_link.dart';

class InvoiceDetailPage extends StatefulWidget {
  final String saleId;
  const InvoiceDetailPage({super.key, required this.saleId});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool isLoading = true;
  Map<String, dynamic>? saleData;
  List<dynamic>? saleItems;
  Map<String, dynamic>?
      configData; // Menampung konfigurasi layout dinamis dari database cabang
  bool isPrinting = false;
  String currentTrackingStatus = "DIPROSES_DI_CABANG";

  @override
  void initState() {
    super.initState();
    _fetchNota();
  }

  Future<void> _fetchNota() async {
    try {
      Map<String, dynamic> resSale = Map<String, dynamic>.from(
        await supabase.from('sales').select().eq('id', widget.saleId).single(),
      );
      try {
        resSale = await InvoiceLifecycleService().ensureTokens(widget.saleId);
      } catch (_) {}
      final resItems = await supabase
          .from('sales_items')
          .select()
          .eq('sale_id', widget.saleId);

      // Sinkronisasi Konfigurasi Cabang: Mengunci banner alamat & footer notice riil dari database
      String cabangNota =
          resSale['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      var resConfig = await supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', cabangNota)
          .maybeSingle();
      resConfig ??= await supabase
          .from('invoice_settings')
          .select()
          .eq('toko_id', 'PUSAT')
          .maybeSingle();

      if (mounted) {
        setState(() {
          saleData = resSale;
          saleItems = resItems;
          configData = resConfig ??
              {
                'shop_name': 'OPTIK B. RISKI',
                'address': 'Alamat Toko Cabang $cabangNota',
                'phone': '-',
                'header_alignment': 'CENTER',
                'font_size_header': 16,
                'font_size_body': 12,
                'show_qr_invoice': true,
                'footer_text': 'Terima kasih atas kepercayaan Anda.'
              };
          currentTrackingStatus =
              resSale['tracking_status'] ?? "DIPROSES_DI_CABANG";
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal muat data detail nota: $e");
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("${"pos_err_muat_nota".tr()} $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _updateTrackingStatus(String status, String snackMsg) async {
    setState(() => isPrinting = true);
    try {
      await supabase
          .from('sales')
          .update({'tracking_status': status}).eq('id', widget.saleId);
      setState(() => currentTrackingStatus = status);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(snackMsg,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal memperbarui status: $e"),
          backgroundColor: Colors.red));
    } finally {
      setState(() => isPrinting = false);
    }
  }

  Future<void> _showFlexiblePrint(
      Map<String, dynamic> sale, List<dynamic> items) async {
    setState(() => isPrinting = true);
    try {
      await PosPrintService.showPrintOptions(
        context,
        sale: sale,
        items: items,
        formatRupiah: (n) => formatRupiah(n.round()),
      );
    } finally {
      if (mounted) setState(() => isPrinting = false);
    }
  }

  // 🎯 MESIN PARSER PINTAR: Membongkar string database menjadi matriks tabel medis riil hulu ke hilir
  String _parseResepDinamis(String rawResep, String mata, String parameter) {
    if (rawResep.isEmpty || rawResep == 'Normal') {
      return parameter == 'PD' ? '-' : '0.00';
    }

    try {
      List<String> parts = rawResep.split('|').map((e) => e.trim()).toList();

      if (parameter == 'PD') {
        for (var part in parts) {
          if (part.toUpperCase().contains('PD PASIEN:')) {
            return part.split(RegExp(r'PD Pasien:\s*'))[1].trim();
          }
        }
        return '-';
      }

      String barisMata = mata == 'OD'
          ? parts.firstWhere((e) => e.startsWith('R:'), orElse: () => '')
          : parts.firstWhere((e) => e.startsWith('L:'), orElse: () => '');

      if (barisMata.isEmpty) return '0.00';

      final regExp = RegExp('$parameter\\s+([^/|\\s°]+)');
      final match = regExp.firstMatch(barisMata);
      return match?.group(1) ?? '0.00';
    } catch (e) {
      return parameter == 'PD' ? '-' : '0.00';
    }
  }

// MESIN SHARE PDF STRUK INVOICE (JIPLAK MURNI 100% SAMA DENGAN PRATINJAU NOTA DAN DATABASE)
  Future<void> _generateDetailPagePDF(
      Map<String, dynamic> sale, List<dynamic> items) async {
    try {
      final pdf = pw.Document();
      final config = configData ?? {};

      final bool hasLensa = items.any((item) =>
          item['tipe_produk'].toString().toLowerCase().contains('lensa') ||
          item['nama_produk'].toString().toLowerCase().contains('lensa'));

      String detailResepDb = items.firstWhere(
              (e) => e['tipe_produk'] == 'Lensa',
              orElse: () => {'detail_resep': ''})['detail_resep'] ??
          '';

      int totalHarga = sale['total_harga'] ?? 0;
      int uangMukaDP = sale['dibayarkan'] ?? 0;
      int sisaTagihan = sale['sisa_tagihan'] ?? 0;

      final double fHeader = (config['font_size_header'] ?? 16).toDouble();
      final double fBody = (config['font_size_body'] ?? 12).toDouble();
      final isCenter = config['header_alignment'] == 'CENTER';

      // 🏢 FIX LOGO: Menggunakan networkImage bawaan package printing
      pw.ImageProvider? logoImage;
      if (config['logo_url'] != null &&
          config['logo_url'].toString().isNotEmpty) {
        logoImage = await networkImage(config['logo_url'].toString());
      }

      // 🎯 SANITASI KARAKTER ILLEGAL (Pencegah kotak tofu silang rusak di PDF)
      String cleanFooter = (config['footer_text'] ?? '')
          .toString()
          .replaceAll('•', '-')
          .replaceAll('–', '-')
          .replaceAll('—', '-');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 🏢 HEADER PERUSAHAAN (CENTERED)
                isCenter
                    ? pw.SizedBox(
                        width: double.infinity,
                        child: pw.Stack(
                          children: [
                            if (logoImage != null)
                              pw.Positioned(
                                left: 0,
                                top: 0,
                                child: pw.Container(
                                    height: 24,
                                    child: pw.Image(logoImage,
                                        fit: pw.BoxFit.contain)),
                              ),
                            pw.SizedBox(
                              width: double.infinity,
                              child: pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    (config['shop_name'] ?? 'OPTIK B. RISKI')
                                        .toString()
                                        .toUpperCase(),
                                    style: pw.TextStyle(
                                        fontSize: fHeader - 2,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColor.fromInt(0xFF0F172A)),
                                  ),
                                  pw.SizedBox(height: 4),
                                  pw.Text(
                                    config['address'] ?? '',
                                    style: pw.TextStyle(
                                        fontSize: 8, color: PdfColors.grey700),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    "Telp: ${config['phone'] ?? '-'}",
                                    style: pw.TextStyle(
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.black),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (logoImage != null)
                            pw.Padding(
                              padding: pw.EdgeInsets.only(right: 12.0),
                              child: pw.Container(
                                  height: 24,
                                  child: pw.Image(logoImage,
                                      fit: pw.BoxFit.contain)),
                            ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(
                                    (config['shop_name'] ?? 'OPTIK B. RISKI')
                                        .toString()
                                        .toUpperCase(),
                                    style: pw.TextStyle(
                                        fontSize: fHeader - 2,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColor.fromInt(0xFF0F172A))),
                                pw.SizedBox(height: 4),
                                pw.Text(config['address'] ?? '',
                                    style: pw.TextStyle(
                                        fontSize: 8, color: PdfColors.grey700),
                                    textAlign: pw.TextAlign.end),
                                pw.SizedBox(height: 1),
                                pw.Text("Telp: ${config['phone'] ?? '-'}",
                                    style: pw.TextStyle(
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.black)),
                              ],
                            ),
                          ),
                        ],
                      ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1.5, color: PdfColors.black),
                pw.SizedBox(height: 8),

                // 👥 DATA PELANGGAN & INVOICE META
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("PELANGGAN",
                            style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey600)),
                        pw.Text(
                            (sale['nama_pelanggan'] ?? '-')
                                .toString()
                                .toUpperCase(),
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: fBody - 2,
                                color: PdfColor.fromInt(0xFF1E293B))),
                        pw.Text("WhatsApp: ${sale['no_wa'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                        pw.Text("Alamat: ${sale['alamat'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                        pw.Text("Email: ${sale['email_pelanggan'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(sale['no_invoice'] ?? '-',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: fBody - 1,
                                color: PdfColor.fromInt(0xFF0F172A))),
                        pw.Text(
                            "Masuk: ${sale['created_at'].toString().split('T')[0]}",
                            style: pw.TextStyle(
                                fontSize: 8.5, color: PdfColors.grey700)),
                        pw.Text("Kasir: ${sale['nama_kasir'] ?? '-'}",
                            style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(color: PdfColors.grey300, height: 1),
                pw.SizedBox(height: 6),

                // 📦 RINCIAN ITEM PESANAN
                pw.Text("RINCIAN ITEM PESANAN",
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600)),
                pw.SizedBox(height: 6),
                ...items.map((item) {
                  String cleanName = item['nama_produk'] ?? '-';
                  if (cleanName.toUpperCase().contains('LENSA') ||
                      cleanName.toUpperCase().contains('PROGRESIF')) {
                    cleanName = cleanName
                        .replaceAll(
                            RegExp(
                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                            '')
                        .trim();
                  }
                  return pw.Padding(
                    padding: pw.EdgeInsets.symmetric(vertical: 4.0),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                            child: pw.Text(
                                "- $cleanName (x${item['qty'] ?? 1})",
                                style: pw.TextStyle(
                                    color: PdfColor.fromInt(0xFF0F172A),
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold))),
                        pw.Text(formatRupiah((item['subtotal'] ?? 0) as int),
                            style: pw.TextStyle(
                                color: PdfColor.fromInt(0xFF0F172A),
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  );
                }),

                // 📊 TABEL REFRAKSI LENSA (SINKRON DATABASE)
                if (hasLensa) ...[
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.grey300, height: 1),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                            color: PdfColors.grey400, width: 0.5)),
                    child: pw.Table(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey300, width: 0.5),
                      children: [
                        pw.TableRow(
                          decoration:
                              pw.BoxDecoration(color: PdfColors.grey200),
                          children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(vertical: 3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.grey700),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OD (Kanan)',
                            _parseResepDinamis(detailResepDb, 'OD', 'SPH'),
                            _parseResepDinamis(detailResepDb, 'OD', 'CYL'),
                            _parseResepDinamis(detailResepDb, 'OD', 'AXIS')
                                    .endsWith('°')
                                ? _parseResepDinamis(
                                    detailResepDb, 'OD', 'AXIS')
                                : "${_parseResepDinamis(detailResepDb, 'OD', 'AXIS')}°",
                            _parseResepDinamis(detailResepDb, 'OD', 'ADD')
                          ]
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.all(3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8, color: PdfColors.black),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                        pw.TableRow(
                          children: [
                            'OS (Kiri)',
                            _parseResepDinamis(detailResepDb, 'OS', 'SPH'),
                            _parseResepDinamis(detailResepDb, 'OS', 'CYL'),
                            _parseResepDinamis(detailResepDb, 'OS', 'AXIS')
                                    .endsWith('°')
                                ? _parseResepDinamis(
                                    detailResepDb, 'OS', 'AXIS')
                                : "${_parseResepDinamis(detailResepDb, 'OS', 'AXIS')}°",
                            _parseResepDinamis(detailResepDb, 'OS', 'ADD')
                          ]
                              .map((txt) => pw.Padding(
                                  padding: pw.EdgeInsets.all(3),
                                  child: pw.Text(txt,
                                      style: pw.TextStyle(
                                          fontSize: 8, color: PdfColors.black),
                                      textAlign: pw.TextAlign.center)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                      padding: pw.EdgeInsets.only(top: 6, left: 4),
                      child: pw.Text(
                          "PD Pasien (R/L): ${_parseResepDinamis(detailResepDb, '', 'PD')} mm",
                          style: pw.TextStyle(
                              color: PdfColors.black,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold))),
                ],
                pw.SizedBox(height: 4),
                pw.Divider(color: PdfColors.black, thickness: 1),
                pw.SizedBox(height: 6),

                // 💰 BADGE LUNAS & RANGKUMAN FINANSIAL
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          padding: pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                              color: sisaTagihan > 0
                                  ? PdfColor.fromInt(0xFFFFF3E0)
                                  : PdfColor.fromInt(0xFFE6F4EA),
                              borderRadius: pw.BorderRadius.circular(4),
                              border: pw.Border.all(
                                  color: sisaTagihan > 0
                                      ? PdfColors.orange300
                                      : PdfColor.fromInt(0xFF34A853))),
                          child: pw.Text(sisaTagihan > 0 ? "DP" : "LUNAS",
                              style: pw.TextStyle(
                                  color: sisaTagihan > 0
                                      ? PdfColors.orange900
                                      : PdfColor.fromInt(0xFF137333),
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 8)),
                        ),
                        pw.SizedBox(height: 6),
                        if (config['show_qr_invoice'] == true)
                          pw.Container(
                              height: 55,
                              width: 55,
                              child: pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: InvoiceLink.encodeFromSale(
                                      Map<String, dynamic>.from(sale as Map)),
                                  padding: pw.EdgeInsets.zero)),
                      ],
                    ),
                    pw.SizedBox(
                      width: 210,
                      child: pw.Table(
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.4),
                          1: pw.FlexColumnWidth(1.2)
                        },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text("TOTAL BELANJA",
                                    style: pw.TextStyle(
                                        color: PdfColors.grey700,
                                        fontSize: fBody - 2,
                                        fontWeight: pw.FontWeight.bold))),
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text(formatRupiah(totalHarga),
                                    style: pw.TextStyle(
                                        color: const PdfColor(0, 0, 0),
                                        fontSize: fBody - 2,
                                        fontWeight: pw.FontWeight.bold),
                                    textAlign: pw.TextAlign.end)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text("UANG MUKA (DP)",
                                    style: pw.TextStyle(
                                        color: PdfColors.grey600,
                                        fontSize: fBody - 3))),
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 1.5),
                                child: pw.Text(formatRupiah(uangMukaDP),
                                    style: pw.TextStyle(
                                        color: PdfColors.grey700,
                                        fontSize: fBody - 3),
                                    textAlign: pw.TextAlign.end)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 3.0),
                                child: pw.Text("SISA TAGIHAN",
                                    style: pw.TextStyle(
                                        color: const PdfColor(0, 0, 0),
                                        fontSize: fBody - 1,
                                        fontWeight: pw.FontWeight.bold))),
                            pw.Padding(
                                padding: pw.EdgeInsets.symmetric(vertical: 3.0),
                                child: pw.Text(formatRupiah(sisaTagihan),
                                    style: pw.TextStyle(
                                        color: sisaTagihan > 0
                                            ? PdfColors.red700
                                            : PdfColor.fromInt(0xFF34A853),
                                        fontSize: fBody - 1,
                                        fontWeight: pw.FontWeight.bold),
                                    textAlign: pw.TextAlign.end)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 4),

                // 📝 FOOTER T&C NOTICE
                pw.Text("TERIMA KASIH ATAS KEPERCAYAAN ANDA",
                    style: pw.TextStyle(
                        color: PdfColors.grey600,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(cleanFooter,
                    style:
                        pw.TextStyle(color: PdfColors.grey700, fontSize: 8.5)),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      String pdfBase64 = base64Encode(pdfBytes);

      await supabase.functions.invoke(
        'send-invoice-email',
        body: {
          'invoice': sale['no_invoice'] ?? 'INV-UNKNOWN',
          'email': sale['email_pelanggan'] ?? '',
          'customerName': sale['nama_pelanggan'] ?? 'Pelanggan Setia',
          'netTotal': (sale['total_harga'] ?? 0).toString(),
          'pdfBase64': pdfBase64,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✓ Resend Nota PDF Berhasil Terkirim!",
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Gagal share PDF: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const PremiumScaffold(
        body:
            Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    if (saleData == null || configData == null) {
      return PremiumScaffold(
        appBar: PremiumAppBar(title: "pos_nota_title".tr()),
        body: Center(
            child: Text("pos_data_tidak_ditemukan".tr(),
                style: const TextStyle(color: Colors.white))),
      );
    }

    final sale = saleData!;
    final items = saleItems ?? [];
    final config = configData!;

    final isCenter = config['header_alignment'] == 'CENTER';
    final double fHeader = (config['font_size_header'] ?? 16).toDouble();
    final double fBody = (config['font_size_body'] ?? 12).toDouble();

    // 🎯 FIX MANDATORI: Inisialisasi variabel finansial laci untuk konsumsi UI Widget Tree screen utama
    int totalHarga = sale['total_harga'] ?? 0;
    int uangMukaDP = sale['dibayarkan'] ?? 0;
    int sisaTagihan = sale['sisa_tagihan'] ?? 0;

    final bool hasLensa = items.any((item) =>
        item['tipe_produk'].toString().toLowerCase().contains('lensa') ||
        item['nama_produk'].toString().toLowerCase().contains('lensa'));

    String detailResepDb = items.firstWhere((e) => e['tipe_produk'] == 'Lensa',
            orElse: () => {'detail_resep': ''})['detail_resep'] ??
        '';

    return PremiumScaffold(
      appBar: const PremiumAppBar(
        title: '📄 INVOICE STRUK DIGITAL REAL',
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 📦 KARTU PUTIH UTAMA (JEPLAK 100% PERSIS SINKRON SAMA LAYAR PREVIEW)
              Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]),
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🏢 1. SECTION HEADER (SINKRON DATA INVOICE SETTINGS AKTIF)
                    isCenter
                        ? SizedBox(
                            width: double.infinity,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (config['logo_url'] != null &&
                                    config['logo_url'].toString().isNotEmpty)
                                  Positioned(
                                    left: 0,
                                    top: -2.0,
                                    child: Image.network(config['logo_url'],
                                        height: 24, fit: BoxFit.contain),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        (config['shop_name'] ??
                                                'OPTIK B. RISKI')
                                            .toString()
                                            .toUpperCase(),
                                        style: TextStyle(
                                            color: OptikAdminTokens.bgMid,
                                            fontWeight: FontWeight.w800,
                                            fontSize: fHeader - 1,
                                            letterSpacing: 0.5,
                                            height: 1.0),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 45.0),
                                        child: Text(config['address'] ?? '',
                                            style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 8.5,
                                                height: 1.35),
                                            textAlign: TextAlign.center),
                                      ),
                                      const SizedBox(height: 3),
                                      Text("Telp: ${config['phone'] ?? '-'}",
                                          style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (config['logo_url'] != null &&
                                  config['logo_url'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Image.network(config['logo_url'],
                                      height: 24, fit: BoxFit.contain),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        (config['shop_name'] ??
                                                'OPTIK B. RISKI')
                                            .toString()
                                            .toUpperCase(),
                                        style: TextStyle(
                                            color: OptikAdminTokens.bgMid,
                                            fontWeight: FontWeight.w800,
                                            fontSize: fHeader - 1,
                                            letterSpacing: 0.5)),
                                    const SizedBox(height: 4),
                                    Text(config['address'] ?? '',
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 8.5,
                                            height: 1.35),
                                        textAlign: TextAlign.end),
                                    const SizedBox(height: 1),
                                    Text("Telp: ${config['phone'] ?? '-'}",
                                        style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 8),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(
                            color: Colors.black87, thickness: 1.5, height: 1),
                        SizedBox(height: 1.5),
                        Divider(
                            color: Colors.black12, thickness: 0.5, height: 1),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 📋 2. DATA PELANGGAN & INTERNAL META ADMINISTRATIF (SISI KIRI PELANGGAN, SISI KANAN NOTA)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sale['no_invoice'] ?? '-',
                                  style: TextStyle(
                                      color: OptikAdminTokens.bgMid,
                                      fontWeight: FontWeight.bold,
                                      fontSize: fBody - 1,
                                      letterSpacing: 0.2)),
                              const SizedBox(height: 6),
                              const Text("PELANGGAN",
                                  style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8)),
                              const SizedBox(height: 1),
                              Text(
                                  (sale['nama_pelanggan'] ?? '-')
                                      .toString()
                                      .toUpperCase(),
                                  style: TextStyle(
                                      color: OptikAdminTokens.card,
                                      fontSize: fBody - 2,
                                      fontWeight: FontWeight.bold)),
                              Text("WhatsApp: ${sale['no_wa'] ?? '-'}",
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: fBody - 3)),
                              if (sale['alamat'] != null &&
                                  sale['alamat'].toString().isNotEmpty)
                                Text("Alamat: ${sale['alamat']}",
                                    style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: fBody - 3)),
                              Text("Email: ${sale['email_pelanggan'] ?? '-'}",
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: fBody - 3)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: sisaTagihan > 0
                                      ? Colors.orange.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: sisaTagihan > 0
                                          ? Colors.orange.shade300
                                          : Colors.green.shade300)),
                              child: Text(
                                  sisaTagihan > 0
                                      ? "DP (SISA TAGIHAN)"
                                      : "LUNAS",
                                  style: TextStyle(
                                      color: sisaTagihan > 0
                                          ? Colors.orange.shade900
                                          : Colors.green.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 8)),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text("Masuk: ",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 8.5)),
                                Text(
                                    sale['created_at'].toString().split('T')[0],
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("Kasir: ",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 8.5)),
                                Text(sale['nama_kasir'] ?? 'Staff',
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("Metode: ",
                                    style: TextStyle(
                                        color: Colors.black38, fontSize: 8.5)),
                                Text(sale['metode_pembayaran'] ?? 'Tunai',
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(color: Colors.black12, height: 1),
                    const SizedBox(height: 6),

                    // 👓 3. SECTION RINCIAN BELANJA ITEM KASIR (DICLEAN DENGAN REGEX PREVIEW)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("RINCIAN ITEM PESANAN",
                            style: TextStyle(
                                color: Colors.black38,
                                fontSize: fBody - 4,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 6),
                        ...items.map((item) {
                          String rawName = item['nama_produk'] ?? '-';

                          if (rawName.toUpperCase().contains('LENSA') ||
                              rawName.toUpperCase().contains('PROGRESIF')) {
                            final rxPrescription = RegExp(
                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)');
                            rawName =
                                rawName.replaceAll(rxPrescription, '').trim();
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                      "- $rawName (x${item['qty'] ?? 1})",
                                      style: const TextStyle(
                                          color: OptikAdminTokens.bgMid,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          height: 1.2)),
                                ),
                                const SizedBox(width: 15),
                                Text(formatRupiah(item['subtotal'] ?? 0),
                                    style: const TextStyle(
                                        color: OptikAdminTokens.bgMid,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w900)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 👁️ 4. SECTION HASIL REFRAKSI MEDIS SINKRON TOTAL (TABLE KEMBAR IDENTIK SAMA PREVIEW)
                    if (hasLensa) ...[
                      const Divider(color: Colors.black12, height: 1),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(4)),
                        child: HScroll(
                          minWidth: 480,
                          child: Table(
                          border: TableBorder.all(color: Colors.black12),
                          columnWidths: const {
                            0: FlexColumnWidth(1.8),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FlexColumnWidth(2),
                            4: FlexColumnWidth(2),
                          },
                          children: [
                            TableRow(
                              decoration:
                                  const BoxDecoration(color: Color(0xFFF8FAFC)),
                              children: ['OD/OS', 'SPH', 'CYL', 'AXIS', 'ADD']
                                  .map((txt) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Text(txt,
                                            style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black45),
                                            textAlign: TextAlign.center),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: [
                                'OD (Kanan)',
                                _parseResepDinamis(detailResepDb, 'OD', 'SPH'),
                                _parseResepDinamis(detailResepDb, 'OD', 'CYL'),
                                _parseResepDinamis(detailResepDb, 'OD', 'AXIS')
                                        .endsWith('°')
                                    ? _parseResepDinamis(
                                        detailResepDb, 'OD', 'AXIS')
                                    : "${_parseResepDinamis(detailResepDb, 'OD', 'AXIS')}°",
                                _parseResepDinamis(detailResepDb, 'OD', 'ADD')
                              ]
                                  .map((txt) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Text(txt,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w500),
                                            textAlign: TextAlign.center),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: [
                                'OS (Kiri)',
                                _parseResepDinamis(detailResepDb, 'OS', 'SPH'),
                                _parseResepDinamis(detailResepDb, 'OS', 'CYL'),
                                _parseResepDinamis(detailResepDb, 'OS', 'AXIS')
                                        .endsWith('°')
                                    ? _parseResepDinamis(
                                        detailResepDb, 'OS', 'AXIS')
                                    : "${_parseResepDinamis(detailResepDb, 'OS', 'AXIS')}°",
                                _parseResepDinamis(detailResepDb, 'OS', 'ADD')
                              ]
                                  .map((txt) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Text(txt,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w500),
                                            textAlign: TextAlign.center),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "PD Pasien (R/L): ${_parseResepDinamis(detailResepDb, '', 'PD')} mm",
                            style: TextStyle(
                                color: Colors.black87,
                                fontSize: (fBody - 3).clamp(8.0, 14.0),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.1),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),
                    const Divider(color: Colors.black87, thickness: 1),
                    const SizedBox(height: 6),

                    // 💰 5. SECTION FINANSIAL & QR EXPANDED (SINKRON PREVIEW RATAN KANAN)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        config['show_qr_invoice'] == true
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      border: Border.all(color: Colors.black12),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: SizedBox(
                                    height: 55,
                                    width: 55,
                                    child: QrImageView(
                                        data: InvoiceLink.encodeFromSale(
                                            Map<String, dynamic>.from(
                                                sale as Map)),
                                        version: QrVersions.auto,
                                        padding: EdgeInsets.zero),
                                  ),
                                ),
                              )
                            : const SizedBox(),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (config['show_qr_invoice'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'QR pelanggan',
                                      style: TextStyle(
                                        color: Colors.black45,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total Belanja",
                                      style: TextStyle(
                                          color: Colors.black54, fontSize: 11)),
                                  Text(formatRupiah(totalHarga),
                                      style: const TextStyle(
                                          color: OptikAdminTokens.bgMid,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold))
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total Dibayar",
                                      style: TextStyle(
                                          color: Colors.black38, fontSize: 11)),
                                  Text(formatRupiah(uangMukaDP),
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600))
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.0),
                                child: Divider(
                                    color: Colors.black12,
                                    height: 1,
                                    thickness: 1),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("SISA TAGIHAN",
                                      style: TextStyle(
                                          color: OptikAdminTokens.bgMid,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold)),
                                  Text(formatRupiah(sisaTagihan),
                                      style: TextStyle(
                                          color: sisaTagihan > 0
                                              ? Colors.red.shade700
                                              : Colors.green.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900))
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.black26),
                    const SizedBox(height: 4),

                    // 🎯 6. FOOTER NOTICE
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(config['footer_text'] ?? '',
                          style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 8.5,
                              height: 1.35)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Lunas: scan QR LUNAS (hub) → serah terima + garansi; scan ke-2 → klaim
              if ((sale['status_pembayaran']?.toString().toLowerCase() ?? '') ==
                  'lunas') ...[
                Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: OptikAdminTokens.card,
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Status: $currentTrackingStatus'
                        '${sale['diambil_at'] != null ? ' · sudah diambil' : ''}\n'
                        'Aksi lifecycle: scan QR pelanggan (DP/LUNAS/CLAIM) '
                        'dengan scanner toko yang terhubung ke web admin.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OptikAdminTokens.card,
                                foregroundColor: Colors.white70,
                              ),
                              onPressed: isPrinting
                                  ? null
                                  : () async {
                                      final inv =
                                          sale['no_invoice']?.toString() ?? '';
                                      if (inv.isEmpty) return;
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => InvoiceHubPage(
                                            noInvoice: inv,
                                            viewOnly: true,
                                            profile: {
                                              'toko_id': sale['toko_id'],
                                              'role': 'admin_toko',
                                            },
                                          ),
                                        ),
                                      );
                                      await _fetchNota();
                                    },
                              icon: const Icon(Icons.receipt_long, size: 16),
                              label: const Text(
                                'LIHAT DETAIL INVOICE',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      currentTrackingStatus == 'PENDING_PO'
                                          ? Colors.orange
                                          : Colors.grey.shade800),
                              onPressed: isPrinting
                                  ? null
                                  : () => _updateTrackingStatus('PENDING_PO',
                                      "✓ Sukses! Pesanan dinyatakan Tertunda (PENDING PO)."),
                              icon:
                                  const Icon(Icons.hourglass_empty, size: 16),
                              label: const Text("PENDING PO",
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              Container(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal),
                        onPressed: isPrinting
                            ? null
                            : () => _showFlexiblePrint(sale, items),
                        icon: const Icon(Icons.print, size: 16),
                        label: Text("nota_btn_cetak".tr(),
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        onPressed: isPrinting
                            ? null
                            : () => _generateDetailPagePDF(sale, items),
                        icon: const Icon(Icons.picture_as_pdf, size: 16),
                        label: Text("nota_btn_share".tr(),
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: R.dialogMaxWidth(context, 420),
                height: 45,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24)),
                  onPressed: () => Navigator.pop(context),
                  child: Text("nota_btn_baru".tr(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
