// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../shared/admin/admin_code_login_service.dart';
import '../../shared/widgets/optik_brand_logo.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

enum _LoginMode { password, code }

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.onLoggedIn,
    this.bannerError,
  });

  final ValueChanged<Map<String, dynamic>>? onLoggedIn;
  final String? bannerError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool isLoading = false;
  bool _isPasswordVisible = false;
  _LoginMode _mode = _LoginMode.code;

  @override
  void initState() {
    super.initState();
    final banner = widget.bannerError;
    if (banner != null && banner.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(banner, OptikAdminTokens.danger);
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        content: Text(
          msg,
          style: const TextStyle(
            color: OptikAdminTokens.snow,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _finishWithCurrentUser({AdminCodeLoginActor? actor}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw 'User tidak ditemukan';

    final userEmail = user.email ?? '';

    final karyawanRes = await client
        .from('karyawan')
        .select('id')
        .eq('email', userEmail)
        .maybeSingle();
    if (karyawanRes != null) {
      await client.auth.signOut();
      throw 'Akses ditolak: akun Karyawan tidak boleh masuk Admin. '
          'Pakai APK Karyawan.';
    }

    final profile = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null) {
      await client.auth.signOut();
      throw 'Profil admin belum diisi di Table Editor.\n'
          'Isi tabel profiles: id = UID Auth, role, toko_id.';
    }

    final assignedRole = (profile['role'] ?? '').toString().toLowerCase();
    final assignedTokoId =
        (profile['toko_id'] ?? '').toString().trim().toUpperCase();

    const adminRoles = {
      'owner',
      'admin_pusat',
      'admin_toko',
      'super_admin',
    };
    if (!adminRoles.contains(assignedRole)) {
      await client.auth.signOut();
      throw 'Role "$assignedRole" tidak diizinkan di Admin. '
          'Set role di Table Editor: owner / admin_pusat / admin_toko.';
    }

    if (assignedTokoId.isEmpty) {
      await client.auth.signOut();
      throw 'toko_id di profiles kosong. Isi lewat Table Editor.';
    }

    final toko = await client
        .from('toko_id')
        .select('id')
        .eq('id', assignedTokoId)
        .maybeSingle();
    if (toko == null) {
      await client.auth.signOut();
      throw 'Toko "$assignedTokoId" belum ada di tabel toko_id.\n'
          'Tambah dulu di Table Editor → toko_id.';
    }

    await client.from('profiles').update({
      'email': userEmail,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);

    final finalProfile =
        await client.from('profiles').select().eq('id', user.id).single();

    final merged = Map<String, dynamic>.from(finalProfile);
    if (actor != null && actor.isPresent) {
      merged['login_via_karyawan_id'] = actor.karyawanId;
      merged['login_via_karyawan_nama'] = actor.nama;
      merged['login_via_karyawan_toko'] = actor.tokoId;
      merged['login_via_karyawan_jabatan'] = actor.jabatan;
      merged['login_via_audit_id'] = actor.auditId;
    }

    if (!mounted) return;
    if (actor != null && actor.isPresent) {
      _snack('Login via kode APK: ${actor.label}', OptikAdminTokens.success);
    }
    widget.onLoggedIn?.call(merged);
  }

  Future<void> handleLogin() async {
    if (_mode == _LoginMode.code) {
      await _handleCodeLogin();
    } else {
      await _handlePasswordLogin();
    }
  }

  Future<void> _handlePasswordLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _snack("admin_login_err_kosong".tr(), OptikAdminTokens.warning);
      return;
    }

    setState(() => isLoading = true);
    try {
      await AdminCodeLoginService.clearActor();
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (res.user == null) throw 'User tidak ditemukan';
      await _finishWithCurrentUser();
    } catch (e) {
      if (mounted) {
        _snack("${'admin_login_err_gagal'.tr()}$e", OptikAdminTokens.danger);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleCodeLogin() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
    if (email.isEmpty || code.length != 6) {
      _snack(
        'Isi email admin dan kode 6 angka dari APK.',
        OptikAdminTokens.warning,
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      final actor = await AdminCodeLoginService.signInWithCode(
        email: email,
        code: code,
      );
      await _finishWithCurrentUser(actor: actor);
    } catch (e) {
      if (mounted) {
        _snack("${'admin_login_err_gagal'.tr()}$e", OptikAdminTokens.danger);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _onCodeChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 6 && !isLoading) {
      handleLogin();
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? hint,
    String? counterText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: counterText,
      prefixIcon: Icon(icon, color: OptikAdminTokens.slate, size: 20),
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(
        color: OptikAdminTokens.slate,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: OptikAdminTokens.slate.withOpacity(0.55),
        fontWeight: FontWeight.w500,
        letterSpacing: 4,
      ),
      filled: true,
      fillColor: OptikAdminTokens.bgMid,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.navy, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      body: Stack(
        children: [
          // Atmosphere — soft ice wash, bukan flat putih kosong.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    OptikAdminTokens.ice.withOpacity(0.22),
                    OptikAdminTokens.bg,
                    OptikAdminTokens.bgMid,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikAdminTokens.ice.withOpacity(0.28),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -70,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikAdminTokens.navy.withOpacity(0.04),
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const OptikBrandLogo.color(height: 58),
                    const SizedBox(height: 10),
                    Text(
                      "admin_login_subtitle".tr().toUpperCase(),
                      style: TextStyle(
                        color: OptikAdminTokens.slate.withOpacity(0.95),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusXl),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                OptikAdminTokens.radiusXl),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                OptikAdminTokens.card.withOpacity(0.98),
                                OptikAdminTokens.bgMid.withOpacity(0.96),
                              ],
                            ),
                            border: Border.all(
                              color: OptikAdminTokens.ice.withOpacity(0.55),
                              width: 1.1,
                            ),
                            boxShadow: OptikAdminTokens.cardShadow,
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(22, 22, 22, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const PremiumIconBadge(
                                      icon: Icons.lock_person_rounded,
                                      color: OptikAdminTokens.ice,
                                      size: 48,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ADMIN ACCESS',
                                            style: TextStyle(
                                              color: OptikAdminTokens.slate
                                                  .withOpacity(0.95),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.6,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Login Admin',
                                            style: TextStyle(
                                              color: OptikAdminTokens.navy,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 21,
                                              height: 1.15,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            _mode == _LoginMode.code
                                                ? 'PUSAT: Admin/Owner. Cabang: Kepala Toko / Kepala Area.'
                                                : 'Pusat / Cabang — kelola operasional toko.',
                                            style: TextStyle(
                                              color: OptikAdminTokens.slate
                                                  .withOpacity(0.95),
                                              fontSize: 12.5,
                                              height: 1.35,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                _modeToggle(),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _emailController,
                                  style: const TextStyle(
                                    color: OptikAdminTokens.navy,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: _fieldDecoration(
                                    label: "admin_login_email".tr(),
                                    icon: Icons.person_outline_rounded,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_mode == _LoginMode.password)
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: !_isPasswordVisible,
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => handleLogin(),
                                    decoration: _fieldDecoration(
                                      label: "admin_login_password".tr(),
                                      icon: Icons.lock_outline_rounded,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility_rounded
                                              : Icons.visibility_off_rounded,
                                          color: OptikAdminTokens.slate,
                                        ),
                                        onPressed: () => setState(() =>
                                            _isPasswordVisible =
                                                !_isPasswordVisible),
                                      ),
                                    ),
                                  )
                                else
                                  TextField(
                                    controller: _codeController,
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 8,
                                    ),
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    maxLength: 6,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(6),
                                    ],
                                    onChanged: _onCodeChanged,
                                    onSubmitted: (_) => handleLogin(),
                                    decoration: _fieldDecoration(
                                      label: 'Kode 6 angka (APK)',
                                      icon: Icons.pin_rounded,
                                      hint: '••••••',
                                      counterText: '',
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: OptikAdminTokens.ice.withOpacity(0.18),
                                    border: Border.all(
                                      color: OptikAdminTokens.ice
                                          .withOpacity(0.65),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _mode == _LoginMode.code
                                            ? Icons.phonelink_lock_rounded
                                            : Icons.shield_rounded,
                                        color: OptikAdminTokens.navy,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _mode == _LoginMode.code
                                              ? 'Kode 6 angka dari APK: digit 1=posisi (1 Owner, 2 Admin, 3 Kepala Area, 4 Kepala Toko). Sisanya unik per orang.'
                                              : 'Akses terbatas akun Admin. Karyawan pakai APK Karyawan.',
                                          style: TextStyle(
                                            color: OptikAdminTokens.slate
                                                .withOpacity(0.95),
                                            fontSize: 12,
                                            height: 1.4,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                PremiumPrimaryButton(
                                  label: _mode == _LoginMode.code
                                      ? 'Masuk dengan kode'
                                      : "admin_login_btn".tr(),
                                  loading: isLoading,
                                  icon: Icons.login_rounded,
                                  onPressed: handleLogin,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "admin_login_footer".tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: OptikAdminTokens.slate.withOpacity(0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        border: Border.all(color: OptikAdminTokens.lineStrong),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeChip(
              selected: _mode == _LoginMode.code,
              label: 'Kode APK',
              onTap: () => setState(() => _mode = _LoginMode.code),
            ),
          ),
          Expanded(
            child: _modeChip(
              selected: _mode == _LoginMode.password,
              label: 'Password',
              onTap: () => setState(() => _mode = _LoginMode.password),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? OptikAdminTokens.navy : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? OptikAdminTokens.snow : OptikAdminTokens.slate,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
