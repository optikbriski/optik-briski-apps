import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/qr/hardware_barcode_listener.dart';
import '../../shared/theme.dart';
import 'login_karyawan_page.dart';

/// Karyawan shell: jobdesk / literatur per individu.
class KaryawanApp extends StatelessWidget {
  const KaryawanApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optik B. Riski — Karyawan',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildKaryawanTheme(),
      builder: (context, child) => GlobalHardwareBarcodeShell(
        navigatorKey: navigatorKey,
        child: child,
      ),
      home: const LoginKaryawanPage(),
    );
  }
}
