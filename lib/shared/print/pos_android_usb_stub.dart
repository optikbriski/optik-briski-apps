/// Stub: USB OTG thermal hanya di Android.
class PosAndroidUsbPrint {
  PosAndroidUsbPrint._();

  static Future<List<({int vid, int pid, String label})>> listDevices() async =>
      const [];

  static Future<void> printRaw({
    required List<int> bytes,
    int? vendorId,
    int? productId,
  }) async {
    throw 'USB OTG thermal hanya tersedia di APK Android.';
  }
}
