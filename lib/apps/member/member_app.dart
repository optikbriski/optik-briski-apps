import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import 'home_member_page.dart';
import 'login_member_page.dart';

/// Member shell: pelanggan (poin, riwayat, promo) — skeleton awal.
class MemberApp extends StatelessWidget {
  const MemberApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optik B. Riski — Member',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildMemberTheme(),
      home: const LoginMemberPage(),
      routes: {
        '/home': (_) => const HomeMemberPage(),
      },
    );
  }
}
