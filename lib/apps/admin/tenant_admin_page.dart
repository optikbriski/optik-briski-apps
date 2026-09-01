import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../shared/bootstrap.dart';
import '../../shared/tenant/industry_catalog.dart';
import '../../shared/tenant/module_catalog.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'tenant_billing_page.dart';

/// Rekasa: daftar UMKM + paket A/B/C + white-label.
/// Paket bawah = kulit Rekasa. Paket A = APK/web merek sendiri.
class TenantAdminPage extends StatefulWidget {
  const TenantAdminPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<TenantAdminPage> createState() => _TenantAdminPageState();
}

class _TenantAdminPageState extends State<TenantAdminPage> {
  static List<Map<String, dynamic>> get _fallbackPlans => [
    {
      'plan_key': 'paket_c',
      'label': 'admin_plan_paket_c'.tr(),
      'white_label': false,
    },
    {
      'plan_key': 'paket_b',
      'label': 'admin_plan_paket_b'.tr(),
      'white_label': false,
    },
    {
      'plan_key': 'paket_a',
      'label': 'admin_plan_paket_a'.tr(),
      'white_label': true,
    },
  ];

  final _slug = TextEditingController();
  final _name = TextEditingController();
  final _short = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _planKey = 'paket_c';
  String _industry = 'optik';
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _plans = List.of(_fallbackPlans);

  String _planLabel(Map<String, dynamic> p) {
    final label = (p['label'] ?? p['plan_key'] ?? '').toString();
    final shell = (p['shell'] ?? '').toString().trim();
    if (shell.isNotEmpty && !label.contains('merek sendiri') && !label.contains('kulit Rekasa')) {
      return '$label · $shell';
    }
    return label;
  }

  String _shellCaption(Map<String, dynamic> row) {
    if (row['white_label'] == true) return 'APK & web merek sendiri';
    return 'kulit Rekasa + kode usaha';
  }

  bool get _isPlatform {
    final v = widget.profile['is_platform'];
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return v == true || v == 'true' || role == 'platform';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _slug.dispose();
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        final plansRaw = await supabase.rpc('list_tenant_plans');
        final plans = <Map<String, dynamic>>[];
        if (plansRaw is List) {
          for (final e in plansRaw) {
            if (e is Map) plans.add(Map<String, dynamic>.from(e));
          }
        }
        if (plans.isNotEmpty) _plans = plans;
      } catch (_) {}

      final raw = await supabase.rpc('platform_list_tenants');
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (!_isPlatform) return;
    final slug = _slug.text.trim();
    final name = _name.text.trim();
    if (slug.length < 3 || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_e48f20b96d'.tr()),
          backgroundColor: OptikAdminTokens.warning,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await supabase.rpc('platform_create_tenant', params: {
        'p_slug': slug,
        'p_display_name': name,
        'p_short_name': _short.text.trim().isEmpty ? null : _short.text.trim(),
        'p_plan_key': _planKey,
      });
      if (!mounted) return;
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) {
        throw map['error'] ?? 'Gagal buat tenant';
      }
      if (map['tenant_id'] != null) {
        try {
          await supabase.rpc('platform_set_tenant_industry', params: {
            'p_tenant_id': map['tenant_id'],
            'p_industry_key': _industry,
          });
        } catch (_) {}
      }
      if (!mounted) return;
      _slug.clear();
      _name.clear();
      _short.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'UMKM siap · ${map['plan_key'] ?? _planKey}. '
            'Kode ${map['slug']} · pusat ${map['pusat_toko_id']}. '
            'admin_auto_not_optik_branch'.tr(),
          ),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _boot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('admin_auto_564b2dc6f1'.tr(namedArgs: {'error': '$e'})),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setPlan(Map<String, dynamic> row, String planKey) async {
    if (!_isPlatform) return;
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final res = await supabase.rpc('platform_set_tenant_plan', params: {
        'p_tenant_id': id,
        'p_plan_key': planKey,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal ganti paket';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Paket ${row['display_name'] ?? row['slug']} → $planKey. '
            'admin_auto_tenant_module_skin'.tr(),
          ),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _boot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_auto_564b2dc6f1'.tr(namedArgs: {'error': '$e'})), backgroundColor: OptikAdminTokens.danger),
      );
    }
  }

  Future<void> _editModules(Map<String, dynamic> row) async {
    if (!_isPlatform) return;
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    final enabled = <String, bool>{
      for (final m in moduleCatalog) m.key: false,
    };
    try {
      final raw = await supabase.rpc(
        'platform_list_tenant_modules',
        params: {'p_tenant_id': id},
      );
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final k = (e['module_key'] ?? '').toString();
          if (enabled.containsKey(k)) enabled[k] = e['enabled'] == true;
        }
      }
    } catch (_) {}

    var whiteLabel = row['white_label'] == true;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('Modul ${row['display_name'] ?? row['slug']}'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Centang yang dibeli merek ini. Boleh campur, tidak harus A/B/C.',
                        style: TextStyle(fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        dense: true,
                        title: Text('admin_auto_b2dc316843'.tr()),
                        subtitle: const Text(
                          'Nama + ikon toko. Paket A default nyala. '
                          'B/C pakai kulit Rekasa + kode usaha.',
                          style: TextStyle(fontSize: 12, height: 1.3),
                        ),
                        value: whiteLabel,
                        onChanged: (v) => setLocal(() => whiteLabel = v),
                      ),
                      const Divider(),
                      for (final m in moduleCatalog)
                        SwitchListTile(
                          dense: true,
                          title: Text(m.label),
                          value: enabled[m.key] ?? false,
                          onChanged: (v) => setLocal(() => enabled[m.key] = v),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('appr_btn_batal'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('btn_simpan'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      final res = await supabase.rpc('platform_set_tenant_modules', params: {
        'p_tenant_id': id,
        'p_modules': enabled,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal simpan modul';
      try {
        final wl = await supabase.rpc('platform_set_tenant_white_label', params: {
          'p_tenant_id': id,
          'p_white_label': whiteLabel,
        });
        final wlMap = wl is Map ? Map<String, dynamic>.from(wl) : <String, dynamic>{};
        if (wlMap['ok'] != true) throw wlMap['error'] ?? 'Gagal simpan white-label';
      } catch (e) {
        if (e.toString().contains('Gagal simpan white-label')) rethrow;
        // Migrasi 000006 belum di-apply: modul tetap tersimpan.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Modul disimpan (${map['plan_key'] ?? 'custom'}). '
            '${whiteLabel ? 'APK/web merek sendiri.' : 'admin_auto_rekasa_skin_code'.tr()} '
            'Menu berubah setelah login ulang.',
          ),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _boot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_auto_564b2dc6f1'.tr(namedArgs: {'error': '$e'})), backgroundColor: OptikAdminTokens.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: Text('admin_auto_d6b7a2e5fb'.tr()),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Setiap UMKM sekat tenant_id — bukan cabang Optik. '
                  'Paket C/B: APK & web Rekasa, beda di kode usaha + isi dalam. '
                  'Paket A: APK & web nama+ikon merek sendiri (build BRAND=slug). '
                  'Modul dan white-label bisa dicentang satu-satu. '
                  'Bidang usaha (optik, resto, bengkel, …) menentukan paket dan nama fitur. '
                  'Tagihan hari H belum lunas → sistem UMKM dimatikan (data tetap).',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.75),
                    height: 1.35,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: OptikAdminTokens.danger)),
                ],
                const SizedBox(height: 20),
                PremiumSectionHeader(label: 'admin_auto_bae1eaeb80'.tr()),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  Text('admin_auto_ae5792b4a1'.tr()),
                for (final r in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumPanel(
                      child: ListTile(
                        title: Text(
                          '${r['display_name'] ?? r['legal_name'] ?? r['slug']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${r['slug']} · ${r['industry_label'] ?? r['industry_key'] ?? ''} · ${r['status'] ?? 'aktif'} · '
                          '${r['plan_label'] ?? r['plan_key'] ?? 'paket?'} · '
                          '${_shellCaption(r)}'
                          '${r['plan_price_idr'] != null ? ' · ${TenantBilling.formatRp(r['plan_price_idr'])}/periode' : ''}'
                          '${(r['overdue_invoices'] ?? 0) != 0 ? ' · ${r['overdue_invoices']} jatuh tempo' : ''}',
                        ),
                        trailing: !_isPlatform
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'admin_auto_9a0a223935'.tr(),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TenantBillingPage(
                                            profile: widget.profile,
                                            tenant: r,
                                          ),
                                        ),
                                      ).then((_) => _boot());
                                    },
                                    icon: const Icon(Icons.receipt_long_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'admin_auto_622844abf0'.tr(),
                                    onPressed: () => _editModules(r),
                                    icon: const Icon(Icons.extension_rounded),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'admin_auto_44b4c191e0'.tr(),
                                    onSelected: (k) => _setPlan(r, k),
                                    itemBuilder: (_) => [
                                      for (final p in _plans)
                                        PopupMenuItem(
                                          value: '${p['plan_key']}',
                                          child: Text(_planLabel(p)),
                                        ),
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.tune_rounded),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                PremiumSectionHeader(label: 'admin_auto_ee8e92e08b'.tr()),
                const SizedBox(height: 8),
                TextField(
                  controller: _slug,
                  decoration: InputDecoration(
                    labelText: 'admin_auto_194858d252'.tr(),
                    hintText: 'admin_auto_2813842c50'.tr(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'admin_auto_0648a27548'.tr(),
                    hintText: 'admin_auto_f1f21558f2'.tr(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _short,
                  decoration: InputDecoration(
                    labelText: 'admin_auto_177246bb03'.tr(),
                    hintText: 'admin_auto_bfbebc0782'.tr(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: industryCatalog.any((i) => i.key == _industry)
                      ? _industry
                      : industryCatalog.first.key,
                  decoration: InputDecoration(labelText: 'admin_auto_ac2a3289ff'.tr()),
                  items: [
                    for (final i in industryCatalog)
                      DropdownMenuItem(
                        value: i.key,
                        child: Text(i.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _industry = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _plans.any((p) => p['plan_key'] == _planKey)
                      ? _planKey
                      : '${_plans.first['plan_key']}',
                  decoration: InputDecoration(labelText: 'admin_auto_2b0a1a8d27'.tr()),
                  items: [
                    for (final p in _plans)
                      DropdownMenuItem(
                        value: '${p['plan_key']}',
                        child: Text(_planLabel(p), overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _planKey = v);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _planKey == 'paket_a'
                      ? 'Paket A: build APK/web merek ini (nama + ikon sendiri).'
                      : 'Paket ini: pakai APK/web Rekasa. Member & karyawan isi kode usaha.',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.65),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                PremiumPrimaryButton(
                  label: _saving ? 'admin_btn_menyimpan'.tr() : 'admin_btn_buat_tenant'.tr(),
                  onPressed: _saving || !_isPlatform ? null : _create,
                ),
                if (!_isPlatform) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Akun ini bukan Rekasa. Di Table Editor → profiles, '
                    'set is_platform = true pada akun operator Rekasa.',
                    style: TextStyle(color: OptikAdminTokens.warning),
                  ),
                ],
              ],
            ),
    );
  }
}
