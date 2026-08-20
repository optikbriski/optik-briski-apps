import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../shared/theme.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/liveness_result.dart';
import '../../shared/karyawan/karyawan_jabatan.dart';
import '../../shared/ktp/ktp_capture_page.dart';
import '../../shared/ktp/ktp_ocr_service.dart';
import '../../shared/liveness_camera_page.dart';
import '../../shared/widgets/app_loading_overlay.dart';
import 'login_karyawan_page.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/tenant/tenant_service.dart';

// MESIN AUTO-CAPSLOCK AWAL KATA
class CapitalizeEachWordFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final words = newValue.text.split(' ');
    final capitalized = words.map((word) {
      if (word.isEmpty) return "";
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
    return TextEditingValue(text: capitalized, selection: newValue.selection);
  }
}

// MESIN PEMAKSA HURUF BESAR (UPPERCASE)
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class RegisterKaryawanPage extends StatefulWidget {
  const RegisterKaryawanPage({super.key});

  @override
  State<RegisterKaryawanPage> createState() => _RegisterKaryawanPageState();
}

class _RegisterKaryawanPageState extends State<RegisterKaryawanPage> {
  // CONTROLLER FORM DATA DIRI
  final formKey = GlobalKey<FormState>();
  final _nikCtrl = TextEditingController();
  final _slugCtrl = TextEditingController(text: TenantService.instance.slug);
  final _namaCtrl = TextEditingController();
  final _alamatKtpCtrl = TextEditingController();
  final _ttlCtrl = TextEditingController();
  final _golDarahCtrl = TextEditingController();
  final _agamaCtrl = TextEditingController();
  final _statusKawinCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _umurCtrl = TextEditingController();
  final _jalanCtrl = TextEditingController();

  // KTP OCR
  final _ktpOcr = KtpOcrService();
  final _picker = ImagePicker();
  bool _ktpScanned = false;
  bool _ktpScanning = false;
  bool _submitting = false;
  File? _ktpFile;
  /// `fisik` = scan kamera grid; `ikd` = upload file IKD saja.
  String? _ktpSumber;
  String? _nikOcr;
  String? _namaOcr;
  String? _alamatKtpOcr;
  String? _ttlOcr;
  String? _genderOcr;
  String? _golDarahOcr;
  String? _agamaOcr;
  String? _statusKawinOcr;
  String? _alamatJalanKtp;
  String? _rtRwKtp;
  String? _kelDesaKtp;
  String? _kecamatanKtp;
  String? _tempatLahirKtp;
  String? _tanggalLahirKtp;
  String? _pekerjaanKtp;
  String? _kewarganegaraanKtp;
  bool _editNik = false;
  bool _editNama = false;
  bool _editAlamatKtp = false;
  bool _editTtl = false;
  bool _editGolDarah = false;
  bool _editAgama = false;
  bool _editStatusKawin = false;
  final pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  final _daruratNamaCtrl = TextEditingController();
  final _daruratWaCtrl = TextEditingController();

  // OTP email inline
  bool _showOtpField = false;
  bool _emailVerified = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _canResendOtp = false;
  int _otpCooldown = 0;
  Timer? _otpTimer;
  String? _otpEmailSentTo;

  // CONTROLLER PASSWORD AKUN
  final passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _isPasswordObscure = true;
  bool _isConfirmObscure = true;

  final TextEditingController namaBankCtrl = TextEditingController();
  final TextEditingController _noRekeningCtrl = TextEditingController();

  //--- VARIABEL VALIDASI PASSWORD
  Color _passwordColor = Colors.grey;
  String _passwordFeedback = '';
  bool isPasswordValid = false;
  Color _confirmColor = Colors.grey;
  String _confirmFeedback = "";
  bool isConfirmValid = false;

  // MESIN DIKTE PASSWORD (REAL-TIME)
  void validasiPassword(String value) {
    setState(() {
      if (value.isEmpty) {
        _passwordColor = Colors.grey;
        _passwordFeedback = "reg_pwd_hint".tr();
        isPasswordValid = false;
        return;
      }

      // Detektor Aturan
      bool hasMinMax = value.length >= 8 && value.length <= 15;
      bool hasUpper = value.contains(RegExp(r'[A-Z]'));
      bool hasLower = value.contains(RegExp(r'[a-z]'));
      bool hasNumber = value.contains(RegExp(r'[0-9]'));
      bool hasSpecial = value.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));

      // Mencatat kekurangan
      List<String> missing = [];
      if (!hasMinMax) {
        missing.add(
            value.length < 8 ? "minimal 8 karakter" : "maksimal 15 karakter");
      }
      if (!hasUpper) missing.add("huruf besar");
      if (!hasLower) missing.add("huruf kecil");
      if (!hasNumber) missing.add("angka");
      if (!hasSpecial) missing.add("simbol");

      if (missing.isEmpty) {
        _passwordColor = OptikKaryawanTokens.seasideMid;
        _passwordFeedback = "reg_pwd_valid".tr();
        isPasswordValid = true;
      } else {
        isPasswordValid = false;
        String dictation = "${"reg_pwd_kurang".tr()}${missing.join(', ')}.";
        if (value.length >= 8 && missing.length <= 2) {
          _passwordColor = Colors.orange;
          _passwordFeedback = "${"reg_pwd_sedikit".tr()}$dictation";
        } else {
          _passwordColor = Colors.redAccent;
          _passwordFeedback = "${"reg_pwd_lemah".tr()}$dictation";
        }
      }
      // Otomatis cek ulang konfirmasi password
      _validasiConfirmPassword(_confirmPasswordCtrl.text);
    });
  }

  // MESIN CEK KONFIRMASI (SIMPEL)
  void _validasiConfirmPassword(String value) {
    setState(() {
      if (value.isEmpty) {
        _confirmFeedback = "";
        isConfirmValid = false;
        _confirmColor = Colors.grey;
      } else if (value == passwordCtrl.text) {
        _confirmColor = OptikKaryawanTokens.seasideMid;
        _confirmFeedback = "reg_pwd_match".tr();
        isConfirmValid = true;
      } else {
        _confirmColor = Colors.redAccent;
        _confirmFeedback = "reg_pwd_mismatch".tr();
        isConfirmValid = false;
      }
    });
  }

  // DROPDOWN STATE
  String? gender;
  String? jabatan;
  String? _cabang;
  DateTime? _tanggalMulai;
  String? _hubunganDarurat;
  final List<String> pilihanHubungan = ['Orang Tua', 'Saudara', 'Sahabat'];

  // ALAMAT CASCADING STATE
  List<dynamic> _listProvinsi = [];
  List<dynamic> _listKota = [];
  List<dynamic> _listKecamatan = [];
  List<dynamic> _listDesa = [];

  String? _idProvinsi, _namaProvinsi;
  String? _idKota, _namaKota;
  String? _idKecamatan, _namaKecamatan;
  String? _idDesa, _namaDesa;

  // BIOMETRIK STATE
  bool isFaceVerified = false;
  LivenessCaptureResult? _faceCapture;

  // Penampung cabang dinamis database Supabase
  List<Map<String, dynamic>> _listToko = [];
  bool _isLoadingToko = true;

  @override
  void initState() {
    super.initState();
    _passwordFeedback = "reg_pwd_hint".tr();
    _ttlCtrl.addListener(_sinkronUmurDariTtl);
    _fetchProvinsi();
    _fetchDaftarToko();
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _ttlCtrl.removeListener(_sinkronUmurDariTtl);
    _nikCtrl.dispose();
    _slugCtrl.dispose();
    _namaCtrl.dispose();
    _alamatKtpCtrl.dispose();
    _ttlCtrl.dispose();
    _golDarahCtrl.dispose();
    _agamaCtrl.dispose();
    _statusKawinCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _waCtrl.dispose();
    _umurCtrl.dispose();
    _jalanCtrl.dispose();
    pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _daruratNamaCtrl.dispose();
    _daruratWaCtrl.dispose();
    passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    namaBankCtrl.dispose();
    _noRekeningCtrl.dispose();
    _ktpOcr.dispose();
    super.dispose();
  }

  /// KTP fisik: hanya kamera + grid, auto jepret saat fokus/terdeteksi.
  Future<void> _scanKtpFisik() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Scan KTP fisik hanya di HP Android/iOS.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _ktpScanning = true);
    try {
      final captured = await Navigator.push<File>(
        context,
        MaterialPageRoute(builder: (_) => const KtpCapturePage()),
      );
      if (captured == null) return;
      await _applyKtpFile(captured, sumber: 'fisik');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal scan KTP: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _ktpScanning = false);
    }
  }

  /// Upload hanya untuk file/gambar dari app IKD (bukan foto KTP fisik).
  Future<void> _uploadIkd() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Upload IKD hanya di HP Android/iOS.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload dari IKD'),
        content: const Text(
          'Cuma bisa upload e-KTP dari aplikasi IKD.\n\n'
          'Foto KTP fisik, foto random, atau screenshot lain akan ditolak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pilih file IKD'),
          ),
        ],
      ),
    );
    if (setuju != true || !mounted) return;

    setState(() => _ktpScanning = true);
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 98,
        maxWidth: 2800,
      );
      if (x == null) return;
      final file = File(x.path);
      final result = await _ktpOcr.scanFile(file);
      if (!mounted) return;

      if (_terlihatKtpFisikBukanIkd(result.rawText)) {
        await _dialogTolakUpload(
          'Terdeteksi foto KTP fisik.\n\n'
          'Cuma bisa upload e-KTP dari aplikasi IKD.\n'
          'Untuk KTP fisik, pakai Scan KTP fisik (kamera + grid).',
        );
        return;
      }

      // Tolak foto random / bukan e-KTP IKD (harus NIK + data identitas terbaca).
      if (!_terlihatSepertiEktpIkd(result)) {
        await _dialogTolakUpload(
          'File tidak dikenali sebagai e-KTP dari aplikasi IKD.\n\n'
          'Foto random, selfie, atau screenshot lain ditolak.\n'
          'Upload ulang file/gambar e-KTP dari app IKD.',
        );
        return;
      }

      await _applyKtpFile(file, sumber: 'ikd', precomputed: result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal upload IKD: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _ktpScanning = false);
    }
  }

  Future<void> _dialogTolakUpload(String pesan) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikKaryawanTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: OptikKaryawanTokens.border),
        ),
        title: const Text(
          'Upload ditolak',
          style: TextStyle(color: OptikKaryawanTokens.ink, fontWeight: FontWeight.bold),
        ),
        content: Text(
          pesan,
          style: const TextStyle(color: OptikKaryawanTokens.muted, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  bool _adaPenandaIkd(String raw) {
    final u = raw.toUpperCase();
    return u.contains('IDENTITAS KEPENDUDUKAN DIGITAL') ||
        RegExp(r'\bIKD\b').hasMatch(u) ||
        u.contains('KEMENDAGRI') ||
        u.contains('DUKCAPIL') ||
        u.contains('KTP DIGITAL') ||
        u.contains('IDENTITAS DIGITAL');
  }

  /// True jika gambar terlihat KTP fisik (bukan e-KTP dari app IKD).
  bool _terlihatKtpFisikBukanIkd(String raw) {
    if (_adaPenandaIkd(raw)) return false;

    final u = raw.toUpperCase();
    final adaFisikKlasik = u.contains('PROVINSI') ||
        u.contains('KABUPATEN') ||
        u.contains('KOTA ') ||
        u.contains('BERLAKU HINGGA') ||
        u.contains('SEUMUR HIDUP') ||
        (u.contains('NIK') &&
            u.contains('AGAMA') &&
            (u.contains('KEWARGANEGARAAN') || u.contains('STATUS PERKAWINAN')));
    return adaFisikKlasik;
  }

  /// Foto random ditolak: wajib NIK + cukup field identitas (dan/atau penanda IKD).
  bool _terlihatSepertiEktpIkd(KtpOcrResult r) {
    if (!r.hasNik || r.nama.trim().length < 3) return false;
    if (_adaPenandaIkd(r.rawText)) return true;
    // Screenshot e-KTP kadang tanpa teks "IKD" — tetap wajib data inti terbaca.
    return r.filledFieldCount >= 5 &&
        r.tempatTglLahir.isNotEmpty &&
        (r.alamat.isNotEmpty || r.agama.isNotEmpty);
  }

  void _sinkronUmurDariTtl() {
    final umur = KtpOcrResult.hitungUmurDariTeks(_ttlCtrl.text);
    _umurCtrl.text = umur != null ? '$umur' : '';
  }

  Future<void> _applyKtpFile(
    File file, {
    required String sumber,
    KtpOcrResult? precomputed,
  }) async {
    final result = precomputed ?? await _ktpOcr.scanFile(file);
    if (!mounted) return;
    if (!result.hasNik || result.filledFieldCount < 4) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          !result.hasNik
              ? sumber == 'ikd'
                  ? 'NIK tidak terbaca dari file IKD. Pastikan gambar jelas, atau lengkapi manual.'
                  : 'NIK 16 digit tidak terbaca. Sejajarkan KTP di grid sampai auto-jepret, atau lengkapi manual.'
              : 'Beberapa data kurang terbaca. Cek & edit field yang kosong, atau ulangi.',
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ));
    }
    setState(() {
      _ktpFile = file;
      _ktpScanned = true;
      _ktpSumber = sumber;
      _nikOcr = result.nik;
      _namaOcr = result.nama;
      _alamatKtpOcr = result.alamat;
      _ttlOcr = result.tempatTglLahir;
      _genderOcr = result.jenisKelamin;
      _golDarahOcr = result.golonganDarah;
      _agamaOcr = result.agama;
      _statusKawinOcr = result.statusPerkawinan;
      _alamatJalanKtp = result.alamatJalan;
      _rtRwKtp = result.rtRw;
      _kelDesaKtp = result.kelDesa;
      _kecamatanKtp = result.kecamatan;
      _tempatLahirKtp = result.tempatLahir;
      _tanggalLahirKtp = result.tanggalLahir;
      _pekerjaanKtp = result.pekerjaan;
      _kewarganegaraanKtp = result.kewarganegaraan;
      _nikCtrl.text = result.nik;
      _namaCtrl.text = result.nama;
      _alamatKtpCtrl.text = result.alamat;
      _ttlCtrl.text = result.tempatTglLahir;
      _golDarahCtrl.text = result.golonganDarah;
      _agamaCtrl.text = result.agama;
      _statusKawinCtrl.text = result.statusPerkawinan;
      if (result.genderCode.isNotEmpty) gender = result.genderCode;
      _sinkronUmurDariTtl();
      if (_jalanCtrl.text.trim().isEmpty) {
        final jalan = result.alamatJalan.isNotEmpty
            ? result.alamatJalan
            : result.alamat;
        if (jalan.isNotEmpty) _jalanCtrl.text = jalan;
      }
      _editNik = false;
      _editNama = false;
      _editAlamatKtp = false;
      _editTtl = false;
      _editGolDarah = false;
      _editAgama = false;
      _editStatusKawin = false;
    });
  }

  Widget _editSuffix(bool editing, VoidCallback onEdit) {
    return IconButton(
      tooltip: editing ? 'Sedang bisa diedit' : 'Edit jika OCR salah',
      onPressed: onEdit,
      icon: Icon(
        editing ? Icons.lock_open_rounded : Icons.edit_rounded,
        color: editing ? Colors.orange : OptikKaryawanTokens.navyMid,
        size: 20,
      ),
    );
  }

  bool _emailFormatOk(String email) {
    final e = email.trim().toLowerCase();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);
  }

  String get _normalizedEmail => _emailCtrl.text.trim().toLowerCase();

  void _resetOtpState() {
    _otpTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showOtpField = false;
      _emailVerified = false;
      _sendingOtp = false;
      _verifyingOtp = false;
      _canResendOtp = false;
      _otpCooldown = 0;
      _otpEmailSentTo = null;
      _otpCtrl.clear();
    });
  }

  void _startOtpCooldown([int seconds = 60]) {
    _otpTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _canResendOtp = false;
      _otpCooldown = seconds;
    });
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_otpCooldown <= 1) {
        t.cancel();
        setState(() {
          _otpCooldown = 0;
          _canResendOtp = true;
        });
      } else {
        setState(() => _otpCooldown--);
      }
    });
  }

  /// Cek surel/NIK sudah ada di tabel karyawan.
  /// [failClosed] = true → error baca DB dilempar (submit wajib aman).
  Future<String?> _findRegisterConflict({
    String? email,
    String? nik,
    bool failClosed = false,
  }) async {
    final client = Supabase.instance.client;
    try {
      if (email != null && email.isNotEmpty) {
        final row = await client
            .from('karyawan')
            .select('id')
            .ilike('email', email)
            .limit(1)
            .maybeSingle();
        if (row != null) return 'email';
      }
      if (nik != null && nik.isNotEmpty) {
        final row = await client
            .from('karyawan')
            .select('id')
            .eq('nik', nik)
            .limit(1)
            .maybeSingle();
        if (row != null) return 'nik';
      }
    } on PostgrestException catch (e) {
      debugPrint('register conflict check: $e');
      if (failClosed) rethrow;
    } catch (e) {
      debugPrint('register conflict check: $e');
      if (failClosed) rethrow;
    }
    return null;
  }

  bool _isLikelyMissingColumnError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('column') ||
        raw.contains('schema cache') ||
        raw.contains('pgrst204') ||
        raw.contains('does not exist');
  }

  Future<void> _kirimOtpEmail() async {
    if (_sendingOtp || _verifyingOtp || _submitting) return;
    final email = _normalizedEmail;
    if (!_emailFormatOk(email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("reg_err_email".tr()),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    if (_emailVerified &&
        (_otpEmailSentTo ?? '').toLowerCase() == email) {
      return;
    }

    if (_emailCtrl.text.trim() != email) {
      _emailCtrl.value = TextEditingValue(
        text: email,
        selection: TextSelection.collapsed(offset: email.length),
      );
    }

    setState(() => _sendingOtp = true);
    try {
      final conflict = await _findRegisterConflict(email: email);
      if (!mounted) return;
      if (conflict == 'email') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_err_email_terdaftar".tr()),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ));
        return;
      }

      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() {
        _showOtpField = true;
        _emailVerified = false;
        _otpEmailSentTo = email;
      });
      _startOtpCooldown();
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
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final friendly = (msg.contains('sending confirmation email') ||
              msg.contains('error sending') ||
              msg.contains('smtp'))
          ? "reg_err_otp_email_server".tr()
          : (e.message.isNotEmpty
              ? "${"otp_gagal_resend".tr()}${e.message}"
              : "otp_gagal_resend".tr());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendly),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      final friendly = (raw.contains('sending confirmation email') ||
              raw.contains('error sending'))
          ? "reg_err_otp_email_server".tr()
          : "${"otp_gagal_resend".tr()}$e";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendly),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifikasiOtpInline() async {
    if (_verifyingOtp || _sendingOtp || _submitting) return;
    final email = _normalizedEmail;
    final token = _otpCtrl.text.trim();
    if (token.length < 6 || token.length > 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("otp_err_digit".tr()),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    if (!_emailFormatOk(email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("reg_err_email".tr()),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _verifyingOtp = true);
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      if (!mounted) return;
      if (res.session == null || res.user == null) {
        throw const AuthException('OTP tidak valid');
      }
      setState(() {
        _emailVerified = true;
        _otpEmailSentTo = email;
        _showOtpField = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "reg_email_terverifikasi".tr(),
          style: const TextStyle(
            color: OptikKaryawanTokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: OptikKaryawanTokens.cyan,
      ));
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
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  // FUNGSI TARIK DAFTAR CABANG MASTER DARI DATABASE
  Future<void> _fetchDaftarToko() async {
    try {
      await TenantService.instance.requireResolved(slug: _slugCtrl.text);
      final data = await Supabase.instance.client.rpc(
        'list_tenant_stores',
        params: withTenant({}),
      );
      final list = <Map<String, dynamic>>[];
      if (data is List) {
        for (final e in data) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) {
        setState(() {
          _listToko = list;
          _isLoadingToko = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal load daftar toko: $e");
      if (mounted) setState(() => _isLoadingToko = false);
    }
  }

  String? get _namaCabangTerpilih {
    if (_cabang == null) return null;
    for (final t in _listToko) {
      if (t['id']?.toString() == _cabang) {
        return t['toko_id']?.toString();
      }
    }
    return _cabang;
  }

  Future<void> _tampilkanPilihCabang() async {
    if (_isLoadingToko) return;
    if (_listToko.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Daftar cabang kosong. Coba muat ulang.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _listToko
                : _listToko.where((t) {
                    final nama = (t['toko_id'] ?? '').toString().toLowerCase();
                    final id = (t['id'] ?? '').toString().toLowerCase();
                    return nama.contains(q) || id.contains(q);
                  }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "reg_label_cabang".tr(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      color: _ink,
                                    ),
                                  ),
                                  Text(
                                    'Ketik untuk mencari di ${filtered.length} cabang',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded,
                                  color: _muted),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          autofocus: true,
                          onChanged: (v) => setModal(() => query = v),
                          decoration: InputDecoration(
                            hintText: 'Cari nama cabang / toko…',
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: _navyMid),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: _navyMid, width: 1.4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'Tidak ada cabang cocok',
                                  style: TextStyle(color: _muted),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(
                                    16, 4, 16, 20),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final toko = filtered[i];
                                  final id = toko['id'].toString();
                                  final nama = toko['toko_id'].toString();
                                  final selected = id == _cabang;
                                  return Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => Navigator.pop(ctx, id),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: selected
                                                ? _navyMid
                                                : const Color(0xFFE2E8F0),
                                            width: selected ? 1.4 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              selected
                                                  ? Icons.check_circle_rounded
                                                  : Icons.storefront_outlined,
                                              color: selected
                                                  ? _navyMid
                                                  : _muted,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                nama,
                                                style: TextStyle(
                                                  fontWeight: selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: _ink,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _cabang = selected);
    }
  }

  // FUNGSI TARIK DATA ALAMAT (API GRATIS EMSIFA)
  Future<void> _fetchProvinsi() async {
    try {
      final response = await http.get(Uri.parse(
          'https://www.emsifa.com/api-wilayah-indonesia/api/provinces.json'));
      if (response.statusCode == 200) {
        if (mounted) setState(() => _listProvinsi = json.decode(response.body));
      }
    } catch (e) {
      debugPrint("Gagal load provinsi: $e");
    }
  }

  Future<void> _fetchKota(String idProv) async {
    try {
      final response = await http.get(Uri.parse(
          'https://www.emsifa.com/api-wilayah-indonesia/api/regencies/$idProv.json'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _listKota = json.decode(response.body);
            _idKota = null;
            _idKecamatan = null;
            _idDesa = null;
            _listKecamatan = [];
            _listDesa = [];
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal load kota: $e");
    }
  }

  Future<void> _fetchKecamatan(String idKota) async {
    try {
      final response = await http.get(Uri.parse(
          'https://www.emsifa.com/api-wilayah-indonesia/api/districts/$idKota.json'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _listKecamatan = json.decode(response.body);
            _idKecamatan = null;
            _idDesa = null;
            _listDesa = [];
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal load kecamatan: $e");
    }
  }

  Future<void> _fetchDesa(String idKec) async {
    try {
      final response = await http.get(Uri.parse(
          'https://www.emsifa.com/api-wilayah-indonesia/api/villages/$idKec.json'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _listDesa = json.decode(response.body);
            _idDesa = null;
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal load desa: $e");
    }
  }

  bool get _showBusyOverlay =>
      _ktpScanning || _submitting || _sendingOtp || _verifyingOtp;

  String get _busyOverlayMessage {
    if (_submitting) return 'Mengirim pendaftaran…';
    if (_ktpScanning) return 'Memproses KTP / IKD…';
    if (_sendingOtp) return 'Mengirim OTP…';
    if (_verifyingOtp) return 'Memverifikasi OTP…';
    return 'Memproses…';
  }

  String get _busyOverlaySubtitle {
    if (_submitting) return 'Upload data & foto — jangan tutup aplikasi';
    if (_ktpScanning) return 'Membaca data, mohon tunggu sebentar';
    if (_sendingOtp || _verifyingOtp) return 'Menghubungi server email';
    return 'Mohon tunggu, jangan tutup aplikasi';
  }

  // FUNGSI SUBMIT PENDAFTARAN
  Future<void> submitPendaftaran() async {
    if (_submitting || _ktpScanning || _sendingOtp || _verifyingOtp) return;

    // 1. Validasi Wajah (Liveness) — di HP wajib ada foto capture
    if (!isFaceVerified ||
        (!kIsWeb &&
            (_faceCapture == null ||
                _faceCapture!.photoBytes == null ||
                _faceCapture!.photoBytes!.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_err_scan_wajah".tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4)));
      return;
    }

    if (!_ktpScanned || _ktpFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Wajib foto/scan KTP dulu agar data terisi otomatis.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ));
      return;
    }

    // 2. Email harus sudah diverifikasi OTP di form
    final email = _normalizedEmail;
    final authEmail =
        (Supabase.instance.client.auth.currentUser?.email ?? '')
            .trim()
            .toLowerCase();
    if (!_emailVerified ||
        Supabase.instance.client.auth.currentUser == null ||
        (_otpEmailSentTo ?? '').toLowerCase() != email ||
        (authEmail.isNotEmpty && authEmail != email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_err_email_belum_otp".tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4)));
      return;
    }

    // 3. Validasi Tanggal Mulai
    if (_tanggalMulai == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_err_tgl_mulai".tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4)));
      return;
    }

    // 4. Validasi Form Kosong
    final formState = formKey.currentState;
    if (formState == null || !formState.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("reg_ditolak_kosong".tr()),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    if (!isPasswordValid || !isConfirmValid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("reg_err_password_syarat".tr()),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    if (_cabang == null || (jabatan ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("reg_ditolak_kosong".tr()),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        throw const AuthException('Sesi OTP hilang. Verifikasi email ulang.');
      }

      final nik = _nikCtrl.text.trim();
      try {
        final conflict = await _findRegisterConflict(
          email: email,
          nik: nik,
          failClosed: true,
        );
        if (conflict == 'email') {
          throw AuthException("reg_err_email_terdaftar".tr());
        }
        if (conflict == 'nik') {
          throw AuthException("reg_err_nik_terdaftar".tr());
        }
      } on AuthException {
        rethrow;
      } on PostgrestException {
        throw AuthException("reg_err_cek_data".tr());
      } catch (_) {
        throw AuthException("reg_err_cek_data".tr());
      }

      // Set password setelah email terverifikasi (OTP dulu, password belakangan)
      await client.auth.updateUser(
        UserAttributes(password: passwordCtrl.text),
      );

      String? ktpUrl;
      final bytes = await _ktpFile!.readAsBytes();
      final path =
          '$uid/ktp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await client.storage.from('ktp_photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      ktpUrl = client.storage.from('ktp_photos').getPublicUrl(path);

      // Enroll wajah dari liveness (untuk absensi / approval)
      String? facePhotoUrl;
      final faceBytes = _faceCapture?.photoBytes;
      if (faceBytes != null && faceBytes.isNotEmpty) {
        final facePath =
            '$uid/enroll_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await client.storage.from('attendance_photos').uploadBinary(
              facePath,
              faceBytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        facePhotoUrl =
            client.storage.from('attendance_photos').getPublicUrl(facePath);
      }

      String namaCabangTeks = _cabang?.toString() ?? '';
      final cabangMatch = _listToko.where(
        (e) => e['id']?.toString() == _cabang?.toString(),
      );
      if (cabangMatch.isNotEmpty) {
        namaCabangTeks = cabangMatch.first['toko_id'].toString();
      }

      final alamatDomisili =
          "${_jalanCtrl.text.trim()}, Desa $_namaDesa, Kec. $_namaKecamatan, $_namaKota, $_namaProvinsi";

      final karyawanData = {
        'id': uid,
        'nik': nik,
        'nama': _namaCtrl.text.trim(),
        'nik_ocr': _nikOcr,
        'nama_ocr': _namaOcr,
        'alamat_ktp_ocr': _alamatKtpOcr,
        'alamat_ktp': _alamatKtpCtrl.text.trim(),
        'alamat_jalan_ktp': _alamatJalanKtp,
        'rt_rw': _rtRwKtp,
        'kelurahan_desa': _kelDesaKtp,
        'kecamatan_ktp': _kecamatanKtp,
        'tempat_lahir': _tempatLahirKtp,
        'tanggal_lahir': _tanggalLahirKtp,
        'pekerjaan': _pekerjaanKtp,
        'kewarganegaraan': _kewarganegaraanKtp,
        'tempat_tgl_lahir': _ttlCtrl.text.trim(),
        'tempat_tgl_lahir_ocr': _ttlOcr,
        'golongan_darah': _golDarahCtrl.text.trim(),
        'golongan_darah_ocr': _golDarahOcr,
        'agama': _agamaCtrl.text.trim(),
        'agama_ocr': _agamaOcr,
        'status_perkawinan': _statusKawinCtrl.text.trim(),
        'status_perkawinan_ocr': _statusKawinOcr,
        'gender_ocr': _genderOcr,
        'ktp_sumber': _ktpSumber,
        'ktp_photo_url': ktpUrl,
        if (facePhotoUrl != null) ...{
          'face_photo_url': facePhotoUrl,
          'foto_profile': facePhotoUrl,
          'face_enrolled_at': DateTime.now().toIso8601String(),
          if (_faceCapture?.faceTemplate != null)
            'face_template': _faceCapture!.faceTemplate,
        },
        'email': email,
        'wa': _waCtrl.text.trim(),
        'gender': gender,
        'umur': _umurCtrl.text.trim(),
        'jabatan': (jabatan ?? '').trim(),
        'cabang': namaCabangTeks,
        'toko_id': _cabang,
        'tenant_id': TenantService.instance.boundId,
        'pin_absensi': pinCtrl.text.trim(),
        'alamat_lengkap': alamatDomisili,
        'nama_bank': namaBankCtrl.text.trim().toUpperCase(),
        'no_rekening': _noRekeningCtrl.text.trim(),
        'darurat_nama': _daruratNamaCtrl.text.trim(),
        'darurat_wa': _daruratWaCtrl.text.trim(),
        'darurat_hubungan': _hubunganDarurat,
        'tanggal_mulai': _tanggalMulai?.toIso8601String(),
        'status_approval': 'Menunggu Persetujuan',
      };

      try {
        await client.from('karyawan').upsert(karyawanData);
      } catch (e) {
        // Fallback HANYA untuk kolom KTP yang mungkin belum dimigrasi.
        if (!_isLikelyMissingColumnError(e)) rethrow;
        final fallback = Map<String, dynamic>.from(karyawanData)
          ..removeWhere((k, _) => k.endsWith('_ocr') ||
              k == 'tempat_tgl_lahir' ||
              k == 'golongan_darah' ||
              k == 'agama' ||
              k == 'status_perkawinan' ||
              k == 'alamat_ktp' ||
              k == 'ktp_photo_url' ||
              k == 'darurat_hubungan' ||
              k == 'alamat_jalan_ktp' ||
              k == 'rt_rw' ||
              k == 'kelurahan_desa' ||
              k == 'kecamatan_ktp' ||
              k == 'tempat_lahir' ||
              k == 'tanggal_lahir' ||
              k == 'pekerjaan' ||
              k == 'kewarganegaraan' ||
              k == 'face_photo_url' ||
              k == 'foto_profile' ||
              k == 'face_enrolled_at' ||
              k == 'face_template' ||
              k == 'ktp_sumber');
        final withKtpDetail = {
          ...fallback,
          'alamat_ktp': _alamatKtpCtrl.text.trim(),
          'ktp_photo_url': ktpUrl,
          'nik_ocr': _nikOcr,
          'nama_ocr': _namaOcr,
          'alamat_ktp_ocr': _alamatKtpOcr,
          'darurat_hubungan': _hubunganDarurat,
          'alamat_jalan_ktp': _alamatJalanKtp,
          'rt_rw': _rtRwKtp,
          'kelurahan_desa': _kelDesaKtp,
          'kecamatan_ktp': _kecamatanKtp,
          'tempat_lahir': _tempatLahirKtp,
          'tanggal_lahir': _tanggalLahirKtp,
          'pekerjaan': _pekerjaanKtp,
          'kewarganegaraan': _kewarganegaraanKtp,
          if (facePhotoUrl != null) ...{
            'face_photo_url': facePhotoUrl,
            'foto_profile': facePhotoUrl,
          },
        };
        try {
          await client.from('karyawan').upsert(withKtpDetail);
        } catch (e2) {
          if (!_isLikelyMissingColumnError(e2)) rethrow;
          await client.from('karyawan').upsert({
            ...fallback,
            'alamat_ktp': _alamatKtpCtrl.text.trim(),
            'ktp_photo_url': ktpUrl,
            'nik_ocr': _nikOcr,
            'nama_ocr': _namaOcr,
            'alamat_ktp_ocr': _alamatKtpOcr,
          });
        }
      }
      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('register signOut: $e');
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "reg_sukses_daftar".tr(),
          style: const TextStyle(
            color: OptikKaryawanTokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: OptikKaryawanTokens.cyan,
        duration: const Duration(seconds: 5),
      ));

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginKaryawanPage()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final friendly = msg.contains('password')
          ? "reg_err_password_syarat".tr()
          : (e.message.isNotEmpty ? e.message : "reg_gagal".tr());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${"reg_gagal".tr()}$friendly"),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ));
    } on StorageException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "${"reg_gagal".tr()}${e.message.isNotEmpty ? e.message : 'Upload KTP gagal'}",
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "${"reg_gagal".tr()}${e.message.isNotEmpty ? e.message : e.code ?? ''}",
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ));
    } catch (error) {
      debugPrint('register submit: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${"reg_gagal".tr()}$error"),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _submitting = false);
      }
    }
  }

  static const _navy = OptikKaryawanTokens.navyDeep;
  static const _navyMid = OptikKaryawanTokens.navyMid;
  static const _gold = OptikKaryawanTokens.gold;
  static const _ink = OptikKaryawanTokens.ink;
  static const _muted = OptikKaryawanTokens.muted;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showBusyOverlay,
      child: Scaffold(
        body: AppLoadingOverlay.gate(
          visible: _showBusyOverlay,
          message: _busyOverlayMessage,
          subtitle: _busyOverlaySubtitle,
          child: Container(
        decoration: BoxDecoration(
          gradient: OptikKaryawanTokens.registerBgGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _showBusyOverlay
                          ? null
                          : () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: OptikKaryawanTokens.ink, size: 18),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "reg_title".tr(),
                            style: const TextStyle(
                              color: OptikKaryawanTokens.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            '${BrandService.name} · Onboarding karyawan',
                            style: TextStyle(
                              color: OptikKaryawanTokens.muted.withOpacity(0.95),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _gold.withOpacity(0.45)),
                      ),
                      child: const Text(
                        'SECURE',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
              _buildIntroBanner(),
              const SizedBox(height: 16),

              // ==========================================================
              // 1. VALIDASI BIOMETRIK WAJAH (LIVENESS)
              // ==========================================================
              _buildPremiumCard(
                step: '01',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      icon: Icons.face_retouching_natural_rounded,
                      title: "reg_sec_biometrik".tr(),
                      subtitle: "reg_desc_biometrik".tr(),
                      done: isFaceVerified,
                    ),
                    const SizedBox(height: 16),
                    _primaryActionButton(
                      label: isFaceVerified
                          ? "reg_wajah_terverifikasi".tr()
                          : "reg_btn_scan_wajah".tr(),
                      icon: isFaceVerified
                          ? Icons.verified_rounded
                          : Icons.camera_alt_rounded,
                      success: isFaceVerified,
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const LivenessCameraPage()),
                        );
                        final ok = result == true ||
                            (result is LivenessCaptureResult &&
                                result.success);
                        if (!ok || !mounted) return;
                        setState(() {
                          isFaceVerified = true;
                          _faceCapture = result is LivenessCaptureResult
                              ? result
                              : const LivenessCaptureResult(success: true);
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ==========================================================
              // SCAN KTP (WAJIB — AUTO ISI)
              // ==========================================================
              _buildPremiumCard(
                step: '02',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      icon: Icons.badge_outlined,
                      title: 'Scan KTP',
                      subtitle:
                          'KTP fisik = scan kamera + grid (auto jepret). IKD = upload file dari app IKD saja.',
                      done: _ktpScanned,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            _navyMid.withOpacity(0.06),
                            _gold.withOpacity(0.08),
                          ],
                        ),
                        border: Border.all(
                          color: _ktpScanned
                              ? OptikKaryawanTokens.seasideMid.withOpacity(0.35)
                              : _navyMid.withOpacity(0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_ktpFile != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  Image.file(
                                    _ktpFile!,
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                  if (_ktpScanned)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: OptikKaryawanTokens.seasideMid,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.check,
                                                size: 12,
                                                color: OptikKaryawanTokens.ink),
                                            const SizedBox(width: 4),
                                            Text(
                                              _ktpSumber == 'ikd'
                                                  ? 'IKD OK'
                                                  : 'KTP OK',
                                              style: const TextStyle(
                                                color: OptikKaryawanTokens.ink,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Column(
                                children: [
                                  Icon(Icons.credit_card_rounded,
                                      size: 42,
                                      color: _navyMid.withOpacity(0.45)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Pilih salah satu: scan KTP fisik atau upload IKD',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_ktpScanning)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: LinearProgressIndicator(minHeight: 3),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _ktpScanning ? null : _scanKtpFisik,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _navyMid,
                                    side: BorderSide(
                                        color: _navyMid.withOpacity(0.35)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(
                                      Icons.photo_camera_outlined, size: 18),
                                  label: const Text(
                                    'Scan KTP fisik',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _ktpScanning ? null : _uploadIkd,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _ktpSumber == 'ikd'
                                        ? OptikKaryawanTokens.seasideMid
                                        : _navyMid,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.upload_file_rounded,
                                      size: 18),
                                  label: const Text(
                                    'Upload IKD',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upload cuma e-KTP dari app IKD. '
                            'KTP fisik, foto random, dan screenshot lain ditolak.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ==========================================================
              // 2. IDENTITAS & AKUN MASUK
              // ==========================================================
              _buildPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge, color: OptikKaryawanTokens.navyMid),
                        const SizedBox(width: 10),
                        Text("reg_sec_identitas".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: OptikKaryawanTokens.navyMid)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // INPUT NIK KTP
                    TextFormField(
                      controller: _nikCtrl,
                      readOnly: _ktpScanned && !_editNik,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16)
                      ],
                      decoration: _premiumDecoration(
                        "reg_label_nik".tr(),
                        Icons.credit_card,
                        _ktpScanned
                            ? _editSuffix(_editNik, () {
                                setState(() => _editNik = true);
                              })
                            : null,
                      ),
                      validator: (value) =>
                          (value == null || value.length != 16)
                              ? "reg_err_nik".tr()
                              : null,
                    ),
                    const SizedBox(height: 15),

                    // INPUT NAMA LENGKAP
                    TextFormField(
                      controller: _namaCtrl,
                      readOnly: _ktpScanned && !_editNama,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [CapitalizeEachWordFormatter()],
                      decoration: _premiumDecoration(
                        "isian_nama_lengkap".tr(),
                        Icons.person,
                        _ktpScanned
                            ? _editSuffix(_editNama, () {
                                setState(() => _editNama = true);
                              })
                            : null,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // ALAMAT KTP lengkap (jalan + RT/RW + kel/desa + kec)
                    TextFormField(
                      controller: _alamatKtpCtrl,
                      readOnly: _ktpScanned && !_editAlamatKtp,
                      maxLines: 3,
                      decoration: _premiumDecoration(
                        'Alamat KTP (jalan, RT/RW, kel/desa, kecamatan)',
                        Icons.home_work_outlined,
                        _ktpScanned
                            ? _editSuffix(_editAlamatKtp, () {
                                setState(() => _editAlamatKtp = true);
                              })
                            : null,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _ttlCtrl,
                      readOnly: _ktpScanned && !_editTtl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _premiumDecoration(
                        'Tempat / tanggal lahir',
                        Icons.cake_outlined,
                        _ktpScanned
                            ? _editSuffix(_editTtl, () {
                                setState(() => _editTtl = true);
                              })
                            : null,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _golDarahCtrl,
                            readOnly: _ktpScanned && !_editGolDarah,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _premiumDecoration(
                              'Gol. darah',
                              Icons.water_drop_outlined,
                              _ktpScanned
                                  ? _editSuffix(_editGolDarah, () {
                                      setState(() => _editGolDarah = true);
                                    })
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _agamaCtrl,
                            readOnly: _ktpScanned && !_editAgama,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _premiumDecoration(
                              'Agama',
                              Icons.menu_book_outlined,
                              _ktpScanned
                                  ? _editSuffix(_editAgama, () {
                                      setState(() => _editAgama = true);
                                    })
                                  : null,
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                    ? "reg_err_wajib".tr()
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _statusKawinCtrl,
                      readOnly: _ktpScanned && !_editStatusKawin,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _premiumDecoration(
                        'Status perkawinan',
                        Icons.favorite_border_rounded,
                        _ktpScanned
                            ? _editSuffix(_editStatusKawin, () {
                                setState(() => _editStatusKawin = true);
                              })
                            : null,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // INPUT EMAIL + KIRIM OTP
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            enabled: !_emailVerified &&
                                !_sendingOtp &&
                                !_verifyingOtp &&
                                !_submitting,
                            onChanged: (value) {
                              final next = value.trim().toLowerCase();
                              final sent =
                                  (_otpEmailSentTo ?? '').toLowerCase();
                              if ((_showOtpField || _emailVerified) &&
                                  next != sent) {
                                _resetOtpState();
                              }
                            },
                            decoration: _premiumDecoration(
                              "reg_label_email".tr(),
                              Icons.email,
                              _emailVerified
                                  ? const Icon(Icons.verified_rounded,
                                      color: OptikKaryawanTokens.cyan)
                                  : null,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "reg_err_wajib".tr();
                              }
                              if (!_emailFormatOk(value)) {
                                return "reg_err_email".tr();
                              }
                              if (!_emailVerified) {
                                return "reg_err_email_belum_otp".tr();
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            onPressed: (_sendingOtp ||
                                    _emailVerified ||
                                    (!_canResendOtp &&
                                        _showOtpField &&
                                        _otpCooldown > 0))
                                ? null
                                : _kirimOtpEmail,
                            style: FilledButton.styleFrom(
                              backgroundColor: OptikKaryawanTokens.navyMid,
                              foregroundColor: OptikKaryawanTokens.ink,
                              disabledBackgroundColor: OptikKaryawanTokens.seasideMid,
                              disabledForegroundColor: OptikKaryawanTokens.ink,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _sendingOtp
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: OptikKaryawanTokens.ink,
                                    ),
                                  )
                                : Text(
                                    _emailVerified
                                        ? "reg_btn_otp_ok".tr()
                                        : (_showOtpField && _otpCooldown > 0
                                            ? '${_otpCooldown}s'
                                            : "reg_btn_kirim_otp".tr()),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    if (_showOtpField && !_emailVerified) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_verifyingOtp && !_sendingOtp && !_submitting) {
                            _verifikasiOtpInline();
                          }
                        },
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: _premiumDecoration(
                          "reg_otp_label".tr(),
                          Icons.pin_rounded,
                          _verifyingOtp
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : TextButton(
                                  onPressed: (_verifyingOtp ||
                                          _sendingOtp ||
                                          _submitting)
                                      ? null
                                      : _verifikasiOtpInline,
                                  child: Text(
                                    "otp_btn_verifikasi".tr(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                        validator: (v) {
                          if (_emailVerified) return null;
                          if (v == null || v.length < 6) {
                            return "otp_err_digit".tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "${"otp_desc".tr()}${_otpEmailSentTo ?? _emailCtrl.text}",
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (_emailVerified) ...[
                      const SizedBox(height: 8),
                      Text(
                        "reg_email_terverifikasi".tr(),
                        style: const TextStyle(
                          color: OptikKaryawanTokens.seasideMid,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 15),

                    // INPUT WHATSAPP
                    TextFormField(
                      controller: _waCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _premiumDecoration(
                          "reg_label_wa".tr(), Icons.phone_android, null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // INPUT KATA SANDI (DENGAN DIKTE KEKUATAN)
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: _isPasswordObscure,
                      onChanged: validasiPassword,
                      decoration: _premiumDecoration(
                        "reg_label_password".tr(),
                        Icons.lock,
                        IconButton(
                          icon: Icon(
                            _isPasswordObscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.blueGrey,
                          ),
                          onPressed: () => setState(
                              () => _isPasswordObscure = !_isPasswordObscure),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "reg_err_wajib".tr();
                        }
                        if (!isPasswordValid)
                          return "reg_err_password_syarat".tr();
                        return null;
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text(_passwordFeedback,
                          style: TextStyle(
                              color: _passwordColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),

                    // KONFIRMASI KATA SANDI
                    TextFormField(
                      controller: _confirmPasswordCtrl,
                      obscureText: _isConfirmObscure,
                      onChanged: _validasiConfirmPassword,
                      decoration: _premiumDecoration(
                        "reg_label_confirm_password".tr(),
                        Icons.lock_clock,
                        IconButton(
                          icon: Icon(
                            _isConfirmObscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.blueGrey,
                          ),
                          onPressed: () => setState(
                              () => _isConfirmObscure = !_isConfirmObscure),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "reg_err_wajib".tr();
                        }
                        if (value != passwordCtrl.text) {
                          return "reg_err_password_match".tr();
                        }
                        return null;
                      },
                    ),
                    if (_confirmPasswordCtrl.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(_confirmFeedback,
                            style: TextStyle(
                                color: _confirmColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(height: 15),

                    // GENDER & UMUR (umur otomatis dari TTL / hari ini)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: gender,
                            dropdownColor: Colors.white,
                            items: ["L", "P"]
                                .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                        e == "L"
                                            ? "gender_l".tr()
                                            : "gender_p".tr(),
                                        style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (val) => setState(() => gender = val),
                            decoration: _premiumDecoration(
                                "reg_label_gender".tr(), Icons.wc, null),
                            validator: (value) =>
                                value == null ? "reg_err_pilih".tr() : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _umurCtrl,
                            readOnly: true,
                            enableInteractiveSelection: false,
                            decoration: _premiumDecoration(
                                    'Umur (otomatis)', Icons.cake, null)
                                .copyWith(
                              suffixText: "reg_label_thn".tr(),
                              suffixStyle: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                              helperText: 'Dari tgl lahir, dihitung hari ini',
                              helperMaxLines: 2,
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                    ? 'Isi tempat/tanggal lahir dulu'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              // ==========================================================
              // 3. ALAMAT DOMISILI (CASCADING API)
              // ==========================================================
              _buildPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: OptikKaryawanTokens.navyMid),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Alamat domisili sekarang',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: OptikKaryawanTokens.navyMid),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Boleh beda dari KTP jika sudah pindah. Admin Pusat akan melihat keduanya.',
                      style: TextStyle(color: Colors.grey, fontSize: 11.5),
                    ),
                    const SizedBox(height: 16),

                    // PROVINSI
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      value: _idProvinsi,
                      hint: Text("reg_label_provinsi".tr()),
                      items: _listProvinsi.map((prov) {
                        return DropdownMenuItem<String>(
                          value: prov['id'],
                          child: Text(prov['name'],
                              style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _idProvinsi = val;
                          _namaProvinsi = _listProvinsi
                              .firstWhere((e) => e['id'] == val)['name'];
                        });
                        _fetchKota(val!);
                      },
                      decoration: _premiumDecoration(
                          "reg_label_provinsi".tr(), Icons.map, null),
                      validator: (value) =>
                          value == null ? "reg_err_wajib_pilih".tr() : null,
                    ),
                    const SizedBox(height: 15),

                    // KOTA / KABUPATEN
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      value: _idKota,
                      hint: Text("reg_label_kota".tr()),
                      items: _listKota.map((kota) {
                        return DropdownMenuItem<String>(
                          value: kota['id'],
                          child: Text(kota['name'],
                              style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _idKota = val;
                          _namaKota = _listKota
                              .firstWhere((e) => e['id'] == val)['name'];
                        });
                        _fetchKecamatan(val!);
                      },
                      decoration: _premiumDecoration(
                          "reg_label_kota".tr(), Icons.location_city, null),
                      validator: (value) =>
                          value == null ? "reg_err_wajib_pilih".tr() : null,
                    ),
                    const SizedBox(height: 15),

                    // KECAMATAN
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      value: _idKecamatan,
                      hint: Text("reg_label_kecamatan".tr()),
                      items: _listKecamatan.map((kec) {
                        return DropdownMenuItem<String>(
                          value: kec['id'],
                          child: Text(kec['name'],
                              style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _idKecamatan = val;
                          _namaKecamatan = _listKecamatan
                              .firstWhere((e) => e['id'] == val)['name'];
                        });
                        _fetchDesa(val!);
                      },
                      decoration: _premiumDecoration("reg_label_kecamatan".tr(),
                          Icons.holiday_village, null),
                      validator: (value) =>
                          value == null ? "reg_err_wajib_pilih".tr() : null,
                    ),
                    const SizedBox(height: 15),

                    // DESA / KELURAHAN
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      value: _idDesa,
                      hint: Text("reg_label_desa".tr()),
                      items: _listDesa.map((desa) {
                        return DropdownMenuItem<String>(
                          value: desa['id'],
                          child: Text(desa['name'],
                              style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _idDesa = val;
                          _namaDesa = _listDesa
                              .firstWhere((e) => e['id'] == val)['name'];
                        });
                      },
                      decoration: _premiumDecoration(
                          "reg_label_desa".tr(), Icons.home_work, null),
                      validator: (value) =>
                          value == null ? "reg_err_wajib_pilih".tr() : null,
                    ),
                    const SizedBox(height: 15),

                    // JALAN LENGKAP
                    TextFormField(
                      controller: _jalanCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.words,
                      decoration: _premiumDecoration(
                          "reg_label_jalan".tr(), Icons.signpost, null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // ==========================================================
              // 4. DATA KEPEGAWAIAN (TERMASUK BANK)
              // ==========================================================
              _buildPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.work, color: OptikKaryawanTokens.navyMid),
                        const SizedBox(width: 10),
                        Text("reg_sec_kepegawaian".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: OptikKaryawanTokens.navyMid)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // JABATAN
                    DropdownButtonFormField<String>(
                      value: jabatan,
                      dropdownColor: Colors.white,
                      items: KaryawanJabatan.registerable
                          .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e,
                                  style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (val) => setState(() => jabatan = val),
                      decoration: _premiumDecoration(
                          "reg_label_jabatan".tr(), Icons.assignment_ind, null),
                      validator: (value) =>
                          value == null ? "reg_err_jabatan".tr() : null,
                    ),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: _slugCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: _premiumDecoration(
                        'Kode usaha',
                        Icons.storefront_outlined,
                        null,
                      ),
                      onFieldSubmitted: (_) => _fetchDaftarToko(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Isi kode usaha'
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // CABANG — searchable (banyak toko)
                    FormField<String>(
                      validator: (_) =>
                          _cabang == null ? "reg_err_cabang".tr() : null,
                      builder: (state) {
                        return InkWell(
                          onTap: _isLoadingToko
                              ? null
                              : () async {
                                  await _tampilkanPilihCabang();
                                  state.didChange(_cabang);
                                  state.validate();
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: _premiumDecoration(
                              "reg_label_cabang".tr(),
                              Icons.storefront,
                              const Icon(Icons.search_rounded,
                                  color: OptikKaryawanTokens.navyMid),
                            ).copyWith(errorText: state.errorText),
                            child: Text(
                              _isLoadingToko
                                  ? 'Memuat data cabang...'
                                  : (_namaCabangTerpilih ??
                                      'Cari & pilih cabang penempatan'),
                              style: TextStyle(
                                fontSize: 13,
                                color: _namaCabangTerpilih == null
                                    ? Colors.grey
                                    : Colors.black87,
                                fontWeight: _namaCabangTerpilih == null
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 15),

                    // TANGGAL MASUK KERJA
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tanggal masuk kerja',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: OptikKaryawanTokens.navyMid,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _tanggalMulai ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          helpText: 'Pilih tanggal masuk',
                          cancelText: 'Batal',
                          confirmText: 'Pilih',
                        );
                        if (picked != null) {
                          setState(() => _tanggalMulai = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _tanggalMulai == null
                                ? OptikKaryawanTokens.navyMid.withOpacity(0.25)
                                : OptikKaryawanTokens.seasideMid.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              color: _tanggalMulai == null
                                  ? OptikKaryawanTokens.navyMid
                                  : OptikKaryawanTokens.seasideMid,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _tanggalMulai == null
                                        ? 'Klik untuk pilih tanggal masuk'
                                        : '${_tanggalMulai!.day.toString().padLeft(2, '0')}-${_tanggalMulai!.month.toString().padLeft(2, '0')}-${_tanggalMulai!.year}',
                                    style: TextStyle(
                                      color: _tanggalMulai == null
                                          ? OptikKaryawanTokens.navyMid
                                          : Colors.black87,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_tanggalMulai == null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      "reg_hint_tgl_mulai".tr(),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Colors.black38),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 15),

                    // INFORMASI BANK
                    TextFormField(
                      controller: namaBankCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                      decoration: _premiumDecoration(
                          "reg_label_bank".tr(), Icons.account_balance, null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_bank".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _noRekeningCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _premiumDecoration(
                          "reg_label_rekening".tr(), Icons.numbers, null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_rekening".tr()
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // ==========================================================
              // 5. PIN ABSENSI (6 ANGKA)
              // ==========================================================
              _buildPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pin, color: OptikKaryawanTokens.navyMid),
                        const SizedBox(width: 10),
                        Text("reg_sec_pin".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: OptikKaryawanTokens.navyMid)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6)
                      ],
                      decoration: _premiumDecoration(
                          "reg_label_pin".tr(), Icons.password, null),
                      validator: (value) => (value == null || value.length != 6)
                          ? "reg_err_pin".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _confirmPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6)
                      ],
                      decoration: _premiumDecoration(
                          "reg_label_confirm_pin".tr(), Icons.password, null),
                      validator: (value) {
                        if (value == null || value.length != 6) {
                          return "reg_err_pin".tr();
                        }
                        if (value != pinCtrl.text) {
                          return "reg_err_pin_match".tr();
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              // ==========================================================
              // 6. KONTAK DARURAT
              // ==========================================================
              _buildPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emergency, color: OptikKaryawanTokens.navyMid),
                        const SizedBox(width: 10),
                        Text("reg_sec_darurat".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: OptikKaryawanTokens.navyMid)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // NAMA KONTAK DARURAT
                    TextFormField(
                      controller: _daruratNamaCtrl,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [CapitalizeEachWordFormatter()],
                      decoration: _premiumDecoration(
                          "reg_label_nama_darurat".tr(),
                          Icons.person_outline,
                          null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // WHATSAPP DARURAT
                    TextFormField(
                      controller: _daruratWaCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _premiumDecoration(
                          "reg_label_wa_darurat".tr(), Icons.phone, null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // HUBUNGAN DARURAT
                    DropdownButtonFormField<String>(
                      value: _hubunganDarurat,
                      dropdownColor: Colors.white,
                      items: pilihanHubungan
                          .map((val) => DropdownMenuItem(
                              value: val,
                              child: Text(
                                  val == 'Orang Tua'
                                      ? "reg_darurat_ortu".tr()
                                      : val == 'Saudara'
                                          ? "reg_darurat_saudara".tr()
                                          : "reg_darurat_sahabat".tr(),
                                  style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _hubunganDarurat = val),
                      decoration: _premiumDecoration(
                          "reg_label_hubungan_darurat".tr(),
                          Icons.family_restroom,
                          null),
                      validator: (value) => value == null
                          ? "reg_err_hubungan_darurat".tr()
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ==========================================================
              // TOMBOL SUBMIT PENDAFTARAN
              // ==========================================================
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: OptikKaryawanTokens.goldGradient,
                  boxShadow: [
                    BoxShadow(
                      color: _navyMid.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _showBusyOverlay ? null : submitPendaftaran,
                  icon: const Icon(Icons.arrow_forward_rounded,
                      color: OptikKaryawanTokens.ink, size: 20),
                  label: Text(
                    "reg_btn_kirim".tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: OptikKaryawanTokens.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Data dicek Admin Pusat sebelum akun aktif',
                  style: TextStyle(
                    color: _muted.withOpacity(0.9),
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(height: 36),
                      ],
                    ),
                  ),
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

  Widget _buildIntroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: OptikKaryawanTokens.surface,
        border: Border.all(color: OptikKaryawanTokens.border),
        boxShadow: OptikKaryawanTokens.cardShadow,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lengkapi data dengan teliti',
            style: TextStyle(
              color: OptikKaryawanTokens.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Scan wajah & KTP, verifikasi email, lalu tunggu persetujuan Pusat.',
            style: TextStyle(
              color: OptikKaryawanTokens.muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    bool done = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (done ? OptikKaryawanTokens.seasideMid : _navyMid).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            done ? Icons.check_rounded : icon,
            color: done ? OptikKaryawanTokens.seasideMid : _navyMid,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool success = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: success ? OptikKaryawanTokens.seasideMid : _navyMid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, color: OptikKaryawanTokens.ink, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            color: OptikKaryawanTokens.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // WIDGET HELPER KUSTOM (DESAIN KARTU & TEXT FIELD)
  // ==========================================================
  Widget _buildPremiumCard({required Widget child, String? step}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: _navy.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (step != null)
            Positioned(
              top: 14,
              right: 16,
              child: Text(
                step,
                style: TextStyle(
                  color: _navyMid.withOpacity(0.12),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: child,
          ),
        ],
      ),
    );
  }

  InputDecoration _premiumDecoration(
      String label, IconData icon, Widget? suffix) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted, fontSize: 13),
      prefixIcon: Icon(icon, color: _navyMid.withOpacity(0.7), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF7FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8EEF5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _navyMid, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
    );
  }
}
