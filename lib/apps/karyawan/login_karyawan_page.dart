// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/app_loading_overlay.dart';
import '../../shared/widgets/optik_brand_logo.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/config.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/tenant/tenant_modules.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/widgets/tenant_suspended_page.dart';
import '../owner/owner_service.dart';
import '../owner/owner_session.dart';
import '../owner/owner_shell.dart';
import 'forgot_password_karyawan_page.dart';
import 'main_karyawan.dart';
import 'register_karyawan_page.dart';

class LoginKaryawanPage extends StatefulWidget {
  const LoginKaryawanPage({super.key});

  @override
  State<LoginKaryawanPage> createState() => _LoginKaryawanPageState();
}

class _LoginKaryawanPageState extends State<LoginKaryawanPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _slugCtrl = TextEditingController(text: TenantService.instance.slug);
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _slugFocus = FocusNode();

  bool _isObscure = true;
  bool _isLoading = false;

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _kSavedEmail = 'saved_email';
  static const _kSavedPassword = 'saved_password';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _bootstrapExistingSession();
      if (!mounted) return;
      // Hanya tawarkan biometrik jika belum ada sesi aktif.
      if (Supabase.instance.client.auth.currentSession == null) {
        await _cekBiometrikOtomatis();
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _slugCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _slugFocus.dispose();
    super.dispose();
  }

  String get _normalizedEmail => _emailCtrl.text.trim().toLowerCase();

  void _snack(String message, {Color? color, Duration? duration}) {
    if (!mounted) return;
    final bg = color ?? OptikKaryawanTokens.ink;
    // Cyan / pastel → ink text; gelap/merah/oranye → teks putih.
    final onBg = (bg == OptikKaryawanTokens.cyan ||
            bg == OptikKaryawanTokens.seasideMid ||
            bg == OptikKaryawanTokens.pale)
        ? OptikKaryawanTokens.ink
        : OptikKaryawanTokens.snow;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: onBg,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _bootstrapExistingSession() async {
    if (_isLoading) return;
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    if (session == null || user == null) return;

    setState(() => _isLoading = true);
    try {
      final email = (user.email ?? '').trim().toLowerCase();
      if (email.isEmpty) {
        await Supabase.instance.client.auth.signOut();
        return;
      }
      final routed = await _routeAfterAuth(userId: user.id, email: email);
      if (!mounted) return;
      if (!routed) return;
    } catch (e) {
      debugPrint('bootstrap session login: $e');
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    } finally {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Owner (profiles.role=owner + owners row) → OwnerShell.
  /// Else karyawan aktif → KaryawanPage.
  /// Returns false if signed out / blocked.
  Future<bool> _routeAfterAuth({
    required String userId,
    required String email,
  }) async {
    Map<String, dynamic>? profileRow;
    try {
      profileRow = await Supabase.instance.client
          .from('profiles')
          .select('id, role, toko_id, email, tenant_id, is_platform')
          .eq('id', userId)
          .maybeSingle();
    } catch (e) {
      debugPrint('profiles lookup: $e');
    }

    final role = (profileRow?['role'] ?? '').toString().toLowerCase();
    if (role == 'owner') {
      try {
        if (!_tenantMatchesLogin(profileRow?['tenant_id']?.toString())) {
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return false;
          _snack('Akun ini bukan staf ${BrandService.name}.', color: Colors.redAccent);
          return false;
        }
        await TenantService.instance.bindFromProfile(profileRow);
        await BrandService.load();
        await TenantModules.instance.load();
        if (await _goSuspendedIfLocked()) return true;
        final ownerProfile = await OwnerService().myProfile();
        OwnerSession.instance.setProfile(ownerProfile);
        if (!mounted) return false;
        _goOwnerHome();
        return true;
      } catch (e) {
        debugPrint('owner profile: $e');
        await Supabase.instance.client.auth.signOut();
        OwnerSession.instance.clear();
        if (!mounted) return false;
        _snack(
          'Akun Owner belum diprovision lengkap. Hubungi Admin Pusat.',
          color: Colors.orange,
          duration: const Duration(seconds: 5),
        );
        return false;
      }
    }

    final ok = await _assertKaryawanAktif(email);
    if (!ok || !mounted) return false;
    if (await _goSuspendedIfLocked()) return true;
    _goHome();
    return true;
  }

  Future<bool> _goSuspendedIfLocked() async {
    final access = await TenantAccess.load();
    if (access.ok || access.platform) return false;
    if (!mounted) return true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TenantSuspendedPage(
          access: access,
          onSignOut: () async {
            await signOutQuiet();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginKaryawanPage()),
              (_) => false,
            );
          },
        ),
      ),
    );
    return true;
  }

  /// Returns `true` if profile exists and status is Aktif.
  /// Signs out and shows snackbar on failure.
  Future<bool> _assertKaryawanAktif(String email) async {
    Map<String, dynamic>? userData;
    try {
      userData = await Supabase.instance.client
          .from('karyawan')
          .select('status_approval, tenant_id, toko_id')
          .ilike('email', email)
          .limit(1)
          .maybeSingle();
    } on PostgrestException catch (e) {
      // Duplikat row / RLS / schema → anggap profil tidak bisa diverifikasi.
      debugPrint('assert karyawan aktif: $e');
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return false;
      _snack("profil_tidak_ditemukan".tr(), color: Colors.redAccent);
      return false;
    }

    if (userData == null) {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return false;
      _snack("profil_tidak_ditemukan".tr(), color: Colors.redAccent);
      return false;
    }

    final status = (userData['status_approval'] ?? '').toString().trim();
    if (status.toLowerCase() != 'aktif') {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return false;
      final ditolak = status.toLowerCase().startsWith('ditolak');
      _snack(
        ditolak
            ? "akun_ditolak".tr()
            : 'Akun menunggu persetujuan Admin Pusat. Belum bisa dipakai.',
        color: ditolak ? Colors.redAccent : Colors.orange,
        duration: const Duration(seconds: 5),
      );
      return false;
    }
    if (!_tenantMatchesLogin(userData['tenant_id']?.toString())) {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return false;
      _snack('Akun ini bukan staf ${BrandService.name}.', color: Colors.redAccent);
      return false;
    }
    await TenantService.instance.bindFromProfile({
      'tenant_id': userData['tenant_id'],
      'toko_id': userData['toko_id'],
    });
    await BrandService.load();
    await TenantModules.instance.load();
    return true;
  }

  Future<void> _persistCredentialsForBiometric({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) return;
    try {
      await _secureStorage.write(key: _kSavedEmail, value: email);
      await _secureStorage.write(key: _kSavedPassword, value: password);
    } catch (e) {
      debugPrint('secure storage write: $e');
    }
  }

  Future<void> _cekBiometrikOtomatis() async {
    if (kIsWeb || _isLoading) return;
    try {
      final emailTersimpan = await _secureStorage.read(key: _kSavedEmail);
      final passwordTersimpan = await _secureStorage.read(key: _kSavedPassword);
      if (emailTersimpan != null &&
          passwordTersimpan != null &&
          emailTersimpan.isNotEmpty &&
          passwordTersimpan.isNotEmpty) {
        await _loginDenganBiometrik(auto: true);
      }
    } catch (e) {
      debugPrint('cek biometrik otomatis: $e');
    }
  }

  Future<void> _loginDenganBiometrik({bool auto = false}) async {
    if (_isLoading) return;

    if (kIsWeb) {
      _snack(
        'Fitur Biometrik hanya tersedia di aplikasi HP (Android/iOS).',
        color: Colors.orange,
      );
      return;
    }

    try {
      final emailTersimpan = await _secureStorage.read(key: _kSavedEmail);
      final passwordTersimpan = await _secureStorage.read(key: _kSavedPassword);

      if (emailTersimpan == null ||
          passwordTersimpan == null ||
          emailTersimpan.isEmpty ||
          passwordTersimpan.isEmpty) {
        if (!auto) {
          _snack(
            'Belum ada akun tersimpan. Silakan masuk manual dulu.',
            color: Colors.orange,
          );
        }
        return;
      }

      final canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (!canAuthenticate) {
        if (!auto) {
          _snack(
            'Perangkat tidak mendukung biometrik.',
            color: Colors.orange,
          );
        }
        return;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason:
            'Pindai sidik jari / wajah Anda untuk masuk otomatis.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!didAuthenticate || !mounted) return;

      _emailCtrl.text = emailTersimpan;
      _passwordCtrl.text = passwordTersimpan;
      await _loginKaryawan();
    } catch (e) {
      debugPrint('Gagal biometrik: $e');
      if (!auto && mounted) {
        _snack(
          'Biometrik gagal. Masuk dengan surel & kata sandi.',
          color: Colors.orange,
        );
      }
    }
  }

  Future<void> _loginKaryawan() async {
    if (_isLoading) return;

    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) {
      // Biometric path fills fields; still validate emptiness.
      if (_normalizedEmail.isEmpty || _passwordCtrl.text.isEmpty) {
        _snack(
          'Surel dan kata sandi wajib diisi.',
          color: Colors.orange,
        );
      }
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = _normalizedEmail;
    final password = _passwordCtrl.text;

    try {
      if (!isBrandedStoreApk) {
        await TenantService.instance.requireResolved(slug: _slugCtrl.text);
        await BrandService.load();
      }
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (res.user == null) {
        throw const AuthException('Login gagal');
      }

      final userEmail =
          (res.user!.email ?? email).trim().toLowerCase();

      await _persistCredentialsForBiometric(
        email: email,
        password: password,
      );

      if (!mounted) return;
      _snack("masuk_berhasil".tr(), color: OptikKaryawanTokens.cyan);

      final routed = await _routeAfterAuth(
        userId: res.user!.id,
        email: userEmail,
      );
      if (!routed || !mounted) return;
    } on StateError catch (e) {
      if (!mounted) return;
      _snack(e.message, color: Colors.orange);
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid') ||
          msg.contains('credentials') ||
          msg.contains('password')) {
        _snack("masuk_gagal".tr(), color: Colors.redAccent);
      } else if (msg.contains('network') || msg.contains('fetch')) {
        _snack(
          'Koneksi gagal. Periksa internet lalu coba lagi.',
          color: Colors.orange,
        );
      } else {
        _snack(
          e.message.isNotEmpty ? e.message : "masuk_gagal".tr(),
          color: Colors.redAccent,
        );
      }
    } catch (e) {
      debugPrint('login karyawan: $e');
      if (!mounted) return;
      _snack("masuk_gagal".tr(), color: Colors.redAccent);
    } finally {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const KaryawanPage()),
    );
  }

  void _goOwnerHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OwnerShell()),
    );
  }

  bool _tenantMatchesLogin(String? tenantId) {
    if (!TenantService.instance.storeMatchesApk(tenantId)) return false;
    if (isBrandedStoreApk) return true;
    final bound = TenantService.instance.id;
    final t = (tenantId ?? '').trim();
    if (bound == null || bound.isEmpty || t.isEmpty) return true;
    return t == bound;
  }

  String? _validateEmail(String? v) {
    final email = (v ?? '').trim().toLowerCase();
    if (email.isEmpty) return 'Surel wajib diisi';
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      return 'Format surel tidak valid';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').isEmpty) return 'Kata sandi wajib diisi';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: OptikKaryawanTokens.authBgGradient,
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      OptikKaryawanTokens.cyan.withOpacity(0.34),
                      OptikKaryawanTokens.cyan.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.pale.withOpacity(0.35),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.42,
            left: -40,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.cyan.withOpacity(0.10),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: AutofillGroup(
                        child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.disabled,
                        child: AbsorbPointer(
                          absorbing: _isLoading,
                          child: Column(
                            children: [
                              const OptikBrandLogo.color(height: 56),
                              const SizedBox(height: 10),
                              Text(
                                BrandService.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: OptikKaryawanTokens.navyMid,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "sub_judul_portal".tr().toUpperCase(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: OptikKaryawanTokens.muted
                                      .withOpacity(0.95),
                                  fontSize: 10.5,
                                  letterSpacing: 2.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: OptikKaryawanTokens.cyan
                                      .withOpacity(0.16),
                                  border: Border.all(
                                    color: OptikKaryawanTokens.cyan
                                        .withOpacity(0.45),
                                  ),
                                ),
                                child: const Text(
                                  'PORTAL KARYAWAN',
                                  style: TextStyle(
                                    color: OptikKaryawanTokens.ink,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    OptikKaryawanTokens.radiusXl),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: 18, sigmaY: 18),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          OptikKaryawanTokens.radiusXl),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          OptikKaryawanTokens.card
                                              .withOpacity(0.97),
                                          OptikKaryawanTokens.bgMid
                                              .withOpacity(0.94),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: OptikKaryawanTokens.cyan
                                            .withOpacity(0.55),
                                        width: 1.1,
                                      ),
                                      boxShadow:
                                          OptikKaryawanTokens.cardShadow,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          22, 22, 22, 20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          15),
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment
                                                        .bottomRight,
                                                    colors: [
                                                      OptikKaryawanTokens
                                                          .cyan
                                                          .withOpacity(0.35),
                                                      OptikKaryawanTokens
                                                          .pale
                                                          .withOpacity(0.55),
                                                    ],
                                                  ),
                                                  border: Border.all(
                                                    color:
                                                        OptikKaryawanTokens
                                                            .cyan
                                                            .withOpacity(
                                                                0.85),
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.badge_rounded,
                                                  color: OptikKaryawanTokens
                                                      .ink,
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                      'EMPLOYEE ACCESS',
                                                      style: TextStyle(
                                                        color:
                                                            OptikKaryawanTokens
                                                                .muted
                                                                .withOpacity(
                                                                    0.95),
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 1.6,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                        height: 4),
                                                    Text(
                                                      "tombol_masuk_label"
                                                          .tr(),
                                                      style: const TextStyle(
                                                        color:
                                                            OptikKaryawanTokens
                                                                .ink,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 22,
                                                        height: 1.15,
                                                        letterSpacing: -0.3,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                        height: 5),
                                                    Text(
                                                      'Masuk dengan akun yang sudah disetujui Pusat',
                                                      style: TextStyle(
                                                        color:
                                                            OptikKaryawanTokens
                                                                .muted
                                                                .withOpacity(
                                                                    0.95),
                                                        fontSize: 12.5,
                                                        height: 1.35,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 22),
                                          if (!isBrandedStoreApk) ...[
                                            _buildField(
                                              controller: _slugCtrl,
                                              focusNode: _slugFocus,
                                              label: 'Kode usaha',
                                              icon: Icons.storefront_outlined,
                                              textInputAction:
                                                  TextInputAction.next,
                                              validator: (v) =>
                                                  (v == null || v.trim().isEmpty)
                                                      ? 'Isi kode usaha'
                                                      : null,
                                              onFieldSubmitted: (_) =>
                                                  _emailFocus.requestFocus(),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          _buildField(
                                            controller: _emailCtrl,
                                            focusNode: _emailFocus,
                                            label: "isian_surel".tr(),
                                            icon: Icons.mail_outline_rounded,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            textInputAction:
                                                TextInputAction.next,
                                            autofillHints: const [
                                              AutofillHints.email,
                                              AutofillHints.username,
                                            ],
                                            validator: _validateEmail,
                                            onFieldSubmitted: (_) =>
                                                _passwordFocus
                                                    .requestFocus(),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildField(
                                            controller: _passwordCtrl,
                                            focusNode: _passwordFocus,
                                            label: "isian_kata_sandi".tr(),
                                            icon:
                                                Icons.lock_outline_rounded,
                                            isPassword: true,
                                            textInputAction:
                                                TextInputAction.done,
                                            autofillHints: const [
                                              AutofillHints.password,
                                            ],
                                            validator: _validatePassword,
                                            onFieldSubmitted: (_) =>
                                                _loginKaryawan(),
                                          ),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              ForgotPasswordKaryawanPage(
                                                            initialEmail:
                                                                _normalizedEmail,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                              child: Text(
                                                'lupa_pw_tautan'.tr(),
                                                style: TextStyle(
                                                  color: OptikKaryawanTokens
                                                      .cyan
                                                      .withOpacity(0.95),
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            height: 54,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        14),
                                                gradient:
                                                    OptikKaryawanTokens
                                                        .accentGradient,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color:
                                                        OptikKaryawanTokens
                                                            .cyan
                                                            .withOpacity(
                                                                0.38),
                                                    blurRadius: 18,
                                                    offset:
                                                        const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: ElevatedButton(
                                                style: ElevatedButton
                                                    .styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  foregroundColor:
                                                      OptikKaryawanTokens
                                                          .ink,
                                                  minimumSize:
                                                      const Size.fromHeight(
                                                          54),
                                                  shape:
                                                      RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(14),
                                                  ),
                                                ),
                                                onPressed: _isLoading
                                                    ? null
                                                    : _loginKaryawan,
                                                child: Text(
                                                  "tombol_masuk_label".tr(),
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    letterSpacing: 1.3,
                                                    color:
                                                        OptikKaryawanTokens
                                                            .ink,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: _isLoading
                                                  ? null
                                                  : () =>
                                                      _loginDenganBiometrik(),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 14,
                                                    vertical: 12),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          14),
                                                  color:
                                                      OptikKaryawanTokens
                                                          .cyan
                                                          .withOpacity(0.12),
                                                  border: Border.all(
                                                    color:
                                                        OptikKaryawanTokens
                                                            .cyan
                                                            .withOpacity(
                                                                0.4),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .center,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .fingerprint_rounded,
                                                      size: 22,
                                                      color:
                                                          OptikKaryawanTokens
                                                              .ink
                                                              .withOpacity(
                                                                  0.9),
                                                    ),
                                                    const SizedBox(
                                                        width: 10),
                                                    Text(
                                                      kIsWeb
                                                          ? 'Biometrik (HP saja)'
                                                          : 'Masuk dengan Biometrik',
                                                      style: TextStyle(
                                                        color:
                                                            OptikKaryawanTokens
                                                                .ink
                                                                .withOpacity(
                                                                    0.88),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                "${'tanya_karyawan_baru'.tr()} ",
                                                style: TextStyle(
                                                  color: OptikKaryawanTokens
                                                      .muted
                                                      .withOpacity(0.95),
                                                  fontSize: 13,
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: _isLoading
                                                    ? null
                                                    : () async {
                                                        if (!isBrandedStoreApk) {
                                                          await TenantService
                                                              .instance
                                                              .persistSlug(
                                                            _slugCtrl.text,
                                                          );
                                                        }
                                                        if (!mounted) return;
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                const RegisterKaryawanPage(),
                                                          ),
                                                        );
                                                      },
                                                child: Text(
                                                  "tautan_daftar".tr(),
                                                  style: const TextStyle(
                                                    color:
                                                        OptikKaryawanTokens
                                                            .cyan,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                'PRIVATE · SECURE · SEASIDE',
                                style: TextStyle(
                                  color: OptikKaryawanTokens.ink
                                      .withOpacity(0.32),
                                  fontSize: 10,
                                  letterSpacing: 2.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AppLoadingOverlay(
            visible: _isLoading,
            message: 'Masuk ke akun…',
            subtitle: 'Memverifikasi kredensial & status akun',
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    List<String>? autofillHints,
    String? Function(String?)? validator,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: isPassword ? _isObscure : false,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      enabled: !_isLoading,
      style: const TextStyle(
        color: OptikKaryawanTokens.ink,
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
      ),
      cursorColor: OptikKaryawanTokens.cyan,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: OptikKaryawanTokens.muted.withOpacity(0.9),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        errorMaxLines: 2,
        prefixIcon: Icon(icon, color: OptikKaryawanTokens.cyan, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isObscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: OptikKaryawanTokens.muted.withOpacity(0.75),
                  size: 20,
                ),
                onPressed: _isLoading
                    ? null
                    : () => setState(() => _isObscure = !_isObscure),
              )
            : null,
        filled: true,
        fillColor: OptikKaryawanTokens.snow.withOpacity(0.72),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
          borderSide:
              BorderSide(color: OptikKaryawanTokens.cyan.withOpacity(0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
          borderSide:
              BorderSide(color: OptikKaryawanTokens.cyan.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
          borderSide: const BorderSide(
            color: OptikKaryawanTokens.cyan,
            width: 1.6,
          ),
        ),
      ),
    );
  }
}
