import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

import '../../shared/bootstrap.dart';
import '../../shared/payroll/payroll_compute_engine.dart';
import '../../shared/payroll/payroll_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/premium_date_range_picker.dart';

/// Admin: aturan gaji (template + grup), periode bonus/OT, preview → submit, export bank.
class PayrollWorkspacePage extends StatefulWidget {
  const PayrollWorkspacePage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<PayrollWorkspacePage> createState() => _PayrollWorkspacePageState();
}

class _PayrollWorkspacePageState extends State<PayrollWorkspacePage>
    with SingleTickerProviderStateMixin {
  final _svc = PayrollService();
  late final TabController _tabs;

  List<Map<String, dynamic>> _tokoMaster = [];
  String? _tokoId;
  final _periode = TextEditingController();

  String _bonusMode = 'pool';
  final _poolRp = TextEditingController();
  final _rpPerPoin = TextEditingController();
  final _omzetRef = TextEditingController();
  final _notes = TextEditingController();

  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _templates = [];
  String? _selectedTemplateId;
  List<Map<String, dynamic>> _otRows = [];
  PayrollComputeResult? _preview;
  Map<String, dynamic>? _savedPeriod;
  bool _previewDirty = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final Set<String> _selectedIds = {};

  bool get _canRun {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return role == 'owner' || role == 'admin_pusat' || role == 'super_admin';
  }

  String get _periodStatus => (_savedPeriod?['status'] ?? '').toString();
  bool get _isPaid => _periodStatus == 'dibayar';
  bool get _isLocked =>
      _periodStatus == 'dikunci' || _periodStatus == 'dibayar';

  static String _ymNow() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _periode.text = _ymNow();
    _boot();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _periode.dispose();
    _poolRp.dispose();
    _rpPerPoin.dispose();
    _omzetRef.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final toko =
          await supabase.from('toko_id').select('id, toko_id').order('id');
      final list = (toko as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) {
        final id = (t['id'] ?? '').toString();
        return id.isNotEmpty && id != 'PUSAT' && id != 'CABANG-PUSAT';
      }).toList();
      final templates = await _svc.listTemplates();
      if (!mounted) return;
      setState(() {
        _tokoMaster = list;
        _tokoId = list.isEmpty ? null : list.first['id']?.toString();
        _templates = templates;
        _loading = false;
      });
      await _reloadTokoData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _reloadTokoData() async {
    final toko = _tokoId;
    final ym = _periode.text.trim();
    if (toko == null || ym.isEmpty) return;
    setState(() => _busy = true);
    try {
      final staff = await _svc.listAssignmentsForToko(toko);
      final ot = await _svc.listOvertime(tokoId: toko, periodeYm: ym);
      final templates = await _svc.listTemplates(tokoId: toko);
      Map<String, dynamic>? saved;
      try {
        saved = await _svc.loadPeriod(tokoId: toko, periodeYm: ym);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _staff = staff;
          _otRows = ot;
          _templates = templates;
          _selectedTemplateId = _keepTemplateId(templates);
          _savedPeriod = null;
          _preview = null;
          _busy = false;
          _error = _friendlyError(e);
        });
        return;
      }
      if (!mounted) return;
      final settings = saved?['settings'];
      if (settings is Map) {
        final sm = Map<String, dynamic>.from(settings);
        _bonusMode = (sm['bonus_mode'] ?? _bonusMode).toString();
        if (sm['bonus_pool_rp'] != null) {
          _poolRp.text =
              PayrollComputeEngine.asInt(sm['bonus_pool_rp']).toString();
        }
        if (sm['rp_per_poin'] != null) {
          _rpPerPoin.text =
              PayrollComputeEngine.asInt(sm['rp_per_poin']).toString();
        }
        if (sm['omzet_referensi'] != null) {
          _omzetRef.text =
              PayrollComputeEngine.asInt(sm['omzet_referensi']).toString();
        }
        if (sm['notes'] != null) {
          _notes.text = sm['notes']?.toString() ?? '';
        }
      }
      PayrollComputeResult? preview;
      if (saved != null) {
        preview = PayrollComputeEngine.fromSavedLines(saved['lines']);
        if (preview.lines.isEmpty) preview = null;
      }
      setState(() {
        _staff = staff;
        _otRows = ot;
        _templates = templates;
        _selectedTemplateId = _keepTemplateId(templates);
        _savedPeriod = saved;
        _preview = preview;
        _previewDirty = false;
        _busy = false;
        _error = null;
        _selectedIds.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  PayrollPeriodBonusInput _bonusInput() {
    if (_bonusMode == 'pool') {
      final pool = int.tryParse(_poolRp.text.replaceAll(RegExp(r'[^0-9]'), ''));
      if (pool == null) throw 'Isi total pool bonus (Rp)';
      return PayrollPeriodBonusInput(
        mode: PayrollBonusMode.pool,
        poolRp: pool,
      );
    }
    final rp = int.tryParse(_rpPerPoin.text.replaceAll(RegExp(r'[^0-9-]'), ''));
    if (rp == null) throw 'Isi Rp per poin';
    return PayrollPeriodBonusInput(
      mode: PayrollBonusMode.rpPerPoin,
      rpPerPoin: rp,
    );
  }

  Future<void> _runPreview() async {
    if (!_canRun) return;
    if (_isLocked) {
      _snack(
        _isPaid
            ? 'admin_auto_fb33ba1955'.tr()
            : 'admin_auto_13d08ac593'.tr(),
        OptikAdminTokens.warning,
      );
      return;
    }
    final toko = _tokoId;
    if (toko == null) return;
    if (_staff.isEmpty) {
      _snack('admin_gl_row_f2c19b4d12'.tr(), OptikAdminTokens.warning);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bonus = _bonusInput();
      final result = await _svc.previewCompute(
        tokoId: toko,
        periodeYm: _periode.text.trim(),
        bonus: bonus,
      );
      if (result.undistributedBonusRp > 0) {
        _snack(
          'admin_auto_3e2c3968f0'.tr(namedArgs: {
            'result': '${result.undistributedBonusRp}',
          }),
          OptikAdminTokens.warning,
        );
      }
      final saved = await _svc.savePeriod(
        tokoId: toko,
        periodeYm: _periode.text.trim(),
        bonus: bonus,
        omzetReferensi:
            int.tryParse(_omzetRef.text.replaceAll(RegExp(r'[^0-9]'), '')),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        lock: false,
        precomputed: result,
      );
      if (!mounted) return;
      setState(() {
        _preview = result;
        _previewDirty = false;
        _savedPeriod = saved;
        _busy = false;
      });
      _snack('admin_gl_row_2d25a3cbae'.tr(), OptikAdminTokens.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _submitLock() async {
    if (!_canRun) return;
    if (_isPaid) {
      _snack('admin_gl_row_2fd6a5b78c'.tr(), OptikAdminTokens.warning);
      return;
    }
    if (_isLocked) {
      _snack('admin_gl_row_bd5ca5dfe8'.tr(),
          OptikAdminTokens.warning);
      return;
    }
    final toko = _tokoId;
    if (toko == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_3aa06ab801'.tr()),
        content: Text('admin_auto_942b693671'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('admin_btn_kunci'.tr())),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final bonus = _bonusInput();
      final result = (_previewDirty && _preview != null)
          ? _preview!
          : await _svc.previewCompute(
              tokoId: toko,
              periodeYm: _periode.text.trim(),
              bonus: bonus,
            );
      final saved = await _svc.savePeriod(
        tokoId: toko,
        periodeYm: _periode.text.trim(),
        bonus: bonus,
        omzetReferensi:
            int.tryParse(_omzetRef.text.replaceAll(RegExp(r'[^0-9]'), '')),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        lock: true,
        precomputed: result,
      );
      if (!mounted) return;
      setState(() {
        _preview = result;
        _previewDirty = false;
        _savedPeriod = saved;
        _busy = false;
      });
      _snack('admin_gl_row_12da0e0ebd'.tr(),
          OptikAdminTokens.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _markPaid() async {
    final toko = _tokoId;
    if (toko == null) return;
    setState(() => _busy = true);
    try {
      PayrollPeriodBonusInput bonus;
      try {
        bonus = _bonusInput();
      } catch (_) {
        final s = _savedPeriod?['settings'];
        if (s is! Map) {
          throw 'Isi mode bonus / buka periode yang sudah tersimpan dulu';
        }
        bonus = PayrollPeriodBonusInput(
          mode:
              PayrollComputeEngine.parseBonusMode(s['bonus_mode']?.toString()),
          poolRp: s['bonus_pool_rp'] == null
              ? null
              : PayrollComputeEngine.asInt(s['bonus_pool_rp']),
          rpPerPoin: s['rp_per_poin'] == null
              ? null
              : PayrollComputeEngine.asInt(s['rp_per_poin']),
        );
      }
      final saved = await _svc.savePeriod(
        tokoId: toko,
        periodeYm: _periode.text.trim(),
        bonus: bonus,
        lock: false,
        markPaid: true,
        precomputed: _preview,
      );
      if (!mounted) return;
      setState(() {
        _savedPeriod = saved;
        _busy = false;
      });
      _snack('admin_gl_row_3d19aa47e8'.tr(), OptikAdminTokens.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _unlock() async {
    final toko = _tokoId;
    if (toko == null) return;
    setState(() => _busy = true);
    try {
      await _svc.unlockPeriod(tokoId: toko, periodeYm: _periode.text.trim());
      await _reloadTokoData();
      _snack('admin_gl_row_c9d49cfce6'.tr(), OptikAdminTokens.navy);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _exportBank() async {
    final lines = _preview?.lines ?? [];
    if (lines.isEmpty && _savedPeriod?['lines'] is List) {
      // use saved
    }
    final staffById = {
      for (final s in _staff) s['id'].toString(): s,
    };
    final rows = <Map<String, dynamic>>[];
    if (_preview != null) {
      for (final l in _preview!.lines) {
        final s = staffById[l.karyawanId];
        rows.add({
          'nama': l.nama,
          'nama_bank': s?['nama_bank'],
          'no_rekening': s?['no_rekening'],
          'nett': l.nett,
          'periode_ym': _periode.text.trim(),
        });
      }
    } else if (_savedPeriod?['lines'] is List) {
      for (final raw in _savedPeriod!['lines'] as List) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final s = staffById[m['karyawan_id'].toString()];
        rows.add({
          'nama': m['nama'],
          'nama_bank': s?['nama_bank'],
          'no_rekening': s?['no_rekening'],
          'nett': m['nett'],
          'periode_ym': _periode.text.trim(),
        });
      }
    }
    if (rows.isEmpty) {
      _snack('admin_gl_row_47e683f46f'.tr(), OptikAdminTokens.warning);
      return;
    }
    final csv = _svc.bankExportCsv(rows);
    await Clipboard.setData(ClipboardData(text: csv));
    _snack('admin_gl_row_a3d58ac0e7'.tr(), OptikAdminTokens.success);
  }

  void _editComponent({
    required String karyawanId,
    required String key,
    required int amount,
  }) {
    final preview = _preview;
    if (preview == null || _isLocked) return;
    final next = [
      for (final l in preview.lines)
        if (l.karyawanId != karyawanId)
          l
        else
          PayrollComputeEngine.lineFromComponents(
            karyawanId: l.karyawanId,
            nama: l.nama,
            jabatan: l.jabatan,
            poin: l.poin,
            components: [
              for (final c in l.components)
                if (c.key == key)
                  PayrollComponentAmount(
                    key: c.key,
                    label: c.label,
                    kind: c.kind,
                    amount: amount,
                    meta: c.meta,
                  )
                else
                  c,
            ],
          ),
    ];
    setState(() {
      _previewDirty = true;
      _preview = PayrollComputeEngine.retotal(
        next,
        poolRemainder: preview.poolRemainder,
        undistributedBonusRp: preview.undistributedBonusRp,
      );
    });
  }

  Future<void> _openGroupAssign() async {
    if (_selectedIds.isEmpty) {
      _snack('admin_gl_row_5e2674c603'.tr(), OptikAdminTokens.warning);
      return;
    }
    final tpl = _selectedTemplate;
    if (tpl == null) {
      _snack('admin_gl_row_835d0ee35e'.tr(), OptikAdminTokens.warning);
      return;
    }
    final nama = (tpl['nama'] ?? 'template').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: OptikAdminTokens.ice),
        ),
        title: Text('admin_auto_b5a7effecd'.tr(namedArgs: {'name': nama})),
        content: Text(
          'Aturan lengkap dari template dipakai ke ${_selectedIds.length} orang yang dicentang. '
          'Ubah nominal di template, bukan di sini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            child: Text('admin_auto_032347b406'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _svc.assignToGroup(
        karyawanIds: _selectedIds.toList(),
        templateId: tpl['id']?.toString(),
        overrides: PayrollService.overridesFromTemplate(tpl),
      );
      await _reloadTokoData();
      _snack(
        'admin_auto_b6098a7018'.tr(namedArgs: {
          'name': nama,
          'n': '${_selectedIds.length}',
        }),
        OptikAdminTokens.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _addOt() async {
    final toko = _tokoId;
    if (toko == null || _staff.isEmpty) return;
    String karyawanId = _staff.first['id'].toString();
    final jam = TextEditingController(text: '1');
    final rate = TextEditingController();
    void applyRateFor(String id) {
      final s = _staff.firstWhere(
        (e) => e['id'].toString() == id,
        orElse: () => _staff.first,
      );
      final ov = PayrollComputeEngine.asMapOrEmpty(
        (s['assignment'] as Map?)?['overrides'],
      );
      if (ov['overtime_rate_rp'] != null) {
        rate.text =
            PayrollComputeEngine.asInt(ov['overtime_rate_rp']).toString();
      }
    }

    applyRateFor(karyawanId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('admin_auto_2f6d860538'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: karyawanId,
                decoration: InputDecoration(labelText: 'default_karyawan'.tr()),
                items: [
                  for (final s in _staff)
                    DropdownMenuItem(
                      value: s['id'].toString(),
                      child: Text((s['nama'] ?? '-').toString()),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() {
                    karyawanId = v;
                    applyRateFor(v);
                  });
                },
              ),
              TextField(
                controller: jam,
                decoration: InputDecoration(labelText: 'admin_auto_9155e3bad8'.tr()),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: rate,
                decoration: InputDecoration(labelText: 'admin_auto_5b87787e44'.tr()),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('appr_btn_batal'.tr())),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('btn_simpan'.tr())),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final j = num.tryParse(jam.text.replaceAll(',', '.'));
    final r = int.tryParse(rate.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (j == null || r == null) {
      _snack('admin_gl_row_c241d79f39'.tr(), OptikAdminTokens.warning);
      return;
    }
    await _svc.upsertOvertime(
      karyawanId: karyawanId,
      tokoId: toko,
      periodeYm: _periode.text.trim(),
      jam: j,
      rateRp: r,
    );
    await _reloadTokoData();
    _snack('admin_gl_row_6e536f0165'.tr(), OptikAdminTokens.success);
  }

  Future<void> _openTemplateEditor({Map<String, dynamic>? existing}) async {
    final result = await showDialog<_TemplateEditResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: OptikAdminTokens.navy.withOpacity(0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: _PayrollTemplateEditor(existing: existing),
      ),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      final id = existing?['id']?.toString();
      if (id == null) return;
      await _svc.deleteTemplate(id);
      final templates = await _svc.listTemplates(tokoId: _tokoId);
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _selectedTemplateId = _keepTemplateId(templates);
      });
      _snack('admin_gl_row_d44c1425b8'.tr(), OptikAdminTokens.navy);
      return;
    }
    final saved = await _svc.upsertTemplate(
      id: existing?['id']?.toString(),
      nama: result.nama,
      tokoId: _tokoId,
      components: result.components,
    );
    final templates = await _svc.listTemplates(tokoId: _tokoId);
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _selectedTemplateId =
          saved['id']?.toString() ?? _keepTemplateId(templates);
    });
    _snack(
      existing == null
          ? 'admin_auto_6ad7ae0e94'.tr()
          : 'admin_auto_9b72d8d19f'.tr(),
      OptikAdminTokens.success,
    );
  }

  Future<void> _createTemplate() => _openTemplateEditor();

  String _friendlyError(Object e) {
    final s = '$e';
    if (s.contains('42P17') || s.toLowerCase().contains('infinite recursion')) {
      return 'Gagal memuat periode payroll. Muat ulang halaman.';
    }
    final jsonMsg = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(s);
    if (jsonMsg != null) return jsonMsg.group(1)!;
    final boxed = RegExp(r'message:\s*([^,\n]+)').firstMatch(s);
    if (boxed != null) {
      final m = boxed.group(1)!.trim();
      if (m.isNotEmpty && m != 'null') return m;
    }
    return s;
  }

  String _rp(dynamic v) {
    final n = PayrollComputeEngine.asInt(v);
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}Rp ${buf.toString()}';
  }

  String? _keepTemplateId(List<Map<String, dynamic>> templates) {
    final cur = _selectedTemplateId;
    if (cur != null &&
        cur.isNotEmpty &&
        templates.any((t) => t['id']?.toString() == cur)) {
      return cur;
    }
    return templates.isEmpty ? null : templates.first['id']?.toString();
  }

  Map<String, dynamic>? get _selectedTemplate {
    final id = _selectedTemplateId;
    if (id == null || id.isEmpty) return null;
    for (final t in _templates) {
      if (t['id']?.toString() == id) return t;
    }
    return null;
  }

  String get _periodeLabel {
    final p = _periode.text.trim().split('-');
    if (p.length != 2) return _periode.text.trim();
    const names = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final m = int.tryParse(p[1]) ?? 0;
    if (m < 1 || m > 12) return _periode.text.trim();
    return '${names[m - 1]} ${p[0]}';
  }

  String _tokoLabel(Map<String, dynamic> t) {
    final id = (t['id'] ?? '').toString();
    final name = (t['toko_id'] ?? id).toString();
    return name.trim().isEmpty ? id : name;
  }

  String _tokoValueText() {
    for (final t in _tokoMaster) {
      if (t['id']?.toString() == _tokoId) return _tokoLabel(t);
    }
    return _tokoId ?? 'Pilih toko';
  }

  Future<void> _pickToko() async {
    if (_tokoMaster.isEmpty) return;
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'admin_auto_fcb2349397'.tr(),
      subtitle: 'admin_auto_c354c88fc5'.tr(),
      searchHint: 'Cari cabang…',
      headerIcon: Icons.storefront_rounded,
      selected: _tokoId,
      options: [
        for (final t in _tokoMaster)
          AdminPickerOption(
            value: t['id'].toString(),
            label: _tokoLabel(t),
            subtitle: t['id']?.toString(),
            icon: Icons.storefront_outlined,
          ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    setState(() => _tokoId = sel.value);
    await _reloadTokoData();
  }

  Future<void> _pickPeriode() async {
    final parts = _periode.text.trim().split('-');
    final now = DateTime.now();
    var y = now.year;
    var m = now.month;
    if (parts.length == 2) {
      y = int.tryParse(parts[0]) ?? y;
      m = int.tryParse(parts[1]) ?? m;
    }
    final start = DateTime(y, m, 1);
    final end = DateTime(y, m + 1, 0);
    final picked = await showPremiumDateRangePicker(
      context: context,
      initialStart: start,
      initialEnd: end,
      initialPresetId: 'custom',
      timezoneNote: 'Periode gaji memakai bulan tanggal mulai (Waktu Jakarta).',
    );
    if (picked == null) return;
    final ym =
        '${picked.start.year}-${picked.start.month.toString().padLeft(2, '0')}';
    _periode.text = ym;
    await _reloadTokoData();
  }

  String _templateSummary(Map<String, dynamic> t) {
    final ov = PayrollService.overridesFromTemplate(t);
    final bits = <String>[];
    if (ov['gaji_pokok'] != null) bits.add('pokok ${_rp(ov['gaji_pokok'])}');
    final allows = ov['allowances'];
    if (allows is List && allows.isNotEmpty) {
      bits.add('${allows.length} tunjangan');
    }
    final deds = ov['deductions'];
    if (deds is List && deds.isNotEmpty) {
      bits.add('${deds.length} potongan');
    }
    if (ov['overtime_rate_rp'] != null) {
      bits.add('lembur ${_rp(ov['overtime_rate_rp'])}/jam');
    }
    final tax = (ov['tax_mode'] ?? 'off').toString();
    if (tax == 'percent') bits.add('PPh ${ov['tax_percent']}%');
    if (tax == 'nominal') bits.add('PPh ${_rp(ov['tax_nominal'])}');
    return bits.isEmpty ? 'Belum diisi — ketuk edit' : bits.join(' · ');
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'dikunci':
        return OptikAdminTokens.navy;
      case 'dibayar':
        return OptikAdminTokens.success;
      case 'draft':
        return OptikAdminTokens.warning;
      default:
        return OptikAdminTokens.slate;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'dikunci':
        return 'Terkunci';
      case 'dibayar':
        return 'Dibayar';
      case 'draft':
        return 'Draft';
      default:
        return 'Belum ada periode';
    }
  }

  InputDecoration _deco(String label, {String? hint, IconData? icon}) {
    final r = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: OptikAdminTokens.slate),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: OptikAdminTokens.ice.withOpacity(0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: OptikAdminTokens.ice.withOpacity(0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: OptikAdminTokens.navy, width: 1.4),
      ),
    );
  }

  Widget _statusPill() {
    final raw = _periodStatus.isEmpty ? '—' : _periodStatus;
    final color = _statusColor(_periodStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        _statusLabel(raw),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'admin_auto_eb68630404'.tr(),
        subtitle: 'admin_auto_3740c25311'.tr(),
        bottom: TabBar(
          controller: _tabs,
          labelColor: OptikAdminTokens.navy,
          unselectedLabelColor: OptikAdminTokens.slate,
          indicatorColor: OptikAdminTokens.navy,
          indicatorWeight: 2.6,
          dividerColor: OptikAdminTokens.ice.withOpacity(0.35),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            letterSpacing: 0.4,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Aturan'),
            Tab(
                icon: Icon(Icons.calendar_month_rounded, size: 18),
                text: 'Periode'),
            Tab(
                icon: Icon(Icons.receipt_long_rounded, size: 18),
                text: 'Preview'),
          ],
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.navy),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _buildFilterBar(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: PremiumPanel(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      borderColor: OptikAdminTokens.danger.withOpacity(0.35),
                      child: Row(
                        children: [
                          const PremiumIconBadge(
                            icon: Icons.error_outline_rounded,
                            color: OptikAdminTokens.danger,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: OptikAdminTokens.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildAturanTab(),
                      _buildPeriodeTab(),
                      _buildPreviewTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    return PremiumPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PremiumIconBadge(
                icon: Icons.storefront_rounded,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Periode cabang',
                  style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _statusPill(),
              if (_busy) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: OptikAdminTokens.navy,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          AdminPickerField(
            label: 'admin_auto_a5629553de'.tr(),
            valueText: _tokoValueText(),
            icon: Icons.storefront_rounded,
            onTap: _pickToko,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PremiumDateRangeTrigger(
                  label: _periodeLabel,
                  onTap: _pickPeriode,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'admin_btn_refresh'.tr(),
                onPressed: _busy ? null : _reloadTokoData,
                icon: const Icon(Icons.refresh_rounded),
                color: OptikAdminTokens.navy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAturanTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        PremiumSectionHeader(
          label: 'admin_auto_5831fd6050'.tr(),
          trailing: Text(
            '${_templates.length}',
            style: TextStyle(
              color: OptikAdminTokens.slate,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Isi gaji pokok, tunjangan, potongan, lembur, dan PPh di template. '
                'Lalu tinggal centang nama dan terapkan.',
                style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.95),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              PremiumChipWrap(
                children: [
                  PremiumActionChip(
                    label: 'admin_auto_8b871ad1b7'.tr(),
                    icon: Icons.add_rounded,
                    onPressed: _createTemplate,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_templates.isEmpty)
                Text(
                  'Belum ada template di cabang ini.',
                  style: TextStyle(
                    color: OptikAdminTokens.slate.withOpacity(0.8),
                    fontSize: 12,
                  ),
                )
              else
                for (final t in _templates)
                  _TemplatePickTile(
                    nama: (t['nama'] ?? '-').toString(),
                    selected: t['id']?.toString() == _selectedTemplateId,
                    subtitle: _templateSummary(t),
                    onSelect: () => setState(
                      () => _selectedTemplateId = t['id']?.toString(),
                    ),
                    onEdit: () => _openTemplateEditor(existing: t),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        PremiumSectionHeader(
          label: 'admin_auto_5f2f2f73e5'.tr(),
          trailing: Text(
            '${_selectedIds.length} dipilih · ${_staff.length} orang',
            style: TextStyle(
              color: OptikAdminTokens.slate,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        PremiumPanel(
          child: Column(
            children: [
              Row(
                children: [
                  PremiumActionChip(
                    label: 'member_cart_select_all'.tr(),
                    onPressed: _staff.isEmpty
                        ? null
                        : () {
                            setState(() {
                              _selectedIds
                                ..clear()
                                ..addAll(_staff.map((e) => e['id'].toString()));
                            });
                          },
                  ),
                  const SizedBox(width: 8),
                  PremiumActionChip(
                    label: 'export_clear_all'.tr(),
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => setState(_selectedIds.clear),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              PremiumPrimaryButton(
                label: _selectedTemplate == null
                    ? 'Terapkan ke pilihan'
                    : 'Terapkan “${_selectedTemplate!['nama']}”',
                icon: Icons.group_add_rounded,
                onPressed: _busy ? null : _openGroupAssign,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_staff.isEmpty)
          PremiumEmptyState(
            title: 'admin_auto_642d324e4c'.tr(),
            message:
                'Payroll hanya memuat status Aktif di toko ini. Pastikan roster cabang sudah disetujui.',
            icon: Icons.badge_outlined,
          )
        else
          for (final s in _staff)
            _StaffPickTile(
              nama: (s['nama'] ?? '-').toString(),
              jabatan: (s['jabatan'] ?? '-').toString(),
              pokok: _rp(s['gaji_pokok']),
              assigned: s['assignment'] != null,
              selected: _selectedIds.contains(s['id'].toString()),
              onChanged: (v) {
                setState(() {
                  final id = s['id'].toString();
                  if (v == true) {
                    _selectedIds.add(id);
                  } else {
                    _selectedIds.remove(id);
                  }
                });
              },
            ),
      ],
    );
  }

  Widget _buildPeriodeTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        PremiumSectionHeader(label: 'admin_auto_1bfc154306'.tr()),
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Poin KPI tidak mengubah gaji pokok. Isi pool dari pendapatan bulan ini, atau Rp per poin.',
                style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.95),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      selected: _bonusMode == 'pool',
                      icon: Icons.pie_chart_rounded,
                      title: 'admin_auto_4db9706a8b'.tr(),
                      subtitle: 'admin_auto_459a31efca'.tr(),
                      onTap: () => setState(() => _bonusMode = 'pool'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeCard(
                      selected: _bonusMode == 'rp_per_poin',
                      icon: Icons.bolt_rounded,
                      title: 'admin_auto_79a6a39dc2'.tr(),
                      subtitle: 'admin_auto_cb19d1dc74'.tr(),
                      onTap: () => setState(() => _bonusMode = 'rp_per_poin'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_bonusMode == 'pool')
                TextField(
                  controller: _poolRp,
                  decoration: _deco(
                    'Total pool bonus (Rp)',
                    hint: 'Dari pendapatan bulan ini',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  keyboardType: TextInputType.number,
                )
              else
                TextField(
                  controller: _rpPerPoin,
                  decoration: _deco(
                    'Rp per poin',
                    hint: 'Tarif periode ini saja',
                    icon: Icons.payments_outlined,
                  ),
                  keyboardType: TextInputType.number,
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _omzetRef,
                decoration: _deco(
                  'Omzet referensi (opsional)',
                  icon: Icons.trending_up_rounded,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: _deco('admin_lbl_catatan'.tr(), icon: Icons.notes_rounded),
                minLines: 1,
                maxLines: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        PremiumSectionHeader(
          label: 'home_shortcut_lembur'.tr(),
          trailing: PremiumActionChip(
            label: 'pm_btn_tambah'.tr(),
            icon: Icons.add_rounded,
            onPressed: _addOt,
          ),
        ),
        if (_otRows.isEmpty)
          PremiumPanel(
            child: Text(
              'Belum ada lembur di periode ini. Rate diisi Admin, bukan angka hardcode.',
              style: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.95),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          )
        else
          for (final o in _otRows)
            PremiumListTile(
              dense: true,
              icon: Icons.schedule_rounded,
              title: (o['karyawan'] is Map
                          ? (o['karyawan'] as Map)['nama']
                          : o['karyawan_id'])
                      ?.toString() ??
                  '-',
              subtitle:
                  '${o['jam']} jam × ${_rp(o['rate_rp'])} = ${_rp(o['jumlah_rp'])} · ${o['status']}',
              trailing: const SizedBox.shrink(),
            ),
        const SizedBox(height: 22),
        PremiumSectionHeader(label: 'admin_auto_a4d3b161ce'.tr()),
        PremiumPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PremiumPrimaryButton(
                label: 'admin_auto_aacbfd2ca0'.tr(),
                icon: Icons.visibility_rounded,
                loading: _busy,
                onPressed: _busy || !_canRun || _isLocked ? null : _runPreview,
              ),
              const SizedBox(height: 10),
              PremiumPrimaryButton(
                label: 'admin_auto_3b272ce0d9'.tr(),
                icon: Icons.lock_rounded,
                onPressed: _busy || !_canRun || _isLocked ? null : _submitLock,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PremiumActionChip(
                    label: 'admin_auto_7e7123b0d2'.tr(),
                    icon: Icons.lock_open_rounded,
                    onPressed: _busy || !_canRun || _isPaid || !_isLocked
                        ? null
                        : _unlock,
                  ),
                  PremiumActionChip(
                    label: 'admin_auto_e03580df48'.tr(),
                    icon: Icons.verified_rounded,
                    onPressed: _busy || !_canRun || _isPaid || !_isLocked
                        ? null
                        : _markPaid,
                  ),
                  PremiumActionChip(
                    label: 'admin_auto_ff597cb5f1'.tr(),
                    icon: Icons.content_copy_rounded,
                    onPressed: _exportBank,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTab() {
    final lines = _preview?.lines;
    if (lines == null || lines.isEmpty) {
      return PremiumEmptyState(
        title: 'admin_auto_3e90fd3e74'.tr(),
        message: _savedPeriod == null
            ? 'Isi bonus di tab Periode, lalu jalankan Preview → draft.'
            : 'Periode tersimpan tanpa line. Unlock dulu jika terkunci, lalu Preview lagi.',
        icon: Icons.receipt_long_outlined,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        PremiumStatGrid(
          items: [
            PremiumStatItem(
              label: 'admin_auto_33c8cbb808'.tr(),
              value: _rp(_preview!.totalNett),
              color: OptikAdminTokens.navy,
            ),
            PremiumStatItem(
              label: 'admin_auto_35948f742c'.tr(),
              value: _rp(_preview!.totalTunjangan),
              color: OptikAdminTokens.success,
            ),
            PremiumStatItem(
              label: 'admin_auto_e1bf49bf4c'.tr(),
              value: _rp(_preview!.totalPotongan),
              color: OptikAdminTokens.warning,
            ),
            PremiumStatItem(
              label: 'admin_auto_f202c510d7'.tr(),
              value: '${lines.length}',
              color: OptikAdminTokens.slate,
            ),
          ],
        ),
        if (_preview!.undistributedBonusRp > 0) ...[
          const SizedBox(height: 12),
          PremiumPanel(
            borderColor: OptikAdminTokens.warning.withOpacity(0.4),
            child: Row(
              children: [
                const PremiumIconBadge(
                  icon: Icons.info_outline_rounded,
                  color: OptikAdminTokens.warning,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pool ${_rp(_preview!.undistributedBonusRp)} belum dibagi — poin tim 0.',
                    style: const TextStyle(
                      color: OptikAdminTokens.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!_isLocked) ...[
          const SizedBox(height: 12),
          Text(
            'Override nominal per orang di bawah. Enter untuk terapkan, lalu Submit & kunci.',
            style: TextStyle(
              color: OptikAdminTokens.slate.withOpacity(0.95),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PremiumPanel(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  leading: const PremiumIconBadge(
                    icon: Icons.person_rounded,
                    size: 40,
                  ),
                  title: Text(
                    l.nama,
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'Pokok ${_rp(l.gajiPokok)} · bonus ${_rp(l.bonusRp)} · ${l.poin} poin',
                    style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.95),
                      fontSize: 11.5,
                    ),
                  ),
                  trailing: Text(
                    _rp(l.nett),
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  children: [
                    for (final c in l.components)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: OptikAdminTokens.textSecondary,
                                ),
                              ),
                            ),
                            _isLocked
                                ? Text(
                                    _rp(c.amount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : SizedBox(
                                    width: 128,
                                    child: TextFormField(
                                      key: ValueKey(
                                          '${l.karyawanId}-${c.key}-${c.amount}'),
                                      initialValue: '${c.amount}',
                                      textAlign: TextAlign.end,
                                      keyboardType: TextInputType.number,
                                      decoration: _deco('Rp'),
                                      onFieldSubmitted: (v) {
                                        final n = int.tryParse(
                                          v.replaceAll(RegExp(r'[^0-9\-]'), ''),
                                        );
                                        if (n == null) return;
                                        _editComponent(
                                          karyawanId: l.karyawanId,
                                          key: c.key,
                                          amount: n,
                                        );
                                      },
                                    ),
                                  ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StaffPickTile extends StatelessWidget {
  const _StaffPickTile({
    required this.nama,
    required this.jabatan,
    required this.pokok,
    required this.assigned,
    required this.selected,
    required this.onChanged,
  });

  final String nama;
  final String jabatan;
  final String pokok;
  final bool assigned;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!selected),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? OptikAdminTokens.accentSoft.withOpacity(0.45)
                  : OptikAdminTokens.card,
              border: Border.all(
                color: selected
                    ? OptikAdminTokens.navy.withOpacity(0.28)
                    : OptikAdminTokens.ice.withOpacity(0.45),
              ),
              boxShadow: OptikAdminTokens.cardShadow,
            ),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: onChanged,
                  activeColor: OptikAdminTokens.navy,
                ),
                const PremiumIconBadge(
                  icon: Icons.badge_outlined,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$jabatan · $pokok',
                        style: TextStyle(
                          color: OptikAdminTokens.slate.withOpacity(0.95),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (assigned)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: OptikAdminTokens.success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Aturan',
                      style: TextStyle(
                        color: OptikAdminTokens.success,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? OptikAdminTokens.navy
                : OptikAdminTokens.cardElevated,
            border: Border.all(
              color: selected
                  ? OptikAdminTokens.navy
                  : OptikAdminTokens.ice.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? OptikAdminTokens.snow : OptikAdminTokens.navy,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color:
                      selected ? OptikAdminTokens.snow : OptikAdminTokens.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: selected
                      ? OptikAdminTokens.snow.withOpacity(0.78)
                      : OptikAdminTokens.slate,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateEditResult {
  const _TemplateEditResult.save({
    required this.nama,
    required this.components,
  }) : delete = false;

  const _TemplateEditResult.delete()
      : delete = true,
        nama = '',
        components = const [];

  final bool delete;
  final String nama;
  final List<Map<String, dynamic>> components;
}

class _NamedAmt {
  _NamedAmt({String label = '', String amount = ''})
      : label = TextEditingController(text: label),
        amount = TextEditingController(text: amount);

  final TextEditingController label;
  final TextEditingController amount;

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _PayrollTemplateEditor extends StatefulWidget {
  const _PayrollTemplateEditor({
    required this.existing,
  });

  final Map<String, dynamic>? existing;

  @override
  State<_PayrollTemplateEditor> createState() => _PayrollTemplateEditorState();
}

class _PayrollTemplateEditorState extends State<_PayrollTemplateEditor> {
  late final TextEditingController _nama;
  late final TextEditingController _gaji;
  late final TextEditingController _otRate;
  late final TextEditingController _taxPct;
  late final TextEditingController _taxNom;
  String _taxMode = 'off';
  final _allows = <_NamedAmt>[];
  final _deds = <_NamedAmt>[];

  static const _taxOptions = <(String, String, String)>[
    ('off', 'Off', 'Tidak potong PPh'),
    ('percent', '% dari bruto', 'Persen dari gaji + tunjangan'),
    ('nominal', 'Nominal tetap', 'Jumlah Rp yang sama tiap bulan'),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nama = TextEditingController(
      text: (t?['nama'] ?? 'Standar toko').toString(),
    );
    _gaji = TextEditingController();
    _otRate = TextEditingController();
    _taxPct = TextEditingController();
    _taxNom = TextEditingController();
    if (t != null) {
      final ov = PayrollService.overridesFromTemplate(t);
      if (ov['gaji_pokok'] != null) {
        _gaji.text = _pretty(PayrollComputeEngine.asInt(ov['gaji_pokok']));
      }
      if (ov['overtime_rate_rp'] != null) {
        _otRate.text =
            _pretty(PayrollComputeEngine.asInt(ov['overtime_rate_rp']));
      }
      _taxMode = (ov['tax_mode'] ?? 'off').toString();
      if (ov['tax_percent'] != null) _taxPct.text = '${ov['tax_percent']}';
      if (ov['tax_nominal'] != null) {
        _taxNom.text = _pretty(PayrollComputeEngine.asInt(ov['tax_nominal']));
      }
      for (final a in PayrollComputeEngine.asMapList(ov['allowances'])) {
        _allows.add(_NamedAmt(
          label: (a['label'] ?? '').toString(),
          amount: _pretty(PayrollComputeEngine.asInt(a['amount'])),
        ));
      }
      for (final d in PayrollComputeEngine.asMapList(ov['deductions'])) {
        _deds.add(_NamedAmt(
          label: (d['label'] ?? '').toString(),
          amount: _pretty(PayrollComputeEngine.asInt(d['amount'])),
        ));
      }
    }
  }

  @override
  void dispose() {
    _nama.dispose();
    _gaji.dispose();
    _otRate.dispose();
    _taxPct.dispose();
    _taxNom.dispose();
    for (final x in _allows) {
      x.dispose();
    }
    for (final x in _deds) {
      x.dispose();
    }
    super.dispose();
  }

  static String _pretty(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}${buf.toString()}';
  }

  int? _digits(TextEditingController c) {
    final t = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  String get _taxLabel {
    for (final o in _taxOptions) {
      if (o.$1 == _taxMode) return o.$2;
    }
    return 'Off';
  }

  String get _taxSubtitle {
    for (final o in _taxOptions) {
      if (o.$1 == _taxMode) return o.$3;
    }
    return '';
  }

  InputDecoration _field(String label, {String? hint, String? prefix}) {
    final r = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      prefixStyle: TextStyle(
        color: OptikAdminTokens.navy,
        fontWeight: FontWeight.w800,
        fontSize: 14,
      ),
      filled: true,
      fillColor: OptikAdminTokens.snow,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: OptikAdminTokens.ice.withOpacity(0.7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: OptikAdminTokens.ice.withOpacity(0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: OptikAdminTokens.navy, width: 1.4),
      ),
    );
  }

  Future<void> _pickTax() async {
    final sel = await showAdminPicker<String>(
      context: context,
      title: 'admin_auto_58478d8da7'.tr(),
      subtitle: 'admin_auto_f31f4d0909'.tr(),
      searchable: false,
      headerIcon: Icons.percent_rounded,
      selected: _taxMode,
      options: [
        for (final o in _taxOptions)
          AdminPickerOption(
            value: o.$1,
            label: o.$2,
            subtitle: o.$3,
            icon: o.$1 == 'off'
                ? Icons.block_rounded
                : o.$1 == 'percent'
                    ? Icons.percent_rounded
                    : Icons.payments_outlined,
          ),
      ],
    );
    if (sel == null || sel.isClear || sel.value == null) return;
    setState(() => _taxMode = sel.value!);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: OptikAdminTokens.ice),
        ),
        title: Text('admin_auto_9c4e9fba80'.tr()),
        content: Text('admin_auto_3e7c6c5dbb'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('appr_btn_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: OptikAdminTokens.danger,
              foregroundColor: OptikAdminTokens.snow,
            ),
            child: Text('btn_hapus'.tr()),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, const _TemplateEditResult.delete());
    }
  }

  void _save() {
    final gaji = _digits(_gaji);
    final ot = _digits(_otRate);
    final comps = <Map<String, dynamic>>[
      {
        'key': 'base_salary',
        'label': 'admin_lbl_gaji_pokok'.tr(),
        'kind': 'base_salary',
        'calc': 'fixed',
        if (gaji != null) 'default_value': gaji,
      },
      {
        'key': 'bonus_points',
        'label': 'admin_lbl_bonus_poin'.tr(),
        'kind': 'bonus_points',
        'calc': 'from_points',
      },
      {
        'key': 'overtime',
        'label': 'admin_lbl_lembur_payroll'.tr(),
        'kind': 'overtime',
        'calc': 'from_overtime',
        if (ot != null) 'overtime_rate_rp': ot,
      },
    ];
    var i = 0;
    for (final a in _allows) {
      final amt = _digits(a.amount);
      final label = a.label.text.trim();
      if (amt == null || amt <= 0) continue;
      i++;
      comps.add({
        'key': 'allow_$i',
        'label': label.isEmpty ? 'Tunjangan' : label,
        'kind': 'allowance',
        'calc': 'fixed',
        'default_value': amt,
      });
    }
    var j = 0;
    for (final d in _deds) {
      final amt = _digits(d.amount);
      final label = d.label.text.trim();
      if (amt == null || amt <= 0) continue;
      j++;
      comps.add({
        'key': 'ded_$j',
        'label': label.isEmpty ? 'Potongan' : label,
        'kind': 'deduction',
        'calc': 'fixed',
        'default_value': amt,
      });
    }
    comps.add({
      'key': 'tax',
      'label': 'PPh',
      'kind': 'tax',
      'calc': _taxMode == 'percent' ? 'percent' : 'manual',
      'tax_mode': _taxMode,
      if (_taxMode == 'percent')
        'tax_percent': double.tryParse(_taxPct.text.replaceAll(',', '.')) ?? 0,
      if (_taxMode == 'nominal') 'tax_nominal': _digits(_taxNom) ?? 0,
    });
    Navigator.pop(
      context,
      _TemplateEditResult.save(
        nama: _nama.text.trim().isEmpty ? 'Template' : _nama.text.trim(),
        components: comps,
      ),
    );
  }

  String get _liveSummary {
    final bits = <String>[];
    final gaji = _digits(_gaji);
    if (gaji != null) bits.add('pokok Rp ${_pretty(gaji)}');
    if (_allows.isNotEmpty) bits.add('${_allows.length} tunjangan');
    if (_deds.isNotEmpty) bits.add('${_deds.length} potongan');
    final ot = _digits(_otRate);
    if (ot != null) bits.add('lembur Rp ${_pretty(ot)}/jam');
    if (_taxMode == 'percent') {
      bits.add('PPh ${_taxPct.text.trim().isEmpty ? '—' : _taxPct.text}%');
    } else if (_taxMode == 'nominal') {
      final n = _digits(_taxNom);
      bits.add(n == null ? 'PPh nominal' : 'PPh Rp ${_pretty(n)}');
    } else {
      bits.add('PPh off');
    }
    return bits.join(' · ');
  }

  Widget _section({
    required String label,
    required IconData icon,
    required List<Widget> children,
    Color? accent,
  }) {
    final wash = accent ?? OptikAdminTokens.ice;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PremiumIconBadge(icon: icon, color: wash, size: 32),
              const SizedBox(width: 10),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.95),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _moneyRow(_NamedAmt row, {required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: row.label,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: _field('admin_auto_c6e88f1b17'.tr(), hint: 'Contoh: makan'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.amount,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: _field('admin_gl_row_79e01c1296'.tr(), prefix: 'Rp '),
            ),
          ),
          IconButton(
            tooltip: 'admin_auto_7723bf5991'.tr(),
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            color: OptikAdminTokens.danger,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final width = mq.width.clamp(320.0, 560.0);
    final maxH = (mq.height - 40).clamp(320.0, 740.0);
    final isEdit = widget.existing != null;

    return Material(
      color: OptikAdminTokens.card,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: OptikAdminTokens.ice, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxH),
        child: SizedBox(
          width: width,
          height: maxH,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [OptikAdminTokens.navy, OptikAdminTokens.ice],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                child: Row(
                  children: [
                    const PremiumIconBadge(
                      icon: Icons.layers_rounded,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Edit template' : 'Template baru',
                            style: TextStyle(
                              color: OptikAdminTokens.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sistem gaji lengkap. Saat terapkan, cukup pilih nama.',
                            style: TextStyle(
                              color: OptikAdminTokens.slate.withOpacity(0.95),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: OptikAdminTokens.slate,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.ice.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _liveSummary,
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _section(
                      label: 'admin_auto_8fa6cc2d57'.tr(),
                      icon: Icons.badge_outlined,
                      children: [
                        TextField(
                          controller: _nama,
                          decoration: _field('Nama template'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _section(
                      label: 'admin_auto_a70eda85d5'.tr(),
                      icon: Icons.payments_outlined,
                      children: [
                        TextField(
                          controller: _gaji,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: _field(
                            'admin_lbl_gaji_pokok'.tr(),
                            hint: 'Kosong = pakai master karyawan',
                            prefix: 'Rp ',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _otRate,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: _field(
                            'Rate lembur / jam',
                            prefix: 'Rp ',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _section(
                      label: 'admin_auto_c87010a632'.tr(),
                      icon: Icons.percent_rounded,
                      children: [
                        AdminPickerField(
                          label: 'admin_auto_58478d8da7'.tr(),
                          valueText: _taxLabel,
                          hint: 'Pilih cara potong',
                          icon: Icons.percent_rounded,
                          onTap: _pickTax,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _taxSubtitle,
                          style: TextStyle(
                            color: OptikAdminTokens.slate.withOpacity(0.95),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        if (_taxMode == 'percent') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _taxPct,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration:
                                _field('admin_gl_row_5e4b3cae7e'.tr(), prefix: '% '),
                          ),
                        ],
                        if (_taxMode == 'nominal') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _taxNom,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: _field('admin_gl_row_8f309304d9'.tr(), prefix: 'Rp '),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    _section(
                      label: 'admin_auto_35948f742c'.tr(),
                      icon: Icons.add_card_rounded,
                      accent: OptikAdminTokens.success,
                      children: [
                        if (_allows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Belum ada tunjangan. Tambah baris, isi nama dan Rp.',
                              style: TextStyle(
                                color: OptikAdminTokens.slate.withOpacity(0.9),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        for (var i = 0; i < _allows.length; i++)
                          _moneyRow(
                            _allows[i],
                            onRemove: () {
                              setState(() {
                                _allows[i].dispose();
                                _allows.removeAt(i);
                              });
                            },
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: PremiumActionChip(
                            label: 'admin_auto_fcb6218725'.tr(),
                            icon: Icons.add_rounded,
                            onPressed: () =>
                                setState(() => _allows.add(_NamedAmt())),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _section(
                      label: 'admin_auto_e1bf49bf4c'.tr(),
                      icon: Icons.remove_circle_outline_rounded,
                      accent: OptikAdminTokens.warning,
                      children: [
                        if (_deds.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Belum ada potongan. Contoh: BPJS, kasbon.',
                              style: TextStyle(
                                color: OptikAdminTokens.slate.withOpacity(0.9),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        for (var i = 0; i < _deds.length; i++)
                          _moneyRow(
                            _deds[i],
                            onRemove: () {
                              setState(() {
                                _deds[i].dispose();
                                _deds.removeAt(i);
                              });
                            },
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: PremiumActionChip(
                            label: 'admin_auto_884c3f842d'.tr(),
                            icon: Icons.add_rounded,
                            onPressed: () =>
                                setState(() => _deds.add(_NamedAmt())),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.bgMid,
                    border: Border(
                      top: BorderSide(
                        color: OptikAdminTokens.ice.withOpacity(0.7),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      PremiumPrimaryButton(
                        label: 'admin_auto_18453d679a'.tr(),
                        icon: Icons.check_rounded,
                        onPressed: _save,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (isEdit)
                            TextButton(
                              onPressed: _confirmDelete,
                              style: TextButton.styleFrom(
                                foregroundColor: OptikAdminTokens.danger,
                              ),
                              child: Text('btn_hapus'.tr()),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('appr_btn_batal'.tr()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatePickTile extends StatelessWidget {
  const _TemplatePickTile({
    required this.nama,
    required this.subtitle,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  final String nama;
  final String subtitle;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? OptikAdminTokens.accentSoft.withOpacity(0.5)
                  : OptikAdminTokens.cardElevated,
              border: Border.all(
                color: selected
                    ? OptikAdminTokens.navy.withOpacity(0.35)
                    : OptikAdminTokens.ice.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color:
                      selected ? OptikAdminTokens.navy : OptikAdminTokens.slate,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikAdminTokens.slate.withOpacity(0.95),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'admin_auto_2992dafa14'.tr(),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: OptikAdminTokens.navy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
