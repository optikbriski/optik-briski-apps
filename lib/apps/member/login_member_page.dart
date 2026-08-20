import 'package:flutter/material.dart';

import '../../shared/member/member_repository.dart';
import '../../shared/member/member_session.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/config.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/optik_brand_logo.dart';
import 'member_forgot_password_page.dart';
import 'member_register_page.dart';

/// Login Member: email/HP + password.
class LoginMemberPage extends StatefulWidget {
  const LoginMemberPage({super.key});

  @override
  State<LoginMemberPage> createState() => _LoginMemberPageState();
}

class _LoginMemberPageState extends State<LoginMemberPage> {
  final _repo = MemberRepository();
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _slugCtrl = TextEditingController(text: TenantService.instance.slug);
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginPassword() async {
    final id = _idCtrl.text.trim();
    final pass = _passCtrl.text;
    if (id.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi email/HP dan password')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await TenantService.instance.requireResolved(
        slug: isBrandedStoreApk ? null : _slugCtrl.text,
      );
      await BrandService.load();
      final res = await _repo.loginWithPassword(identifier: id, password: pass);
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Login gagal'}'),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
      try {
        await MemberStatusWatch.instance.start();
      } catch (_) {}
      if (!mounted) return;
      // Clear stack — jangan tumpuk MemberShell di atas guest shell dari Beranda.
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    if (!isBrandedStoreApk) {
      try {
        await TenantService.instance.requireResolved(slug: _slugCtrl.text);
        await BrandService.load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  InputDecoration _fieldDec({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: OptikMemberTokens.blue),
      suffixIcon: suffix,
      filled: true,
      fillColor: OptikMemberTokens.blueMist.withOpacity(0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: OptikMemberTokens.lineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: OptikMemberTokens.blue, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final already = MemberSession.instance.isLoggedIn;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEAF2FF),
              OptikMemberTokens.white,
              Color(0xFFF7FAFF),
            ],
            stops: [0, 0.42, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikMemberTokens.blue.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              top: 120,
              left: -70,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikMemberTokens.blueDeep.withOpacity(0.06),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(22, 20, 22, 24 + bottom),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        const Center(child: OptikBrandLogo.color(height: 48)),
                        const SizedBox(height: 16),
                        ValueListenableBuilder<int>(
                          valueListenable: BrandService.revision,
                          builder: (_, __, ___) => Column(
                            children: [
                              Text(
                                BrandService.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: OptikMemberTokens.blueDeep,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Login Member ${BrandService.name} — nota, garansi, dan promo toko.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: OptikMemberTokens.inkMuted,
                                  fontSize: 14.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (already) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: OptikMemberTokens.blueSoft,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: OptikMemberTokens.blue.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Lanjut sebagai ${MemberSession.instance.nama ?? MemberSession.instance.phoneRaw ?? MemberSession.instance.email ?? 'Member'}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: OptikMemberTokens.blueDeep,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: () => Navigator.of(context)
                                      .pushNamedAndRemoveUntil(
                                          '/home', (_) => false),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text('Lanjut'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await MemberStatusWatch.instance
                                        .clearLocalState();
                                    await MemberSession.instance.logout();
                                    setState(() {});
                                  },
                                  child: const Text('Ganti akun'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                          decoration: BoxDecoration(
                            color: OptikMemberTokens.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: OptikMemberTokens.lineSoft,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: OptikMemberTokens.blueDeep
                                    .withOpacity(0.08),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: OptikMemberTokens.blue,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Masuk akun',
                                    style: TextStyle(
                                      color: OptikMemberTokens.blueDeep,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              if (!isBrandedStoreApk) ...[
                                TextField(
                                  controller: _slugCtrl,
                                  textInputAction: TextInputAction.next,
                                  onChanged: (v) {
                                    TenantService.instance.persistSlug(v);
                                  },
                                  onSubmitted: (_) async {
                                    await TenantService.instance
                                        .persistSlug(_slugCtrl.text);
                                    await BrandService.load();
                                    if (mounted) setState(() {});
                                  },
                                  decoration: _fieldDec(
                                    label: 'Kode usaha',
                                    icon: Icons.storefront_outlined,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'APK Rekasa dipakai banyak toko. Kode usaha memisahkan data merek.',
                                  style: TextStyle(
                                    color: OptikMemberTokens.inkMuted.withOpacity(0.95),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                controller: _idCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: _fieldDec(
                                  label: 'Email atau nomor HP',
                                  icon: Icons.person_outline_rounded,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passCtrl,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) =>
                                    _busy ? null : _loginPassword(),
                                decoration: _fieldDec(
                                  label: 'Password',
                                  icon: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: OptikMemberTokens.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
                                    if (!isBrandedStoreApk) {
                                      await TenantService.instance
                                          .persistSlug(_slugCtrl.text);
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            MemberForgotPasswordPage(
                                          initialIdentifier:
                                              _idCtrl.text.trim(),
                                          initialSlug: isBrandedStoreApk
                                              ? null
                                              : _slugCtrl.text.trim(),
                                        ),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: OptikMemberTokens.blue,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text(
                                    'Lupa password?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FilledButton(
                                onPressed: _busy ? null : _loginPassword,
                                style: FilledButton.styleFrom(
                                  backgroundColor: OptikMemberTokens.blueDeep,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Masuk',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15.5,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () async {
                                  if (!isBrandedStoreApk) {
                                    await TenantService.instance
                                        .persistSlug(_slugCtrl.text);
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MemberRegisterPage(),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: OptikMemberTokens.blueDeep,
                                  side: const BorderSide(
                                    color: OptikMemberTokens.blue,
                                    width: 1.2,
                                  ),
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Daftar akun baru',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _guest,
                                style: TextButton.styleFrom(
                                  foregroundColor: OptikMemberTokens.inkMuted,
                                ),
                                child: const Text(
                                  'Jelajahi tanpa login',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Pakai nomor yang sama saat belanja di toko\nagar nota & garansi muncul otomatis.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: OptikMemberTokens.inkMuted.withOpacity(0.9),
                            fontSize: 12.5,
                            height: 1.4,
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
    );
  }
}
