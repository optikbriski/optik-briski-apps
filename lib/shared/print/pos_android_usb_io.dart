import 'dart:io';
import 'dart:typed_data';

import 'package:another_flutter_usb_write/another_flutter_usb_write.dart';
import 'package:flutter/services.dart';

/// Cetak ESC/POS raw ke printer USB lewat OTG/hub (Android host).
class PosAndroidUsbPrint {
  PosAndroidUsbPrint._();

  static final FlutterUsbWrite _usb = FlutterUsbWrite();

  /// POS-80 / thermal umum — dipakai jika scan USB kosong tapi printer ada.
  static const _fallbackPrinters = <({int vid, int pid})>[
    (vid: 1048, pid: 20497),
    (vid: 1046, pid: 20497),
    (vid: 1046, pid: 43707),
    (vid: 1155, pid: 22336),
    (vid: 1155, pid: 22337),
  ];

  static Future<bool> hasUsbHost() async {
    if (!Platform.isAndroid) return false;
    return _usb.hasUsbHost();
  }

  static Future<List<({int vid, int pid, String label})>> listDevices() async {
    if (!Platform.isAndroid) return const [];
    try {
      final devices = await _usb.listDevices();
      return [
        for (final d in devices)
          if (d.vid != null && d.pid != null)
            (
              vid: d.vid!,
              pid: d.pid!,
              label: _deviceLabel(d),
            ),
      ];
    } on ListDevicesException catch (e) {
      throw e.message?.trim().isNotEmpty == true
          ? e.message!
          : 'Gagal scan perangkat USB OTG.';
    } on PlatformException catch (e) {
      throw e.message?.trim().isNotEmpty == true
          ? e.message!
          : 'Gagal scan perangkat USB OTG.';
    }
  }

  static String _deviceLabel(UsbDevice d) {
    final parts = <String>[];
    if ((d.productName ?? '').trim().isNotEmpty) {
      parts.add(d.productName!.trim());
    }
    if ((d.manufacturerName ?? '').trim().isNotEmpty) {
      parts.add(d.manufacturerName!.trim());
    }
    if (parts.isEmpty) {
      parts.add('USB ${d.vid!.toRadixString(16)}:${d.pid!.toRadixString(16)}');
    }
    parts.add('VID ${d.vid} / PID ${d.pid}');
    return parts.join(' · ');
  }

  /// Buka USB, kirim bytes ESC/POS, tutup. Meminta izin USB jika perlu.
  static Future<void> printRaw({
    required List<int> bytes,
    int? vendorId,
    int? productId,
  }) async {
    if (!Platform.isAndroid) {
      throw 'USB OTG thermal hanya tersedia di APK Android.';
    }
    if (bytes.isEmpty) throw 'Data cetak kosong.';

    final hostOk = await hasUsbHost();
    if (!hostOk) {
      throw 'Tablet/HP ini tidak mendukung USB OTG (host).\n'
          'Coba tablet lain atau printer Bluetooth (tombol BT).';
    }

    final resolved = await _resolveVidPid(
      vendorId: vendorId,
      productId: productId,
    );

    try {
      await _usb.open(vendorId: resolved.vid, productId: resolved.pid);
      const chunk = 512;
      final data = Uint8List.fromList(bytes);
      for (var i = 0; i < data.length; i += chunk) {
        final end = (i + chunk < data.length) ? i + chunk : data.length;
        final ok = await _usb.write(Uint8List.sublistView(data, i, end));
        if (ok != true) {
          throw 'Gagal kirim data ke printer USB (offset $i).';
        }
      }
    } on PermissionException {
      throw 'Izin USB ditolak. Izinkan akses printer saat dialog muncul.';
    } on DeviceNotFoundException {
      throw 'Printer USB tidak ditemukan.\n'
          'Pastikan OTG/hub + printer menyala, cabut-colok, lalu tap Cetak Termal lagi.\n'
          'Saat dialog USB muncul → pilih OK / Izinkan.';
    } on InterfaceNotFoundException {
      throw 'Printer USB tidak punya interface yang didukung.';
    } on EndpointNotFoundException {
      throw 'Printer USB tidak punya endpoint bulk OUT (bukan ESC/POS?).';
    } on PlatformException catch (e) {
      throw e.message?.trim().isNotEmpty == true
          ? e.message!
          : 'Gagal cetak USB OTG.';
    } finally {
      try {
        await _usb.close();
      } catch (_) {}
    }
  }

  static Future<({int vid, int pid})> _resolveVidPid({
    int? vendorId,
    int? productId,
  }) async {
    var vid = vendorId;
    var pid = productId;
    if (vid != null && pid != null) {
      return (vid: vid, pid: pid);
    }

    final devices = await listDevices();
    if (devices.isNotEmpty) {
      ({int vid, int pid, String label}) preferred = devices.first;
      for (final d in devices) {
        final l = d.label.toLowerCase();
        if (l.contains('pos') ||
            l.contains('printer') ||
            (d.vid == 1048 && d.pid == 20497) ||
            (d.vid == 1046 && d.pid == 20497)) {
          preferred = d;
          break;
        }
      }
      return (vid: preferred.vid, pid: preferred.pid);
    }

    // Scan kosong — coba buka langsung (memicu dialog izin USB di Android 12+).
    for (final fb in _fallbackPrinters) {
      try {
        await _usb.open(vendorId: fb.vid, productId: fb.pid);
        await _usb.close();
        return (vid: fb.vid, pid: fb.pid);
      } on PermissionException {
        rethrow;
      } on DeviceNotFoundException {
        continue;
      }
    }

    throw 'Printer USB belum terdeteksi.\n'
        '1) OTG/hub tersambung ke tablet\n'
        '2) Printer POS-80 menyala\n'
        '3) Cabut-colok kabel USB\n'
        '4) Tap Cetak Termal → izinkan dialog USB\n'
        '5) Jika tetap gagal, pakai tombol BT (Bluetooth).';
  }
}
