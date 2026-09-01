import 'dart:io';
import 'dart:typed_data';

import 'package:another_flutter_usb_write/another_flutter_usb_write.dart';
import 'package:flutter/services.dart';

import 'pos_usb_device_pick.dart';

export 'pos_usb_device_pick.dart' show PosUsbDevicePick;

/// Satu baris perangkat USB untuk UI / picker.
typedef PosUsbDeviceRow = PosUsbPickRow;

/// Cetak ESC/POS raw ke printer USB lewat OTG/hub (Android host).
class PosAndroidUsbPrint {
  PosAndroidUsbPrint._();

  static final FlutterUsbWrite _usb = FlutterUsbWrite();

  static Future<bool> hasUsbHost() async {
    if (!Platform.isAndroid) return false;
    return _usb.hasUsbHost();
  }

  static Future<List<PosUsbDeviceRow>> listDevices() async {
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
              deviceClass: d.deviceClass,
              hasPermission: d.hasPermission,
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
    if (d.deviceClass == PosUsbDevicePick.usbClassHub) {
      parts.add('USB Hub');
    } else if (d.deviceClass == PosUsbDevicePick.usbClassPrinter) {
      parts.add('Printer');
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
      if (vendorId != null && productId != null) {
        await _tryFallbackOpen(bytes);
        return;
      }
      throw 'Printer USB tidak ditemukan.\n'
          'Pastikan OTG/hub + printer menyala, cabut-colok, lalu tap Cetak Termal lagi.\n'
          'Saat dialog USB muncul → pilih OK / Izinkan.';
    } on InterfaceNotFoundException {
      if (vendorId != null && productId != null) {
        await _tryFallbackOpen(bytes);
        return;
      }
      throw 'Printer USB tidak punya interface yang didukung.';
    } on EndpointNotFoundException {
      if (vendorId != null && productId != null) {
        await _tryFallbackOpen(bytes);
        return;
      }
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
    if (vendorId != null && productId != null) {
      return (vid: vendorId, pid: productId);
    }

    final devices = await listDevices();
    if (devices.isNotEmpty) {
      final picked = PosUsbDevicePick.pickPreferred(
        devices: devices,
        savedVid: null,
        savedPid: null,
      );
      if (picked != null) return picked;
    }

    // Scan kosong — coba buka langsung (memicu dialog izin USB di Android 12+).
    for (final fb in PosUsbDevicePick.knownPosPrinters) {
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

  static Future<void> _tryFallbackOpen(List<int> bytes) async {
    for (final fb in PosUsbDevicePick.knownPosPrinters) {
      try {
        await _usb.open(vendorId: fb.vid, productId: fb.pid);
        const chunk = 512;
        final data = Uint8List.fromList(bytes);
        for (var i = 0; i < data.length; i += chunk) {
          final end = (i + chunk < data.length) ? i + chunk : data.length;
          final ok = await _usb.write(Uint8List.sublistView(data, i, end));
          if (ok != true) {
            throw 'Gagal kirim data ke printer USB (offset $i).';
          }
        }
        return;
      } on PermissionException {
        rethrow;
      } on DeviceNotFoundException {
        continue;
      } on InterfaceNotFoundException {
        continue;
      } on EndpointNotFoundException {
        continue;
      }
    }
    throw DeviceNotFoundException(
      'DEVICE_NOT_FOUND_ERROR',
      'No such device',
      null,
    );
  }
}
