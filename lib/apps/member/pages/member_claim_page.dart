import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/garansi/garansi_service.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/safe_image_picker.dart';
import '../../../shared/theme.dart';
import '../member_layout.dart';
import '../member_widgets.dart';
import 'member_option_picker.dart';
import 'member_schedule_picker.dart';

/// Fitur 19 — klaim wajib datang ke toko + bawa barang.
class MemberClaimPage extends StatefulWidget {
  const MemberClaimPage({super.key, this.initialKartu});

  final Map<String, dynamic>? initialKartu;

  @override
  State<MemberClaimPage> createState() => _MemberClaimPageState();
}

class _MemberClaimPageState extends State<MemberClaimPage> {
  final _repo = MemberRepository();
  final _alasan = TextEditingController();
  List<Map<String, dynamic>> _kartu = const [];
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _toko = const [];
  String? _kartuId;
  String? _tokoId;
  Uint8List? _fotoBytes;
  String _fotoExt = 'jpg';
  DateTime? _jadwal;
  bool _loading = true;
  bool _busy = false;
  bool _needsLogin = false;
  /// False = RPC pengajuan gagal → jangan izinkan klaim (fail-closed).
  bool _openRequestsKnown = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialKartu;
    if (initial != null && GaransiService.kartuBisaDiklaim(initial)) {
      _kartuId = initial['id']?.toString();
      _tokoId = initial['toko_id']?.toString();
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _claimableKartu =>
      GaransiService.filterClaimableKartu(
        kartu: _kartu,
        requests: _requests,
        openRequestsKnown: _openRequestsKnown,
      );

  Map<String, dynamic>? _kartuById(String? id) {
    if (id == null) return null;
    for (final g in _kartu) {
      if (g['id']?.toString() == id) return g;
    }
    return null;
  }

  bool _hasOpenRequestFor(String kartuId) {
    if (!_openRequestsKnown) return true;
    for (final r in _requests) {
      if (r['kartu_id']?.toString() != kartuId) continue;
      if (GaransiService.isOpenClaimRequestStatus(r['status']?.toString())) {
        return true;
      }
    }
    return false;
  }

  String _friendlyClaimError(Object e) {
    if (e is PostgrestException) {
      final m = e.message.trim();
      if (m.isNotEmpty && m.length <= 200) return m;
    }
    var s = e.toString().trim();
    final extracted =
        RegExp(r'message:\s*([^,\n]+)').firstMatch(s)?.group(1)?.trim();
    if (extracted != null &&
        extracted.isNotEmpty &&
        extracted.length <= 200 &&
        !extracted.contains('{')) {
      return extracted;
    }
    s = s.replaceFirst(
      RegExp(r'^(Exception|PostgrestException|FunctionException):\s*'),
      '',
    );
    if (s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection closed')) {
      return 'Tidak ada koneksi. Periksa jaringan lalu coba lagi.';
    }
    if (s.isEmpty || s.length > 200 || s.contains('{') || s.contains('code:')) {
      return 'Gagal mengajukan klaim. Coba lagi.';
    }
    return s;
  }

  Future<void> _bootstrap() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      setState(() {
        _needsLogin = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _needsLogin = false;
      _loading = true;
    });
    try {
      final kartu = await _repo.listGaransi(phone);
      List<Map<String, dynamic>> reqs = const [];
      var openKnown = true;
      try {
        reqs = await _repo.listClaimRequests(phone);
      } catch (_) {
        // Fail-closed: tanpa data pengajuan, anggap status tidak diketahui.
        openKnown = false;
        reqs = const [];
      }
      List<Map<String, dynamic>> toko = [];
      try {
        final rows = await Supabase.instance.client
            .from('invoice_settings')
            .select('toko_id, shop_name')
            .order('toko_id');
        toko = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}
      if (!mounted) return;

      final claimable = GaransiService.filterClaimableKartu(
        kartu: kartu,
        requests: reqs,
        openRequestsKnown: openKnown,
      );
      var kartuId = _kartuId;
      if (kartuId == null ||
          !claimable.any((g) => g['id']?.toString() == kartuId)) {
        kartuId = claimable.isNotEmpty ? claimable.first['id']?.toString() : null;
      }
      String? tokoId = _tokoId;
      Map<String, dynamic>? selected;
      for (final g in kartu) {
        if (g['id']?.toString() == kartuId) {
          selected = g;
          break;
        }
      }
      tokoId ??= selected?['toko_id']?.toString();
      tokoId ??= toko.isNotEmpty ? toko.first['toko_id']?.toString() : null;

      setState(() {
        _kartu = kartu;
        _requests = reqs;
        _toko = toko;
        _kartuId = kartuId;
        _tokoId = tokoId;
        _openRequestsKnown = openKnown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyClaimError(e)),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    }
  }

  Future<void> _pickFoto(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file;
    if (source == ImageSource.camera) {
      file = await pickImageSafe(
        picker: picker,
        context: context,
        imageQuality: 82,
        maxWidth: 1600,
      );
    } else {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );
    }
    // Cancel picker = soft fail (jangan snackbar error).
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final ext = name.endsWith('.png')
        ? 'png'
        : name.endsWith('.webp')
            ? 'webp'
            : 'jpg';
    if (!mounted) return;
    setState(() {
      _fotoBytes = bytes;
      _fotoExt = ext;
    });
  }

  Future<void> _pickJadwal() async {
    final today = GaransiService.jakartaDateOnly();
    final kartu = _kartuById(_kartuId);
    if (kartu == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih kartu garansi dulu.')),
      );
      return;
    }
    final akhir = GaransiService.tanggalAkhirKartu(kartu);
    if (akhir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tanggal akhir garansi tidak valid.'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      return;
    }
    // Jangan perluas lastDate ke hari ini kalau window sudah lewat.
    if (akhir.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Masa garansi sudah habis — tidak bisa jadwalkan kunjungan.',
          ),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      return;
    }
    final last = akhir;
    final initial = _jadwal ??
        (today.isBefore(last) ? today.add(const Duration(days: 1)) : today);
    final picked = await pickMemberSchedule(
      context,
      initial: initial.isAfter(last) ? last : initial,
      firstDate: today,
      lastDate: last,
      dateHelpText:
          'Tanggal datang ke toko (maks. s/d akhir masa garansi aktif)',
      confirmTitle: 'Konfirmasi jadwal kunjungan',
    );
    if (picked == null || !mounted) return;
    setState(() => _jadwal = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login dulu.')),
      );
      return;
    }
    if (!_openRequestsKnown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak bisa cek pengajuan terbuka. Tarik refresh dulu.',
          ),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      return;
    }
    if (_kartuId == null ||
        _tokoId == null ||
        _alasan.text.trim().isEmpty ||
        _fotoBytes == null ||
        _jadwal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lengkapi kartu, cabang, alasan, foto, dan jadwal kunjungan.',
          ),
        ),
      );
      return;
    }
    final kartu = _kartuById(_kartuId);
    final blocked = kartu == null
        ? 'Kartu garansi tidak ditemukan.'
        : GaransiService.alasanTidakBisaKlaim(kartu);
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blocked), backgroundColor: OptikMemberTokens.danger),
      );
      return;
    }
    if (_hasOpenRequestFor(_kartuId!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pengajuan untuk kartu ini masih terbuka. Datang ke toko atau tunggu status selesai.',
          ),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      return;
    }
    final akhir = GaransiService.tanggalAkhirKartu(kartu!);
    if (akhir != null) {
      final jktVisit = GaransiService.jakartaDateOnly(_jadwal);
      if (jktVisit.isAfter(akhir)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Jadwal kunjungan di luar masa garansi (maks. 7 hari sejak diambil).',
            ),
            backgroundColor: OptikMemberTokens.danger,
          ),
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final fotoUrl = await _repo.uploadClaimPhoto(
        phone: phone,
        bytes: _fotoBytes!,
        ext: _fotoExt,
      );
      await _repo.submitClaimRequest(
        phone: phone,
        kartuId: _kartuId!,
        tokoId: _tokoId!,
        alasan: _alasan.text.trim(),
        jadwalKunjungan: _jadwal!,
        saleId: kartu['sale_id']?.toString(),
        memberId: MemberSession.instance.memberId,
        fotoUrl: fotoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pengajuan tersimpan. Datang ke toko sesuai jadwal membawa barang.',
          ),
        ),
      );
      _alasan.clear();
      setState(() {
        _fotoBytes = null;
        _jadwal = null;
      });
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyClaimError(e)),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _kartuLabel {
    final g = _kartuById(_kartuId);
    if (g == null) return _kartuId;
    return '${g['jenis_garansi']} · ${g['nama_produk']}';
  }

  String? get _tokoLabel {
    if (_tokoId == null) return null;
    for (final t in _toko) {
      if (t['toko_id']?.toString() == _tokoId) {
        return '${t['toko_id']} · ${t['shop_name'] ?? ''}';
      }
    }
    return _tokoId;
  }

  Future<void> _pickKartu() async {
    if (!_openRequestsKnown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak bisa cek pengajuan terbuka. Tarik refresh dulu.',
          ),
        ),
      );
      return;
    }
    final options = _claimableKartu;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak ada kartu aktif yang bisa diklaim. '
            'Cek status di Kartu garansi.',
          ),
        ),
      );
      return;
    }
    final picked = await showMemberOptionPicker<String>(
      context,
      title: 'Pilih kartu garansi',
      icon: Icons.verified_outlined,
      selected: _kartuId,
      searchHint: 'Cari kartu / produk…',
      options: options
          .map(
            (g) => MemberPickerOption<String>(
              value: g['id']?.toString() ?? '',
              label: '${g['jenis_garansi']} · ${g['nama_produk']}',
              subtitle: GaransiService.statusLabel(g),
              icon: Icons.verified_outlined,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList(),
    );
    if (picked == null || !mounted) return;
    final g = _kartuById(picked);
    setState(() {
      _kartuId = picked;
      final tid = g?['toko_id']?.toString();
      if (tid != null && tid.isNotEmpty) _tokoId = tid;
    });
  }

  Future<void> _pickToko() async {
    final picked = await showMemberOptionPicker<String>(
      context,
      title: 'Pilih cabang kunjungan',
      icon: Icons.storefront_outlined,
      selected: _tokoId,
      searchHint: 'Cari cabang…',
      options: _toko
          .map(
            (t) => MemberPickerOption<String>(
              value: t['toko_id']?.toString() ?? '',
              label: '${t['toko_id']}',
              subtitle: t['shop_name']?.toString(),
              icon: Icons.storefront_outlined,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList(),
    );
    if (picked != null && mounted) setState(() => _tokoId = picked);
  }

  String get _emptyClaimableMessage {
    if (!_openRequestsKnown) {
      return 'Tidak bisa cek pengajuan terbuka. Tarik refresh atau tekan muat ulang.';
    }
    if (_kartu.isEmpty) {
      return 'Belum ada kartu garansi. Kartu muncul setelah barang diambil di toko.';
    }
    return 'Tidak ada kartu aktif yang bisa diklaim saat ini '
        '(belum diambil, mati, sudah diklaim, atau pengajuan masih terbuka).';
  }

  @override
  Widget build(BuildContext context) {
    final m = MemberLayout.of(context);
    final pad = m.pagePadding;
    final jadwalLabel =
        _jadwal == null
            ? 'Pilih hari, tanggal & jam'
            : formatMemberSchedule(_jadwal!);

    return MemberPremiumScaffold(
      title: 'Klaim garansi',
      subtitle: 'Wajib ke toko + bawa barang',
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: _loading || _busy ? null : _bootstrap,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _needsLogin
              ? MemberEmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Login dulu',
                  message:
                      'Klaim garansi terikat nomor HP yang dipakai saat belanja.',
                  actionLabel: 'Ke login',
                  onAction: () =>
                      Navigator.of(context).pushReplacementNamed('/login'),
                )
              : RefreshIndicator(
                  onRefresh: _bootstrap,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(pad, 16, pad, 36),
                    children: [
                      MemberLayout.constrain(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: EdgeInsets.all(m.isTablet ? 16 : 14),
                              decoration: BoxDecoration(
                                color: OptikMemberTokens.blueSoft,
                                borderRadius: BorderRadius.circular(
                                    OptikMemberTokens.radiusMd),
                              ),
                              child: Text(
                                'App hanya mengajukan niat klaim. Keputusan bisa/tidak '
                                'hanya setelah petugas memeriksa barang di toko.\n'
                                'Masa garansi: ${GaransiService.garansiHari} hari sejak diambil (hari ke-${GaransiService.garansiHari} masih bisa; lebih dari itu mati) · maks. 1× per nota.',
                                style: TextStyle(
                                  color: OptikMemberTokens.blueDeep,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                  fontSize: m.bodySize,
                                ),
                              ),
                            ),
                            if (_claimableKartu.isEmpty) ...[
                              SizedBox(height: m.sectionGap),
                              Text(
                                _emptyClaimableMessage,
                                style: TextStyle(
                                  color: OptikMemberTokens.inkMuted,
                                  height: 1.4,
                                  fontSize: m.bodySize,
                                ),
                              ),
                            ],
                            SizedBox(height: m.sectionGap),
                            MemberPickerField(
                              label: 'Kartu garansi',
                              icon: Icons.verified_outlined,
                              valueLabel: _kartuLabel,
                              placeholder: 'Pilih kartu garansi',
                              metrics: m,
                              enabled: !_busy,
                              onTap: _pickKartu,
                            ),
                            const SizedBox(height: 12),
                            MemberPickerField(
                              label: 'Cabang kunjungan',
                              icon: Icons.storefront_outlined,
                              valueLabel: _tokoLabel,
                              placeholder: 'Pilih cabang',
                              metrics: m,
                              enabled: !_busy,
                              onTap: _pickToko,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _alasan,
                              maxLines: 3,
                              enabled: !_busy,
                              style: TextStyle(fontSize: m.bodySize),
                              decoration: const InputDecoration(
                                labelText: 'Alasan / keluhan',
                              ),
                            ),
                            SizedBox(height: m.sectionGap),
                            Text(
                              'Foto kondisi barang *',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: m.menuTitleSize,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_fotoBytes != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: AspectRatio(
                                  aspectRatio: m.isTablet ? 16 / 9 : 4 / 3,
                                  child: Image.memory(
                                    _fotoBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            else
                              Container(
                                height: m.isTablet ? 160 : 140,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: OptikMemberTokens.blueMist,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: OptikMemberTokens.lineSoft),
                                ),
                                child: Text(
                                  'Belum ada foto',
                                  style: TextStyle(
                                    color: OptikMemberTokens.inkMuted,
                                    fontSize: m.bodySize,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _pickFoto(ImageSource.camera),
                                    icon: const Icon(Icons.photo_camera_outlined),
                                    label: Text(
                                      'Kamera',
                                      style: TextStyle(fontSize: m.bodySize),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _pickFoto(ImageSource.gallery),
                                    icon: const Icon(Icons.photo_library_outlined),
                                    label: Text(
                                      'Galeri',
                                      style: TextStyle(fontSize: m.bodySize),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: m.sectionGap),
                            Text(
                              'Rencana datang ke toko *',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: m.menuTitleSize,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _busy ? null : _pickJadwal,
                                borderRadius: BorderRadius.circular(14),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Hari, tanggal & jam',
                                    prefixIcon: const Icon(
                                      Icons.event_available_rounded,
                                      color: OptikMemberTokens.blue,
                                    ),
                                    suffixIcon: const Icon(
                                      Icons.schedule_rounded,
                                      color: OptikMemberTokens.blue,
                                    ),
                                    filled: true,
                                    fillColor: OptikMemberTokens.blueMist,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    jadwalLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: m.bodySize,
                                      color: _jadwal == null
                                          ? OptikMemberTokens.inkMuted
                                          : OptikMemberTokens.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _busy ||
                                      !_openRequestsKnown ||
                                      _claimableKartu.isEmpty
                                  ? null
                                  : _submit,
                              style: FilledButton.styleFrom(
                                minimumSize:
                                    Size.fromHeight(m.isTablet ? 52 : 48),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      'Ajukan & siap datang ke toko',
                                      style: TextStyle(fontSize: m.bodySize),
                                    ),
                            ),
                            const SizedBox(height: 22),
                            const MemberSectionLabel('Pengajuan saya'),
                            if (!_openRequestsKnown)
                              Text(
                                'Gagal memuat pengajuan. Tarik refresh atau tekan muat ulang.',
                                style: TextStyle(
                                  color: OptikMemberTokens.danger,
                                  fontSize: m.bodySize,
                                  height: 1.4,
                                ),
                              )
                            else if (_requests.isEmpty)
                              Text(
                                'Belum ada pengajuan.',
                                style: TextStyle(
                                  color: OptikMemberTokens.inkMuted,
                                  fontSize: m.bodySize,
                                ),
                              )
                            else
                              ..._requests.map((r) {
                                final jadwalRaw =
                                    r['jadwal_kunjungan']?.toString();
                                final jadwalDt =
                                    jadwalRaw == null || jadwalRaw.isEmpty
                                        ? null
                                        : DateTime.tryParse(jadwalRaw)?.toLocal();
                                final foto = r['foto_url']?.toString();
                                final statusLabel =
                                    GaransiService.claimRequestStatusLabel(
                                  r['status']?.toString(),
                                );
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: foto != null && foto.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            foto,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                        )
                                      : Icon(
                                          Icons.assignment_outlined,
                                          color: OptikMemberTokens.blue,
                                          size: m.iconSize,
                                        ),
                                  title: Text(
                                    '$statusLabel · ${r['toko_id']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: m.menuTitleSize,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      r['alasan']?.toString() ?? '',
                                      if (jadwalDt != null)
                                        'Datang: ${formatMemberSchedule(jadwalDt)}',
                                      r['created_at']?.toString() ?? '',
                                    ].where((e) => e.isNotEmpty).join('\n'),
                                    style:
                                        TextStyle(fontSize: m.menuSubtitleSize),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
