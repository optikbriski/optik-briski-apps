import 'package:flutter/material.dart';
import '../../shared/brand/brand_service.dart';
import '../../shared/theme.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../shared/attendance/attendance_service.dart';
import '../../shared/whatsapp_launcher.dart';

class DetailDataPribadiPage extends StatefulWidget {
  const DetailDataPribadiPage({super.key});

  @override
  State<DetailDataPribadiPage> createState() => _DetailDataPribadiPageState();
}

class _DetailDataPribadiPageState extends State<DetailDataPribadiPage> {
  String? _fotoProfileUrl;
  bool _isUploading = false;

  Map<String, dynamic>? _userData;
  bool _isLoadingData = true;
  bool _unlocked = false;
  bool _pinChecking = false;
  final _pinCtrl = TextEditingController();
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _fetchDataKaryawan();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDataKaryawan() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      final data = await supabase
          .from('karyawan')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null) {
            _userData = data;
            _fotoProfileUrl = data['foto_profile']?.toString();
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

  String get _storedPin =>
      (_userData?['pin_absensi'] ?? '').toString().trim();

  Future<void> _tryUnlock() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = 'profil_pin_wajib'.tr());
      return;
    }
    if (_storedPin.isEmpty) {
      setState(() => _pinError = 'profil_pin_belum_ada'.tr());
      return;
    }
    setState(() {
      _pinChecking = true;
      _pinError = null;
    });
    final ok = AttendanceService()
        .verifyPinAbsensi(_userData ?? const {}, pin);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _pinChecking = false;
        _pinError = 'profil_pin_salah'.tr();
      });
      return;
    }
    setState(() {
      _pinChecking = false;
      _unlocked = true;
      _pinCtrl.clear();
    });
  }

  Future<void> _pilihDanUploadFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;
    if (!mounted) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 4),
      uiSettings: [
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          barrierColor: Colors.black54,
        ),
        AndroidUiSettings(
          toolbarTitle: 'Paskan Wajah di Tengah (3x4)',
          toolbarColor: OptikKaryawanTokens.seasideMid,
          toolbarWidgetColor: OptikKaryawanTokens.ink,
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

    setState(() => _isUploading = true);

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
        setState(() => _fotoProfileUrl = publicUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("profil_sukses_foto".tr()),
            backgroundColor: OptikKaryawanTokens.seasideMid,
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
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _str(String key) {
    final v = _userData?[key];
    if (v == null) return '-';
    final s = v.toString().trim();
    return s.isEmpty ? '-' : s;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        backgroundColor: OptikKaryawanTokens.scaffold,
        body: Center(
          child: CircularProgressIndicator(color: OptikKaryawanTokens.navyDeep),
        ),
      );
    }

    if (!_unlocked) {
      return _buildPinLockScaffold();
    }

    final namaAsli = _str('nama');
    final nikAsli = _str('nik');
    final rekeningAsli = _str('no_rekening');
    final noHpDarurat = _str('darurat_wa');
    final namaDarurat = _str('darurat_nama');
    final hubunganDarurat = _str('darurat_hubungan');
    final cabangAsli = _str('cabang');
    final tokoIdAsli = _str('toko_id');
    final bankAsli = _str('nama_bank');
    final emailAsli = _str('email');
    final waAsli = _str('wa');
    final alamatKtp = _str('alamat_ktp');
    final alamatJalanKtp = _str('alamat_jalan_ktp');
    final rtRw = _str('rt_rw');
    final kelDesa = _str('kelurahan_desa');
    final kecamatanKtp = _str('kecamatan_ktp');
    final alamatDomisili = _str('alamat_lengkap');
    final ttl = _str('tempat_tgl_lahir');
    final tempatLahir = _str('tempat_lahir');
    final tanggalLahir = _str('tanggal_lahir');
    final golDarah = _str('golongan_darah');
    final agama = _str('agama');
    final statusKawin = _str('status_perkawinan');
    final pekerjaan = _str('pekerjaan');
    final kewarganegaraan = _str('kewarganegaraan');
    final ktpSumber = _str('ktp_sumber');
    final umurAsli = _str('umur');
    final jabatanAsli = _str('jabatan');
    final statusApproval = _str('status_approval');
    final approvedBy = _str('approved_by_name');
    final ktpUrl = _userData?['ktp_photo_url']?.toString();
    final faceEnrolled = _userData?['face_enrolled_at'] != null
        ? _userData!['face_enrolled_at'].toString().split('T')[0]
        : '-';

    String genderTr = '-';
    final g = _userData?['gender']?.toString();
    if (g == 'L' || g == 'Laki-laki') {
      genderTr = 'gender_l'.tr();
    } else if (g == 'P' || g == 'Perempuan') {
      genderTr = 'gender_p'.tr();
    }

    final tglMulai = _userData?['tanggal_mulai'] != null
        ? _userData!['tanggal_mulai'].toString().split('T')[0]
        : '-';
    final approvedAt = _userData?['approved_at'] != null
        ? _userData!['approved_at'].toString().split('T')[0]
        : '-';

    return KaryawanPremiumScaffold(
      title: 'profil_title'.tr(),
      eyebrow: BrandService.name.toUpperCase(),
      actions: [
        IconButton(
          tooltip: 'Kunci lagi',
          onPressed: () => setState(() {
            _unlocked = false;
            _pinCtrl.clear();
            _pinError = null;
          }),
          icon: const Icon(Icons.lock_outline_rounded),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildIDCard(namaAsli, jabatanAsli.tr()),
            const SizedBox(height: 25),

            _buildSectionTitle('profil_sec_kepegawaian'.tr()),
            _buildDataBox([
              _buildDataRow('profil_label_jabatan'.tr(), jabatanAsli.tr()),
              _buildDataRow('profil_label_cabang'.tr(), cabangAsli),
              _buildDataRow('profil_label_toko_id'.tr(), tokoIdAsli),
              _buildDataRow('profil_label_mulai_kerja'.tr(), tglMulai),
              _buildDataRow('profil_label_status'.tr(), statusApproval),
              _buildDataRow('profil_label_disetujui_oleh'.tr(), approvedBy),
              _buildDataRow('profil_label_tgl_disetujui'.tr(), approvedAt),
              _buildDataRow(
                  'profil_label_wajah_terdaftar'.tr(), faceEnrolled, true),
            ]),
            const SizedBox(height: 20),

            _buildSectionTitle('profil_sec_kontak'.tr()),
            _buildDataBox([
              _buildDataRow('profil_label_email'.tr(), emailAsli),
              _buildDataRow('profil_label_wa'.tr(), waAsli, true),
            ]),
            const SizedBox(height: 20),

            _buildSectionTitle('profil_sec_identitas_ktp'.tr()),
            _buildDataBox([
              _buildDataRow('profil_label_nik'.tr(), nikAsli),
              _buildDataRow('profil_label_nama'.tr(), namaAsli),
              _buildDataRow('profil_label_jk'.tr(), genderTr),
              _buildDataRow('profil_label_tempat_lahir'.tr(), tempatLahir),
              _buildDataRow('profil_label_tgl_lahir'.tr(), tanggalLahir),
              _buildDataRow('profil_label_ttl'.tr(), ttl),
              _buildDataRow('profil_label_umur'.tr(), umurAsli),
              _buildDataRow('profil_label_gol_darah'.tr(), golDarah),
              _buildDataRow('profil_label_agama'.tr(), agama),
              _buildDataRow('profil_label_status_kawin'.tr(), statusKawin),
              _buildDataRow('profil_label_pekerjaan'.tr(), pekerjaan),
              _buildDataRow(
                  'profil_label_kewarganegaraan'.tr(), kewarganegaraan),
              _buildDataRow('profil_label_alamat_jalan'.tr(), alamatJalanKtp),
              _buildDataRow('profil_label_rt_rw'.tr(), rtRw),
              _buildDataRow('profil_label_kel_desa'.tr(), kelDesa),
              _buildDataRow('profil_label_kecamatan'.tr(), kecamatanKtp),
              _buildDataRow('profil_label_alamat_ktp'.tr(), alamatKtp),
              _buildDataRow(
                  'profil_label_sumber_ktp'.tr(), ktpSumber, true),
            ]),
            if (ktpUrl != null && ktpUrl.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 5, bottom: 8),
                  child: Text(
                    'profil_label_foto_ktp'.tr(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey),
                  ),
                ),
              ),
              _buildKtpThumb(ktpUrl),
            ],
            const SizedBox(height: 20),

            _buildSectionTitle('profil_sec_alamat'.tr()),
            _buildDataBox([
              _buildDataRow(
                  'profil_label_alamat_domisili'.tr(), alamatDomisili, true),
            ]),
            const SizedBox(height: 20),

            _buildSectionTitle('profil_sec_payroll'.tr()),
            _buildDataBox([
              _buildDataRow('profil_label_bank'.tr(), bankAsli),
              _buildDataRow('profil_label_rekening'.tr(), rekeningAsli),
              _buildDataRow('profil_label_nama_darurat'.tr(), namaDarurat),
              _buildDataRow('profil_label_no_darurat'.tr(), noHpDarurat),
              _buildDataRow(
                  'profil_label_hubungan'.tr(), hubunganDarurat, true),
            ]),
            const SizedBox(height: 35),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: OptikKaryawanTokens.seasideMid,
                  foregroundColor: OptikKaryawanTokens.ink,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  elevation: 2,
                  shadowColor: OptikKaryawanTokens.seasideMid.withOpacity(0.35),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await openAdminWhatsApp(
                      message:
                          'Halo Admin, saya ingin mengajukan perubahan data pribadi.',
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('$e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.edit_document,
                    color: OptikKaryawanTokens.ink, size: 20),
                label: Text(
                  'profil_btn_ubah_data'.tr(),
                  style: const TextStyle(
                    color: OptikKaryawanTokens.ink,
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

  Widget _buildPinLockScaffold() {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: OptikKaryawanTokens.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OptikKaryawanTokens.gold.withOpacity(0.14),
                  border: Border.all(
                      color: OptikKaryawanTokens.gold.withOpacity(0.45)),
                ),
                child: const Icon(Icons.lock_rounded,
                    color: OptikKaryawanTokens.gold, size: 34),
              ),
              const SizedBox(height: 20),
              Text(
                'profil_pin_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: OptikKaryawanTokens.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'profil_pin_desc'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.95),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                style: const TextStyle(
                  color: OptikKaryawanTokens.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                ),
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: TextStyle(
                      color: OptikKaryawanTokens.muted.withOpacity(0.45)),
                  filled: true,
                  fillColor: OptikKaryawanTokens.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: OptikKaryawanTokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: OptikKaryawanTokens.gold, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _tryUnlock(),
              ),
              if (_pinError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _pinError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _pinChecking ? null : _tryUnlock,
                  style: FilledButton.styleFrom(
                    backgroundColor: OptikKaryawanTokens.gold,
                    foregroundColor: OptikKaryawanTokens.navyDeep,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _pinChecking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: OptikKaryawanTokens.navyDeep,
                          ),
                        )
                      : Text(
                          'profil_pin_buka'.tr(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                ),
              ),
              const Spacer(),
              Text(
                'profil_pin_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: OptikKaryawanTokens.muted.withOpacity(0.85),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKtpThumb(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: Text(
              'Foto KTP tidak bisa dimuat',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIDCard(String nama, String jabatan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        gradient: OptikKaryawanTokens.navyGradient,
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
        boxShadow: [
          BoxShadow(
            color: OptikKaryawanTokens.gold.withOpacity(0.2),
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
                      colors: [OptikKaryawanTokens.gold, OptikKaryawanTokens.goldLite],
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
                  child: CircularProgressIndicator(color: OptikKaryawanTokens.ink),
                ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            nama,
            style: const TextStyle(
                color: OptikKaryawanTokens.ink,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.65),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: OptikKaryawanTokens.border),
            ),
            child: Text(
              jabatan.toUpperCase(),
              style: const TextStyle(
                  color: OptikKaryawanTokens.seasideMid,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            'profil_lanyard_subtitle'.tr(),
            style: const TextStyle(
                color: OptikKaryawanTokens.muted, fontSize: 11, letterSpacing: 2),
          ),
          const SizedBox(height: 15),
          TextButton.icon(
            onPressed: _isUploading ? null : _pilihDanUploadFoto,
            icon: const Icon(Icons.camera_alt, color: OptikKaryawanTokens.ink, size: 16),
            label: Text(
              'profil_btn_ubah_foto'.tr(),
              style: const TextStyle(color: OptikKaryawanTokens.ink),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.65),
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
      decoration: OptikKaryawanTokens.premiumCard,
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
              const Text(':',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(width: 10),
              Expanded(
                  flex: 3,
                  child: Text(value,
                      style: const TextStyle(
                          color: OptikKaryawanTokens.navyDeep,
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
