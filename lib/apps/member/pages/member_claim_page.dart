import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _kartuId = widget.initialKartu?['id']?.toString();
    _tokoId = widget.initialKartu?['toko_id']?.toString();
    _bootstrap();
  }

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final phone = MemberSession.instance.phoneForQuery;
    setState(() => _loading = true);
    try {
      final kartu =
          phone.isEmpty ? <Map<String, dynamic>>[] : await _repo.listGaransi(phone);
      final reqs = phone.isEmpty
          ? <Map<String, dynamic>>[]
          : await _repo.listClaimRequests(phone);
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
      setState(() {
        _kartu = kartu;
        _requests = reqs;
        _toko = toko;
        _kartuId ??= kartu.isNotEmpty ? kartu.first['id']?.toString() : null;
        _tokoId ??= kartu.isNotEmpty
            ? kartu.first['toko_id']?.toString()
            : (toko.isNotEmpty ? toko.first['toko_id']?.toString() : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
    final now = DateTime.now();
    final picked = await pickMemberSchedule(
      context,
      initial: _jadwal ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
      dateHelpText: 'Tanggal datang ke toko',
      confirmTitle: 'Konfirmasi jadwal kunjungan',
    );
    if (picked == null || !mounted) return;
    setState(() => _jadwal = picked);
  }

  Future<void> _submit() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login dulu.')),
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
    Map<String, dynamic>? kartu;
    for (final g in _kartu) {
      if (g['id']?.toString() == _kartuId) {
        kartu = g;
        break;
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
        saleId: kartu?['sale_id']?.toString(),
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
            content: Text('$e'), backgroundColor: OptikMemberTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _kartuLabel {
    if (_kartuId == null) return null;
    for (final g in _kartu) {
      if (g['id']?.toString() == _kartuId) {
        return '${g['jenis_garansi']} · ${g['nama_produk']}';
      }
    }
    return _kartuId;
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
    final picked = await showMemberOptionPicker<String>(
      context,
      title: 'Pilih kartu garansi',
      icon: Icons.verified_outlined,
      selected: _kartuId,
      searchHint: 'Cari kartu / produk…',
      options: _kartu
          .map(
            (g) => MemberPickerOption<String>(
              value: g['id']?.toString() ?? '',
              label: '${g['jenis_garansi']} · ${g['nama_produk']}',
              icon: Icons.verified_outlined,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList(),
    );
    if (picked != null && mounted) setState(() => _kartuId = picked);
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                          'hanya setelah petugas memeriksa barang di toko.',
                          style: TextStyle(
                            color: OptikMemberTokens.blueDeep,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            fontSize: m.bodySize,
                          ),
                        ),
                      ),
                      SizedBox(height: m.sectionGap),
                      MemberPickerField(
                        label: 'Kartu garansi',
                        icon: Icons.verified_outlined,
                        valueLabel: _kartuLabel,
                        placeholder: 'Pilih kartu garansi',
                        metrics: m,
                        onTap: _pickKartu,
                      ),
                      const SizedBox(height: 12),
                      MemberPickerField(
                        label: 'Cabang kunjungan',
                        icon: Icons.storefront_outlined,
                        valueLabel: _tokoLabel,
                        placeholder: 'Pilih cabang',
                        metrics: m,
                        onTap: _pickToko,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _alasan,
                        maxLines: 3,
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
                            border: Border.all(color: OptikMemberTokens.lineSoft),
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
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: Size.fromHeight(m.isTablet ? 52 : 48),
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
                      if (_requests.isEmpty)
                        Text(
                          'Belum ada pengajuan.',
                          style: TextStyle(
                            color: OptikMemberTokens.inkMuted,
                            fontSize: m.bodySize,
                          ),
                        )
                      else
                        ..._requests.map((r) {
                          final jadwalRaw = r['jadwal_kunjungan']?.toString();
                          final jadwalDt = jadwalRaw == null || jadwalRaw.isEmpty
                              ? null
                              : DateTime.tryParse(jadwalRaw)?.toLocal();
                          final foto = r['foto_url']?.toString();
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
                                      errorBuilder: (_, __, ___) => const Icon(
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
                              '${r['status']} · ${r['toko_id']}',
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
                              style: TextStyle(fontSize: m.menuSubtitleSize),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
