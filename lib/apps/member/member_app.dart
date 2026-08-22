import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../shared/member/member_notification_payload.dart';
import '../../shared/member/member_session.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/theme.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/widgets/tenant_suspended_page.dart';
import 'login_member_page.dart';
import 'member_shell.dart';
import 'member_update_coordinator.dart';
import 'pages/member_invoice_hub_page.dart';
import 'pages/member_online_order_page.dart';
import 'pages/member_orders_list_page.dart';
import '../../shared/brand/brand_chrome.dart';

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
    MemberStatusWatch.instance.onNotificationOpen = _openNotificationPayload;
    _boot();
  }

  @override
  void dispose() {
    if (identical(
      MemberStatusWatch.instance.onNotificationOpen,
      _openNotificationPayload,
    )) {
      MemberStatusWatch.instance.onNotificationOpen = null;
    }
    super.dispose();
  }

  void _openNotificationPayload(String payload) {
    final nav = _navKey.currentState;
    if (nav == null) return;
    final parsed = MemberNotificationPayload.parse(payload);
    if ((parsed.invoice ?? '').isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => MemberInvoiceHubPage(noInvoice: parsed.invoice!),
        ),
      );
      return;
    }
    if ((parsed.onlineOrderId ?? '').isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) =>
              MemberOnlineOrderPage(onlineOrderId: parsed.onlineOrderId!),
        ),
      );
      return;
    }
    // Fallback status-relevant: tab Status (bukan Riwayat penuh).
    nav.push(
      MaterialPageRoute(
        builder: (_) => const MemberOrdersListPage(
          title: 'Status pesanan',
          onlyActive: true,
        ),
      ),
    );
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
    // Jangan listen session di sini: rebuild `home` saat update profil
    // bisa mereset Navigator stack. Login/logout pakai named routes.
    return MaterialApp(
      navigatorKey: _navKey,
      title: BrandChrome.windowTitle,
      onGenerateTitle: (_) => BrandChrome.windowTitle,
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
          : _memberHome(),
      routes: {
        '/home': (_) => _memberHome(loggedIn: true),
        '/login': (_) => const LoginMemberPage(),
      },
    );
  }

  Widget _memberHome({bool? loggedIn}) {
    final reason = TenantService.instance.lastResolveReason;
    if (reason == 'suspend' || reason == 'trial') {
      return TenantSuspendedPage(
        access: TenantAccessSnapshot(
          ok: false,
          reason: reason,
          error: TenantService.instance.lastResolveError,
          displayName: TenantService.instance.displayName,
          slug: TenantService.instance.slug,
        ),
      );
    }
    final inSession = loggedIn ?? MemberSession.instance.isLoggedIn;
    return inSession ? const MemberShell() : const LoginMemberPage();
  }
}
