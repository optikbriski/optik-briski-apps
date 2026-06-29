// ignore_for_file: use_build_context_synchronously, deprecated_member_use
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

      // 2. DETEKSI DARI TABEL KARYAWAN: Ambil data untuk pengecekan asal aplikasi
      final karyawanRes = await Supabase.instance.client
          .from('karyawan')
          .select('toko_id, jabatan')
          .eq('email', userEmail)
          .maybeSingle();

      // 🛑 KUNCI SEKURITI MUTLAK: Jika akun DITEMUKAN di tabel karyawan, artinya akun ini dibuat dari APK Karyawan.
      // Langsung paksa role-nya menjadi 'kasir' agar otomatis ditendang oleh barikade di bawah,
      // tidak peduli apakah di tabel jabatannya tertulis 'admin', 'manager', atau lainnya!
      if (karyawanRes != null) {
        assignedTokoId = karyawanRes['toko_id'] ?? 'PUSAT';
        assignedRole = 'kasir';
      } else {
        // 3. JALUR AKUN ADMIN ASLI: Hanya mengecek akun yang dibuat LANGSUNG di Supabase Dashboard (Tidak ada di tabel karyawan)
        if (userEmail == 'risctonn@gmail.com') {
          assignedTokoId = 'PUSAT';
          assignedRole = 'owner';
        } else if (userEmail == 'riscton11@gmail.com') {
          assignedTokoId = 'CABANG-CIMAHI';
          assignedRole = 'admin_toko';
        } else if (userEmail == 'nriscton@gmail.com') {
          assignedTokoId = 'PUSAT';
          assignedRole = 'kasir'; // Email kasir fallback tetap diblokir
        } else {
          // Akun admin baru lainnya yang lu buat langsung via Supabase Dashboard Auth tanpa lewat apk lapangan
          assignedTokoId = 'PUSAT';
          assignedRole = user.userMetadata?['role'] ?? 'admin_toko';
        }
      }

      // 🛑 BARIKADE UTAMA: TENDANG INSTAN AKUN KARYAWAN LAPANGAN
      if (assignedRole == 'kasir') {
        // Hancurkan session login di level Supabase Auth seketika agar tidak bypass refresh page
        await Supabase.instance.client.auth.signOut();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Akses Ditolak: Akun Lapangan/Karyawan tidak diizinkan masuk ke sistem Admin!"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        setState(() => isLoading = false);
        return; // Blokir eksekusi total ke bawah!
      }

      // 🏢 JALUR OTOMATISASI RE-REGISTRASI MASTER TOKO (Hanya untuk Admin/Owner yang lolos)
      await Supabase.instance.client.from('toko_id').upsert({
        'id': assignedTokoId,
        'toko_id': assignedTokoId == 'PUSAT'
            ? 'Optik B. Riski - Pusat'
            : 'Optik B. Riski - $assignedTokoId',
      });

      // 4. Lakukan upsert ke profiles harian admin
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
