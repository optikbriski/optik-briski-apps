// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Hostname situs perusahaan (Midtrans). Bukan konsol Admin.
const rekasaPublicHost = 'rekasa-karya-indonesia.vercel.app';

void redirectRekasaPublicHostIfNeeded() {
  final loc = html.window.location;
  if (loc.hostname != rekasaPublicHost) return;
  if (loc.pathname.startsWith('/perusahaan')) return;
  loc.replace('/perusahaan/');
}
