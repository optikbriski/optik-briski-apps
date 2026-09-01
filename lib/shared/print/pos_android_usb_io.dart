import 'dart:io';
import 'dart:typed_data';

import 'package:another_flutter_usb_write/another_flutter_usb_write.dart';
import 'package:flutter/services.dart';

/// Cetak ESC/POS raw ke printer USB lewat OTG/hub (Android host).
class PosAndroidUsbPrint {
  PosAndroidUsbPrint._();

  static final FlutterUsbWrite _usb = FlutterUsbWrite();

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
              label: [
                if ((d.productName ?? '').trim().isNotEmpty) d.productName!.trim(),
                if ((d.manufacturerName ?? '').trim().isNotEmpty)
                  d.manufacturerName!.trim(),
                'VID ${d.vid} / PID ${d.pid}',
              ].join(' · '),
            ),
      ];
    } on ListDevicesException {
      rethrow;
    } on PlatformException {
      return const [];
    }
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

    var vid = vendorId;
    var pid = productId;
    if (vid == null || pid == null) {
      final devices = await listDevices();
      if (devices.isEmpty) {
        throw 'Printer USB belum terdeteksi.\n'
            'Pastikan OTG/hub tersambung, printer menyala, lalu cabut-colok sekali.';
      }
      // Prefer nama POS-80 / printer class umum.
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
      vid = preferred.vid;
      pid = preferred.pid;
    }

    try {
      await _usb.open(vendorId: vid, productId: pid);
      // Chunk agar bulk transfer stabil di printer murah / hub.
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
      throw 'Printer USB tidak ditemukan. Cek OTG/hub dan cabut-colok.';
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
}
