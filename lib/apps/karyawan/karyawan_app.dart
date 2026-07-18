import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import 'login_karyawan_page.dart';

/// Karyawan shell: jobdesk / literatur per individu.
class KaryawanApp extends StatelessWidget {
  const KaryawanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optik B. Riski — Karyawan',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildKaryawanTheme(),
      home: const LoginKaryawanPage(),
    );
  }
}
