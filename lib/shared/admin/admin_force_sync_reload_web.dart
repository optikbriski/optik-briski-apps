// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Hard-reload shell Admin di browser (sesi/modul sudah di-refresh dulu).
void reloadAdminPageImpl() {
  html.window.location.reload();
}
