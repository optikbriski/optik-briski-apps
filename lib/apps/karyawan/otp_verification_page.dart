import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart'; // <-- Senjata Utama
import 'login_karyawan_page.dart';

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
    setState(() {
      canResend = false;
      _remainingSeconds = _cooldownMinutes * 60;
    });

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        setState(() {
          canResend = true;
          _cooldownMinutes++;
        });
        timer.cancel();
      }
    });
  }

  Future<void> _resendOtp() async {
    setState(() => isLoading = true);
    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("otp_sukses_resend".tr()),
        backgroundColor: Colors.green,
      ));
      _startTimer();
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);

    try {
      final res = await _supabase.auth.verifyOTP(
        email: widget.email,
        token: _otpCtrl.text.trim(),
        type: OtpType.signup,
      );

      if (!mounted) return;

      if (res.session != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("otp_sukses_verifikasi".tr()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));

        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => const LoginKaryawanPage()));
      } else {
        throw "Token tidak valid";
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("otp_gagal_verifikasi".tr()),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("otp_title".tr(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.mark_email_read_rounded,
                        size: 80, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 30),
                  Text("otp_subtitle".tr(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Text(
                    "${"otp_desc".tr()} ${widget.email}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: Colors.white),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                              color: Colors.blueAccent, width: 2)),
                    ),
                    validator: (v) => (v == null || v.length != 8)
                        ? "otp_err_digit".tr()
                        : null,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15))),
                      onPressed: isLoading ? null : _verifyOtp,
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text("otp_btn_verifikasi".tr(),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2)),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("otp_tanya_resend".tr(),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 14)),
                      canResend
                          ? GestureDetector(
                              onTap: isLoading ? null : _resendOtp,
                              child: Text("otp_btn_resend".tr(),
                                  style: const TextStyle(
                                      color: Colors.blueAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                            )
                          : Text(
                              "${"otp_tunggu".tr()} ${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                    ],
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
