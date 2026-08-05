import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../shared/member/member_home_controller.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_status_watch.dart';
import '../../../shared/theme.dart';
import '../../../shared/wilayah/indonesia_wilayah_api.dart';
import '../member_forgot_password_page.dart';
import '../member_layout.dart';
import '../member_widgets.dart';
import 'member_care_page.dart';
import 'member_date_picker.dart';
import 'member_face_shape_page.dart';
import 'member_notifications_page.dart';
import 'member_option_picker.dart';
import 'member_software_update_page.dart';

/// Tab Akun — daftar menu; isi detail dibuka setelah diklik.
/// Layout: mode HP (1 kolom) vs mode tablet (grid 2 kolom).
class MemberProfilePage extends StatefulWidget {
  const MemberProfilePage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  @override
  void initState() {
    super.initState();
    MemberSession.instance.addListener(_onSession);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MemberSession.instance.removeListener(_onSession);
    super.dispose();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar akun?'),
        content:
            const Text('Anda perlu login lagi untuk melihat nota & garansi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await MemberSession.instance.logout();
    MemberStatusWatch.instance.stop();
    // Bersihkan cache beranda agar guest/login berikutnya tidak lihat data lama.
    await MemberHomeController.instance.refresh(force: true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  List<_MenuItem> _accountMenus(MemberSession s) {
    return [
      _MenuItem(
        icon: Icons.badge_outlined,
        title: 'Data diri',
        subtitle: 'Nama, WA/HP, email, tanggal lahir, alamat',
        onTap: () => _open(const MemberPersonalDataPage()),
      ),
      _MenuItem(
        icon: Icons.lock_outline_rounded,
        title: 'Keamanan',
        subtitle: 'Ubah password akun',
        onTap: () => _open(
          MemberForgotPasswordPage(
            initialIdentifier: (s.email?.isNotEmpty == true)
                ? s.email
                : (s.phoneRaw ?? s.phoneE164),
          ),
        ),
      ),
      _MenuItem(
        icon: Icons.family_restroom_rounded,
        title: 'Keluarga',
        subtitle: 'Anggota yang sering ikut belanja / garansi',
        onTap: () => _open(const MemberFamilyPage()),
      ),
      _MenuItem(
        icon: Icons.tune_rounded,
        title: 'Preferensi app',
        subtitle: 'Ukuran teks & bahasa',
        onTap: () => _open(const MemberPreferencesPage()),
      ),
    ];
  }

  List<_MenuItem> _otherMenus() {
    return [
      _MenuItem(
        icon: Icons.system_update_rounded,
        title: 'Update aplikasi',
        subtitle: 'Cek & pasang versi terbaru Member',
        onTap: () => _open(const MemberSoftwareUpdatePage()),
      ),
      _MenuItem(
        icon: Icons.face_retouching_natural_rounded,
        title: 'Bentuk wajah',
        subtitle: 'Referensi bentuk + rekomendasi frame',
        onTap: () => _open(const MemberFaceShapePage()),
      ),
      _MenuItem(
        icon: Icons.notifications_active_outlined,
        title: 'Notifikasi',
        subtitle: 'Update status pesanan',
        onTap: () => _open(const MemberNotificationsPage()),
      ),
      _MenuItem(
        icon: Icons.menu_book_outlined,
        title: 'Panduan perawatan',
        subtitle: 'Tips & syarat garansi',
        onTap: () => _open(const MemberCarePage()),
      ),
      _MenuItem(
        icon: Icons.info_outline_rounded,
        title: 'Kehilangan kacamata',
        subtitle: 'Bukan tanggung jawab toko',
        onTap: () => _open(
          const MemberBaseFeaturePage(
            title: 'Kehilangan kacamata',
            eyebrow: 'Penting',
            icon: Icons.info_outline_rounded,
            description:
                'Kehilangan kacamata bukan tanggung jawab Optik B. Riski. '
                'Gunakan riwayat nota/resep di app untuk membantu pesan ulang di toko — tanpa janji ganti rugi.',
            bullets: [
              'Buka Riwayat / Resep & pesan ulang',
              'Hubungi cabang terdekat via WA',
              'Kehilangan di luar kebijakan garansi standar',
            ],
          ),
        ),
      ),
    ];
  }

  Widget _menuBlock(List<_MenuItem> items, MemberLayoutMetrics m) {
    if (m.menuColumns <= 1) {
      return _MenuCard(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _MenuTile(item: items[i], metrics: m),
          ],
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: m.menuColumns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: m.isTablet ? 2.35 : 2.1,
      ),
      itemBuilder: (context, i) => _MenuGridCard(item: items[i], metrics: m),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = MemberSession.instance;
    final m = MemberLayout.of(context);
    final pad = m.pagePadding;

    final content = ListView(
      padding: EdgeInsets.fromLTRB(pad, m.isTablet ? 20 : 16, pad, 36),
      children: [
        MemberLayout.constrain(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileHero(session: s, metrics: m),
              SizedBox(height: m.sectionGap),
              if (!s.isLoggedIn) ...[
                FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed('/login'),
                  child: Text(
                    'Masuk / Daftar',
                    style: TextStyle(fontSize: m.bodySize),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Login untuk mengelola data diri, keluarga, dan keamanan akun.',
                  style: TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    height: 1.35,
                    fontSize: m.bodySize,
                  ),
                ),
              ] else ...[
                _menuBlock(_accountMenus(s), m),
                SizedBox(height: m.sectionGap),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OptikMemberTokens.danger,
                    side: const BorderSide(color: OptikMemberTokens.danger),
                    minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
                  ),
                  onPressed: _logout,
                  child: Text(
                    'Keluar dari akun',
                    style: TextStyle(fontSize: m.bodySize),
                  ),
                ),
              ],
              SizedBox(height: m.isTablet ? 22 : 18),
              const MemberSectionLabel('Lainnya'),
              SizedBox(height: m.isTablet ? 10 : 8),
              if (m.menuColumns > 1)
                _menuBlock(_otherMenus(), m)
              else ...[
                for (final item in _otherMenus()) ...[
                  MemberFeatureTile(
                    icon: item.icon,
                    title: item.title,
                    subtitle: item.subtitle,
                    onTap: item.onTap,
                  ),
                  SizedBox(height: m.isTablet ? 12 : 10),
                ],
              ],
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(color: OptikMemberTokens.canvas, child: content);
    }
    return MemberPremiumScaffold(title: 'Akun', body: content);
  }
}

/// Halaman edit data diri (dibuka dari menu Akun).
class MemberPersonalDataPage extends StatefulWidget {
  const MemberPersonalDataPage({super.key});

  @override
  State<MemberPersonalDataPage> createState() => _MemberPersonalDataPageState();
}

class _MemberPersonalDataPageState extends State<MemberPersonalDataPage> {
  final _repo = MemberRepository();
  final _wilayah = IndonesiaWilayahApi();
  final _nama = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _jalan = TextEditingController();
  DateTime? _dob;
  double _fontScale = 1.0;
  bool _saving = false;
  bool _loadingWilayah = false;

  List<Map<String, dynamic>> _listProvinsi = [];
  List<Map<String, dynamic>> _listKota = [];
  List<Map<String, dynamic>> _listKecamatan = [];
  List<Map<String, dynamic>> _listDesa = [];
  String? _idProvinsi;
  String? _idKota;
  String? _idKecamatan;
  String? _idDesa;
  String? _namaProvinsi;
  String? _namaKota;
  String? _namaKecamatan;
  String? _namaDesa;

  @override
  void initState() {
    super.initState();
    final s = MemberSession.instance;
    _nama.text = s.nama ?? '';
    _email.text = s.email ?? '';
    _phone.text = s.phoneRaw ?? s.phoneE164 ?? '';
    _jalan.text = _extractJalan(s.alamat);
    _dob = s.tanggalLahir;
    _fontScale = s.fontScale;
    _loadProvinsi();
  }

  /// Ambil bagian jalan dari alamat lama (sebelum "Desa " / "Kec.").
  String _extractJalan(String? alamat) {
    final a = (alamat ?? '').trim();
    if (a.isEmpty) return '';
    final desaIdx = a.indexOf(', Desa ');
    final kecIdx = a.indexOf(', Kec. ');
    final cut = desaIdx >= 0
        ? desaIdx
        : kecIdx >= 0
            ? kecIdx
            : -1;
    if (cut > 0) return a.substring(0, cut).trim();
    return a;
  }

  Future<void> _loadProvinsi() async {
    setState(() => _loadingWilayah = true);
    try {
      final list = await _wilayah.provinces();
      if (!mounted) return;
      setState(() => _listProvinsi = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat daftar provinsi: $e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingWilayah = false);
    }
  }

  Future<void> _onProvinsi(String? id) async {
    if (id == null) return;
    final row =
        _listProvinsi.firstWhere((e) => e['id']?.toString() == id);
    final nama = formatWilayahLabel(row['name']?.toString() ?? '');
    setState(() {
      _idProvinsi = id;
      _namaProvinsi = nama;
      _idKota = null;
      _idKecamatan = null;
      _idDesa = null;
      _namaKota = null;
      _namaKecamatan = null;
      _namaDesa = null;
      _listKota = [];
      _listKecamatan = [];
      _listDesa = [];
      _loadingWilayah = true;
    });
    try {
      final list = await _wilayah.regencies(id);
      if (!mounted) return;
      setState(() => _listKota = list);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat kota/kabupaten')),
      );
    } finally {
      if (mounted) setState(() => _loadingWilayah = false);
    }
  }

  Future<void> _onKota(String? id) async {
    if (id == null) return;
    final row = _listKota.firstWhere((e) => e['id']?.toString() == id);
    final nama = formatWilayahLabel(row['name']?.toString() ?? '');
    setState(() {
      _idKota = id;
      _namaKota = nama;
      _idKecamatan = null;
      _idDesa = null;
      _namaKecamatan = null;
      _namaDesa = null;
      _listKecamatan = [];
      _listDesa = [];
      _loadingWilayah = true;
    });
    try {
      final list = await _wilayah.districts(id);
      if (!mounted) return;
      setState(() => _listKecamatan = list);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat kecamatan')),
      );
    } finally {
      if (mounted) setState(() => _loadingWilayah = false);
    }
  }

  Future<void> _onKecamatan(String? id) async {
    if (id == null) return;
    final row =
        _listKecamatan.firstWhere((e) => e['id']?.toString() == id);
    final nama = formatWilayahLabel(row['name']?.toString() ?? '');
    setState(() {
      _idKecamatan = id;
      _namaKecamatan = nama;
      _idDesa = null;
      _namaDesa = null;
      _listDesa = [];
      _loadingWilayah = true;
    });
    try {
      final list = await _wilayah.villages(id);
      if (!mounted) return;
      setState(() => _listDesa = list);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat kelurahan/desa')),
      );
    } finally {
      if (mounted) setState(() => _loadingWilayah = false);
    }
  }

  void _onDesa(String? id) {
    if (id == null) return;
    final row = _listDesa.firstWhere((e) => e['id']?.toString() == id);
    final nama = formatWilayahLabel(row['name']?.toString() ?? '');
    setState(() {
      _idDesa = id;
      _namaDesa = nama;
    });
  }

  String? _composedAlamat() {
    final jalan = _jalan.text.trim();
    final hasWilayah = _namaProvinsi != null &&
        _namaKota != null &&
        _namaKecamatan != null &&
        _namaDesa != null;
    if (!hasWilayah) {
      if (_idProvinsi != null ||
          _idKota != null ||
          _idKecamatan != null ||
          _idDesa != null) {
        return null; // partial selection
      }
      return jalan;
    }
    final parts = <String>[
      if (jalan.isNotEmpty) jalan,
      'Desa $_namaDesa',
      'Kec. $_namaKecamatan',
      _namaKota!,
      _namaProvinsi!,
    ];
    return parts.join(', ');
  }

  @override
  void dispose() {
    _nama.dispose();
    _email.dispose();
    _phone.dispose();
    _jalan.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showMemberDatePicker(
      context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 5, now.month, now.day),
      title: 'Tanggal lahir',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  String? _wilayahName(List<Map<String, dynamic>> items, String? id) {
    if (id == null) return null;
    for (final e in items) {
      if (e['id']?.toString() == id) {
        return formatWilayahLabel(e['name']?.toString() ?? '');
      }
    }
    return null;
  }

  Future<void> _pickWilayah({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required String? selectedId,
    required Future<void> Function(String id) onPicked,
  }) async {
    if (items.isEmpty) return;
    final picked = await showMemberOptionPicker<String>(
      context,
      title: title,
      icon: icon,
      selected: selectedId,
      searchHint: 'Cari $title…',
      options: items
          .map(
            (e) => MemberPickerOption<String>(
              value: e['id']?.toString() ?? '',
              label: formatWilayahLabel(e['name']?.toString() ?? ''),
              icon: icon,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList(),
    );
    if (picked != null && mounted) await onPicked(picked);
  }

  Future<void> _save() async {
    final s = MemberSession.instance;
    final phoneKey = s.phoneForQuery;
    if (phoneKey.isEmpty) return;
    final nama = _nama.text.trim();
    final email = _email.text.trim();
    if (nama.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama wajib diisi')),
      );
      return;
    }
    if (email.isNotEmpty && !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Format email tidak valid')),
      );
      return;
    }
    final alamat = _composedAlamat();
    if (alamat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi alamat sampai kelurahan/desa'),
        ),
      );
      return;
    }
    if (alamat.isNotEmpty && _jalan.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi detail jalan / RT-RW')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.upsertProfile(
        phone: phoneKey,
        nama: nama,
        email: email,
        alamat: alamat,
        phoneRaw: _phone.text.trim(),
        tanggalLahir: _dob,
        fontScale: _fontScale,
        locale: context.locale.languageCode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil disimpan'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final pad = m.pagePadding;
    final dobLabel = _dob == null
        ? 'Pilih tanggal lahir'
        : DateFormat('dd/MM/yyyy').format(_dob!);

    final namaField = _field(
      controller: _nama,
      label: 'Nama lengkap *',
      icon: Icons.badge_outlined,
      textCapitalization: TextCapitalization.words,
      metrics: m,
    );
    final phoneField = _field(
      controller: _phone,
      label: 'No. WhatsApp / HP *',
      icon: Icons.phone_android_rounded,
      keyboard: TextInputType.phone,
      formatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
      ],
      metrics: m,
    );
    final emailField = _field(
      controller: _email,
      label: 'Email',
      icon: Icons.email_outlined,
      keyboard: TextInputType.emailAddress,
      metrics: m,
    );
    final dobField = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _pickDob,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: _dec(
            label: 'Tanggal lahir',
            icon: Icons.cake_outlined,
            suffix: const Icon(
              Icons.calendar_month_rounded,
              color: OptikMemberTokens.blue,
            ),
            metrics: m,
          ),
          child: Text(
            dobLabel,
            style: TextStyle(
              color: _dob == null
                  ? OptikMemberTokens.inkMuted
                  : OptikMemberTokens.ink,
              fontWeight: FontWeight.w600,
              fontSize: m.bodySize,
            ),
          ),
        ),
      ),
    );

    return MemberPremiumScaffold(
      title: 'Data diri',
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, m.isTablet ? 20 : 16, pad, 36),
        children: [
          MemberLayout.constrain(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dipakai di nota, garansi, dan OTP. Pakai nomor yang sama saat belanja.',
                  style: TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    height: 1.35,
                    fontSize: m.bodySize,
                  ),
                ),
                SizedBox(height: m.sectionGap),
                if (m.formColumns > 1) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: namaField),
                      const SizedBox(width: 12),
                      Expanded(child: phoneField),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: emailField),
                      const SizedBox(width: 12),
                      Expanded(child: dobField),
                    ],
                  ),
                ] else ...[
                  namaField,
                  const SizedBox(height: 12),
                  phoneField,
                  const SizedBox(height: 12),
                  emailField,
                  const SizedBox(height: 12),
                  dobField,
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: OptikMemberTokens.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Alamat',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: m.bodySize,
                        color: OptikMemberTokens.blueDeep,
                      ),
                    ),
                    if (_loadingWilayah) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pilih dari provinsi sampai kelurahan, lalu isi detail jalan.',
                  style: TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    fontSize: m.menuSubtitleSize,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                MemberPickerField(
                  label: 'Provinsi',
                  icon: Icons.map_outlined,
                  valueLabel: _wilayahName(_listProvinsi, _idProvinsi) ??
                      _namaProvinsi,
                  metrics: m,
                  onTap: () => _pickWilayah(
                    title: 'Pilih provinsi',
                    icon: Icons.map_outlined,
                    items: _listProvinsi,
                    selectedId: _idProvinsi,
                    onPicked: _onProvinsi,
                  ),
                ),
                const SizedBox(height: 12),
                MemberPickerField(
                  label: 'Kota / Kabupaten',
                  icon: Icons.location_city_outlined,
                  valueLabel: _wilayahName(_listKota, _idKota) ?? _namaKota,
                  enabled: _idProvinsi != null && _listKota.isNotEmpty,
                  metrics: m,
                  onTap: () => _pickWilayah(
                    title: 'Pilih kota / kabupaten',
                    icon: Icons.location_city_outlined,
                    items: _listKota,
                    selectedId: _idKota,
                    onPicked: _onKota,
                  ),
                ),
                const SizedBox(height: 12),
                MemberPickerField(
                  label: 'Kecamatan',
                  icon: Icons.holiday_village_outlined,
                  valueLabel:
                      _wilayahName(_listKecamatan, _idKecamatan) ??
                          _namaKecamatan,
                  enabled: _idKota != null && _listKecamatan.isNotEmpty,
                  metrics: m,
                  onTap: () => _pickWilayah(
                    title: 'Pilih kecamatan',
                    icon: Icons.holiday_village_outlined,
                    items: _listKecamatan,
                    selectedId: _idKecamatan,
                    onPicked: _onKecamatan,
                  ),
                ),
                const SizedBox(height: 12),
                MemberPickerField(
                  label: 'Kelurahan / Desa',
                  icon: Icons.home_work_outlined,
                  valueLabel: _wilayahName(_listDesa, _idDesa) ?? _namaDesa,
                  enabled: _idKecamatan != null && _listDesa.isNotEmpty,
                  metrics: m,
                  onTap: () => _pickWilayah(
                    title: 'Pilih kelurahan / desa',
                    icon: Icons.home_work_outlined,
                    items: _listDesa,
                    selectedId: _idDesa,
                    onPicked: (id) async => _onDesa(id),
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _jalan,
                  label: 'Detail jalan / RT-RW *',
                  icon: Icons.signpost_outlined,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  metrics: m,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Simpan profil',
                          style: TextStyle(fontSize: m.bodySize),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MemberFamilyPage extends StatefulWidget {
  const MemberFamilyPage({super.key});

  @override
  State<MemberFamilyPage> createState() => _MemberFamilyPageState();
}

class _MemberFamilyPageState extends State<MemberFamilyPage> {
  final _repo = MemberRepository();
  final _famNama = TextEditingController();
  final _famHub = TextEditingController();
  final _famPhone = TextEditingController();
  List<Map<String, dynamic>> _family = const [];
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _famNama.dispose();
    _famHub.dispose();
    _famPhone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = MemberSession.instance.memberId;
    if (id == null) return;
    final list = await _repo.listFamily(id);
    if (!mounted) return;
    setState(() => _family = list);
  }

  Future<void> _add() async {
    final id = MemberSession.instance.memberId;
    final nama = _famNama.text.trim();
    if (id == null) return;
    if (nama.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi nama anggota keluarga')),
      );
      return;
    }
    setState(() => _adding = true);
    try {
      await _repo.addFamily(
        memberId: id,
        nama: nama,
        hubungan: _famHub.text.trim(),
        phone: _famPhone.text.trim().isEmpty ? null : _famPhone.text.trim(),
      );
      _famNama.clear();
      _famHub.clear();
      _famPhone.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anggota keluarga ditambahkan')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final pad = m.pagePadding;

    return MemberPremiumScaffold(
      title: 'Keluarga',
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, m.isTablet ? 20 : 16, pad, 36),
        children: [
          MemberLayout.constrain(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Anggota yang sering ikut belanja atau klaim garansi.',
                  style: TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    height: 1.35,
                    fontSize: m.bodySize,
                  ),
                ),
                SizedBox(height: m.sectionGap),
                if (_family.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Belum ada anggota.',
                      style: TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: m.bodySize,
                      ),
                    ),
                  ),
                if (m.menuColumns > 1 && _family.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _family.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 3.2,
                    ),
                    itemBuilder: (context, i) =>
                        _FamilyCard(data: _family[i], metrics: m),
                  )
                else
                  ..._family.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FamilyCard(data: f, metrics: m),
                      )),
                const SizedBox(height: 8),
                if (m.formColumns > 1) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          controller: _famNama,
                          label: 'Nama anggota',
                          icon: Icons.person_add_alt_1_outlined,
                          textCapitalization: TextCapitalization.words,
                          metrics: m,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          controller: _famHub,
                          label: 'Hubungan (anak / pasangan / dll.)',
                          icon: Icons.diversity_3_outlined,
                          metrics: m,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field(
                    controller: _famPhone,
                    label: 'No. WA anggota (opsional)',
                    icon: Icons.phone_outlined,
                    keyboard: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                    ],
                    metrics: m,
                  ),
                ] else ...[
                  _field(
                    controller: _famNama,
                    label: 'Nama anggota',
                    icon: Icons.person_add_alt_1_outlined,
                    textCapitalization: TextCapitalization.words,
                    metrics: m,
                  ),
                  const SizedBox(height: 8),
                  _field(
                    controller: _famHub,
                    label: 'Hubungan (anak / pasangan / dll.)',
                    icon: Icons.diversity_3_outlined,
                    metrics: m,
                  ),
                  const SizedBox(height: 8),
                  _field(
                    controller: _famPhone,
                    label: 'No. WA anggota (opsional)',
                    icon: Icons.phone_outlined,
                    keyboard: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                    ],
                    metrics: m,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _adding ? null : _add,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
                  ),
                  child: _adding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Tambah anggota',
                          style: TextStyle(fontSize: m.bodySize),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MemberPreferencesPage extends StatefulWidget {
  const MemberPreferencesPage({super.key});

  @override
  State<MemberPreferencesPage> createState() => _MemberPreferencesPageState();
}

class _MemberPreferencesPageState extends State<MemberPreferencesPage> {
  final _repo = MemberRepository();
  late double _fontScale;

  @override
  void initState() {
    super.initState();
    _fontScale = MemberSession.instance.fontScale;
  }

  Future<void> _persistScale(double v) async {
    setState(() => _fontScale = v);
    final s = MemberSession.instance;
    if (!s.isLoggedIn) return;
    await _repo.upsertProfile(
      phone: s.phoneForQuery,
      fontScale: v,
      locale: context.locale.languageCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = MemberSession.instance;
    final m = MemberLayout.of(context);
    final pad = m.pagePadding;

    return MemberPremiumScaffold(
      title: 'Preferensi',
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, m.isTablet ? 20 : 16, pad, 36),
        children: [
          MemberLayout.constrain(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ukuran teks: ${_fontScale.toStringAsFixed(1)}x',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: m.menuTitleSize,
                  ),
                ),
                Slider(
                  value: _fontScale,
                  min: 0.9,
                  max: 1.35,
                  divisions: 9,
                  activeColor: OptikMemberTokens.blue,
                  label: '${_fontScale.toStringAsFixed(1)}x',
                  onChanged: (v) => setState(() => _fontScale = v),
                  onChangeEnd: _persistScale,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.translate_rounded,
                    color: OptikMemberTokens.blue,
                    size: m.iconSize,
                  ),
                  title: Text(
                    'Bahasa: ${context.locale.languageCode == 'id' ? 'Indonesia' : 'English'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: m.menuTitleSize,
                    ),
                  ),
                  subtitle: Text(
                    'Ketuk untuk ganti ID / EN',
                    style: TextStyle(fontSize: m.menuSubtitleSize),
                  ),
                  trailing: const Icon(Icons.swap_horiz_rounded),
                  onTap: () async {
                    final next = context.locale.languageCode == 'id'
                        ? const Locale('en')
                        : const Locale('id');
                    await context.setLocale(next);
                    if (!mounted) return;
                    if (s.isLoggedIn) {
                      await _repo.upsertProfile(
                        phone: s.phoneForQuery,
                        locale: next.languageCode,
                        fontScale: _fontScale,
                      );
                    }
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.session, required this.metrics});

  final MemberSession session;
  final MemberLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final name = session.isLoggedIn
        ? ((session.nama ?? '').trim().isNotEmpty
            ? session.nama!.trim()
            : 'Member')
        : 'Tamu';
    final phone = session.isLoggedIn
        ? (session.phoneRaw ?? session.phoneE164 ?? '-')
        : 'Belum login';
    final email = session.email?.trim();
    final avatarR = metrics.isTablet ? 36.0 : 30.0;

    return Container(
      padding: EdgeInsets.all(metrics.isTablet ? 22 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [OptikMemberTokens.blueDeep, OptikMemberTokens.blue],
        ),
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusLg),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: avatarR,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.isTablet ? 30 : 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: metrics.isTablet ? 16 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.heroTitleSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: metrics.heroSubtitleSize,
                  ),
                ),
                if (email != null && email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: metrics.menuSubtitleSize,
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

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OptikMemberTokens.lineSoft),
        boxShadow: OptikMemberTokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.metrics});

  final _MenuItem item;
  final MemberLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: metrics.isTablet ? 16 : 14,
        vertical: metrics.isTablet ? 6 : 4,
      ),
      leading: Icon(item.icon, color: OptikMemberTokens.blue, size: metrics.iconSize),
      title: Text(
        item.title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: metrics.menuTitleSize,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        style: TextStyle(
          color: OptikMemberTokens.inkMuted,
          fontSize: metrics.menuSubtitleSize,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: item.onTap,
    );
  }
}

class _MenuGridCard extends StatelessWidget {
  const _MenuGridCard({required this.item, required this.metrics});

  final _MenuItem item;
  final MemberLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OptikMemberTokens.lineSoft),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: OptikMemberTokens.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.icon,
                  color: OptikMemberTokens.blue,
                  size: metrics.iconSize,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: metrics.menuTitleSize,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: OptikMemberTokens.inkMuted,
                        fontSize: metrics.menuSubtitleSize,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: OptikMemberTokens.blue),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.data, required this.metrics});

  final Map<String, dynamic> data;
  final MemberLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.isTablet ? 14 : 12,
        vertical: metrics.isTablet ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikMemberTokens.lineSoft),
      ),
      child: Row(
        children: [
          Icon(
            Icons.family_restroom_rounded,
            color: OptikMemberTokens.blue,
            size: metrics.iconSize,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${data['nama']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: metrics.menuTitleSize,
                  ),
                ),
                Text(
                  [
                    data['hubungan']?.toString(),
                    data['phone_e164']?.toString(),
                  ]
                      .where((e) => e != null && e.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: OptikMemberTokens.inkMuted,
                    fontSize: metrics.menuSubtitleSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _dec({
  required String label,
  required IconData icon,
  Widget? suffix,
  MemberLayoutMetrics? metrics,
}) {
  final labelSize = metrics?.labelSize ?? 12.5;
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(fontSize: labelSize),
    prefixIcon: Icon(icon, color: OptikMemberTokens.blue),
    suffixIcon: suffix,
    filled: true,
    fillColor: OptikMemberTokens.blueMist,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: OptikMemberTokens.lineSoft),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: OptikMemberTokens.lineSoft),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: OptikMemberTokens.blue, width: 1.6),
    ),
  );
}

Widget _field({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  TextInputType? keyboard,
  List<TextInputFormatter>? formatters,
  TextCapitalization textCapitalization = TextCapitalization.none,
  int maxLines = 1,
  MemberLayoutMetrics? metrics,
}) {
  return TextField(
    controller: controller,
    keyboardType: keyboard,
    inputFormatters: formatters,
    textCapitalization: textCapitalization,
    maxLines: maxLines,
    style: TextStyle(fontSize: metrics?.bodySize ?? 14),
    decoration: _dec(label: label, icon: icon, metrics: metrics),
  );
}
