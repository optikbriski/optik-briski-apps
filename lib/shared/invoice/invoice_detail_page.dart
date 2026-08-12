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
import 'invoice_delivery_service.dart';
import 'invoice_hub_page.dart';
import 'invoice_layout.dart';
import 'invoice_lifecycle_service.dart';
import 'invoice_link.dart';
import 'invoice_settings_service.dart';
import 'invoice_status_footer.dart';
import 'sale_fulfillment_service.dart';
import '../widgets/admin/admin_premium.dart';

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
  Map<String, dynamic>? configData;
  InvoiceSettings? invSettings;
  bool isPrinting = false;
  String currentTrackingStatus = "DIPROSES_DI_CABANG";
  List<String> karyawanTerlibatNames = const [];

  @override
  void initState() {
    super.initState();
    _fetchNota();
  }

  Future<List<String>> _loadKaryawanTerlibatNames(String saleId) async {
    try {
      final rows = await supabase
          .from('sales_karyawan_terlibat')
          .select('karyawan_id, karyawan:karyawan_id(nama)')
          .eq('sale_id', saleId);
      final names = <String>[];
      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final nested = row['karyawan'];
        String? nama;
        if (nested is Map) {
          nama = nested['nama']?.toString();
        } else if (nested is List && nested.isNotEmpty && nested.first is Map) {
          nama = (nested.first as Map)['nama']?.toString();
        }
        if (nama != null && nama.trim().isNotEmpty) {
          names.add(nama.trim());
        }
      }
      return names;
    } catch (e) {
      debugPrint('Muat karyawan terlibat gagal: $e');
      return const [];
    }
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
      final terlibat = await _loadKaryawanTerlibatNames(widget.saleId);

      final cabangNota =
          resSale['toko_id']?.toString().toUpperCase() ?? 'PUSAT';
      final settings =
          await InvoiceSettingsService().fetchForToko(cabangNota);

      if (mounted) {
        setState(() {
          saleData = resSale;
          saleItems = resItems;
          invSettings = settings;
          configData = settings.toLegacyConfigMap();
          currentTrackingStatus =
              resSale['tracking_status'] ?? "DIPROSES_DI_CABANG";
          karyawanTerlibatNames = terlibat;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal muat data detail nota: $e");
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("${"pos_err_muat_nota".tr()} $e"),
            backgroundColor: OptikAdminTokens.danger));
      }
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
      final settings = invSettings ??
          await InvoiceSettingsService()
              .fetchForToko(sale['toko_id']?.toString());
      final config = settings.toLegacyConfigMap();

      int totalHarga = sale['total_harga'] ?? 0;
      int uangMukaDP = sale['dibayarkan'] ?? 0;
      int sisaTagihan = sale['sisa_tagihan'] ?? 0;

      pw.ImageProvider? logoImage;
      if (settings.hasLogo) {
        try {
          logoImage = await networkImage(settings.logoUrl);
        } catch (_) {}
      }

      final statusFooter = InvoiceStatusFooter.forSale(
        Map<String, dynamic>.from(sale as Map),
        footers: settings.statusFooters,
        forPdf: true,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            final pdfLines = <InvoiceDocLine>[
              for (final item in items)
                InvoiceDocLine(
                  label: () {
                    var cleanName = item['nama_produk'] ?? '-';
                    if (cleanName.toString().toUpperCase().contains('LENSA') ||
                        cleanName
                            .toString()
                            .toUpperCase()
                            .contains('PROGRESIF')) {
                      cleanName = cleanName.toString().replaceAll(
                            RegExp(
                                r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                            '',
                          ).trim();
                    }
                    return '$cleanName  ×${item['qty'] ?? 1}';
                  }(),
                  amount: formatRupiah(item['subtotal'] ?? 0),
                  group: InvoiceLayout.groupOfProduct(
                    tipe: item['tipe_produk']?.toString() ??
                        item['kategori']?.toString(),
                    nama: item['nama_produk']?.toString(),
                  ),
                ),
            ];

            pw.Widget? qrPdf;
            if (config['show_qr_invoice'] == true) {
              qrPdf = pw.Container(
                height: 44,
                width: 44,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: InvoiceLink.encodeFromSale(
                      Map<String, dynamic>.from(sale as Map)),
                  padding: pw.EdgeInsets.zero,
                ),
              );
            }

            return InvoiceLayout.documentBodyPdf(
              settings: settings,
              footerText: statusFooter,
              logoImage: logoImage,
              meta: InvoiceDocMeta(
                noInvoice: sale['no_invoice']?.toString() ?? '-',
                customerName: (sale['nama_pelanggan'] ?? '-').toString(),
                whatsapp: sale['no_wa']?.toString(),
                address: sale['alamat']?.toString(),
                email: sale['email_pelanggan']?.toString(),
                cashier: karyawanTerlibatNames.isNotEmpty
                    ? karyawanTerlibatNames.join(', ')
                    : (sale['nama_kasir']?.toString() ?? '-'),
                dateLabel:
                    'Masuk: ${sale['created_at'].toString().split('T').first}',
                createdAtLabel: InvoiceLayout.formatInvoiceCreatedAt(
                  sale['created_at'],
                ),
                status: sisaTagihan > 0 ? 'DP' : 'LUNAS',
                boardStatus: InvoiceStatusFooter.statusOf(
                  Map<String, dynamic>.from(sale as Map),
                ),
              ),
              lines: pdfLines,
              totalFormatted: formatRupiah(totalHarga),
              paidLabel: sisaTagihan > 0 ? 'Uang muka (DP)' : 'Dibayar',
              paidFormatted: formatRupiah(uangMukaDP),
              remainingFormatted: formatRupiah(sisaTagihan),
              hasRemainingDebt: sisaTagihan > 0,
              qrChild: qrPdf,
              itemsTitle: 'RINCIAN ITEM PESANAN',
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      final pdfBase64 = base64Encode(pdfBytes);

      final delivered = await InvoiceDeliveryService().deliver(
        sale: Map<String, dynamic>.from(sale as Map),
        pdfBase64: pdfBase64,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              delivered.summary,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: delivered.anyOk || delivered.allRequestedOk
                ? OptikAdminTokens.success
                : OptikAdminTokens.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint("Gagal share PDF: $e");
    }
  }

  Widget _detailLensTable(String detailResepDb, double fBody) {
    String p(String eye, String param) =>
        _parseResepDinamis(detailResepDb, eye, param);
    String ax(String eye) {
      final a = p(eye, 'AXIS');
      return a.endsWith('°') ? a : '$a°';
    }

    Widget cell(String txt, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            txt,
            style: TextStyle(
              fontSize: header ? 8 : 9,
              fontWeight: header ? FontWeight.bold : FontWeight.w500,
              color: OptikAdminTokens.navy,
            ),
            textAlign: TextAlign.center,
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
                  p('OD', 'SPH'),
                  p('OD', 'CYL'),
                  ax('OD'),
                  p('OD', 'ADD'),
                ].map(cell).toList(),
              ),
              TableRow(
                children: [
                  'OS (Kiri)',
                  p('OS', 'SPH'),
                  p('OS', 'CYL'),
                  ax('OS'),
                  p('OS', 'ADD'),
                ].map(cell).toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            'PD Pasien (R/L): ${p('', 'PD')} mm',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: (fBody - 3).clamp(8.0, 14.0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const PremiumScaffold(
        body:
            Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy)),
      );
    }

    if (saleData == null || configData == null) {
      return PremiumScaffold(
        appBar: PremiumAppBar(title: "pos_nota_title".tr()),
        body: Center(
            child: Text("pos_data_tidak_ditemukan".tr(),
                style: const TextStyle(color: OptikAdminTokens.navy))),
      );
    }

    final sale = saleData!;
    final items = saleItems ?? [];
    final config = configData!;
    final settings = invSettings ??
        InvoiceSettings.fromRow(config,
            tokoId: sale['toko_id']?.toString());

    final double fBody = settings.fontSizeBody;

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
              InvoiceLayout.paper(
                width: 420,
                child: InvoiceLayout.documentBody(
                  settings: settings,
                  footerText: InvoiceStatusFooter.forSale(
                    Map<String, dynamic>.from(sale as Map),
                    footers: settings.statusFooters,
                  ),
                  meta: InvoiceDocMeta(
                    noInvoice: sale['no_invoice']?.toString() ?? '-',
                    customerName:
                        (sale['nama_pelanggan'] ?? '-').toString(),
                    whatsapp: sale['no_wa']?.toString(),
                    address: (sale['alamat']?.toString().isNotEmpty ?? false)
                        ? sale['alamat'].toString()
                        : null,
                    email: sale['email_pelanggan']?.toString(),
                    cashier: karyawanTerlibatNames.isNotEmpty
                        ? karyawanTerlibatNames.join(', ')
                        : (sale['nama_kasir']?.toString() ?? 'Staff'),
                    dateLabel:
                        'Masuk: ${sale['created_at'].toString().split('T').first}',
                    createdAtLabel: InvoiceLayout.formatInvoiceCreatedAt(
                      sale['created_at'],
                    ),
                    method: sale['metode_pembayaran']?.toString(),
                    status: sisaTagihan > 0 ? 'DP' : 'LUNAS',
                    boardStatus: InvoiceStatusFooter.statusOf(
                      Map<String, dynamic>.from(sale as Map),
                    ),
                  ),
                  lines: [
                    for (final item in items)
                      InvoiceDocLine(
                        label: () {
                          var rawName = item['nama_produk'] ?? '-';
                          if (rawName.toString().toUpperCase().contains('LENSA') ||
                              rawName
                                  .toString()
                                  .toUpperCase()
                                  .contains('PROGRESIF')) {
                            rawName = rawName.toString().replaceAll(
                                  RegExp(
                                      r'\s*\(\s*[-+\d./\s\w]*?(?:/|ADD)[-+\d./\s\w]*?\)'),
                                  '',
                                ).trim();
                          }
                          return '$rawName  ×${item['qty'] ?? 1}';
                        }(),
                        amount: formatRupiah(item['subtotal'] ?? 0),
                        group: InvoiceLayout.groupOfProduct(
                          tipe: item['tipe_produk']?.toString() ??
                              item['kategori']?.toString(),
                          nama: item['nama_produk']?.toString(),
                        ),
                      ),
                  ],
                  totalFormatted: formatRupiah(totalHarga),
                  paidLabel: sisaTagihan > 0 ? 'Uang muka (DP)' : 'Dibayar',
                  paidFormatted: formatRupiah(uangMukaDP),
                  remainingFormatted: formatRupiah(sisaTagihan),
                  hasRemainingDebt: sisaTagihan > 0,
                  extras: hasLensa
                      ? _detailLensTable(detailResepDb, fBody)
                      : null,
                  qrChild: settings.showQrInvoice
                      ? Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(color: OptikAdminTokens.line),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: SizedBox(
                            height: 52,
                            width: 52,
                            child: QrImageView(
                              data: InvoiceLink.encodeFromSale(
                                  Map<String, dynamic>.from(sale as Map)),
                              version: QrVersions.auto,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        )
                      : null,
                  itemsTitle: 'Rincian item pesanan',
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
                      Builder(builder: (_) {
                        final lineMaps = items
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        final c = SaleFulfillmentService.counts(lineMaps);
                        final lineSummary = c.total == 0
                            ? currentTrackingStatus
                            : 'Ready ${c.ready} · RO ${c.pendingRo} · Diambil ${c.diambil}';
                        final hasRo = c.pendingRo > 0;
                        final canPartial = c.ready > 0 && c.pendingRo > 0;
                        return Text(
                          'Status: ${SaleFulfillmentService.summaryLabel(lineMaps)}\n'
                          'Line: $lineSummary'
                          '${sale['diambil_at'] != null ? ' · invoice diambil' : ''}\n'
                          '${canPartial ? 'Item READY bisa diambil sekarang, atau tunggu RO selesai. ' : ''}'
                          '${hasRo && !canPartial ? 'RO otomatis pending sampai stok ready. ' : ''}'
                          'Aksi lifecycle: scan QR pelanggan (DP/LUNAS/CLAIM) di hub.',
                          style: const TextStyle(
                            color: OptikAdminTokens.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: OptikAdminTokens.navy,
                                foregroundColor: OptikAdminTokens.snow,
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
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: OptikAdminTokens.bgMid,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: OptikAdminTokens.lineStrong,
                                ),
                              ),
                              child: Text(
                                currentTrackingStatus == 'SIAP_DIAMBIL' ||
                                        currentTrackingStatus == 'CLEAR'
                                    ? 'SIAP AMBIL'
                                    : currentTrackingStatus == 'PENDING_PO'
                                        ? 'RO · OTOMATIS'
                                        : currentTrackingStatus,
                                style: const TextStyle(
                                  color: OptikAdminTokens.navy,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
                        onPressed: isPrinting
                            ? null
                            : () => _showFlexiblePrint(sale, items),
                        icon: const Icon(Icons.print, size: 16),
                        label: Text(
                          "nota_btn_cetak".tr(),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isPrinting
                            ? null
                            : () => _generateDetailPagePDF(sale, items),
                        icon: const Icon(Icons.picture_as_pdf, size: 16),
                        label: Text(
                          "nota_btn_share".tr(),
                          style: const TextStyle(fontSize: 11),
                        ),
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
                      side: const BorderSide(color: OptikAdminTokens.lineStrong)),
                  onPressed: () => Navigator.pop(context),
                  child: Text("nota_btn_baru".tr(),
                      style: const TextStyle(
                          color: OptikAdminTokens.navy, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
