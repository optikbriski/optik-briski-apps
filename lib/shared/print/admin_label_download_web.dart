import 'dart:html' as html;
import 'dart:typed_data';

void downloadBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
