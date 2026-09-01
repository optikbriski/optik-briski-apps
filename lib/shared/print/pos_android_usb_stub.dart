import 'pos_usb_device_pick.dart';

/// Stub: USB OTG thermal hanya di Android.
class PosAndroidUsbPrint {
  PosAndroidUsbPrint._();

  static Future<bool> hasUsbHost() async => false;

  static Future<List<PosUsbPickRow>> listDevices() async => const [];

  static Future<({int vid, int pid})> printRaw({
    required List<int> bytes,
    int? vendorId,
    int? productId,
  }) async {
    throw 'USB OTG thermal hanya tersedia di APK Android.';
  }
}
