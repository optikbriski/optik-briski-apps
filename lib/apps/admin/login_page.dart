// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

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
  bool isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    final banner = widget.bannerError;
    if (banner != null && banner.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(banner),
            backgroundColor: OptikAdminTokens.danger,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("admin_login_err_kosong".tr())));
      return;
    }

    setState(() => isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = res.user;
      if (user == null) throw "User tidak ditemukan";

      final userEmail = user.email ?? '';
      final client = Supabase.instance.client;

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

      final finalProfile = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      widget.onLoggedIn?.call(Map<String, dynamic>.from(finalProfile));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${'admin_login_err_gagal'.tr()}$e"),
            backgroundColor: OptikAdminTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo di luar box — brand hero, tidak sesak di kartu
                Image.asset(
                  'assets/images/logo_briski.png',
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(
                    Icons.broken_image_rounded,
                    size: 72,
                    color: OptikAdminTokens.accentSoft,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "admin_login_subtitle".tr().toUpperCase(),
                  style: TextStyle(
                    color: OptikAdminTokens.accentSoft.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            OptikAdminTokens.card.withOpacity(0.97),
                            OptikAdminTokens.panel.withOpacity(0.99),
                          ],
                        ),
                        border: Border.all(
                          color: OptikAdminTokens.accent.withOpacity(0.45),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: OptikAdminTokens.accent.withOpacity(0.18),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const PremiumIconBadge(
                                  icon: Icons.lock_person_rounded,
                                  color: OptikAdminTokens.accentSoft,
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
                                          color: OptikAdminTokens.accentSoft
                                              .withOpacity(0.95),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Login Admin',
                                        style: TextStyle(
                                          color: OptikAdminTokens.textPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 20,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Pusat / Cabang — kelola operasional toko.',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 13,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _emailController,
                              style: const TextStyle(
                                  color: OptikAdminTokens.textPrimary),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: "admin_login_email".tr(),
                                prefixIcon:
                                    const Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              style: const TextStyle(
                                  color: OptikAdminTokens.textPrimary),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => handleLogin(),
                              decoration: InputDecoration(
                                labelText: "admin_login_password".tr(),
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordVisible
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                  onPressed: () => setState(() =>
                                      _isPasswordVisible = !_isPasswordVisible),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: OptikAdminTokens.bg.withOpacity(0.45),
                                border: Border.all(
                                  color:
                                      OptikAdminTokens.accent.withOpacity(0.28),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.shield_rounded,
                                    color: OptikAdminTokens.accentSoft
                                        .withOpacity(0.95),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Akses terbatas akun Admin. Karyawan pakai APK Karyawan.',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.72),
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            PremiumPrimaryButton(
                              label: "admin_login_btn".tr(),
                              loading: isLoading,
                              icon: Icons.login_rounded,
                              onPressed: handleLogin,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              "admin_login_footer".tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: Colors.white.withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
