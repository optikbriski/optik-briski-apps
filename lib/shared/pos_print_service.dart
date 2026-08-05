import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'invoice/invoice_document_builder.dart';
import 'invoice/invoice_layout.dart';
import 'theme.dart';
import 'widgets/admin/admin_picker.dart';

const _prefPrinterMac = 'pos_bt_printer_mac';
const _prefPrinterName = 'pos_bt_printer_name';

class PosPrintService {
  /// Picker Frozen Lake: Print PDF / Share PDF / Bluetooth thermal.
  /// Semua jalur memakai setting Adjust Invoice (kit yang sama).
  static Future<void> showPrintOptions(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cara cetak',
      subtitle: 'PDF sistem, share, atau thermal Bluetooth',
      headerIcon: Icons.print_rounded,
      searchable: false,
      selected: null,
      options: const [
        AdminPickerOption(
          value: 'pdf',
          label: 'Print PDF (sistem)',
          subtitle: 'Layout sama Adjust Invoice (A5)',
          icon: Icons.print_outlined,
        ),
        AdminPickerOption(
          value: 'share',
          label: 'Share PDF',
          subtitle: 'Kirim file PDF layout Adjust Invoice',
          icon: Icons.share_outlined,
        ),
        AdminPickerOption(
          value: 'bluetooth',
          label: 'Bluetooth thermal (ESC/POS)',
          subtitle: 'Isi & footer ikut Adjust Invoice (58mm)',
          icon: Icons.bluetooth_outlined,
        ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    if (!context.mounted) return;
    switch (sel.value) {
      case 'pdf':
        await printPdf(sale: sale, items: items, formatRupiah: formatRupiah);
      case 'share':
        await sharePdf(sale: sale, items: items, formatRupiah: formatRupiah);
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
    await Printing.layoutPdf(onLayout: (_) async => bytes);
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

  static Future<void> printBluetooth(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
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
          throw 'Gagal konek printer Bluetooth. Pakai Print PDF saja.';
        }
      }

      final doc = await _doc(sale: sale, items: items);
      final bytes = await _buildEscPos(doc);
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
          label: 'PDF',
          textColor: OptikAdminTokens.snow,
          onPressed: () => printPdf(
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

  /// Thermal 58mm — teks mengikuti settings + footer status Adjust Invoice.
  static Future<List<int>> _buildEscPos(InvoiceDocumentModel doc) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(PaperSize.mm58, profile);
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
