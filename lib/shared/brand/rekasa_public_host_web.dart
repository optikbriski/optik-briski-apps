// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'rekasa_public_host.dart';

export 'rekasa_public_host.dart';

void redirectRekasaPublicHostIfNeeded() {
  final loc = html.window.location;
  if (!isRekasaPublicHost(loc.hostname)) return;
  if (!shouldRedirectRekasaPublicPath(loc.pathname)) return;
  loc.replace('/perusahaan/');
}
