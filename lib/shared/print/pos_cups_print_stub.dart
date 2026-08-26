/// Stub non-IO (web): USB/CUPS thermal tidak tersedia.
class PosCupsPrint {
  PosCupsPrint._();

  static Future<List<String>> listQueues() async => const [];

  static Future<String?> findUsbUri({String nameHint = 'POS-80'}) async => null;

  static Future<String?> ensureQueue({
    String queue = 'POS-80',
    String nameHint = 'POS-80',
  }) async =>
      null;

  static Future<void> printRaw({
    required String queue,
    required List<int> bytes,
    String jobTitle = 'nota',
  }) async {
    throw 'Cetak USB thermal hanya di app desktop/macOS, bukan web.';
  }
}
