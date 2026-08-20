import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/brand/brand_service.dart';
import '../../shared/config.dart';
import '../../shared/member/member_repository.dart';
import '../../shared/tenant/tenant_service.dart';
import '../../shared/theme.dart';
import 'pages/member_date_picker.dart';

class MemberRegisterPage extends StatefulWidget {
  const MemberRegisterPage({super.key});

  @override
  State<MemberRegisterPage> createState() => _MemberRegisterPageState();
}

class _MemberRegisterPageState extends State<MemberRegisterPage> {
  final _repo = MemberRepository();
  final _slug = TextEditingController(text: TenantService.instance.slug);
  final _nama = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _waOtp = TextEditingController();
  final _emailOtp = TextEditingController();

  DateTime? _dob;
  bool _obscure = true;
  bool _busyCreate = false;
  bool _sendingWa = false;
  bool _sendingEmail = false;

  bool _waOtpVisible = false;
  bool _emailOtpVisible = false;
  bool? _waOk; // null=belum, true/false
  bool? _emailOk;
  String? _waDebug;
  String? _emailDebug;
  String? _waHint;
  String? _emailHint;

  Timer? _waDebounce;
  Timer? _emailDebounce;

  @override
  void initState() {
    super.initState();
    _waOtp.addListener(_onWaOtpChanged);
    _emailOtp.addListener(_onEmailOtpChanged);
    for (final c in [_slug, _nama, _phone, _email, _pass, _pass2]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _waDebounce?.cancel();
    _emailDebounce?.cancel();
    _waOtp.removeListener(_onWaOtpChanged);
    _emailOtp.removeListener(_onEmailOtpChanged);
    _slug.dispose();
    _nama.dispose();
    _phone.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _waOtp.dispose();
    _emailOtp.dispose();
    super.dispose();
  }

  bool get _formCoreValid {
    return _nama.text.trim().isNotEmpty &&
        _phone.text.trim().length >= 9 &&
        _email.text.trim().contains('@') &&
        _dob != null &&
        _pass.text.length >= 6 &&
        _pass.text == _pass2.text;
  }

  bool get _canCreate =>
      _formCoreValid && _waOk == true && _emailOk == true && !_busyCreate;

  void _onWaOtpChanged() {
    _waDebounce?.cancel();
    final code = _waOtp.text.trim();
    if (code.length < 6) {
      if (_waOk != null) setState(() => _waOk = null);
      return;
    }
    _waDebounce = Timer(const Duration(milliseconds: 350), () {
      _checkOtp(channel: 'wa', code: code);
    });
  }

  void _onEmailOtpChanged() {
    _emailDebounce?.cancel();
    final code = _emailOtp.text.trim();
    if (code.length < 6) {
      if (_emailOk != null) setState(() => _emailOk = null);
      return;
    }
    _emailDebounce = Timer(const Duration(milliseconds: 350), () {
      _checkOtp(channel: 'email', code: code);
    });
  }

  Future<void> _checkOtp({required String channel, required String code}) async {
    final res = await _repo.checkRegisterChannelOtp(
      phone: _phone.text.trim(),
      channel: channel,
      code: code,
    );
    if (!mounted) return;
    final verified = res['verified'] == true;
    setState(() {
      if (channel == 'wa') {
        _waOk = verified;
        _waHint = verified ? 'WhatsApp terverifikasi' : (res['error']?.toString() ?? 'Kode salah');
      } else {
        _emailOk = verified;
        _emailHint = verified
            ? 'Email terverifikasi'
            : (res['error']?.toString() ?? 'Kode salah');
      }
    });
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showMemberDatePicker(
      context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 10, now.month, now.day),
      title: 'Tanggal lahir',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  /// OTP WA cukup nomor; OTP email cukup email (+ nomor sebagai ID draft).
  String? _validateBeforeSend(String channel) {
    if (channel == 'wa') {
      if (_phone.text.trim().length < 9) return 'Isi nomor WhatsApp dulu';
      return null;
    }
    if (!_email.text.trim().contains('@')) return 'Isi email yang valid';
    if (_phone.text.trim().length < 9) {
      return 'Isi nomor WhatsApp dulu (dipakai sebagai ID akun)';
    }
    return null;
  }

  Future<void> _sendChannel(String channel) async {
    final err = _validateBeforeSend(channel);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    try {
      await TenantService.instance.requireResolved(
        slug: isBrandedStoreApk ? null : _slug.text,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
      return;
    }
    setState(() {
      if (channel == 'wa') {
        _sendingWa = true;
      } else {
        _sendingEmail = true;
      }
    });
    try {
      final res = await _repo.sendRegisterChannelOtp(
        channel: channel,
        phone: _phone.text.trim(),
        password: _pass.text,
        email: _email.text.trim(),
        tanggalLahir: _dob,
        nama: _nama.text.trim(),
      );
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Gagal kirim OTP'}'),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
      setState(() {
        if (channel == 'wa') {
          _waOtpVisible = true;
          _waOk = null;
          _waOtp.clear();
          _waDebug = res['debug_otp']?.toString();
          _waHint = res['sent'] == true
              ? 'Kode dikirim ke WhatsApp'
              : 'Pakai kode debug (gateway belum siap)';
        } else {
          _emailOtpVisible = true;
          _emailOk = null;
          _emailOtp.clear();
          _emailDebug = res['debug_otp']?.toString();
          _emailHint = res['sent'] == true
              ? 'Kode dikirim ke email'
              : 'Pakai kode debug (gateway belum siap)';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _sendingWa = false;
          _sendingEmail = false;
        });
      }
    }
  }

  Future<void> _createAccount() async {
    if (!_canCreate) return;
    setState(() => _busyCreate = true);
    try {
      await TenantService.instance.requireResolved(
        slug: isBrandedStoreApk ? null : _slug.text,
      );
      final res = await _repo.finalizeRegister(
        phone: _phone.text.trim(),
        password: _pass.text,
        email: _email.text.trim(),
        tanggalLahir: _dob,
        nama: _nama.text.trim(),
      );
      if (!mounted) return;
      if (res['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['error'] ?? 'Gagal buat akun'}'),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akun berhasil dibuat. Silakan masuk.'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
      // Kembali ke login (jangan auto-login)
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } finally {
      if (mounted) setState(() => _busyCreate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dob == null
        ? 'Pilih tanggal lahir'
        : DateFormat('dd/MM/yyyy').format(_dob!);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F1FF),
              OptikMemberTokens.canvas,
              Colors.white,
            ],
            stops: [0, 0.35, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: OptikMemberTokens.blueDeep),
                    ),
                    Expanded(
                      child: Text(
                        'Daftar Member ${BrandService.name}',
                        style: const TextStyle(
                          color: OptikMemberTokens.blueDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            OptikMemberTokens.blue.withOpacity(0.12),
                            OptikMemberTokens.blueSoft,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: OptikMemberTokens.blue.withOpacity(0.18),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_outlined,
                              color: OptikMemberTokens.blue),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'OTP WA / email bisa dikirim dulu (cukup isi nomor & email). '
                              'Tombol Bikin akun baru aktif kalau semua data terisi '
                              'dan OTP WhatsApp + email sudah valid.',
                              style: TextStyle(
                                color: OptikMemberTokens.inkSecondary,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isBrandedStoreApk) ...[
                            _field(
                              controller: _slug,
                              label: 'Kode usaha',
                              icon: Icons.storefront_outlined,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _field(
                            controller: _nama,
                            label: 'Nama lengkap',
                            icon: Icons.badge_outlined,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 12),
                          _channelBlock(
                            label: 'WhatsApp',
                            icon: Icons.phone_android_rounded,
                            controller: _phone,
                            keyboard: TextInputType.phone,
                            formatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+]')),
                            ],
                            sendLabel: 'Kirim OTP',
                            sending: _sendingWa,
                            onSend: () => _sendChannel('wa'),
                            otpVisible: _waOtpVisible,
                            otpController: _waOtp,
                            verified: _waOk,
                            hint: _waHint,
                            debugOtp: _waDebug,
                          ),
                          const SizedBox(height: 12),
                          _channelBlock(
                            label: 'Email',
                            icon: Icons.email_outlined,
                            controller: _email,
                            keyboard: TextInputType.emailAddress,
                            sendLabel: 'Kirim OTP',
                            sending: _sendingEmail,
                            onSend: () => _sendChannel('email'),
                            otpVisible: _emailOtpVisible,
                            otpController: _emailOtp,
                            verified: _emailOk,
                            hint: _emailHint,
                            debugOtp: _emailDebug,
                          ),
                          const SizedBox(height: 12),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _pickDob,
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: _dec(
                                  label: 'Tanggal lahir *',
                                  icon: Icons.cake_outlined,
                                  suffix: const Icon(
                                    Icons.calendar_month_rounded,
                                    color: OptikMemberTokens.blue,
                                  ),
                                ),
                                child: Text(
                                  dobLabel,
                                  style: TextStyle(
                                    color: _dob == null
                                        ? OptikMemberTokens.inkMuted
                                        : OptikMemberTokens.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _field(
                            controller: _pass,
                            label: 'Password *',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscure,
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
                          const SizedBox(height: 12),
                          _field(
                            controller: _pass2,
                            label: 'Ulangi password *',
                            icon: Icons.lock_rounded,
                            obscure: _obscure,
                          ),
                          const SizedBox(height: 20),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: _canCreate
                                  ? const LinearGradient(
                                      colors: [
                                        OptikMemberTokens.blue,
                                        OptikMemberTokens.blueDeep,
                                      ],
                                    )
                                  : null,
                              color: _canCreate
                                  ? null
                                  : OptikMemberTokens.lineSoft,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _canCreate ? _createAccount : null,
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  height: 52,
                                  child: Center(
                                    child: _busyCreate
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            'Bikin akun',
                                            style: TextStyle(
                                              color: _canCreate
                                                  ? Colors.white
                                                  : OptikMemberTokens.inkMuted,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!_canCreate) ...[
                            const SizedBox(height: 10),
                            Text(
                              () {
                                final missingOtp =
                                    _waOk != true || _emailOk != true;
                                if (!_formCoreValid && missingOtp) {
                                  return 'Lengkapi data + verifikasi OTP WA & email.';
                                }
                                if (!_formCoreValid) {
                                  return 'Lengkapi nama, tanggal lahir & password cocok.';
                                }
                                return 'Verifikasi OTP WhatsApp dan email dulu.';
                              }(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: OptikMemberTokens.inkMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
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

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: [
          BoxShadow(
            color: OptikMemberTokens.blueDeep.withOpacity(0.07),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  InputDecoration _dec({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: OptikMemberTokens.blue),
      suffixIcon: suffix,
      filled: true,
      fillColor: OptikMemberTokens.blueMist,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: OptikMemberTokens.lineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: OptikMemberTokens.lineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: OptikMemberTokens.blue, width: 1.6),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    Widget? suffix,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscure,
      textCapitalization: textCapitalization,
      decoration: _dec(label: label, icon: icon, suffix: suffix),
    );
  }

  Widget _channelBlock({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String sendLabel,
    required bool sending,
    required VoidCallback onSend,
    required bool otpVisible,
    required TextEditingController otpController,
    required bool? verified,
    String? hint,
    String? debugOtp,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    Color statusColor = OptikMemberTokens.inkMuted;
    IconData statusIcon = Icons.radio_button_unchecked;
    if (verified == true) {
      statusColor = OptikMemberTokens.success;
      statusIcon = Icons.check_circle_rounded;
    } else if (verified == false) {
      statusColor = OptikMemberTokens.danger;
      statusIcon = Icons.cancel_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboard,
                inputFormatters: formatters,
                decoration: _dec(label: '$label *', icon: icon),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: IntrinsicWidth(
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: OptikMemberTokens.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: sending ? null : onSend,
                    child: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            sendLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (otpVisible) ...[
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: verified == true
                  ? OptikMemberTokens.success.withOpacity(0.08)
                  : verified == false
                      ? OptikMemberTokens.danger.withOpacity(0.06)
                      : OptikMemberTokens.blueMist,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: verified == true
                    ? OptikMemberTokens.success.withOpacity(0.35)
                    : verified == false
                        ? OptikMemberTokens.danger.withOpacity(0.35)
                        : OptikMemberTokens.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  maxLength: 6,
                  style: const TextStyle(
                    letterSpacing: 4,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'Kode OTP $label',
                    hintText: 'Ketik 6 digit di sini',
                    prefixIcon: Icon(statusIcon, color: statusColor),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (debugOtp != null && verified != true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Belum lewat WA/email — pakai kode debug dulu:',
                    style: TextStyle(
                      color: OptikMemberTokens.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () {
                      otpController.text = debugOtp;
                      otpController.selection = TextSelection.collapsed(
                        offset: debugOtp.length,
                      );
                    },
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: Text(
                      'Isi kode $debugOtp',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
