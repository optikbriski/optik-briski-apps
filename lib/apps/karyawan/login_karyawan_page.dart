// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_loading_overlay.dart';
import 'main_karyawan.dart';
import 'register_karyawan_page.dart';

class LoginKaryawanPage extends StatefulWidget {
  const LoginKaryawanPage({super.key});

  @override
  State<LoginKaryawanPage> createState() => _LoginKaryawanPageState();
}

class _LoginKaryawanPageState extends State<LoginKaryawanPage>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isObscure = true;
  bool _isLoading = false;

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _navy = Color(0xFF0A1628);
  static const _navyMid = Color(0xFF132F4C);
  static const _gold = Color(0xFFD4AF37);
  static const _goldSoft = Color(0xFFC4A35A);

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
    _cekBiometrikOtomatis();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _cekBiometrikOtomatis() async {
    if (kIsWeb) return;
    final emailTersimpan = await _secureStorage.read(key: 'saved_email');
    final passwordTersimpan = await _secureStorage.read(key: 'saved_password');
    if (emailTersimpan != null && passwordTersimpan != null) {
      _loginDenganBiometrik();
    }
  }

  Future<void> _loginDenganBiometrik() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Fitur Biometrik hanya tersedia di aplikasi HP (Android/iOS).'),
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
              Text('Belum ada akun tersimpan. Silakan masuk manual dulu.'),
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
          options: const AuthenticationOptions(biometricOnly: true),
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
      debugPrint('Gagal biometrik: $e');
    }
  }

  Future<void> _loginKaryawan() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Surel dan kata sandi wajib diisi.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (res.user == null) throw Exception('login gagal');

      final userEmail = res.user!.email ?? _emailCtrl.text.trim();
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

      final status = (userData['status_approval'] ?? '').toString();
      if (status != 'Aktif') {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        final ditolak = status.startsWith('Ditolak');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            ditolak
                ? "akun_ditolak".tr()
                : 'Akun menunggu persetujuan Admin Pusat. Belum bisa dipakai.',
          ),
          backgroundColor: ditolak ? Colors.redAccent : Colors.orange,
          duration: const Duration(seconds: 5),
        ));
        setState(() => _isLoading = false);
        return;
      }

      await _secureStorage.write(
          key: 'saved_email', value: _emailCtrl.text.trim());
      await _secureStorage.write(
          key: 'saved_password', value: _passwordCtrl.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("masuk_berhasil".tr()),
        backgroundColor: const Color(0xFF16A34A),
      ));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const KaryawanPage()),
      );
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
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      body: Stack(
        children: [
          // Full-bleed brand plane
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF071018),
                  _navy,
                  _navyMid,
                  Color(0xFF1A3A5C),
                ],
                stops: [0, 0.35, 0.72, 1],
              ),
            ),
          ),
          // Atmospheric light
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _gold.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Fine line texture
          Positioned.fill(
            child: CustomPaint(painter: _LuxuryGridPainter()),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        children: [
                          // Brand hero — must dominate first viewport
                          const Text(
                            'OPTIK B. RISKI',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.2,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 48,
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  _gold.withOpacity(0.9),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "sub_judul_portal".tr(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 13,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Portal Karyawan',
                            style: TextStyle(
                              color: _goldSoft.withOpacity(0.95),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.5,
                            ),
                          ),
                          const SizedBox(height: 36),

                          // Glass card
                          Container(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: Colors.white.withOpacity(0.07),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.14),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 40,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  "tombol_masuk_label".tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Masuk dengan akun yang sudah disetujui Pusat',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _buildField(
                                  controller: _emailCtrl,
                                  label: "isian_surel".tr(),
                                  icon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 14),
                                _buildField(
                                  controller: _passwordCtrl,
                                  label: "isian_kata_sandi".tr(),
                                  icon: Icons.lock_outline_rounded,
                                  isPassword: true,
                                ),
                                const SizedBox(height: 26),
                                SizedBox(
                                  height: 54,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFE8C872),
                                          _gold,
                                          _goldSoft,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _gold.withOpacity(0.35),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        foregroundColor: _navy,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      onPressed:
                                          _isLoading ? null : _loginKaryawan,
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: _navy,
                                              ),
                                            )
                                          : Text(
                                              "tombol_masuk_label".tr(),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.2,
                                                color: _navy,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Center(
                                  child: InkWell(
                                    onTap: _loginDenganBiometrik,
                                    borderRadius: BorderRadius.circular(40),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _gold.withOpacity(0.45),
                                            ),
                                            color: Colors.white.withOpacity(0.05),
                                          ),
                                          child: Icon(
                                            Icons.fingerprint_rounded,
                                            size: 28,
                                            color: _gold.withOpacity(0.95),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Masuk dengan Biometrik',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "${'tanya_karyawan_baru'.tr()} ",
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
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
                                          color: _gold,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'PRIVATE · SECURE · ENTERPRISE',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 10,
                              letterSpacing: 2.2,
                              fontWeight: FontWeight.w600,
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
          AppLoadingOverlay(
            visible: _isLoading,
            message: 'Masuk ke akun…',
            subtitle: 'Memverifikasi kredensial',
          ),
        ],
      ),
    );
  }

  Widget _buildField({
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
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontSize: 14.5,
      ),
      cursorColor: _gold,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: _goldSoft.withOpacity(0.85), size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isObscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withOpacity(0.45),
                  size: 20,
                ),
                onPressed: () => setState(() => _isObscure = !_isObscure),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _gold.withOpacity(0.75), width: 1.4),
        ),
      ),
    );
  }
}

class _LuxuryGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1;
    const step = 42.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
