import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/bootstrap.dart';
import '../../shared/qr/hardware_barcode_listener.dart';
import '../../shared/theme.dart';
import 'dashboard_page.dart';
import 'login_page.dart';

/// Role yang boleh masuk Admin (pusat / cabang). Bukan karyawan lapangan.
const _adminRoles = {
  'owner',
  'admin_pusat',
  'admin_toko',
  'super_admin',
};

/// Admin shell: back-office + POS.
/// Pusat vs cabang ditentukan akun login (`role` + `toko_id` di profiles).
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optik B. Riski — Admin',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildAdminTheme(),
      builder: (context, child) => GlobalHardwareBarcodeShell(
        navigatorKey: navigatorKey,
        child: child,
      ),
      home: const AdminAuthWrapper(),
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
      setState(() {
        _session = null;
        _profile = null;
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

      setState(() {
        _session = session;
        _profile = Map<String, dynamic>.from(row);
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
      });
    }
  }

  void _onLoggedIn(Map<String, dynamic> profile) {
    setState(() {
      _session = supabase.auth.currentSession;
      _profile = profile;
      _booting = false;
      _bannerError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    if (_session == null || _profile == null) {
      return LoginPage(
        bannerError: _bannerError,
        onLoggedIn: _onLoggedIn,
      );
    }

    return DashboardPage(profile: _profile!);
  }
}
