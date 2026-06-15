import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; // Aktifkan jika dipakai di sini
import '../shared/liveness_camera_page.dart';
import 'otp_verification_page.dart';
import 'package:easy_localization/easy_localization.dart'; // <-- Senjata Utama

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
  final _namaCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _umurCtrl = TextEditingController();
  final _jalanCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  final _daruratNamaCtrl = TextEditingController();
  final _daruratWaCtrl = TextEditingController();

  // CONTROLLER PASSWORD AKUN
  final passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _isPasswordObscure = true;
  bool _isConfirmObscure = true;

  final TextEditingController namaBankCtrl = TextEditingController();
  final TextEditingController _noRekeningCtrl = TextEditingController();

  //--- VARIABEL VALIDASI PASSWORD
  Color _passwordColor = Colors.grey;
  String _passwordFeedback = "reg_pwd_hint".tr();
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
        _passwordColor = Colors.green;
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
        _confirmColor = Colors.green;
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

  // Penampung cabang dinamis database Supabase
  List<Map<String, dynamic>> _listToko = [];
  bool _isLoadingToko = true;

  @override
  void initState() {
    super.initState();
    _fetchProvinsi();
    _fetchDaftarToko();
  }

  // FUNGSI TARIK DAFTAR CABANG MASTER DARI DATABASE
  Future<void> _fetchDaftarToko() async {
    try {
      final data = await Supabase.instance.client
          .from('toko_id')
          .select('id, toko_id')
          .order('id', ascending: true);
      if (mounted) {
        setState(() {
          _listToko = List<Map<String, dynamic>>.from(data);
          _isLoadingToko = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal load daftar toko: $e");
      if (mounted) setState(() => _isLoadingToko = false);
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

  // MESIN SUPABASE UNTUK PENDAFTARAN
  final supabase = Supabase.instance.client;

  // FUNGSI SUBMIT PENDAFTARAN
  Future<void> submitPendaftaran() async {
    // 1. Validasi Wajah (Liveness)
    if (!isFaceVerified) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_err_scan_wajah".tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4)));
      return;
    }

    // 2. Validasi Tanggal Mulai
    if (_tanggalMulai == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_err_tgl_mulai".tr()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4)));
      return;
    }

    // 3. Validasi Form Kosong
    if (formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("reg_memproses".tr()),
          backgroundColor: Colors.blueAccent));

      try {
        // 4. DAFTARKAN AKUN AUTH SUPABASE DULU
        final authResponse = await Supabase.instance.client.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: passwordCtrl.text,
        );

        if (authResponse.user != null) {
          // Cari nama teks toko display dari list toko lokal
          String namaCabangTeks = _cabang ?? '';
          if (_listToko.any((e) => e['id'] == _cabang)) {
            namaCabangTeks = _listToko
                .firstWhere((e) => e['id'] == _cabang)['toko_id']
                .toString();
          }

          final karyawanData = {
            'nik': _nikCtrl.text,
            'nama': _namaCtrl.text,
            'email': _emailCtrl.text.trim(),
            'wa': _waCtrl.text,
            'gender': gender,
            'umur': _umurCtrl.text,
            'jabatan': jabatan,
            'cabang': namaCabangTeks,
            'toko_id': _cabang, // ID relasi foreign key database
            'pin_absensi': pinCtrl.text,
            'alamat_lengkap':
                "${_jalanCtrl.text}, Desa $_namaDesa, Kec. $_namaKecamatan, $_namaKota, $_namaProvinsi",
            'nama_bank': namaBankCtrl.text.trim().toUpperCase(),
            'no_rekening': _noRekeningCtrl.text.trim(),
            'darurat_nama': _daruratNamaCtrl.text,
            'darurat_wa': _daruratWaCtrl.text,
            'tanggal_mulai': _tanggalMulai?.toIso8601String(),
            'status_approval': 'Menunggu OTP'
          };

          // 5. SUNTIK DATA KE TABEL KARYAWAN
          await supabase.from('karyawan').upsert(karyawanData);
          if (!mounted) return;

          // 6. TAMPILKAN PESAN SUKSES & ARAHKAN KE HALAMAN OTP
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("reg_sukses_otp".tr()),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5)));

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OtpVerificationPage(email: _emailCtrl.text),
            ),
          );
        }
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("${"reg_gagal".tr()}$error"),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("reg_ditolak_kosong".tr()),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Warna Latar Premium
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1E3C72),
        title: Text("reg_title".tr(),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================================
              // 1. VALIDASI BIOMETRIK WAJAH (LIVENESS)
              // ==========================================================
              _buildPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.face_retouching_natural,
                            color: Color(0xFF1E3C72)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text("reg_sec_biometrik".tr(),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E3C72))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("reg_desc_biometrik".tr(),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFaceVerified
                              ? Colors.green
                              : const Color(0xFF1E3C72),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(
                            isFaceVerified
                                ? Icons.check_circle
                                : Icons.camera_alt,
                            color: Colors.white),
                        label: Text(
                          isFaceVerified
                              ? "reg_wajah_terverifikasi".tr()
                              : "reg_btn_scan_wajah".tr(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const LivenessCameraPage()),
                          );
                          if (result == true) {
                            setState(() => isFaceVerified = true);
                          }
                        },
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
                        const Icon(Icons.badge, color: Color(0xFF1E3C72)),
                        const SizedBox(width: 10),
                        Text("reg_sec_identitas".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3C72))),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // INPUT NIK KTP
                    TextFormField(
                      controller: _nikCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16)
                      ],
                      decoration: _premiumDecoration(
                          "reg_label_nik".tr(), Icons.credit_card, null),
                      validator: (value) =>
                          (value == null || value.length != 16)
                              ? "reg_err_nik".tr()
                              : null,
                    ),
                    const SizedBox(height: 15),

                    // INPUT NAMA LENGKAP
                    TextFormField(
                      controller: _namaCtrl,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [CapitalizeEachWordFormatter()],
                      decoration: _premiumDecoration(
                          "isian_nama_lengkap".tr(), Icons.person, null),
                      validator: (value) => (value == null || value.isEmpty)
                          ? "reg_err_wajib".tr()
                          : null,
                    ),
                    const SizedBox(height: 15),

                    // INPUT EMAIL
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _premiumDecoration(
                          "reg_label_email".tr(), Icons.email, null),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "reg_err_wajib".tr();
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return "reg_err_email".tr();
                        }
                        return null;
                      },
                    ),
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

                    // GENDER & UMUR
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
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2)
                            ],
                            decoration: _premiumDecoration(
                                    "reg_label_umur".tr(), Icons.cake, null)
                                .copyWith(
                              suffixText: "reg_label_thn".tr(),
                              suffixStyle: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                    ? "reg_err_wajib".tr()
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
                        const Icon(Icons.location_on, color: Color(0xFF1E3C72)),
                        const SizedBox(width: 10),
                        Text("reg_sec_alamat".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3C72))),
                      ],
                    ),
                    const SizedBox(height: 20),

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
                        const Icon(Icons.work, color: Color(0xFF1E3C72)),
                        const SizedBox(width: 10),
                        Text("reg_sec_kepegawaian".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3C72))),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // JABATAN
                    DropdownButtonFormField<String>(
                      value: jabatan,
                      dropdownColor: Colors.white,
                      items: ["Kasir", "RO", "Sales / SPG"]
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

                    // 🎯 CABANG PENEMPATAN DINAMIS DATABASE
                    DropdownButtonFormField<String>(
                      value: _cabang,
                      dropdownColor: Colors.white,
                      hint: Text(
                        _isLoadingToko
                            ? "Memuat data cabang..."
                            : "Pilih Penempatan Cabang",
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      items: _listToko.map((toko) {
                        return DropdownMenuItem<String>(
                          value: toko['id'].toString(),
                          child: Text(
                            toko['toko_id'].toString(),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _cabang = val),
                      decoration: _premiumDecoration(
                          "reg_label_cabang".tr(), Icons.storefront, null),
                      validator: (value) =>
                          value == null ? "reg_err_cabang".tr() : null,
                    ),
                    const SizedBox(height: 15),

                    // TANGGAL MULAI KERJA (KALENDER)
                    InkWell(
                      onTap: () async {
                        DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() => _tanggalMulai = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 18),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month,
                                color: Colors.blueGrey),
                            const SizedBox(width: 15),
                            Text(
                              _tanggalMulai == null
                                  ? "reg_hint_tgl_mulai".tr()
                                  : "${_tanggalMulai!.day}-${_tanggalMulai!.month}-${_tanggalMulai!.year}",
                              style: TextStyle(
                                  color: _tanggalMulai == null
                                      ? Colors.grey
                                      : Colors.black87,
                                  fontSize: 13),
                            ),
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
                        const Icon(Icons.pin, color: Color(0xFF1E3C72)),
                        const SizedBox(width: 10),
                        Text("reg_sec_pin".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3C72))),
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
                        const Icon(Icons.emergency, color: Color(0xFF1E3C72)),
                        const SizedBox(width: 10),
                        Text("reg_sec_darurat".tr(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3C72))),
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
              const SizedBox(height: 40),

              // ==========================================================
              // TOMBOL SUBMIT PENDAFTARAN
              // ==========================================================
              Container(
                width: double.infinity,
                height: 55,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF0F172A).withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: submitPendaftaran,
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                  label: Text("reg_btn_kirim".tr(),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.white)),
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // WIDGET HELPER KUSTOM (DESAIN KARTU & TEXT FIELD)
  // ==========================================================
  Widget _buildPremiumCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      child: child,
    );
  }

  InputDecoration _premiumDecoration(
      String label, IconData icon, Widget? suffix) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.blueGrey, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.blueGrey.shade400, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E3C72), width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5)),
    );
  }
}
