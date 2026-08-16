// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import 'main_karyawan.dart';

/// Lupa password Karyawan: recovery OTP ke surel terdaftar → set sandi baru.
///
/// Alur Auth yang benar (Supabase):
/// `resetPasswordForEmail` → `verifyOTP(OtpType.recovery)` → `updateUser(password)`.
/// Jangan pakai `signInWithOtp` + `OtpType.email` (magic-link login) untuk reset.
class ForgotPasswordKaryawanPage extends StatefulWidget {
  const ForgotPasswordKaryawanPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordKaryawanPage> createState() =>
      _ForgotPasswordKaryawanPageState();
}

class _ForgotPasswordKaryawanPageState
    extends State<ForgotPasswordKaryawanPage> {
  static const _kSavedEmail = 'karyawan_saved_email';
  static const _kSavedPassword = 'karyawan_saved_password';

  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _secureStorage = const FlutterSecureStorage();

  bool _busy = false;
  bool _codeSent = false;
  bool _obscure = true;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = (widget.initialEmail ?? '').trim();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  String get _email => _emailCtrl.text.trim().toLowerCase();

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startCooldown([int seconds = 60]) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _safeSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('karyawan forgot signOut: $e');
    }
  }

  /// Hanya baris di tabel `karyawan` (bukan Member / Auth-only).
  Future<bool> _karyawanExists(String email) async {
    final row = await Supabase.instance.client
        .from('karyawan')
        .select('id,status_approval')
        .ilike('email', email)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    final email = _email;
    if (email.isEmpty || !email.contains('@')) {
      _snack('lupa_pw_email_wajib'.tr(), color: Colors.orange);
      return;
    }

    setState(() => _busy = true);
    try {
      final exists = await _karyawanExists(email);
      if (!exists) {
        if (!mounted) return;
        _snack('lupa_pw_akun_tidak_ada'.tr(), color: Colors.redAccent);
        return;
      }

      // Recovery path — tidak create Auth user; template "Reset Password".
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCooldown();
      _snack('lupa_pw_kode_terkirim'.tr(), color: OptikKaryawanTokens.cyan);
    } on AuthException catch (e) {
      if (!mounted) return;
      _snack(
        e.message.isNotEmpty ? e.message : 'lupa_pw_kirim_gagal'.tr(),
        color: Colors.redAccent,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('lupa_pw_kirim_gagal'.tr(), color: Colors.redAccent);
      debugPrint('karyawan forgot request: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    final email = _email;
    final token = _otpCtrl.text.trim();
    final pass = _passCtrl.text;
    final pass2 = _pass2Ctrl.text;

    if (token.length < 6) {
      _snack('lupa_pw_kode_wajib'.tr(), color: Colors.orange);
      return;
    }
    if (pass.length < 6) {
      _snack('lupa_pw_sandi_min'.tr(), color: Colors.orange);
      return;
    }
    if (pass != pass2) {
      _snack('lupa_pw_sandi_beda'.tr(), color: Colors.orange);
      return;
    }

    setState(() => _busy = true);
    var sessionHeld = false;
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.recovery,
      );
      if (res.session == null || res.user == null) {
        throw const AuthException('OTP tidak valid');
      }
      sessionHeld = true;

      final authEmail =
          (res.user!.email ?? '').trim().toLowerCase();
      if (authEmail.isEmpty || authEmail != email) {
        await _safeSignOut();
        sessionHeld = false;
        if (!mounted) return;
        _snack('profil_tidak_ditemukan'.tr(), color: Colors.redAccent);
        return;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: pass),
      );

      // Pastikan profil karyawan Aktif sebelum masuk shell.
      final row = await Supabase.instance.client
          .from('karyawan')
          .select('status_approval')
          .ilike('email', email)
          .limit(1)
          .maybeSingle();

      if (row == null) {
        await _safeSignOut();
        sessionHeld = false;
        if (!mounted) return;
        _snack('profil_tidak_ditemukan'.tr(), color: Colors.redAccent);
        Navigator.of(context).pop();
        return;
      }

      final status =
          (row['status_approval'] ?? '').toString().trim().toLowerCase();
      if (status != 'aktif') {
        await _safeSignOut();
        sessionHeld = false;
        if (!mounted) return;
        _snack(
          status.startsWith('ditolak')
              ? 'akun_ditolak'.tr()
              : 'lupa_pw_menunggu'.tr(),
          color:
              status.startsWith('ditolak') ? Colors.redAccent : Colors.orange,
        );
        Navigator.of(context).pop();
        return;
      }

      if (!kIsWeb) {
        try {
          await _secureStorage.write(key: _kSavedEmail, value: email);
          await _secureStorage.write(key: _kSavedPassword, value: pass);
        } catch (_) {}
      }

      sessionHeld = false; // sesi Aktif sengaja dipertahankan
      if (!mounted) return;
      _snack('lupa_pw_sukses'.tr(), color: OptikKaryawanTokens.cyan);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const KaryawanPage()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (sessionHeld) {
        await _safeSignOut();
        sessionHeld = false;
      }
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('otp') ||
          msg.contains('token') ||
          msg.contains('expired') ||
          msg.contains('invalid')) {
        _snack('otp_gagal_verifikasi'.tr(), color: Colors.redAccent);
      } else {
        _snack(
          e.message.isNotEmpty ? e.message : 'lupa_pw_reset_gagal'.tr(),
          color: Colors.redAccent,
        );
      }
    } catch (e) {
      if (sessionHeld) {
        await _safeSignOut();
        sessionHeld = false;
      }
      if (!mounted) return;
      _snack('lupa_pw_reset_gagal'.tr(), color: Colors.redAccent);
      debugPrint('karyawan forgot reset: $e');
    } finally {
      // Pertahanan terakhir: jangan biarkan sesi setengah jalan.
      if (sessionHeld) {
        await _safeSignOut();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        title: Text('lupa_pw_judul'.tr()),
        backgroundColor: Colors.transparent,
        foregroundColor: OptikKaryawanTokens.ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'lupa_pw_deskripsi'.tr(),
            style: TextStyle(
              color: OptikKaryawanTokens.muted.withOpacity(0.95),
              height: 1.4,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: OptikKaryawanTokens.cyan.withOpacity(0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailCtrl,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: 'isian_surel'.tr(),
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy || _cooldown > 0 ? null : _requestCode,
                  child: Text(
                    _cooldown > 0
                        ? '${'lupa_pw_kirim_ulang'.tr()} ($_cooldown)'
                        : (_codeSent
                            ? 'lupa_pw_kirim_ulang'.tr()
                            : 'lupa_pw_kirim_kode'.tr()),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'lupa_pw_kode_label'.tr(),
                      prefixIcon: const Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'lupa_pw_sandi_baru'.tr(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pass2Ctrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'lupa_pw_sandi_ulang'.tr(),
                      prefixIcon: const Icon(Icons.lock_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OptikKaryawanTokens.cyan,
                        foregroundColor: OptikKaryawanTokens.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'lupa_pw_simpan'.tr(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
