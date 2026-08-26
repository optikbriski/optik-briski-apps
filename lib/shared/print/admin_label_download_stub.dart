import 'dart:typed_data';

/// Unduh bytes sebagai file di browser.
void downloadBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  throw UnsupportedError('downloadBytes hanya di web');
}
