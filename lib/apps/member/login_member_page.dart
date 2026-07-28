import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/member/member_repository.dart';
import '../../shared/member/member_session.dart';
import '../../shared/member/member_status_watch.dart';
import '../../shared/theme.dart';

/// Fitur 4 — login HP + OTP.
class LoginMemberPage extends StatefulWidget {
  const LoginMemberPage({super.key});

  @override
  State<LoginMemberPage> createState() => _LoginMemberPageState();
}

class _LoginMemberPageState extends State<LoginMemberPage> {
  final _repo = MemberRepository();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _debugOtp;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nomor HP yang valid.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _repo.requestOtp(phone);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _debugOtp = res['otp']?.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _debugOtp == null
                ? 'OTP dikirim.'
                : 'OTP (sementara di app): $_debugOtp — ganti WA gateway nanti.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await _repo.verifyOtp(
        _phoneController.text.trim(),
        _otpController.text.trim(),
      );
      await MemberStatusWatch.instance.start();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _guest() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final already = MemberSession.instance.isLoggedIn;
    return Scaffold(
      backgroundColor: OptikMemberTokens.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      OptikMemberTokens.blueDeep,
                      OptikMemberTokens.blue,
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusMd),
                ),
                child: const Icon(Icons.visibility_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(height: 22),
              const Text(
                'OPTIK B. RISKI',
                style: TextStyle(
                  color: OptikMemberTokens.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Member',
                style: TextStyle(
                  color: OptikMemberTokens.blueDeep,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Login dengan nomor HP yang sama saat belanja agar nota, '
                'status, dan garansi muncul otomatis.',
                style: TextStyle(
                  color: OptikMemberTokens.inkSecondary,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              if (already) ...[
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/home'),
                  child: Text(
                    'Lanjut sebagai ${MemberSession.instance.phoneRaw ?? MemberSession.instance.phoneE164}',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () async {
                    await MemberSession.instance.logout();
                    MemberStatusWatch.instance.stop();
                    setState(() {});
                  },
                  child: const Text('Ganti akun'),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: OptikMemberTokens.white,
                  borderRadius:
                      BorderRadius.circular(OptikMemberTokens.radiusLg),
                  border: Border.all(color: OptikMemberTokens.lineSoft),
                  boxShadow: OptikMemberTokens.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Masuk dengan OTP',
                      style: TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Nomor HP / WhatsApp',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Kode OTP',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : (_otpSent ? _verify : _requestOtp),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_otpSent ? 'Verifikasi & masuk' : 'Kirim OTP'),
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _requestOtp,
                        child: const Text('Kirim ulang OTP'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _guest,
                      child: const Text('Jelajahi tanpa login'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
