import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../shared/theme.dart';
import '../../shared/local_form_draft.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/karyawan/pengaduan_case_flow.dart';
import '../../shared/pengaduan/pengaduan_product_sheet.dart';
import '../../shared/safe_image_picker.dart';

class PengaduanPage extends StatefulWidget {
  const PengaduanPage({super.key});

  @override
  State<PengaduanPage> createState() => _PengaduanPageState();
}

class _PengaduanPageState extends State<PengaduanPage> {
  final formKey = GlobalKey<FormState>();
  final TextEditingController deskripsiCtrl = TextEditingController();
  String? kategoriKode;
  Uint8List? buktiFoto;
  bool isSubmitting = false;
  bool _loadingMine = true;
  List<Map<String, dynamic>> _mine = [];
  final List<PengaduanItemLine> _items = [];
  RealtimeChannel? _mineRt;
  String? _mineRtKid;
  final _composeAutosave = DebouncedFormSave();

  String get _draftKey {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    return 'pengaduan_compose_draft_karyawan_$uid';
  }

  bool get _isProduk => PengaduanCaseFlow.isProduk(kategoriKode);

  bool get _canKirim => PengaduanCaseFlow.canSubmit(
        kategoriKode: kategoriKode,
        detail: deskripsiCtrl.text,
        hasFoto: buktiFoto != null,
        items: _items,
      );

  @override
  void initState() {
    super.initState();
    deskripsiCtrl.addListener(_onComposeChanged);
    _loadMine();
    unawaited(_restoreDraftIfNeeded());
  }

  void _onComposeChanged() {
    setState(() {});
    _scheduleComposeAutosave();
  }

  bool _hasComposeDraftContent() =>
      (kategoriKode ?? '').isNotEmpty ||
      deskripsiCtrl.text.trim().isNotEmpty ||
      buktiFoto != null ||
      _items.isNotEmpty;

  void _scheduleComposeAutosave() {
    if (!_hasComposeDraftContent()) return;
    _composeAutosave.schedule(() => _saveComposeDraftLocal(silent: true));
  }

  Future<void> _saveComposeDraftLocal({bool silent = true}) async {
    if (!_hasComposeDraftContent()) return;
    try {
      final fotoB64 = LocalFormDraft.bytesToB64(buktiFoto);
      await LocalFormDraft.save(_draftKey, {
        'kategori_kode': kategoriKode,
        'deskripsi': deskripsiCtrl.text,
        'foto_b64': fotoB64,
        'foto_omitted': buktiFoto != null && fotoB64 == null,
        'items': _items.map((e) => e.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('Pengaduan compose autosave: $e');
    }
  }

  Future<void> _clearComposeDraftLocal() async {
    await LocalFormDraft.clear(_draftKey);
  }

  Future<void> _restoreDraftIfNeeded() async {
    if (_hasComposeDraftContent()) return;
    try {
      final map = await LocalFormDraft.read(_draftKey);
      if (map == null) return;
      final itemsRaw = map['items'];
      final restoredItems = <PengaduanItemLine>[];
      if (itemsRaw is List) {
        for (final e in itemsRaw) {
          if (e is Map) {
            final line = PengaduanItemLine.tryParse(e);
            if (line != null) restoredItems.add(line);
          }
        }
      }
      final hasContent = (map['kategori_kode'] ?? '').toString().isNotEmpty ||
          (map['deskripsi'] ?? '').toString().trim().isNotEmpty ||
          LocalFormDraft.bytesFromB64(map['foto_b64']) != null ||
          restoredItems.isNotEmpty;
      if (!hasContent) return;
      if (!mounted) return;
      setState(() {
        final kode = (map['kategori_kode'] ?? '').toString().trim();
        kategoriKode = kode.isEmpty ? null : kode;
        deskripsiCtrl.text = (map['deskripsi'] ?? '').toString();
        buktiFoto = LocalFormDraft.bytesFromB64(map['foto_b64']);
        _items
          ..clear()
          ..addAll(restoredItems);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('pengaduan_draft_restored'.tr()),
          backgroundColor: OptikKaryawanTokens.seasideMid,
        ));
      }
    } catch (e) {
      debugPrint('Pengaduan draft restore: $e');
    }
  }

  @override
  void dispose() {
    _composeAutosave.cancel();
    if (_hasComposeDraftContent()) {
      unawaited(_saveComposeDraftLocal(silent: true));
    }
    deskripsiCtrl.removeListener(_onComposeChanged);
    deskripsiCtrl.dispose();
    final ch = _mineRt;
    _mineRt = null;
    if (ch != null) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
    super.dispose();
  }

  void _ensureMineRealtime(String karyawanId) {
    if (_mineRtKid == karyawanId) return;
    _mineRtKid = karyawanId;
    final prev = _mineRt;
    _mineRt = null;
    if (prev != null) {
      unawaited(Supabase.instance.client.removeChannel(prev));
    }
    final ch = Supabase.instance.client
        .channel('pengaduan-mine-$karyawanId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pengaduan',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'karyawan_id',
            value: karyawanId,
          ),
          callback: (_) {
            if (mounted) unawaited(_loadMine(silent: true));
          },
        );
    _mineRt = ch;
    ch.subscribe();
  }

  Future<Map<String, dynamic>?> _fetchKaryawan() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final byId = await Supabase.instance.client
        .from('karyawan')
        .select('id, toko_id, nama, nik, tenant_id')
        .eq('id', user.id)
        .maybeSingle();
    if (byId != null) return byId;
    final email = user.email;
    if (email == null) return null;
    return Supabase.instance.client
        .from('karyawan')
        .select('id, toko_id, nama, nik, tenant_id')
        .eq('email', email)
        .maybeSingle();
  }

  Future<void> _loadMine({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingMine = true);
    }
    try {
      final karyawan = await _fetchKaryawan();
      if (karyawan == null) {
        if (mounted) {
          setState(() {
            _mine = [];
            _loadingMine = false;
          });
        }
        return;
      }
      final rows = await Supabase.instance.client
          .from('pengaduan')
          .select(
            'id, kategori, kategori_kode, isi, items, status, keputusan, '
            'stok_tindakan, balasan, dibalas_at, dibalas_oleh, created_at',
          )
          .eq('karyawan_id', karyawan['id'])
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      _ensureMineRealtime(karyawan['id'].toString());
      setState(() {
        _mine = List<Map<String, dynamic>>.from(rows as List);
        _loadingMine = false;
      });
    } catch (_) {
      try {
        final karyawan = await _fetchKaryawan();
        if (karyawan == null) {
          if (mounted) setState(() => _loadingMine = false);
          return;
        }
        final rows = await Supabase.instance.client
            .from('pengaduan')
            .select(
              'id, kategori, isi, status, balasan, dibalas_at, dibalas_oleh, created_at',
            )
            .eq('karyawan_id', karyawan['id'])
            .order('created_at', ascending: false)
            .limit(30);
        if (!mounted) return;
        _ensureMineRealtime(karyawan['id'].toString());
        setState(() {
          _mine = List<Map<String, dynamic>>.from(rows as List);
          _loadingMine = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingMine = false);
      }
    }
  }

  Future<void> pilihBuktiFoto() async {
    final pickedFile = await pickImageSafe(context: context, imageQuality: 70);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;
      setState(() => buktiFoto = bytes);
      _scheduleComposeAutosave();
    }
  }

  Future<void> _pilihBarang() async {
    final karyawan = await _fetchKaryawan();
    if (!mounted) return;
    final toko = (karyawan?['toko_id'] ?? '').toString().trim();
    if (toko.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('pengaduan_err_toko'.tr())),
      );
      return;
    }
    final picked = await showPengaduanProductSheet(
      context,
      tokoId: toko,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final i = _items.indexWhere((e) => e.sku == picked.sku);
      if (i >= 0) {
        _items[i] = _items[i].copyWith(qty: _items[i].qty + picked.qty);
      } else {
        _items.add(picked);
      }
    });
    _scheduleComposeAutosave();
  }

  Future<void> kirimLaporan() async {
    final block = PengaduanCaseFlow.submitBlocker(
      kategoriKode: kategoriKode,
      detail: deskripsiCtrl.text,
      hasFoto: buktiFoto != null,
      items: _items,
    );
    if (block != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(block.tr()),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!formKey.currentState!.validate()) return;
    setState(() => isSubmitting = true);
    try {
      final karyawan = await _fetchKaryawan();
      if (karyawan == null) throw 'Data karyawan tidak ditemukan.';

      final bytes = buktiFoto!;
      final path =
          '${karyawan['id']}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage.from('pengaduan_photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final fotoUrl = Supabase.instance.client.storage
          .from('pengaduan_photos')
          .getPublicUrl(path);

      final kode = kategoriKode!;
      final tenant = (karyawan['tenant_id'] ?? '').toString().trim().isNotEmpty
          ? karyawan['tenant_id'].toString().trim()
          : AttendanceAdminScope.boundTenantIdOrNull();
      final row = <String, dynamic>{
        'karyawan_id': karyawan['id'],
        'toko_id': karyawan['toko_id'],
        'kategori': PengaduanCaseFlow.labelKey(kode).tr(),
        'kategori_kode': kode,
        'isi': deskripsiCtrl.text.trim(),
        'foto_url': fotoUrl,
        'status': 'OPEN',
        'sumber': PengaduanCaseFlow.sumberKaryawan,
        'pelapor_nama': (karyawan['nama'] ?? '').toString(),
        'pelapor_kontak': (karyawan['nik'] ?? '').toString(),
        'items': _isProduk ? _items.map((e) => e.toJson()).toList() : const [],
        if (tenant != null && tenant.isNotEmpty) 'tenant_id': tenant,
      };

      try {
        await Supabase.instance.client.from('pengaduan').insert(row);
      } catch (e) {
        row.remove('sumber');
        row.remove('pelapor_nama');
        row.remove('pelapor_kontak');
        row.remove('tenant_id');
        try {
          await Supabase.instance.client.from('pengaduan').insert(row);
        } catch (_) {
          if (_isProduk) throw e;
          row.remove('kategori_kode');
          row.remove('items');
          await Supabase.instance.client.from('pengaduan').insert(row);
        }
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await Supabase.instance.client.from('notifikasi').insert({
            'user_id': userId,
            'judul': 'Pengaduan terkirim',
            'isi':
                'Laporan "${PengaduanCaseFlow.labelKey(kode).tr()}" sudah masuk ke pusat.',
            'tipe': 'ADMIN',
          });
        } catch (_) {}
      }

      if (!mounted) return;
      deskripsiCtrl.clear();
      setState(() {
        kategoriKode = null;
        buktiFoto = null;
        _items.clear();
      });
      await _clearComposeDraftLocal();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("pengaduan_msg_sukses".tr()),
          backgroundColor: OptikKaryawanTokens.seasideMid,
        ),
      );
      await _loadMine();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim pengaduan: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  InputDecoration inputStyle(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        title: Text("pengaduan_title".tr()),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadMine(silent: true),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: OptikKaryawanTokens.cyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              "pengaduan_info_desc".tr(),
              style: const TextStyle(height: 1.35, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("pengaduan_label_kategori".tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: kategoriKode,
                  decoration: inputStyle("pengaduan_hint_kategori".tr()),
                  items: PengaduanCaseFlow.kategoriKodes
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(PengaduanCaseFlow.labelKey(k).tr()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      kategoriKode = v;
                      if (!PengaduanCaseFlow.isProduk(v)) _items.clear();
                    });
                    _scheduleComposeAutosave();
                  },
                  validator: (v) =>
                      v == null ? "pengaduan_err_kategori".tr() : null,
                ),
                const SizedBox(height: 12),
                Text("pengaduan_label_penjelasan".tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: deskripsiCtrl,
                  maxLines: 4,
                  decoration: inputStyle("pengaduan_hint_penjelasan".tr()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? "pengaduan_err_penjelasan".tr()
                      : null,
                ),
                if (_isProduk) ...[
                  const SizedBox(height: 14),
                  Text(
                    'pengaduan_label_barang'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'pengaduan_hint_barang'.tr(),
                    style: TextStyle(
                      color: OptikKaryawanTokens.muted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pilihBarang,
                    icon: const Icon(Icons.add_box_outlined),
                    label: Text('pengaduan_btn_pilih_barang'.tr()),
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    Text(
                      'pengaduan_err_barang'.tr(),
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    ..._items.asMap().entries.map(_itemRow),
                ],
                const SizedBox(height: 12),
                Text("pengaduan_label_foto".tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: pilihBuktiFoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    buktiFoto == null
                        ? "pengaduan_hint_foto".tr()
                        : "pengaduan_admin_foto_ok".tr(),
                  ),
                ),
                if (buktiFoto != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      buktiFoto!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: isSubmitting || !_canKirim ? null : kirimLaporan,
                  child: Text(
                    isSubmitting
                        ? "pengaduan_btn_mengirim".tr()
                        : "pengaduan_btn_kirim".tr(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'pengaduan_riwayat_title'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          if (_loadingMine)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_mine.isEmpty)
            Text(
              'pengaduan_riwayat_empty'.tr(),
              style: TextStyle(color: OptikKaryawanTokens.muted),
            )
          else
            ..._mine.map(_mineCard),
        ],
      ),
      ),
    );
  }

  Widget _itemRow(MapEntry<int, PengaduanItemLine> entry) {
    final i = entry.key;
    final line = entry.value;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikKaryawanTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  line.sku,
                  style: TextStyle(
                    color: OptikKaryawanTokens.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                if (line.qty <= 1) {
                  _items.removeAt(i);
                } else {
                  _items[i] = line.copyWith(qty: line.qty - 1);
                }
              });
              _scheduleComposeAutosave();
            },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '${line.qty}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _items[i] = line.copyWith(qty: line.qty + 1);
              });
              _scheduleComposeAutosave();
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _mineCard(Map<String, dynamic> row) {
    final st = (row['status'] ?? 'OPEN').toString().toUpperCase();
    final balasan = (row['balasan'] ?? '').toString().trim();
    final when = DateTime.tryParse((row['created_at'] ?? '').toString());
    final kode = PengaduanCaseFlow.kategoriKodeOf(row);
    final items = PengaduanCaseFlow.parseItems(row['items']);
    final Color stColor;
    if (st == 'DONE') {
      stColor = OptikKaryawanTokens.success;
    } else if (st == 'REJECTED') {
      stColor = OptikKaryawanTokens.danger;
    } else if (st == 'IN_PROGRESS') {
      stColor = OptikKaryawanTokens.ink;
    } else {
      stColor = Colors.orange.shade800;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikKaryawanTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kode.isNotEmpty
                      ? PengaduanCaseFlow.labelKey(kode).tr()
                      : (row['kategori'] ?? '-').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                st == 'DONE'
                    ? 'pengaduan_status_done'.tr()
                    : st == 'REJECTED'
                        ? 'pengaduan_status_rejected'.tr()
                        : st == 'IN_PROGRESS'
                            ? 'pengaduan_status_progress'.tr()
                            : 'pengaduan_status_open'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: stColor,
                ),
              ),
            ],
          ),
          if (when != null) ...[
            const SizedBox(height: 2),
            Text(
              DateFormat('d MMM yyyy · HH:mm').format(when.toLocal()),
              style: TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 11.5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            (row['isi'] ?? '').toString(),
            style: const TextStyle(height: 1.35, fontSize: 13),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...items.map(
              (e) => Text(
                '• ${e.nama}  ×${e.qty}',
                style: const TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
          if ((row['stok_tindakan'] ?? '').toString().toUpperCase() == 'BUANG' ||
              (row['stok_tindakan'] ?? '').toString().toUpperCase() ==
                  'BALIK') ...[
            const SizedBox(height: 6),
            Text(
              (row['stok_tindakan'] ?? '').toString().toUpperCase() == 'BUANG'
                  ? 'pengaduan_admin_stok_buang'.tr()
                  : 'pengaduan_admin_stok_balik'.tr(),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (balasan.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: st == 'REJECTED'
                    ? OptikKaryawanTokens.danger.withOpacity(0.08)
                    : OptikKaryawanTokens.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'pengaduan_riwayat_balasan'.tr(namedArgs: {
                      'oleh': (row['dibalas_oleh'] ?? 'Admin').toString(),
                    }),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(balasan, style: const TextStyle(height: 1.35, fontSize: 13)),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              st == 'IN_PROGRESS'
                  ? 'pengaduan_riwayat_diusut'.tr()
                  : 'pengaduan_riwayat_menunggu'.tr(),
              style: TextStyle(
                color: OptikKaryawanTokens.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
