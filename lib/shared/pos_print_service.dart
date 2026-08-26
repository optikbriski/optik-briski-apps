import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'invoice/invoice_document_builder.dart';
import 'invoice/invoice_layout.dart';
import 'print/pos_cups_print_stub.dart'
    if (dart.library.io) 'print/pos_cups_print_io.dart' as cups;
import 'theme.dart';
import 'widgets/admin/admin_picker.dart';

const _prefPrinterMac = 'pos_bt_printer_mac';
const _prefPrinterName = 'pos_bt_printer_name';
const _prefCupsQueue = 'pos_cups_queue';

class PosPrintService {
  /// Picker: Print PDF / Share PDF / USB POS-80 / Bluetooth thermal.
  /// Semua jalur memakai setting Adjust Invoice (kit yang sama).
  static Future<void> showPrintOptions(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final options = <AdminPickerOption<String>>[
      const AdminPickerOption(
        value: 'thermal80',
        label: 'Cetak thermal 80mm',
        subtitle: 'Ukuran gulungan POS-80 — pilih printer POS-80 di dialog',
        icon: Icons.receipt_long_rounded,
      ),
      const AdminPickerOption(
        value: 'pdf',
        label: 'Print PDF A5',
        subtitle: 'Layout Adjust Invoice (kertas A5)',
        icon: Icons.print_outlined,
      ),
      const AdminPickerOption(
        value: 'share',
        label: 'Share PDF',
        subtitle: 'Kirim file PDF layout Adjust Invoice',
        icon: Icons.share_outlined,
      ),
      if (!kIsWeb) ...const [
        AdminPickerOption(
          value: 'usb',
          label: 'USB POS-80 (ESC/POS raw)',
          subtitle: 'Langsung ke printer USB lewat CUPS',
          icon: Icons.usb_rounded,
        ),
        AdminPickerOption(
          value: 'bluetooth',
          label: 'Bluetooth thermal (ESC/POS)',
          subtitle: 'Printer BT 58mm',
          icon: Icons.bluetooth_outlined,
        ),
      ],
    ];

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cara cetak',
      subtitle: kIsWeb
          ? 'Web: pilih thermal 80mm, lalu Destination = POS-80 (bukan Save as PDF)'
          : 'Thermal 80mm, PDF A5, USB raw, atau Bluetooth',
      headerIcon: Icons.print_rounded,
      searchable: false,
      selected: null,
      options: options,
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    if (!context.mounted) return;
    switch (sel.value) {
      case 'thermal80':
        await printThermal80(
          sale: sale,
          items: items,
          formatRupiah: formatRupiah,
        );
      case 'pdf':
        await printPdf(sale: sale, items: items, formatRupiah: formatRupiah);
      case 'share':
        await sharePdf(sale: sale, items: items, formatRupiah: formatRupiah);
      case 'usb':
        await printUsb(
          context,
          sale: sale,
          items: items,
          formatRupiah: formatRupiah,
        );
      case 'bluetooth':
        await printBluetooth(
          context,
          sale: sale,
          items: items,
          formatRupiah: formatRupiah,
        );
    }
  }

  static Future<InvoiceDocumentModel> _doc({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    bool loadLogoForPdf = false,
  }) {
    return InvoiceDocumentBuilder.fromSale(
      sale: sale,
      items: items,
      loadLogoForPdf: loadLogoForPdf,
    );
  }

  static Future<Uint8List> buildReceiptPdfBytes({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final doc = await _doc(
      sale: sale,
      items: items,
      loadLogoForPdf: true,
    );
    return InvoiceDocumentBuilder.buildPdfBytes(doc);
  }

  static Future<void> printPdf({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final bytes = await buildReceiptPdfBytes(
        sale: sale, items: items, formatRupiah: formatRupiah);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.a5,
      name: 'nota_${sale['no_invoice'] ?? 'invoice'}',
    );
  }

  /// Struk gulungan 80mm — di dialog Chrome pilih Destination = POS-80 agar tombol jadi Print.
  static Future<void> printThermal80({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final doc = await _doc(
      sale: sale,
      items: items,
      loadLogoForPdf: true,
    );
    final bytes = await InvoiceDocumentBuilder.buildThermalPdfBytes(doc);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: InvoiceDocumentBuilder.thermal80Format,
      name: 'struk_${sale['no_invoice'] ?? 'invoice'}',
    );
  }

  static Future<void> sharePdf({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final bytes = await buildReceiptPdfBytes(
        sale: sale, items: items, formatRupiah: formatRupiah);
    final name = 'nota_${sale['no_invoice'] ?? 'invoice'}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  /// Cetak ESC/POS ke POS-80 (USB) via antrian CUPS — macOS/Linux desktop.
  static Future<void> printUsb(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    if (kIsWeb) {
      await printThermal80(
        sale: sale,
        items: items,
        formatRupiah: formatRupiah,
      );
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final known = await cups.PosCupsPrint.listQueues();
      var queue = prefs.getString(_prefCupsQueue);
      if (queue == null ||
          queue.isEmpty ||
          !known.any((q) => q.toLowerCase() == queue!.toLowerCase())) {
        queue = await cups.PosCupsPrint.ensureQueue(
          queue: 'POS-80',
          nameHint: 'POS-80',
        );
      }
      if (queue == null || queue.isEmpty) {
        throw 'Printer POS-80 belum siap di Mac.\n'
            'System Settings → Printers & Scanners → Add Printer → pilih POS-80 '
            '(Generic/Raw), namakan POS-80, lalu coba lagi.';
      }
      await prefs.setString(_prefCupsQueue, queue);

      final doc = await _doc(sale: sale, items: items);
      final bytes = await buildEscPos(doc, paper: PaperSize.mm80);
      final title = 'nota_${sale['no_invoice'] ?? 'invoice'}';
      await cups.PosCupsPrint.printRaw(
        queue: queue,
        bytes: bytes,
        jobTitle: title,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nota terkirim ke $queue (USB ESC/POS 80mm).'),
          backgroundColor: OptikAdminTokens.success,
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: OptikAdminTokens.danger,
        action: SnackBarAction(
          label: '80mm',
          textColor: OptikAdminTokens.snow,
          onPressed: () => printThermal80(
            sale: sale,
            items: items,
            formatRupiah: formatRupiah,
          ),
        ),
      ));
    }
  }

  static Future<void> printBluetooth(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    if (kIsWeb) {
      await printThermal80(
        sale: sale,
        items: items,
        formatRupiah: formatRupiah,
      );
      return;
    }
    try {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Izin Bluetooth diperlukan untuk cetak thermal.'),
            backgroundColor: OptikAdminTokens.warning,
          ));
        }
        return;
      }

      var mac = await _savedPrinterMac();
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        if (!context.mounted) return;
        mac ??= await _pickPrinter(context);
        if (mac == null) return;
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
        if (!ok) {
          throw 'Gagal konek printer Bluetooth. Pakai USB POS-80 atau Print PDF.';
        }
      }

      final doc = await _doc(sale: sale, items: items);
      final bytes = await buildEscPos(doc, paper: PaperSize.mm58);
      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      if (!sent) {
        throw 'Gagal mengirim data ke printer.';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nota thermal terkirim (layout Adjust Invoice).'),
          backgroundColor: OptikAdminTokens.success,
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: OptikAdminTokens.danger,
        action: SnackBarAction(
          label: '80mm',
          textColor: OptikAdminTokens.snow,
          onPressed: () => printThermal80(
            sale: sale,
            items: items,
            formatRupiah: formatRupiah,
          ),
        ),
      ));
    }
  }

  static Future<String?> _savedPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPrinterMac);
  }

  static Future<String?> _pickPrinter(BuildContext context) async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    if (devices.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Tidak ada printer terpasang. Pair dulu di Settings Bluetooth HP.'),
          backgroundColor: OptikAdminTokens.warning,
        ));
      }
      return null;
    }
    if (!context.mounted) return null;
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih printer Bluetooth',
      subtitle: 'Printer thermal yang sudah dipasangkan',
      headerIcon: Icons.print_rounded,
      searchHint: 'Cari nama / MAC…',
      selected: null,
      options: [
        for (final d in devices)
          AdminPickerOption(
            value: d.macAdress,
            label: d.name,
            subtitle: d.macAdress,
            icon: Icons.print_outlined,
          ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return null;
    final mac = sel.value!;
    final name = devices
        .firstWhere((d) => d.macAdress == mac, orElse: () => devices.first)
        .name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPrinterMac, mac);
    await prefs.setString(_prefPrinterName, name);
    return mac;
  }

  /// ESC/POS thermal — [PaperSize.mm80] untuk POS-80 USB, [PaperSize.mm58] BT.
  static Future<List<int>> buildEscPos(
    InvoiceDocumentModel doc, {
    PaperSize paper = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paper, profile);
    final bytes = <int>[];
    final s = doc.settings;
    final m = doc.meta;

    bytes.addAll(g.reset());
    bytes.addAll(g.text(
      s.shopName.toUpperCase(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    ));
    if (s.address.trim().isNotEmpty) {
      bytes.addAll(g.text(s.address,
          styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(g.text('Telp ${s.phone}',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(g.hr());

    bytes.addAll(g.text('Nota: ${m.noInvoice}',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    if ((m.createdAtLabel ?? '').isNotEmpty) {
      bytes.addAll(g.text(m.createdAtLabel!,
          styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(g.text('Pelanggan: ${m.customerName}'));
    if ((m.whatsapp ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text('WA: ${m.whatsapp}'));
    }
    if ((m.method ?? '').trim().isNotEmpty) {
      bytes.addAll(g.text('Bayar: ${m.method}'));
    }
    final board = m.boardStatus == null
        ? ''
        : ' · ${InvoiceLayout.boardLabel(m.boardStatus!)}';
    bytes.addAll(g.text('${m.status}$board'));
    bytes.addAll(g.hr());

    String? lastGroup;
    for (final line in doc.lines) {
      final group = (line.group ?? '').trim();
      if (group.isNotEmpty && group != lastGroup) {
        bytes.addAll(g.text(group.toUpperCase(),
            styles: const PosStyles(bold: true)));
        lastGroup = group;
      }
      bytes.addAll(g.text(line.label));
      bytes.addAll(g.text(line.amount,
          styles: const PosStyles(align: PosAlign.right)));
    }

    if (doc.hasLensa && doc.detailResep.trim().isNotEmpty) {
      bytes.addAll(g.hr());
      bytes.addAll(g.text('RESEP', styles: const PosStyles(bold: true)));
      bytes.addAll(g.text(doc.detailResep.replaceAll(' | ', '\n')));
    }

    bytes.addAll(g.hr());
    bytes.addAll(g.text('TOTAL ${doc.totalFormatted}',
        styles: const PosStyles(bold: true)));
    bytes.addAll(g.text('${doc.paidLabel} ${doc.paidFormatted}'));
    bytes.addAll(g.text('SISA ${doc.remainingFormatted}'));
    bytes.addAll(g.hr());

    for (final part in doc.footerTextPdf.split('\n')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      bytes.addAll(g.text(t,
          styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }
}
