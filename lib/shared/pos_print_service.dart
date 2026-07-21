import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

const _prefPrinterMac = 'pos_bt_printer_mac';
const _prefPrinterName = 'pos_bt_printer_name';

class PosPrintService {
  /// Bottom sheet: Print PDF / Share PDF / Bluetooth thermal.
  static Future<void> showPrintOptions(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: OptikAdminTokens.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pilih cara cetak',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.print, color: Colors.tealAccent),
              title: const Text('Print PDF (sistem)',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Printer HP / Wi‑Fi / USB via dialog sistem',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                await printPdf(sale: sale, items: items, formatRupiah: formatRupiah);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.lightBlueAccent),
              title: const Text('Share PDF',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await sharePdf(sale: sale, items: items, formatRupiah: formatRupiah);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.bluetooth, color: Colors.orangeAccent),
              title: const Text('Bluetooth thermal (ESC/POS)',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Printer 58mm yang sudah dipasangkan',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                if (!context.mounted) return;
                await printBluetooth(
                  context,
                  sale: sale,
                  items: items,
                  formatRupiah: formatRupiah,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<Uint8List> buildReceiptPdfBytes({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final pdf = pw.Document();
    final invoice = sale['no_invoice']?.toString() ?? '-';
    final nama = sale['nama_pelanggan']?.toString() ?? '-';
    final total = sale['total_harga'] ?? 0;
    final dp = sale['dibayarkan'] ?? 0;
    final sisa = sale['sisa_tagihan'] ?? 0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('OPTIK B. RISKI',
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Nota: $invoice', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Pelanggan: $nama', style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            ...items.map((item) {
              final name = item['nama_produk']?.toString() ?? '-';
              final qty = item['qty'] ?? 1;
              final harga = item['harga_jual'] ?? item['subtotal'] ?? 0;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                        child: pw.Text('$name x$qty',
                            style: const pw.TextStyle(fontSize: 9))),
                    pw.Text(formatRupiah(harga is num ? harga : 0),
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              );
            }),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(formatRupiah(total is num ? total : 0),
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Text('DP: ${formatRupiah(dp is num ? dp : 0)}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Sisa: ${formatRupiah(sisa is num ? sisa : 0)}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text('Terima kasih', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
    return pdf.save();
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
        throw 'Izin Bluetooth belum diberikan. Aktifkan di pengaturan HP.';
      }
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) {
        throw 'Bluetooth mati. Nyalakan Bluetooth dulu.';
      }

      final prefs = await SharedPreferences.getInstance();
      var mac = prefs.getString(_prefPrinterMac);

      if (mac == null || mac.isEmpty) {
        if (!context.mounted) return;
        mac = await _pickPairedPrinter(context);
        if (mac == null) return;
      }

      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (!connected) {
        // Coba pilih ulang
        if (!context.mounted) return;
        final retry = await _pickPairedPrinter(context);
        if (retry == null) {
          throw 'Gagal konek printer. Coba Print PDF sebagai cadangan.';
        }
        mac = retry;
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
        if (!ok) {
          throw 'Gagal konek printer Bluetooth. Pakai Print PDF saja.';
        }
      }

      final bytes = await _buildEscPos(
          sale: sale, items: items, formatRupiah: formatRupiah);
      final result = await PrintBluetoothThermal.writeBytes(bytes);
      if (!result) {
        throw 'Gagal mengirim data ke printer.';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nota thermal terkirim ke printer.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.redAccent,
            action: SnackBarAction(
              label: 'PDF',
              textColor: Colors.white,
              onPressed: () => printPdf(
                  sale: sale, items: items, formatRupiah: formatRupiah),
            ),
          ),
        );
      }
    }
  }

  static Future<String?> _pickPairedPrinter(BuildContext context) async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    if (devices.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Tidak ada printer terpasang. Pair dulu di Settings Bluetooth HP.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    if (!context.mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: OptikAdminTokens.card,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Pilih printer Bluetooth',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          ...devices.map(
            (d) => ListTile(
              title: Text(d.name, style: const TextStyle(color: Colors.white)),
              subtitle:
                  Text(d.macAdress, style: const TextStyle(color: Colors.white54)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_prefPrinterMac, d.macAdress);
                await prefs.setString(_prefPrinterName, d.name);
                if (ctx.mounted) Navigator.pop(ctx, d.macAdress);
              },
            ),
          ),
        ],
      ),
    );
  }

  static Future<List<int>> _buildEscPos({
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];

    bytes.addAll(g.reset());
    bytes.addAll(g.text('OPTIK B. RISKI',
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(g.text('Nota: ${sale['no_invoice'] ?? '-'}',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(g.text('Pelanggan: ${sale['nama_pelanggan'] ?? '-'}'));
    bytes.addAll(g.hr());

    for (final item in items) {
      final name = item['nama_produk']?.toString() ?? '-';
      final qty = item['qty'] ?? 1;
      final harga = item['harga_jual'] ?? item['subtotal'] ?? 0;
      bytes.addAll(g.text('$name x$qty'));
      bytes.addAll(g.text(formatRupiah(harga is num ? harga : 0),
          styles: const PosStyles(align: PosAlign.right)));
    }

    bytes.addAll(g.hr());
    final total = sale['total_harga'] ?? 0;
    final dp = sale['dibayarkan'] ?? 0;
    final sisa = sale['sisa_tagihan'] ?? 0;
    bytes.addAll(g.text('TOTAL ${formatRupiah(total is num ? total : 0)}',
        styles: const PosStyles(bold: true)));
    bytes.addAll(g.text('DP ${formatRupiah(dp is num ? dp : 0)}'));
    bytes.addAll(g.text('SISA ${formatRupiah(sisa is num ? sisa : 0)}'));
    bytes.addAll(g.feed(2));
    bytes.addAll(g.text('Terima kasih',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(g.cut());
    return bytes;
  }
}
