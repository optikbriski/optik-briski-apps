import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme.dart';
import 'login_karyawan_page.dart';

/// Legacy standalone OTP page (register flow uses inline OTP).
class OtpVerificationPage extends StatefulWidget {
  final String email;
  const OtpVerificationPage({super.key, required this.email});

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _otpCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  final _supabase = Supabase.instance.client;

  Timer? timer;
  int _cooldownMinutes = 1;
  int _remainingSeconds = 60;
  bool canResend = false;

  String get _email => widget.email.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    timer?.cancel();
    if (!mounted) return;
    setState(() {
      canResend = false;
      _remainingSeconds = _cooldownMinutes * 60;
    });

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        setState(() {
          canResend = true;
          _cooldownMinutes++;
        });
        t.cancel();
      }
    });
  }

  Future<void> _resendOtp() async {
    if (isLoading || !canResend) return;
    setState(() => isLoading = true);
    try {
      await _supabase.auth.signInWithOtp(
        email: _email,
        shouldCreateUser: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "otp_sukses_resend".tr(),
          style: const TextStyle(
            color: OptikKaryawanTokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: OptikKaryawanTokens.cyan,
      ));
      _startTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.message.isNotEmpty
              ? "${"otp_gagal_resend".tr()}${e.message}"
              : "otp_gagal_resend".tr(),
        ),
        backgroundColor: Colors.redAccent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${"otp_gagal_resend".tr()} $e"),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (isLoading) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => isLoading = true);

    try {
      final res = await _supabase.auth.verifyOTP(
        email: _email,
        token: _otpCtrl.text.trim(),
        type: OtpType.email,
      );

      if (!mounted) return;

      if (res.session == null || res.user == null) {
        throw const AuthException('OTP tidak valid');
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "otp_sukses_verifikasi".tr(),
          style: const TextStyle(
            color: OptikKaryawanTokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: OptikKaryawanTokens.cyan,
        duration: const Duration(seconds: 5),
      ));

      try {
        await _supabase.auth.signOut();
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginKaryawanPage()),
      );
    } on AuthException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("otp_gagal_verifikasi".tr()),
        backgroundColor: Colors.redAccent,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("otp_gagal_verifikasi".tr()),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: OptikKaryawanTokens.ink),
          onPressed: isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text("otp_title".tr(),
            style: const TextStyle(
                color: OptikKaryawanTokens.ink, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AbsorbPointer(
                absorbing: isLoading,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: OptikKaryawanTokens.cyan.withOpacity(0.12),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.mark_email_read_rounded,
                          size: 80, color: OptikKaryawanTokens.cyan),
                    ),
                    const SizedBox(height: 30),
                    Text("otp_subtitle".tr(),
                        style: const TextStyle(
                            color: OptikKaryawanTokens.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    Text(
                      "${"otp_desc".tr()} $_email",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: OptikKaryawanTokens.muted,
                          fontSize: 14,
                          height: 1.5),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _verifyOtp(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: OptikKaryawanTokens.ink),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                                color: OptikKaryawanTokens.border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                                color: OptikKaryawanTokens.border)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                                color: OptikKaryawanTokens.cyan, width: 2)),
                      ),
                      validator: (value) {
                        if (value == null ||
                            value.trim().length < 6 ||
                            value.trim().length > 8) {
                          return "otp_err_digit".tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OptikKaryawanTokens.cyan,
                          foregroundColor: OptikKaryawanTokens.ink,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: OptikKaryawanTokens.ink,
                                ),
                              )
                            : Text("otp_btn_verifikasi".tr(),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: OptikKaryawanTokens.ink)),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("otp_tanya_resend".tr(),
                            style: const TextStyle(
                                color: OptikKaryawanTokens.muted)),
                        canResend
                            ? TextButton(
                                onPressed: isLoading ? null : _resendOtp,
                                child: Text("otp_btn_resend".tr(),
                                    style: const TextStyle(
                                        color: OptikKaryawanTokens.cyan,
                                        fontWeight: FontWeight.bold)),
                              )
                            : Text(
                                "${"otp_tunggu".tr()}$_remainingSeconds dtk",
                                style: const TextStyle(
                                    color: OptikKaryawanTokens.muted,
                                    fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
