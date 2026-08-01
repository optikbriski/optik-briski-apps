import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/member/member_session.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/theme.dart';
import 'login_member_page.dart';
import 'member_shell.dart';
import 'member_update_coordinator.dart';

class MemberApp extends StatefulWidget {
  const MemberApp({super.key});

  @override
  State<MemberApp> createState() => _MemberAppState();
}

class _MemberAppState extends State<MemberApp> {
  bool _ready = false;
  final _navKey = GlobalKey<NavigatorState>();
  final _update = MemberUpdateCoordinator();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await MemberSession.instance.load();
    if (MemberSession.instance.isLoggedIn) {
      await MemberStatusWatch.instance.start();
    }
    if (mounted) setState(() => _ready = true);
    // Cek update juga dari layar login (belum login) — jangan lewatkan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _navKey.currentContext;
      if (ctx != null) _update.checkSilent(ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Optik B. Riski — Member',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildMemberTheme(),
      home: !_ready
          ? const Scaffold(
              backgroundColor: OptikMemberTokens.canvas,
              body: Center(child: CircularProgressIndicator()),
            )
          : (MemberSession.instance.isLoggedIn
              ? const MemberShell()
              : const LoginMemberPage()),
      routes: {
        '/home': (_) => const MemberShell(),
        '/login': (_) => const LoginMemberPage(),
      },
    );
  }
}
