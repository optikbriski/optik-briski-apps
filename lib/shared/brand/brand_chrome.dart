import 'package:flutter/services.dart';

import '../config.dart';
import 'brand_service.dart';
import 'brand_title_stub.dart'
    if (dart.library.html) 'brand_title_web.dart';

/// Judul jendela / tab / recent-apps. Bukan label ikon di home screen.
///
/// Label ikon: Admin = Rekasa. Member & Karyawan APK = merek toko.
class BrandChrome {
  BrandChrome._();

  /// `Admin` / `Member` / `Karyawan`.
  static String roleSuffix = '';

  static bool _attached = false;

  static String get windowTitle {
    final n = BrandService.name.trim();
    if (n.isEmpty) return roleSuffix.isEmpty ? 'POS' : 'POS — $roleSuffix';
    if (roleSuffix.isEmpty) return n;
    return '$n — $roleSuffix';
  }

  static String roleForFlavor(AppFlavor flavor) {
    switch (flavor) {
      case AppFlavor.admin:
        return 'Admin';
      case AppFlavor.member:
        return 'Member';
      case AppFlavor.karyawan:
        return 'Karyawan';
    }
  }

  static void attach({AppFlavor? flavor}) {
    roleSuffix = roleForFlavor(flavor ?? currentFlavor);
    if (!_attached) {
      _attached = true;
      BrandService.revision.addListener(sync);
    }
    sync();
  }

  static void sync() {
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: windowTitle,
        primaryColor: 0xFF0B3D8C,
      ),
    );
    setWebDocumentTitle(windowTitle);
  }
}
