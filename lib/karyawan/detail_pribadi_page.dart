import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import 'main_karyawan.dart';

class DetailDataPribadiPage extends StatefulWidget {
  const DetailDataPribadiPage({super.key});

  @override
  State<DetailDataPribadiPage> createState() => _DetailDataPribadiPageState();
}

class _DetailDataPribadiPageState extends State<DetailDataPribadiPage> {
  // Variabel State
  String? _fotoProfileUrl;
  bool _isUploading = false;

  // Variabel untuk menyimpan data asli dari database
  Map<String, dynamic>? _userData;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _fetchDataKaryawan(); // Tarik semua data & URL foto dari Supabase
  }

// FUNGSI TARIK DATA & FOTO DARI DATABASE
  Future<void> _fetchDataKaryawan() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      // CETAK ID INI KE TERMINAL UNTUK DICOCOKKAN
      debugPrint(">>> UID YANG SEDANG LOGIN: $userId <<<");

      // Tarik seluruh baris data karyawan yang sedang login
      final data = await supabase
          .from('karyawan')
          .select()
          .eq('id', userId)
          .maybeSingle(); // <-- GANTI .single() JADI .maybeSingle()

      if (mounted) {
        setState(() {
          // Hanya isi data jika hasil pencariannya tidak kosong
          if (data != null) {
            _userData = data;
            _fotoProfileUrl = data['foto_profile'];
          }
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal memuat data karyawan: $e");
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  // FUNGSI UPLOAD & CROP FOTO (Dukungan Web & Mobile - BEBAS ERROR)
  Future<void> _pilihDanUploadFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    if (!mounted) return;

    // 1. PROSES PANGKAS (CROP) FOTO DENGAN RASIO 3x4
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 4),
      uiSettings: [
        WebUiSettings(
          context: context,
        ),
        AndroidUiSettings(
          toolbarTitle: 'Paskan Wajah di Tengah (3x4)',
          toolbarColor: const Color(0xFF1E293B),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio3x2,
          lockAspectRatio: true,
          hideBottomControls: true,
          cropStyle: CropStyle.rectangle,
        ),
        IOSUiSettings(
          title: 'Paskan Wajah di Tengah',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      final bytes = await croppedFile.readAsBytes();

      final fileName =
          'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      await supabase
          .from('karyawan')
          .update({'foto_profile': publicUrl}).eq('id', userId);

      if (mounted) {
        setState(() {
          _fotoProfileUrl = publicUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("profil_sukses_foto".tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Gagal mengunggah foto: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal mengunggah foto: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6F9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1E293B)),
        ),
      );
    }

// 1. DATA RAW (DIPAKSA MENJADI STRING AGAR AMAN DARI ERROR)
    final String namaAsli = _userData?['nama']?.toString() ?? "-";
    final String nikAsli = _userData?['nik']?.toString() ?? "-";
    final String rekeningAsli = _userData?['no_rekening']?.toString() ?? "-";
    final String noHpAsli = _userData?['darurat_wa']?.toString() ?? "-";
    final String namaDaruratAsli =
        _userData?['darurat_nama']?.toString() ?? "-";
    final String cabangAsli = _userData?['cabang']?.toString() ?? "-";
    final String bankAsli = _userData?['nama_bank']?.toString() ?? "-";

    // Umur kita ambil angkanya saja
    final String umurAsli =
        _userData?['umur'] != null ? _userData!['umur'].toString() : "-";

    // 2. DATA YANG DI-TRANSLATE (SANGAT AMAN UNTUK DITAMBAH .tr())
    final String jabatanAsli = _userData?['jabatan']?.toString() ?? "Staff";

    // Logika Gender
    String genderTr = "-";
    if (_userData?['gender'] == 'L' || _userData?['gender'] == 'Laki-laki') {
      genderTr = "gender_l".tr();
    } else if (_userData?['gender'] == 'P' ||
        _userData?['gender'] == 'Perempuan') {
      genderTr = "gender_p".tr();
    }

    final String tglMulai = _userData?['tanggal_mulai'] != null
        ? _userData!['tanggal_mulai'].toString().split('T')[0]
        : "-";

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "profil_title".tr(), // TRANSLATE
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. KARTU ID VIRTUAL
            // Jabatan ditambahkan .tr() agar misal "Kepala Toko" bisa jadi "Head of Store" jika key-nya ada di JSON
            _buildIDCard(namaAsli, jabatanAsli.tr()),
            const SizedBox(height: 25),

            // 2. DATA KEPEGAWAIAN
            _buildSectionTitle("profil_sec_kepegawaian".tr()), // TRANSLATE
            _buildDataBox([
              _buildDataRow("profil_label_jabatan".tr(),
                  jabatanAsli.tr()), // LABEL TRANSLATE
              _buildDataRow(
                  "profil_label_cabang".tr(), cabangAsli), // CABANG RAW
              _buildDataRow("profil_label_mulai_kerja".tr(), tglMulai,
                  true), // LABEL TRANSLATE
            ]),
            const SizedBox(height: 20),

            // 3. DATA UTAMA KTP
            _buildSectionTitle("profil_sec_data_utama".tr()), // TRANSLATE
            _buildDataBox([
              _buildDataRow("profil_label_nik".tr(), nikAsli), // NIK RAW
              _buildDataRow("profil_label_nama".tr(), namaAsli), // NAMA RAW
              _buildDataRow(
                  "profil_label_jk".tr(), genderTr), // GENDER TRANSLATE
              _buildDataRow(
                  "profil_label_umur".tr(), umurAsli, true), // UMUR ANGKA RAW
            ]),
            const SizedBox(height: 20),

            // 4. PAYROLL & DARURAT
            _buildSectionTitle("profil_sec_payroll".tr()), // TRANSLATE
            _buildDataBox([
              _buildDataRow("profil_label_bank".tr(), bankAsli), // BANK RAW
              _buildDataRow(
                  "profil_label_rekening".tr(), rekeningAsli), // REKENING RAW
              _buildDataRow(
                  "profil_label_no_darurat".tr(), noHpAsli), // NO HP RAW
              _buildDataRow("profil_label_hubungan".tr(), namaDaruratAsli,
                  true), // NAMA KONTAK RAW
            ]),
            const SizedBox(height: 35),

            // 5. TOMBOL AJUKAN PERUBAHAN
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                  shadowColor: Colors.black26,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("profil_msg_wa_admin".tr())), // TRANSLATE
                  );
                },
                icon: const Icon(Icons.edit_document,
                    color: Colors.white, size: 20),
                label: Text(
                  "profil_btn_ubah_data".tr(), // TRANSLATE
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // WIDGET PEMBANTU: KARTU ID (LANYARD VIRTUAL)
  Widget _buildIDCard(String nama, String jabatan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              GestureDetector(
                onTap: _isUploading ? null : _pilihDanUploadFoto,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.blueAccent, Colors.lightBlueAccent],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _fotoProfileUrl != null
                        ? NetworkImage(_fotoProfileUrl!)
                        : null,
                    child: _fotoProfileUrl == null
                        ? const Icon(Icons.person, size: 50, color: Colors.grey)
                        : null,
                  ),
                ),
              ),
              if (_isUploading)
                const Positioned.fill(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            nama,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              jabatan.toUpperCase(),
              style: const TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            "profil_lanyard_subtitle".tr(), // TRANSLATE
            style: const TextStyle(
                color: Colors.white54, fontSize: 11, letterSpacing: 2),
          ),
          const SizedBox(height: 15),
          TextButton.icon(
            onPressed: _isUploading ? null : _pilihDanUploadFoto,
            icon: const Icon(Icons.camera_alt, color: Colors.white70, size: 16),
            label: Text(
              "profil_btn_ubah_foto".tr(), // TRANSLATE
              style: const TextStyle(color: Colors.white70),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
      ),
    );
  }

  Widget _buildDataBox(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDataRow(String label, String value, [bool isLast = false]) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  flex: 2,
                  child: Text(label,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13))),
              const Text(":",
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(width: 10),
              Expanded(
                  flex: 3,
                  child: Text(value,
                      style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
            ],
          ),
        ),
        if (!isLast) Divider(color: Colors.grey.shade200, height: 1),
      ],
    );
  }
}
