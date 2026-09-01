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
import 'print/pos_android_usb_stub.dart'
    if (dart.library.io) 'print/pos_android_usb_io.dart' as android_usb;
import 'print/pos_cups_print_stub.dart'
    if (dart.library.io) 'print/pos_cups_print_io.dart' as cups;
import 'print/pos_usb_device_pick.dart';
import 'theme.dart';
import 'widgets/admin/admin_picker.dart';

const _prefPrinterMac = 'pos_bt_printer_mac';
const _prefPrinterName = 'pos_bt_printer_name';
const _prefCupsQueue = 'pos_cups_queue';
const _prefAndroidUsbVid = 'pos_android_usb_vid';
const _prefAndroidUsbPid = 'pos_android_usb_pid';

bool get _supportsUsbCups =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

bool get _supportsAndroidUsbOtg =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _supportsBluetoothThermal =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

class PosPrintService {
  /// Picker cetak — opsi menyesuaikan platform (web / Android APK / desktop).
  /// Data nota sama (Adjust Invoice); jalur printer beda per device.
  static Future<void> showPrintOptions(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    final options = <AdminPickerOption<String>>[
      if (_supportsAndroidUsbOtg)
        const AdminPickerOption(
          value: 'usb_otg',
          label: 'USB OTG / hub (ESC/POS 80mm)',
          subtitle: 'Poco/tablet + OTG/hub ke POS-80',
          icon: Icons.usb_rounded,
        ),
      if (_supportsBluetoothThermal)
        const AdminPickerOption(
          value: 'bluetooth',
          label: 'Bluetooth thermal (ESC/POS)',
          subtitle: 'APK/HP + printer BT — layout thermal khusus',
          icon: Icons.bluetooth_outlined,
        ),
      if (_supportsUsbCups)
        const AdminPickerOption(
          value: 'usb',
          label: 'USB POS-80 desktop (ESC/POS)',
          subtitle: 'macOS/Linux + kabel USB (CUPS)',
          icon: Icons.cable_rounded,
        ),
      const AdminPickerOption(
        value: 'pdf',
        label: 'Print PDF A5',
        subtitle: 'Nota digital PDF — printer biasa / Save as PDF',
        icon: Icons.print_outlined,
      ),
      const AdminPickerOption(
        value: 'share',
        label: 'Share PDF',
        subtitle: 'Kirim file PDF layout Adjust Invoice',
        icon: Icons.share_outlined,
      ),
    ];

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Pilih cara cetak',
      subtitle: kIsWeb
          ? 'Web: PDF/share. Struk thermal: APK Admin + USB OTG / Bluetooth.'
          : _supportsAndroidUsbOtg
              ? 'APK: USB OTG/hub atau Bluetooth ke printer 80mm.'
              : _supportsUsbCups
                  ? 'Desktop: USB CUPS atau Bluetooth. Jangan PDF ke POS-80.'
                  : 'Pilih cara cetak yang tersedia di perangkat ini.',
      headerIcon: Icons.print_rounded,
      searchable: false,
      selected: null,
      options: options,
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    if (!context.mounted) return;
    switch (sel.value) {
      case 'pdf':
        await printPdf(sale: sale, items: items, formatRupiah: formatRupiah);
      case 'share':
        await sharePdf(sale: sale, items: items, formatRupiah: formatRupiah);
      case 'usb_otg':
        await printAndroidUsbOtg(
          context,
          sale: sale,
          items: items,
          formatRupiah: formatRupiah,
        );
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

  /// Tombol "Cetak Termal" — langsung ke jalur thermal terbaik per platform.
  static Future<void> printThermalDefault(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    if (_supportsAndroidUsbOtg) {
      await printAndroidUsbOtg(
        context,
        sale: sale,
        items: items,
        formatRupiah: formatRupiah,
      );
      return;
    }
    if (_supportsBluetoothThermal && !kIsWeb) {
      await printBluetooth(
        context,
        sale: sale,
        items: items,
        formatRupiah: formatRupiah,
      );
      return;
    }
    await showPrintOptions(
      context,
      sale: sale,
      items: items,
      formatRupiah: formatRupiah,
    );
  }

  /// Pilih VID/PID printer USB — murni (testable), tanpa UI.
  @visibleForTesting
  static ({int vid, int pid})? pickAndroidUsbDevice({
    required List<PosUsbPickRow> devices,
    int? savedVid,
    int? savedPid,
  }) =>
      PosUsbDevicePick.pickPreferred(
        devices: devices,
        savedVid: savedVid,
        savedPid: savedPid,
      );

  /// Butuh dialog picker manual (≥2 device & belum ada preferensi tersimpan).
  @visibleForTesting
  static bool needsAndroidUsbDevicePicker({
    required List<PosUsbPickRow> devices,
    int? savedVid,
    int? savedPid,
  }) =>
      PosUsbDevicePick.needsManualPicker(
        devices: devices,
        savedVid: savedVid,
        savedPid: savedPid,
      );

  /// Cetak ESC/POS lewat USB OTG / hub di Android (Poco, tablet, dll).
  static Future<void> printAndroidUsbOtg(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    if (!_supportsAndroidUsbOtg) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('USB OTG hanya di APK Android.'),
        backgroundColor: OptikAdminTokens.warning,
      ));
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVid = prefs.getInt(_prefAndroidUsbVid);
      final savedPid = prefs.getInt(_prefAndroidUsbPid);

      final devices = await android_usb.PosAndroidUsbPrint.listDevices();
      int? vid = savedVid;
      int? pid = savedPid;

      // Hanya tampilkan printer/hub di picker — hindari pilih hub by default.
      final pickerRows = [
        for (final d in devices)
          if (!PosUsbDevicePick.isLikelyHub(d.deviceClass, d.label) ||
              PosUsbDevicePick.isLikelyPrinter(
                vid: d.vid,
                pid: d.pid,
                label: d.label,
                deviceClass: d.deviceClass,
              ))
            d,
      ];
      final uiDevices = pickerRows.isNotEmpty ? pickerRows : devices;

      if (uiDevices.isNotEmpty) {
        if (!context.mounted) return;
        if (needsAndroidUsbDevicePicker(
          devices: uiDevices,
          savedVid: savedVid,
          savedPid: savedPid,
        )) {
          final sel = await showAdminPicker<String>(
            context: context,
            title: 'Pilih printer USB',
            subtitle: 'Perangkat tersambung lewat OTG / hub',
            headerIcon: Icons.usb_rounded,
            searchable: false,
            selected: null,
            options: [
              for (final d in uiDevices)
                AdminPickerOption(
                  value: '${d.vid}:${d.pid}',
                  label: d.label,
                  subtitle: 'VID ${d.vid} · PID ${d.pid}',
                  icon: Icons.print_outlined,
                ),
            ],
          );
          if (sel == null || sel.isClear || sel.value == null) return;
          final parts = sel.value!.split(':');
          vid = int.tryParse(parts[0]);
          pid = int.tryParse(parts[1]);
        } else {
          final picked = pickAndroidUsbDevice(
            devices: uiDevices,
            savedVid: savedVid,
            savedPid: savedPid,
          );
          if (picked != null) {
            vid = picked.vid;
            pid = picked.pid;
          } else {
            // Hanya hub / tidak bisa auto-pick → pakai fallback di printRaw.
            vid = null;
            pid = null;
          }
        }
      } else if (vid == null || pid == null) {
        // Scan kosong & belum pernah simpan — biarkan printRaw coba fallback + dialog izin.
        vid = null;
        pid = null;
      }

      final doc = await _doc(sale: sale, items: items);
      final bytes = await buildEscPos(doc, paper: PaperSize.mm80);
      await android_usb.PosAndroidUsbPrint.printRaw(
        bytes: bytes,
        vendorId: vid,
        productId: pid,
      );
      if (vid != null && pid != null) {
        await prefs.setInt(_prefAndroidUsbVid, vid);
        await prefs.setInt(_prefAndroidUsbPid, pid);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nota terkirim ke printer USB OTG (ESC/POS 80mm).'),
          backgroundColor: OptikAdminTokens.success,
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      if ('$e'.contains('tidak ditemukan') ||
          '$e'.contains('belum terdeteksi')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefAndroidUsbVid);
        await prefs.remove(_prefAndroidUsbPid);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: OptikAdminTokens.danger,
        action: _supportsBluetoothThermal
            ? SnackBarAction(
                label: 'BT',
                textColor: OptikAdminTokens.snow,
                onPressed: () => printBluetooth(
                  context,
                  sale: sale,
                  items: items,
                  formatRupiah: formatRupiah,
                ),
              )
            : null,
      ));
    }
  }

  /// Cetak ESC/POS ke POS-80 (USB) via antrian CUPS — macOS/Linux desktop saja.
  static Future<void> printUsb(
    BuildContext context, {
    required Map<String, dynamic> sale,
    required List<dynamic> items,
    required String Function(num) formatRupiah,
  }) async {
    if (!_supportsUsbCups) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          kIsWeb
              ? 'USB POS-80 tidak tersedia di web. Pakai APK Admin + Bluetooth.'
              : 'USB POS-80 hanya di desktop macOS/Linux. Di APK pakai Bluetooth thermal.',
        ),
        backgroundColor: OptikAdminTokens.warning,
        action: _supportsBluetoothThermal
            ? SnackBarAction(
                label: 'BT',
                textColor: OptikAdminTokens.snow,
                onPressed: () => printBluetooth(
                  context,
                  sale: sale,
                  items: items,
                  formatRupiah: formatRupiah,
                ),
              )
            : null,
      ));
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // Selalu lewat ensureQueue agar antrian PostScript diganti ESC/POS.
      final queue = await cups.PosCupsPrint.ensureQueue(
        queue: 'POS-80',
        nameHint: 'POS-80',
        recreateIfPostScript: true,
      );
      if (queue == null || queue.isEmpty) {
        throw 'Printer POS-80 belum terdeteksi USB.\n'
            'Cabut-colok kabel, pastikan menyala, lalu coba lagi.\n'
            'Jangan cetak PDF ke POS-80 — akan ngeprint kode tanpa berhenti.';
      }
      await prefs.setString(_prefCupsQueue, queue);
      await cups.PosCupsPrint.cancelAll(queue);

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

  /// Layout thermal khusus (ESC/POS) — info lengkap dari nota,
  /// **tanpa** mengubah layout nota digital UI/PDF.
  static Future<List<int>> buildEscPos(
    InvoiceDocumentModel doc, {
    PaperSize paper = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paper, profile);
    final bytes = <int>[];
    final s = doc.settings;
    final m = doc.meta;
    String a(String? raw) => _escPosAscii(raw ?? '');

    void hr() => bytes.addAll(g.hr(ch: '-'));
    void center(String text, {bool bold = false, PosTextSize? height}) {
      bytes.addAll(g.text(
        a(text),
        styles: PosStyles(
          align: PosAlign.center,
          bold: bold,
          height: height ?? PosTextSize.size1,
        ),
      ));
    }

    void left(String text, {bool bold = false}) {
      bytes.addAll(g.text(
        a(text),
        styles: PosStyles(align: PosAlign.left, bold: bold),
      ));
    }

    void money(String label, String value, {bool bold = false}) {
      bytes.addAll(g.row([
        PosColumn(
          text: a(label),
          width: 7,
          styles: PosStyles(align: PosAlign.left, bold: bold),
        ),
        PosColumn(
          text: a(value),
          width: 5,
          styles: PosStyles(align: PosAlign.right, bold: bold),
        ),
      ]));
    }

    // ----- HEADER TOKO -----
    bytes.addAll(g.reset());
    center(s.shopName.toUpperCase(), bold: true, height: PosTextSize.size2);
    if (s.address.trim().isNotEmpty) center(s.address);
    if (s.phone.trim().isNotEmpty) center('Telp ${s.phone}');
    hr();

    // ----- PELANGGAN (semua field nota digital) -----
    left('PELANGGAN', bold: true);
    left(m.customerName);
    if ((m.whatsapp ?? '').trim().isNotEmpty) left('WA: ${m.whatsapp}');
    if ((m.email ?? '').trim().isNotEmpty) left('Email: ${m.email}');
    if ((m.address ?? '').trim().isNotEmpty) left('Alamat: ${m.address}');
    hr();

    // ----- NOTA / META -----
    left('NOTA', bold: true);
    left(m.noInvoice, bold: true);
    if ((m.createdAtLabel ?? '').isNotEmpty) left(m.createdAtLabel!);
    if ((m.dateLabel ?? '').isNotEmpty) left(m.dateLabel!);
    if ((m.cashier ?? '').trim().isNotEmpty) left('Kasir: ${m.cashier}');
    if ((m.method ?? '').trim().isNotEmpty) left('Bayar: ${m.method}');
    final board = m.boardStatus == null
        ? a(m.status)
        : '${a(m.status)} | ${InvoiceLayout.boardLabel(m.boardStatus!)}';
    left('Status: $board', bold: true);
    hr();

    // ----- RINCIAN ITEM -----
    left('RINCIAN ITEM PESANAN', bold: true);
    String? lastGroup;
    for (final line in doc.lines) {
      final group = (line.group ?? '').trim();
      if (group.isNotEmpty && group != lastGroup) {
        left(group.toUpperCase(), bold: true);
        lastGroup = group;
      }
      money(line.label, line.amount);
    }

    if (doc.hasLensa && doc.detailResep.trim().isNotEmpty) {
      hr();
      left('RESEP', bold: true);
      for (final part in doc.detailResep.split(RegExp(r'\s*\|\s*'))) {
        final line = part.trim();
        if (line.isEmpty) continue;
        left(line);
      }
    }
    hr();

    // ----- TOTAL -----
    money('Total belanja', doc.totalFormatted, bold: true);
    money(doc.paidLabel, doc.paidFormatted);
    money('Sisa piutang', doc.remainingFormatted, bold: true);
    hr();

    // ----- QR -----
    if (doc.showQr && doc.qrPayload.trim().isNotEmpty) {
      center('Scan invoice');
      bytes.addAll(g.qrcode(doc.qrPayload.trim(), size: QRSize.size4));
      bytes.addAll(g.feed(1));
      hr();
    }

    // ----- FOOTER (sama sumber status footer nota) -----
    final footer = (doc.footerTextPdf.trim().isNotEmpty
            ? doc.footerTextPdf
            : doc.footerText)
        .trim();
    for (final part in footer.split('\n')) {
      final line = part.trim();
      if (line.isEmpty) continue;
      center(line);
    }

    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }

  /// ASCII aman untuk printer thermal (hindari · → π).
  static String _escPosAscii(String input) {
    return input
        .replaceAll('·', '|')
        .replaceAll('•', '-')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('×', 'x')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '?');
  }
}
