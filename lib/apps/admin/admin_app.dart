import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/admin/admin_code_login_service.dart';
import '../../shared/bootstrap.dart';
import '../../shared/qr/hardware_barcode_listener.dart';
import '../../shared/theme.dart';
import '../../shared/training/training_banner.dart';
import '../../shared/training/training_mode.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import '../../shared/brand/brand_chrome.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/tenant/tenant_modules.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import '../../shared/widgets/tenant_suspended_page.dart';

/// Role yang boleh masuk Admin (pusat / cabang). Bukan karyawan lapangan.
const _adminRoles = {
  'owner',
  'admin_pusat',
  'admin_toko',
  'super_admin',
  'platform',
};

/// Admin shell: back-office + POS.
/// Pusat vs cabang ditentukan akun login (`role` + `toko_id` di profiles).
/// Training Mode uses the same dashboard/menus — banner is the only UI delta.
class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  @override
  void initState() {
    super.initState();
    // Wipe orphan training dirs / crash-recovery flags before any UI write path.
    TrainingMode.instance.recoverOnLaunch();
  }

  Future<void> _onExitTraining() async {
    final navCtx = AdminApp.navigatorKey.currentContext ?? context;
    final ok = await TrainingModeDialogs.confirmExit(navCtx);
    if (!ok) return;
    await TrainingMode.instance.exit();
    final messengerCtx = AdminApp.navigatorKey.currentContext;
    if (messengerCtx != null && messengerCtx.mounted) {
      ScaffoldMessenger.of(messengerCtx).showSnackBar(
        SnackBar(
          content: Text('training_msg_exited'.tr()),
          backgroundColor: OptikAdminTokens.panel,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: BrandChrome.windowTitle,
      onGenerateTitle: (_) => BrandChrome.windowTitle,
      debugShowCheckedModeBanner: false,
      navigatorKey: AdminApp.navigatorKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildAdminTheme(),
      builder: (context, child) => GlobalHardwareBarcodeShell(
        navigatorKey: AdminApp.navigatorKey,
        child: Column(
          children: [
            TrainingBanner(onExitRequested: _onExitTraining),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
      home: () {
        if (kIsWeb) {
          final token = TenantBilling.tokenFromUri(Uri.base);
          if (token != null) {
            return TenantContractSignPage(token: token);
          }
        }
        return const AdminAuthWrapper();
      }(),
    );
  }
}

class AdminAuthWrapper extends StatefulWidget {
  const AdminAuthWrapper({super.key});

  @override
  State<AdminAuthWrapper> createState() => _AdminAuthWrapperState();
}

class _AdminAuthWrapperState extends State<AdminAuthWrapper> {
  StreamSubscription<AuthState>? _authSub;
  Session? _session;
  Map<String, dynamic>? _profile;
  TenantAccessSnapshot? _access;
  bool _booting = true;
  String? _bannerError;

  @override
  void initState() {
    super.initState();
    _session = supabase.auth.currentSession;
    _authSub = supabase.auth.onAuthStateChange.listen(_onAuthChanged);
    _resolveProfileFromSession();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _onAuthChanged(AuthState data) {
    if (!mounted) return;

    // Login sukses diurus LoginPage.onLoggedIn (hindari race dengan upsert profiles).
    if (data.event == AuthChangeEvent.signedIn) {
      return;
    }

    if (data.event == AuthChangeEvent.signedOut) {
      unawaited(AdminCodeLoginService.clearActor());
      setState(() {
        _session = null;
        _profile = null;
        _access = null;
        _booting = false;
      });
      return;
    }

    // Cold start / refresh token: pulihkan sesi admin dari tabel profiles.
    if (data.event == AuthChangeEvent.initialSession ||
        data.event == AuthChangeEvent.tokenRefreshed) {
      setState(() {
        _session = data.session;
        if (data.session == null) {
          _profile = null;
          _access = null;
          _booting = false;
        } else {
          _booting = true;
        }
      });
      if (data.session != null) {
        _resolveProfileFromSession();
      }
    }
  }

  Future<void> _resolveProfileFromSession() async {
    final session = _session ?? supabase.auth.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _profile = null;
        _access = null;
        _booting = false;
      });
      return;
    }

    try {
      final row = await supabase
          .from('profiles')
          .select()
          .eq('id', session.user.id)
          .maybeSingle();

      if (!mounted) return;

      if (row == null) {
        await supabase.auth.signOut();
        if (!mounted) return;
        setState(() {
          _session = null;
          _profile = null;
          _booting = false;
          _bannerError =
              'Sesi tidak valid. Silakan login ulang dengan akun Admin.';
        });
        return;
      }

      final role = (row['role'] ?? '').toString().toLowerCase();
      if (!_adminRoles.contains(role)) {
        await supabase.auth.signOut();
        if (!mounted) return;
        setState(() {
          _session = null;
          _profile = null;
          _booting = false;
          _bannerError =
              'Akses ditolak: akun Karyawan tidak bisa masuk Admin. Pakai APK Karyawan.';
        });
        return;
      }

      final merged = Map<String, dynamic>.from(row);
      final actor = await AdminCodeLoginService.loadActor();
      if (actor != null && actor.isPresent) {
        merged['login_via_karyawan_id'] = actor.karyawanId;
        merged['login_via_karyawan_nama'] = actor.nama;
        merged['login_via_karyawan_toko'] = actor.tokoId;
        merged['login_via_karyawan_jabatan'] = actor.jabatan;
        merged['login_via_audit_id'] = actor.auditId;
      }

      await TenantService.instance.bindFromProfile(merged);
      await BrandService.load();
      await TenantModules.instance.load();
      final access = await TenantAccess.load();

      setState(() {
        _session = session;
        _profile = merged;
        _access = access;
        _booting = false;
        _bannerError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _bannerError = 'Gagal memuat profil admin: $e';
        _session = null;
        _profile = null;
        _access = null;
      });
    }
  }

  void _onLoggedIn(Map<String, dynamic> profile) {
    setState(() {
      _session = supabase.auth.currentSession;
      _profile = profile;
      _access = null;
      _booting = true;
      _bannerError = null;
    });
    _resolveProfileFromSession();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const PremiumScaffold(
        body: Center(
          child: CircularProgressIndicator(color: OptikAdminTokens.ice),
        ),
      );
    }

    if (_session == null || _profile == null) {
      return LoginPage(
        bannerError: _bannerError,
        onLoggedIn: _onLoggedIn,
      );
    }

    final access = _access;
    if (access != null && !access.ok && !access.platform) {
      return TenantSuspendedPage(
        access: access,
        onSignOut: () => unawaited(signOutQuiet()),
      );
    }

    return DashboardPage(profile: _profile!);
  }
}
