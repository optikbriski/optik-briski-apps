import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/admin/admin_premium.dart';

/// Hasil review dari halaman detail verifikasi.
enum KtpReviewResult { approved, rejected, cancelled }

/// Halaman penuh: lihat KTP + bandingkan OCR vs edit + Tolak/Approve.
class KtpApprovalReviewPage extends StatefulWidget {
  const KtpApprovalReviewPage({super.key, required this.karyawan});

  final Map<String, dynamic> karyawan;

  @override
  State<KtpApprovalReviewPage> createState() => _KtpApprovalReviewPageState();
}

class _KtpApprovalReviewPageState extends State<KtpApprovalReviewPage> {
  String? _nikChoice;
  String? _namaChoice;
  String? _alamatKtpChoice;
  String? _ttlChoice;
  String? _genderChoice;
  String? _golDarahChoice;
  String? _agamaChoice;
  String? _statusKawinChoice;
  String? _alamatChoice;
  bool _saving = false;

  String get _nikOcr => (widget.karyawan['nik_ocr'] ?? '').toString().trim();
  String get _nikEdit => (widget.karyawan['nik'] ?? '').toString().trim();
  String get _namaOcr => (widget.karyawan['nama_ocr'] ?? '').toString().trim();
  String get _namaEdit => (widget.karyawan['nama'] ?? '').toString().trim();
  String get _alamatKtpOcr =>
      (widget.karyawan['alamat_ktp_ocr'] ?? '').toString().trim();
  String get _alamatKtpEdit =>
      (widget.karyawan['alamat_ktp'] ?? '').toString().trim();
  String get _ttlOcr =>
      (widget.karyawan['tempat_tgl_lahir_ocr'] ?? '').toString().trim();
  String get _ttlEdit =>
      (widget.karyawan['tempat_tgl_lahir'] ?? '').toString().trim();
  String get _genderOcr =>
      (widget.karyawan['gender_ocr'] ?? '').toString().trim();
  String get _genderEdit {
    final g = (widget.karyawan['gender'] ?? '').toString().trim().toUpperCase();
    if (g == 'L' || g == 'LAKI-LAKI' || g == 'LAKI LAKI') return 'LAKI-LAKI';
    if (g == 'P' || g == 'PEREMPUAN') return 'PEREMPUAN';
    return g;
  }

  String get _golOcr =>
      (widget.karyawan['golongan_darah_ocr'] ?? '').toString().trim();
  String get _golEdit =>
      (widget.karyawan['golongan_darah'] ?? '').toString().trim();
  String get _agamaOcr => (widget.karyawan['agama_ocr'] ?? '').toString().trim();
  String get _agamaEdit => (widget.karyawan['agama'] ?? '').toString().trim();
  String get _statusOcr =>
      (widget.karyawan['status_perkawinan_ocr'] ?? '').toString().trim();
  String get _statusEdit =>
      (widget.karyawan['status_perkawinan'] ?? '').toString().trim();
  String get _alamatDomisili =>
      (widget.karyawan['alamat_lengkap'] ?? '').toString().trim();
  String get _karyawanId => (widget.karyawan['id'] ?? '').toString();

  bool _diff(String ocr, String edit) =>
      ocr.isNotEmpty && edit.isNotEmpty && ocr.toLowerCase() != edit.toLowerCase();

  bool get _nikDiff => _diff(_nikOcr, _nikEdit);
  bool get _namaDiff => _diff(_namaOcr, _namaEdit);
  bool get _alamatKtpDiff => _diff(_alamatKtpOcr, _alamatKtpEdit);
  bool get _ttlDiff => _diff(_ttlOcr, _ttlEdit);
  bool get _genderDiff => _diff(_genderOcr, _genderEdit);
  bool get _golDiff => _diff(_golOcr, _golEdit);
  bool get _agamaDiff => _diff(_agamaOcr, _agamaEdit);
  bool get _statusDiff => _diff(_statusOcr, _statusEdit);

  bool get _domisiliDiff {
    final ktpRef = _alamatKtpEdit.isNotEmpty ? _alamatKtpEdit : _alamatKtpOcr;
    return ktpRef.isNotEmpty &&
        _alamatDomisili.isNotEmpty &&
        ktpRef.toLowerCase() != _alamatDomisili.toLowerCase();
  }

  bool get _canApprove {
    if (_karyawanId.isEmpty) return false;
    if (_nikDiff && _nikChoice == null) return false;
    if (_namaDiff && _namaChoice == null) return false;
    if (_alamatKtpDiff && _alamatKtpChoice == null) return false;
    if (_ttlDiff && _ttlChoice == null) return false;
    if (_genderDiff && _genderChoice == null) return false;
    if (_golDiff && _golDarahChoice == null) return false;
    if (_agamaDiff && _agamaChoice == null) return false;
    if (_statusDiff && _statusKawinChoice == null) return false;
    if (_domisiliDiff && _alamatChoice == null) return false;
    return true;
  }

  int get _conflictCount {
    var n = 0;
    if (_nikDiff) n++;
    if (_namaDiff) n++;
    if (_alamatKtpDiff) n++;
    if (_ttlDiff) n++;
    if (_genderDiff) n++;
    if (_golDiff) n++;
    if (_agamaDiff) n++;
    if (_statusDiff) n++;
    if (_domisiliDiff) n++;
    return n;
  }

  String _pick(bool diff, String? choice, String ocr, String edit) {
    if (!diff) return edit.isNotEmpty ? edit : ocr;
    return choice == 'ocr' ? ocr : edit;
  }

  String _genderCode(String label) {
    final u = label.toUpperCase();
    if (u.contains('PEREMPUAN') || u == 'P') return 'P';
    if (u.contains('LAKI') || u == 'L') return 'L';
    return label;
  }

  Future<void> _approve() async {
    if (!_canApprove || _saving) return;
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final admin = client.auth.currentUser;
      var adminName = admin?.email ?? 'Admin Pusat';
      if (admin != null) {
        try {
          final profile = await client
              .from('profiles')
              .select('email, role')
              .eq('id', admin.id)
              .maybeSingle();
          final email = profile?['email']?.toString();
          final role = profile?['role']?.toString();
          if (email != null && email.isNotEmpty) {
            adminName =
                role != null && role.isNotEmpty ? '$email ($role)' : email;
          }
        } catch (_) {}
      }

      final finalNik = _pick(_nikDiff, _nikChoice, _nikOcr, _nikEdit);
      final finalNama = _pick(_namaDiff, _namaChoice, _namaOcr, _namaEdit);
      final ktpBase =
          _pick(_alamatKtpDiff, _alamatKtpChoice, _alamatKtpOcr, _alamatKtpEdit);
      final finalTtl = _pick(_ttlDiff, _ttlChoice, _ttlOcr, _ttlEdit);
      final finalGenderLabel =
          _pick(_genderDiff, _genderChoice, _genderOcr, _genderEdit);
      final finalGol = _pick(_golDiff, _golDarahChoice, _golOcr, _golEdit);
      final finalAgama = _pick(_agamaDiff, _agamaChoice, _agamaOcr, _agamaEdit);
      final finalStatus =
          _pick(_statusDiff, _statusKawinChoice, _statusOcr, _statusEdit);

      var finalAlamatLengkap = _alamatDomisili;
      String? finalAlamatKtp = ktpBase.isEmpty ? null : ktpBase;

      if (_domisiliDiff) {
        switch (_alamatChoice) {
          case 'ocr':
            finalAlamatLengkap = ktpBase;
            finalAlamatKtp = ktpBase;
          case 'edit':
            finalAlamatLengkap = _alamatDomisili;
            finalAlamatKtp = ktpBase.isEmpty ? null : ktpBase;
          case 'both':
            finalAlamatLengkap = _alamatDomisili;
            finalAlamatKtp = ktpBase;
        }
      }

      final choices = {
        'nik': _nikDiff ? _nikChoice : 'same',
        'nama': _namaDiff ? _namaChoice : 'same',
        'alamat_ktp': _alamatKtpDiff ? _alamatKtpChoice : 'same',
        'tempat_tgl_lahir': _ttlDiff ? _ttlChoice : 'same',
        'gender': _genderDiff ? _genderChoice : 'same',
        'golongan_darah': _golDiff ? _golDarahChoice : 'same',
        'agama': _agamaDiff ? _agamaChoice : 'same',
        'status_perkawinan': _statusDiff ? _statusKawinChoice : 'same',
        'alamat': _domisiliDiff ? _alamatChoice : 'same',
        'resolved_at': DateTime.now().toIso8601String(),
      };

      final fullUpdate = <String, dynamic>{
        'nik': finalNik,
        'nama': finalNama,
        'alamat_lengkap': finalAlamatLengkap,
        if (finalAlamatKtp != null) 'alamat_ktp': finalAlamatKtp,
        if (finalTtl.isNotEmpty) 'tempat_tgl_lahir': finalTtl,
        if (finalGenderLabel.isNotEmpty)
          'gender': _genderCode(finalGenderLabel),
        if (finalGol.isNotEmpty) 'golongan_darah': finalGol,
        if (finalAgama.isNotEmpty) 'agama': finalAgama,
        if (finalStatus.isNotEmpty) 'status_perkawinan': finalStatus,
        'status_approval': 'Aktif',
        'approval_choices': choices,
        if (admin?.id != null) 'approved_by': admin!.id,
        'approved_by_name': adminName,
        'approved_at': DateTime.now().toIso8601String(),
      };

      try {
        await client
            .from('karyawan')
            .update(fullUpdate)
            .eq('id', _karyawanId);
      } catch (_) {
        await client.from('karyawan').update({
          'nik': finalNik,
          'nama': finalNama,
          'alamat_lengkap': finalAlamatLengkap,
          'status_approval': 'Aktif',
        }).eq('id', _karyawanId);
      }

      if (!mounted) return;
      Navigator.pop(context, KtpReviewResult.approved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal approve: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reject() async {
    final alasanCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.bgMid,
        title: const Text('Tolak pendaftaran?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: alasanCtrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Alasan penolakan wajib diisi…',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: OptikAdminTokens.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (alasanCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    final alasan = alasanCtrl.text.trim();
    alasanCtrl.dispose();
    if (ok != true || alasan.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('karyawan').update({
        'status_approval': 'Ditolak: $alasan',
      }).eq('id', _karyawanId);
      if (!mounted) return;
      Navigator.pop(context, KtpReviewResult.rejected);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal menolak: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.karyawan['ktp_photo_url']?.toString() ?? '';
    final nama =
        _namaEdit.isNotEmpty ? _namaEdit : (_namaOcr.isNotEmpty ? _namaOcr : '-');
    final jabatan = (widget.karyawan['jabatan'] ?? '-').toString();
    final cabang = (widget.karyawan['cabang'] ?? '-').toString();
    final email = (widget.karyawan['email'] ?? '-').toString();
    final wa = (widget.karyawan['wa'] ?? '-').toString();
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Detail Verifikasi',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _saving
              ? null
              : () => Navigator.pop(context, KtpReviewResult.cancelled),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _photoPane(photo),
                      ),
                      Expanded(
                        flex: 4,
                        child: _scrollContent(
                          nama: nama,
                          jabatan: jabatan,
                          cabang: cabang,
                          email: email,
                          wa: wa,
                          showPhotoInline: false,
                          photo: photo,
                        ),
                      ),
                    ],
                  )
                : _scrollContent(
                    nama: nama,
                    jabatan: jabatan,
                    cabang: cabang,
                    email: email,
                    wa: wa,
                    showPhotoInline: true,
                    photo: photo,
                  ),
          ),
          _bottomActions(),
        ],
      ),
    );
  }

  Widget _photoPane(String photo) {
    return Container(
      color: const Color(0xFF020617),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Foto KTP',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pinch / scroll untuk zoom. Foto ditampilkan utuh (tidak dipotong).',
            style: TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Expanded(child: _ktpViewer(photo)),
        ],
      ),
    );
  }

  Widget _ktpViewer(String photo) {
    if (photo.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: OptikAdminTokens.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'Belum ada foto KTP',
          style: TextStyle(color: Colors.orangeAccent),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: OptikAdminTokens.card,
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Center(
            child: Image.network(
              photo,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Foto KTP gagal dimuat',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollContent({
    required String nama,
    required String jabatan,
    required String cabang,
    required String email,
    required String wa,
    required bool showPhotoInline,
    required String photo,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _sectionCard(
          title: 'Data pendaftar',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nama,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$jabatan · $cabang',
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              _metaRow(Icons.email_outlined, email),
              const SizedBox(height: 6),
              _metaRow(Icons.phone_outlined, wa),
              const SizedBox(height: 6),
              _metaRow(
                Icons.badge_outlined,
                () {
                  final s = (widget.karyawan['ktp_sumber'] ?? '')
                      .toString()
                      .toLowerCase();
                  if (s == 'ikd') return 'Sumber: Upload IKD';
                  if (s == 'fisik') return 'Sumber: Scan KTP fisik';
                  return 'Sumber: belum ditandai';
                }(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_conflictCount > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.45)),
            ),
            child: Text(
              'Ada $_conflictCount data beda. Pilih opsi yang valid di bawah sebelum Approve.',
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.greenAccent.withOpacity(0.35)),
            ),
            child: const Text(
              'OCR & form cocok. Review foto KTP lalu putuskan.',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        if (showPhotoInline) ...[
          _sectionCard(
            title: 'Foto KTP',
            subtitle: 'Pinch untuk zoom — foto ditampilkan utuh',
            child: AspectRatio(
              aspectRatio: 1.58,
              child: _ktpViewer(photo),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _sectionCard(
          title: 'Perbandingan data KTP',
          subtitle: 'OCR vs isian karyawan — alamat harus lengkap RT/RW, kel, kec',
          child: Column(
            children: [
              _choiceBlock(
                title: 'NIK',
                diff: _nikDiff,
                ocr: _nikOcr,
                edit: _nikEdit,
                value: _nikChoice,
                onChanged: (v) => setState(() => _nikChoice = v),
              ),
              _choiceBlock(
                title: 'Nama',
                diff: _namaDiff,
                ocr: _namaOcr,
                edit: _namaEdit,
                value: _namaChoice,
                onChanged: (v) => setState(() => _namaChoice = v),
              ),
              _choiceBlock(
                title: 'Tempat/Tgl lahir',
                diff: _ttlDiff,
                ocr: _ttlOcr,
                edit: _ttlEdit,
                value: _ttlChoice,
                onChanged: (v) => setState(() => _ttlChoice = v),
              ),
              _choiceBlock(
                title: 'Jenis kelamin',
                diff: _genderDiff,
                ocr: _genderOcr,
                edit: _genderEdit,
                value: _genderChoice,
                onChanged: (v) => setState(() => _genderChoice = v),
              ),
              _choiceBlock(
                title: 'Gol. darah',
                diff: _golDiff,
                ocr: _golOcr,
                edit: _golEdit,
                value: _golDarahChoice,
                onChanged: (v) => setState(() => _golDarahChoice = v),
              ),
              _choiceBlock(
                title: 'Agama',
                diff: _agamaDiff,
                ocr: _agamaOcr,
                edit: _agamaEdit,
                value: _agamaChoice,
                onChanged: (v) => setState(() => _agamaChoice = v),
              ),
              _choiceBlock(
                title: 'Status perkawinan',
                diff: _statusDiff,
                ocr: _statusOcr,
                edit: _statusEdit,
                value: _statusKawinChoice,
                onChanged: (v) => setState(() => _statusKawinChoice = v),
              ),
              _choiceBlock(
                title: 'Alamat KTP',
                diff: _alamatKtpDiff,
                ocr: _alamatKtpOcr,
                edit: _alamatKtpEdit,
                value: _alamatKtpChoice,
                onChanged: (v) => setState(() => _alamatKtpChoice = v),
              ),
            ],
          ),
        ),
        if (_domisiliDiff) ...[
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Alamat domisili vs KTP',
            subtitle: 'Wajib pilih sebelum Approve',
            accent: Colors.blueAccent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _compareBox(
                  label: 'Alamat di KTP',
                  value: _alamatKtpEdit.isNotEmpty
                      ? _alamatKtpEdit
                      : _alamatKtpOcr,
                ),
                const SizedBox(height: 10),
                _compareBox(
                  label: 'Alamat domisili (form)',
                  value: _alamatDomisili,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Pakai alamat KTP', 'ocr', _alamatChoice,
                        (v) => setState(() => _alamatChoice = v)),
                    _chip('Pakai domisili', 'edit', _alamatChoice,
                        (v) => setState(() => _alamatChoice = v)),
                    _chip('Simpan keduanya', 'both', _alamatChoice,
                        (v) => setState(() => _alamatChoice = v)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomActions() {
    return Material(
      color: OptikAdminTokens.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size(0, 50),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Tolak',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: (!_canApprove || _saving) ? null : _approve,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    disabledBackgroundColor: Colors.white12,
                    minimumSize: const Size(0, 50),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _canApprove ? 'Approve & aktifkan' : 'Pilih data dulu',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    Color accent = Colors.blueAccent,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OptikAdminTokens.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _compareBox({required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceBlock({
    required String title,
    required bool diff,
    required String ocr,
    required String edit,
    required String? value,
    required ValueChanged<String> onChanged,
  }) {
    if (!diff) {
      final shown = edit.isNotEmpty ? edit : ocr;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                shown.isEmpty ? '-' : shown,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'sama',
                style: TextStyle(color: Colors.greenAccent, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'beda — wajib pilih',
                  style: TextStyle(color: Colors.amber, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _compareBox(label: 'OCR (scan KTP)', value: ocr),
          const SizedBox(height: 8),
          _compareBox(label: 'Edit karyawan', value: edit),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Pakai OCR', 'ocr', value, onChanged),
              _chip('Pakai edit karyawan', 'edit', value, onChanged),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    String key,
    String? selected,
    ValueChanged<String> onChanged,
  ) {
    final on = selected == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: on ? Colors.black : Colors.white70,
        ),
      ),
      selected: on,
      selectedColor: Colors.greenAccent,
      backgroundColor: OptikAdminTokens.bgMid,
      onSelected: (_) => onChanged(key),
    );
  }
}
