import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/karyawan/pengaduan_case_flow.dart';
import '../../shared/local_form_draft.dart';
import '../../shared/pengaduan/pengaduan_product_sheet.dart';
import '../../shared/safe_image_picker.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Form kirim pengaduan dari APK Admin (bukan partner / karyawan lain).
class PengaduanComposePage extends StatefulWidget {
  const PengaduanComposePage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<PengaduanComposePage> createState() => _PengaduanComposePageState();
}

class _PengaduanComposePageState extends State<PengaduanComposePage> {
  final _db = Supabase.instance.client;
  final _detail = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _kategoriKode;
  String? _tokoId;
  Uint8List? _fotoBytes;
  bool _submitting = false;
  List<String> _tokoOptions = const [];
  final List<PengaduanItemLine> _items = [];
  final _composeAutosave = DebouncedFormSave();

  String get _draftKey {
    final uid = _db.auth.currentUser?.id ?? 'anon';
    return 'pengaduan_compose_draft_admin_$uid';
  }

  bool get _isProduk => PengaduanCaseFlow.isProduk(_kategoriKode);

  bool get _canKirim =>
      PengaduanCaseFlow.canSubmit(
        kategoriKode: _kategoriKode,
        detail: _detail.text,
        hasFoto: _fotoBytes != null,
        items: _items,
        allowedKodes: PengaduanCaseFlow.kategoriKodesPublik,
      ) &&
      (_tokoId ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _detail.addListener(_onComposeChanged);
    _tokoId = AttendanceAdminScope.tokoOf(widget.profile);
    _loadToko();
  }

  void _onComposeChanged() {
    setState(() {});
    _scheduleComposeAutosave();
  }

  bool _hasComposeDraftContent() =>
      (_kategoriKode ?? '').isNotEmpty ||
      _detail.text.trim().isNotEmpty ||
      _fotoBytes != null ||
      _items.isNotEmpty;

  void _scheduleComposeAutosave() {
    if (!_hasComposeDraftContent()) return;
    _composeAutosave.schedule(() => _saveComposeDraftLocal(silent: true));
  }

  Future<void> _saveComposeDraftLocal({bool silent = true}) async {
    if (!_hasComposeDraftContent()) return;
    try {
      await LocalFormDraft.save(_draftKey, {
        'toko_id': _tokoId,
        'kategori_kode': _kategoriKode,
        'detail': _detail.text,
        'foto_b64': LocalFormDraft.bytesToB64(_fotoBytes),
        'foto_omitted': _fotoBytes != null &&
            LocalFormDraft.bytesToB64(_fotoBytes) == null,
        'items': _items.map((e) => e.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('Pengaduan admin compose autosave: $e');
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
          (map['detail'] ?? '').toString().trim().isNotEmpty ||
          LocalFormDraft.bytesFromB64(map['foto_b64']) != null ||
          restoredItems.isNotEmpty;
      if (!hasContent) return;
      if (!mounted) return;
      final draftToko = (map['toko_id'] ?? '').toString().trim();
      setState(() {
        if (draftToko.isNotEmpty &&
            (_tokoOptions.isEmpty || _tokoOptions.contains(draftToko))) {
          _tokoId = draftToko;
        }
        final kode = (map['kategori_kode'] ?? '').toString().trim();
        _kategoriKode = kode.isEmpty ? null : kode;
        _detail.text = (map['detail'] ?? '').toString();
        _fotoBytes = LocalFormDraft.bytesFromB64(map['foto_b64']);
        _items
          ..clear()
          ..addAll(restoredItems);
      });
      if (mounted) {
        _snack('admin_auto_4005894c0a'.tr(), OptikAdminTokens.success);
      }
    } catch (e) {
      debugPrint('Pengaduan admin draft restore: $e');
    }
  }

  @override
  void dispose() {
    _composeAutosave.cancel();
    if (_hasComposeDraftContent()) {
      unawaited(_saveComposeDraftLocal(silent: true));
    }
    _detail.removeListener(_onComposeChanged);
    _detail.dispose();
    super.dispose();
  }

  Future<void> _loadToko() async {
    try {
      final rows = await _db.from('toko_id').select('id').order('id');
      final all = [
        for (final r in rows) r['id']?.toString() ?? '',
      ].where((e) => e.isNotEmpty).toList();
      final opts =
          AttendanceAdminScope.filterTokoForMonitor(all, widget.profile);
      if (!mounted) return;
      setState(() {
        _tokoOptions = opts.isEmpty && (_tokoId ?? '').isNotEmpty
            ? [_tokoId!]
            : opts;
        final cur = (_tokoId ?? '').trim();
        if (cur.isEmpty || !_tokoOptions.contains(cur)) {
          _tokoId = _tokoOptions.isEmpty ? cur : _tokoOptions.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      final own = AttendanceAdminScope.tokoOf(widget.profile);
      setState(() {
        _tokoOptions = own.isEmpty ? const [] : [own];
        if ((_tokoId ?? '').isEmpty) _tokoId = own;
      });
    }
    await _restoreDraftIfNeeded();
  }

  Future<void> _pickToko() async {
    if (_tokoOptions.length < 2) return;
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pengaduan_admin_pilih_toko'.tr(),
      selected: _tokoId,
      options: [
        for (final t in _tokoOptions)
          AdminPickerOption(value: t, label: t, icon: Icons.storefront_outlined),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    setState(() {
      _tokoId = sel.value;
      _items.clear();
    });
    _scheduleComposeAutosave();
  }

  Future<void> _pickKategori() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'pengaduan_label_kategori'.tr(),
      selected: _kategoriKode,
      options: [
        for (final k in PengaduanCaseFlow.kategoriKodesPublik)
          AdminPickerOption(
            value: k,
            label: PengaduanCaseFlow.labelKey(k).tr(),
          ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    setState(() {
      _kategoriKode = sel.value;
      if (!PengaduanCaseFlow.isProduk(sel.value)) _items.clear();
    });
    _scheduleComposeAutosave();
  }

  Future<void> _pickFoto() async {
    final file = await pickImageSafe(context: context, imageQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _fotoBytes = bytes);
    _scheduleComposeAutosave();
  }

  Future<void> _pilihBarang() async {
    final toko = (_tokoId ?? '').trim();
    if (toko.isEmpty) {
      _snack('admin_auto_0bd934f631'.tr(), OptikAdminTokens.danger);
      return;
    }
    final picked = await showPengaduanProductSheet(context, tokoId: toko);
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

  Future<void> _kirim() async {
    final block = PengaduanCaseFlow.submitBlocker(
      kategoriKode: _kategoriKode,
      detail: _detail.text,
      hasFoto: _fotoBytes != null,
      items: _items,
      allowedKodes: PengaduanCaseFlow.kategoriKodesPublik,
    );
    if (block != null) {
      _snack(block.tr(), OptikAdminTokens.danger);
      return;
    }
    final toko = (_tokoId ?? '').trim();
    if (toko.isEmpty) {
      _snack('admin_auto_0bd934f631'.tr(), OptikAdminTokens.danger);
      return;
    }
    final uid = _db.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      _snack('admin_auto_2c3ab67b02'.tr(), OptikAdminTokens.danger);
      return;
    }
    setState(() => _submitting = true);
    try {
      final path = 'admin/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from('pengaduan_photos').uploadBinary(
            path,
            _fotoBytes!,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final fotoUrl = _db.storage.from('pengaduan_photos').getPublicUrl(path);
      final kode = _kategoriKode!;
      final nama = (widget.profile['nama'] ??
              widget.profile['email'] ??
              _db.auth.currentUser?.email ??
              'Admin')
          .toString()
          .trim();
      final kontak =
          (widget.profile['email'] ?? _db.auth.currentUser?.email ?? '')
              .toString()
              .trim();
      final tenant = AttendanceAdminScope.boundTenantIdOrNull() ??
          widget.profile['tenant_id']?.toString();
      final row = <String, dynamic>{
        'toko_id': toko,
        'kategori': PengaduanCaseFlow.labelKey(kode).tr(),
        'kategori_kode': kode,
        'isi': _detail.text.trim(),
        'foto_url': fotoUrl,
        'status': 'OPEN',
        'sumber': PengaduanCaseFlow.sumberAdmin,
        'pelapor_nama': nama,
        'pelapor_kontak': kontak,
        'pelapor_user_id': uid,
        'items': _isProduk ? _items.map((e) => e.toJson()).toList() : const [],
        if (tenant != null && tenant.toString().trim().isNotEmpty)
          'tenant_id': tenant,
      };
      try {
        await _db.from('pengaduan').insert(row);
      } catch (e) {
        // Jangan buang kategori_kode/items — decide stok butuh keduanya.
        row.remove('tenant_id');
        try {
          await _db.from('pengaduan').insert(row);
        } catch (_) {
          throw e;
        }
      }
      if (!mounted) return;
      await _clearComposeDraftLocal();
      if (!mounted) return;
      _snack('admin_auto_d906ab5ae3'.tr(), OptikAdminTokens.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('admin_auto_4bc37d9b3d'.tr(namedArgs: {'error': '$e'}), OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: TextStyle(
            color: OptikAdminTokens.snow,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'pengaduan_admin_buat'.tr(),
        subtitle: 'pengaduan_admin_buat_subtitle'.tr(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          PremiumPanel(
            padding: const EdgeInsets.all(14),
            borderRadius: 16,
            child: Text(
              'pengaduan_admin_buat_info'.tr(),
              style: TextStyle(
                color: OptikAdminTokens.slate,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminPickerField(
                  label: 'pengaduan_admin_pilih_toko'.tr(),
                  valueText: (_tokoId ?? '').trim().isEmpty
                      ? 'pengaduan_admin_pilih_toko'.tr()
                      : _tokoId!,
                  onTap: _tokoOptions.length < 2 ? null : _pickToko,
                  icon: Icons.storefront_outlined,
                ),
                const SizedBox(height: 12),
                AdminPickerField(
                  label: 'pengaduan_label_kategori'.tr(),
                  valueText: _kategoriKode == null
                      ? 'pengaduan_hint_kategori'.tr()
                      : PengaduanCaseFlow.labelKey(_kategoriKode!).tr(),
                  onTap: _pickKategori,
                  icon: Icons.category_outlined,
                ),
                const SizedBox(height: 12),
                Text(
                  'pengaduan_label_penjelasan'.tr(),
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _detail,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'pengaduan_hint_penjelasan'.tr(),
                    filled: true,
                    fillColor: OptikAdminTokens.snow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (_isProduk) ...[
                  const SizedBox(height: 14),
                  Text(
                    'pengaduan_label_barang'.tr(),
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'pengaduan_hint_barang'.tr(),
                    style: TextStyle(
                      color: OptikAdminTokens.slate,
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
                        color: OptikAdminTokens.warning,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    ..._items.asMap().entries.map(_itemRow),
                ],
                const SizedBox(height: 12),
                Text(
                  'pengaduan_label_foto'.tr(),
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _pickFoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    _fotoBytes == null
                        ? 'pengaduan_hint_foto'.tr()
                        : 'pengaduan_admin_foto_ok'.tr(),
                  ),
                ),
                if (_fotoBytes != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _fotoBytes!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                PremiumPrimaryButton(
                  label: _submitting
                      ? 'pengaduan_btn_mengirim'.tr()
                      : 'pengaduan_btn_kirim'.tr(),
                  loading: _submitting,
                  onPressed: _submitting || !_canKirim ? null : _kirim,
                ),
              ],
            ),
          ),
        ],
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
        color: OptikAdminTokens.snow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptikAdminTokens.chromeEdge),
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
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  line.sku,
                  style: TextStyle(
                    color: OptikAdminTokens.slate,
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
}
