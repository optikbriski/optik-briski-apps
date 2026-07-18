// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.onLoggedIn,
    this.bannerError,
  });

  /// Dipanggil setelah login sukses + profil pusat/cabang tersimpan.
  final ValueChanged<Map<String, dynamic>>? onLoggedIn;

  /// Pesan error dari AuthWrapper (mis. akun karyawan ditolak).
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
            backgroundColor: Colors.redAccent,
          ),
        );
      });
    }
  }

  Future<void> handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("admin_login_err_kosong".tr())));
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Autentikasi akun ke Supabase Auth
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = res.user;
      if (user == null) throw "User tidak ditemukan";

      final userEmail = user.email ?? '';
      final client = Supabase.instance.client;

      // Akun yang ada di tabel karyawan = APK Karyawan, bukan Admin
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

      // Pusat/cabang & role HANYA dari Table Editor (tabel profiles)
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

      // toko harus sudah ada di master toko_id (diisi Table Editor, bukan hardcode app)
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

      // Sync email saja; role & toko tetap dari Table Editor
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
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF080E15),
              Colors.blueAccent.withOpacity(0.05)
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo_briski.png',
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.broken_image_rounded,
                      size: 100,
                      color: Colors.blueAccent,
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -45),
                    child: Text(
                      "admin_login_subtitle".tr(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login Admin Pusat / Cabang',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueAccent.withOpacity(0.85),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "admin_login_email".tr(),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "admin_login_password".tr(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: isLoading ? null : handleLogin,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              "admin_login_btn".tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "admin_login_footer".tr(),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
