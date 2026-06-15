import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '/main.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;
  bool _isPasswordVisible = false;

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
      String assignedTokoId = 'PUSAT';
      String assignedRole = 'kasir';

      // 2. DETEKSI DARI TABEL KARYAWAN: Cari data toko_id aslinya
      final karyawanRes = await Supabase.instance.client
          .from('karyawan')
          .select('toko_id, jabatan')
          .eq('email', userEmail)
          .maybeSingle();

      if (karyawanRes != null) {
        assignedTokoId = karyawanRes['toko_id'] ?? 'PUSAT';
        assignedRole =
            (karyawanRes['jabatan']?.toString().toLowerCase() == 'manager' ||
                    karyawanRes['jabatan']?.toString().toLowerCase() == 'admin')
                ? 'admin_toko'
                : 'kasir';
      } else {
        // 3. JALUR HARD-MAPPING FALLBACK (Jika tabel karyawan kosong akibat SQL clean)
        if (userEmail == 'risctonn@gmail.com') {
          assignedTokoId = 'PUSAT';
          assignedRole = 'owner';
        } else if (userEmail == 'riscton11@gmail.com') {
          assignedTokoId = 'CABANG-CIMAHI';
          assignedRole = 'admin_toko';
        } else if (userEmail == 'nriscton@gmail.com') {
          assignedTokoId = 'PUSAT';
          assignedRole = 'kasir';
        }
      }

      // 💡 FIX UTAMA: JALUR OTOMATISASI MAKSIMAL BIAR GA USAH SENTUH SQL LAGI
      // Aplikasi Flutter otomatis mendaftarkan ID Toko baru ke Master Toko agar tidak terkena Foreign Key Error
      await Supabase.instance.client.from('toko_id').upsert({
        'id': assignedTokoId,
        'toko_id': assignedTokoId == 'PUSAT'
            ? 'Optik B. Riski - Pusat'
            : 'Optik B. Riski - $assignedTokoId',
      });

      // 4. Lakukan upsert ke profiles (Sekarang dijamin lolos 100% karena toko_id sudah aman terdaftar di atas)
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'email': userEmail,
        'role': assignedRole,
        'toko_id': assignedTokoId,
      });

      // 5. Ambil data profil final yang sudah sinkron
      final finalProfile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      // Ambil profile bersih dan kunci tipe datanya agar aman dari warning lint closure
      final Map<String, dynamic> safeProfile = finalProfile;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardPage(profile: safeProfile),
        ),
      );
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
