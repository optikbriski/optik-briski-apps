import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:local_auth/local_auth.dart'; // Wajib ditambahkan
import 'main_karyawan.dart';
import 'register_karyawan_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class LoginKaryawanPage extends StatefulWidget {
  const LoginKaryawanPage({super.key});

  @override
  State<LoginKaryawanPage> createState() => _LoginKaryawanPageState();
}

class _LoginKaryawanPageState extends State<LoginKaryawanPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isObscure = true;
  bool _isLoading = false;

  // Instansiasi mesin pemindai biometrik
  final LocalAuthentication _localAuth = LocalAuthentication();
  // Instansiasi brankas penyimpanan
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _cekBiometrikOtomatis();
  }

// FUNGSI 1: CEK APAKAH ADA KREDENSIAL TERSIMPAN SAAT APLIKASI DIBUKA
  Future<void> _cekBiometrikOtomatis() async {
    if (kIsWeb) return; // 🔒 JIKA DI WEB, LANGSUNG STOP (BIAR GA CRASH)

    final emailTersimpan = await _secureStorage.read(key: 'saved_email');
    final passwordTersimpan = await _secureStorage.read(key: 'saved_password');

    // Jika ada data di brankas, langsung tawarkan pop-up sidik jari
    if (emailTersimpan != null && passwordTersimpan != null) {
      _loginDenganBiometrik();
    }
  }

// FUNGSI 2: PROSES LOGIN MENGGUNAKAN SIDIK JARI
  Future<void> _loginDenganBiometrik() async {
    if (kIsWeb) {
      // 🔒 JIKA DI WEB, KASIH TAHU USER JANGAN DIKLIK
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            "Fitur Biometrik hanya tersedia di aplikasi HP (Android/iOS)."),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    try {
      final emailTersimpan = await _secureStorage.read(key: 'saved_email');
      final passwordTersimpan =
          await _secureStorage.read(key: 'saved_password');

      if (emailTersimpan == null || passwordTersimpan == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Belum ada akun yang tersimpan. Silakan login manual dulu."),
          backgroundColor: Colors.orange,
        ));
        return;
      }

      final bool canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (canAuthenticate) {
        final bool didAuthenticate = await _localAuth.authenticate(
          localizedReason:
              'Pindai sidik jari / wajah Anda untuk masuk otomatis.',
          biometricOnly: true,
        );

        if (didAuthenticate) {
          setState(() {
            _emailCtrl.text = emailTersimpan;
            _passwordCtrl.text = passwordTersimpan;
          });
          _loginKaryawan();
        }
      }
    } catch (e) {
      debugPrint("Gagal biometrik: $e");
    }
  }

  // FUNGSI MASUK UTAMA (MANUAL PAKAI EMAIL & KATA SANDI)
  Future<void> _loginKaryawan() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("validasi_kosong"
            .tr()), // Spasinya sudah saya perbaiki sesuai JSON terakhir
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Eksekusi Masuk ke Supabase
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (res.user != null) {
        final String userEmail = res.user!.email!;

        // Memeriksa data tabel karyawan
        final userData = await Supabase.instance.client
            .from('karyawan')
            .select('status_approval')
            .eq('email', userEmail)
            .maybeSingle();

        if (userData == null) {
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("profil_tidak_ditemukan".tr()),
            backgroundColor: Colors.redAccent,
          ));
          setState(() => _isLoading = false);
          return;
        }

        final status = userData['status_approval'];

        if (status == 'Pending') {
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("akun_tertunda".tr()), // Spasinya sudah saya perbaiki
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ));
          setState(() => _isLoading = false);
          return;
        } else if (status == 'Ditolak') {
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("akun_ditolak".tr()),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ));
          setState(() => _isLoading = false);
          return;
        }

        // ✅ SIMPAN KE BRANKAS JIKA BERHASIL LOGIN MANUAL
        await _secureStorage.write(
            key: 'saved_email', value: _emailCtrl.text.trim());
        await _secureStorage.write(
            key: 'saved_password', value: _passwordCtrl.text);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("masuk_berhasil".tr()), // Spasinya sudah saya perbaiki
          backgroundColor: Colors.green,
        ));

        // Pindah ke Halaman Utama Karyawan
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const KaryawanPage()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("masuk_gagal".tr()),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1. LATAR BELAKANG GRADASI PREMIUM (Bukan putih polos)
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFE2E8F0)
            ], // Gradasi Slate muda yang elegan
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 2. LOGO MATA (LEBIH ELEGAN DENGAN SHADOW)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.15),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: const Icon(Icons.visibility_rounded,
                      size: 50, color: Color(0xFF1E3C72)),
                ),
                const SizedBox(height: 25),
                // 3. TEKS JUDUL (TYPOGRAPHY PREMIUM)
                Text(
                  "judul_aplikasi".tr(),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                      color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 5),
                Text(
                  "sub_judul_portal".tr(),
                  style: const TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.2,
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 40),
                // 4. KARTU FORM (MELAYANG DAN SUDUT MELENGKUNG HALUS)
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 40,
                        offset: const Offset(0, 15),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      // INPUT EMAIL
                      _buildPremiumTextField(
                        controller: _emailCtrl,
                        label: "isian_surel".tr(),
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      // INPUT KATA SANDI
                      _buildPremiumTextField(
                        controller: _passwordCtrl,
                        label: "isian_kata_sandi".tr(),
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                      ),
                      const SizedBox(height: 35),
                      // TOMBOL LOGIN (GRADIENT GELAP ELEGAN)
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1E293B),
                                Color(0xFF0F172A)
                              ], // Biru Navy Gelap
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              )
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isLoading ? null : _loginKaryawan,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : Text(
                                    "tombol_masuk_label".tr(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.0,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // ✅ TOMBOL FINGERPRINT STANDAR M-BANKING
                      GestureDetector(
                        onTap: _loginDenganBiometrik,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.fingerprint_rounded,
                                  size: 30, color: Colors.blueAccent),
                            ),
                            const SizedBox(height: 8),
                            const Text("Masuk dengan Biometrik",
                                style: TextStyle(
                                    color: Colors.blueGrey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),
                      // 5. TOMBOL DAFTAR (LEBIH BERSIH)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("${'tanya_karyawan_baru'.tr()} ",
                              style: const TextStyle(
                                  color: Colors.blueGrey, fontSize: 14)),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const RegisterKaryawanPage()));
                            },
                            child: Text(
                              "tautan_daftar".tr(),
                              style: const TextStyle(
                                color: Color(0xFF1E3C72),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // WIDGET HELPER: TEXT FIELD PREMIUM
  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? _isObscure : false,
      keyboardType: keyboardType,
      style: const TextStyle(
          fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.blueGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.blueGrey.shade400, size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    _isObscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.blueGrey.shade400,
                    size: 20),
                onPressed: () => setState(() => _isObscure = !_isObscure),
              )
            : null,
        filled: true,
        fillColor: const Color(
            0xFFF8FAFC), // Warna abu-abu sangat muda untuk kolom ketik
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none, // Tanpa garis saat diam
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF1E3C72),
            width: 1.5,
          ), // Garis biru elegan saat diketik
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
    );
  }
}
