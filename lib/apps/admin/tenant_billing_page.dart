import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/bootstrap.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';

/// Rekasa: tagihan langganan + kontrak online per UMKM.
class TenantBillingPage extends StatefulWidget {
  const TenantBillingPage({
    super.key,
    required this.profile,
    required this.tenant,
  });

  final Map<String, dynamic> profile;
  final Map<String, dynamic> tenant;

  @override
  State<TenantBillingPage> createState() => _TenantBillingPageState();
}

class _TenantBillingPageState extends State<TenantBillingPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _contracts = [];

  String get _tenantId => '${widget.tenant['id'] ?? ''}';
  String get _name =>
      '${widget.tenant['display_name'] ?? widget.tenant['legal_name'] ?? widget.tenant['slug']}';

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

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invRaw = await supabase.rpc(
        'platform_list_invoices',
        params: {'p_tenant_id': _tenantId},
      );
      final ctrRaw = await supabase.rpc(
        'platform_list_contracts',
        params: {'p_tenant_id': _tenantId},
      );
      final inv = <Map<String, dynamic>>[];
      final ctr = <Map<String, dynamic>>[];
      if (invRaw is List) {
        for (final e in invRaw) {
          if (e is Map) inv.add(Map<String, dynamic>.from(e));
        }
      }
      if (ctrRaw is List) {
        for (final e in ctrRaw) {
          if (e is Map) ctr.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _invoices = inv;
        _contracts = ctr;
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

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params, String okMsg) async {
    if (!_isPlatform || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await supabase.rpc(fn, params: params);
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal';
      _snack(okMsg, OptikAdminTokens.success);
      await _boot();
    } catch (e) {
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createInvoice() async {
    final period = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 7),
    );
    final amount = TextEditingController(
      text: '${widget.tenant['plan_price_idr'] ?? ''}',
    );
    final notes = TextEditingController();
    final due = TextEditingController(
      text: DateTime.now()
          .add(const Duration(days: 7))
          .toIso8601String()
          .substring(0, 10),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_36e943f02f'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: period,
                decoration: InputDecoration(
                  labelText: 'admin_auto_9562db598e'.tr(),
                ),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'admin_lbl_nominal_rp'.tr()),
              ),
              TextField(
                controller: due,
                decoration: InputDecoration(
                  labelText: 'admin_auto_4b72608256'.tr(),
                ),
              ),
              TextField(
                controller: notes,
                decoration: InputDecoration(labelText: 'admin_lbl_catatan'.tr()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('appr_btn_batal'.tr())),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('admin_btn_kirim'.tr())),
        ],
      ),
    );
    final p = period.text;
    final a = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', ''));
    final d = due.text.trim();
    final n = notes.text;
    period.dispose();
    amount.dispose();
    notes.dispose();
    due.dispose();
    if (ok != true) return;
    DateTime? dueAt;
    if (d.isNotEmpty) dueAt = DateTime.tryParse(d);
    await _rpc(
      'platform_create_invoice',
      {
        'p_tenant_id': _tenantId,
        'p_period': p,
        'p_amount_idr': a,
        'p_due_at': dueAt?.toIso8601String(),
        'p_notes': n,
      },
      'Tagihan terkirim. Hari H lewat & belum bayar → sistem down.',
    );
  }

  Future<void> _createContract() async {
    final title = TextEditingController();
    final extra = TextEditingController();
    final amount = TextEditingController(
      text: '${widget.tenant['plan_price_idr'] ?? ''}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('admin_auto_4710aa2222'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Klien buka tautan, baca, centang setuju, ketik nama. '
                'Berlaku terus sampai diakhiri — bukan fork aplikasi.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: 'admin_auto_269b82e35d'.tr(),
                ),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'admin_auto_c1456912d4'.tr()),
              ),
              TextField(
                controller: extra,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'admin_auto_e3659c3a61'.tr(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('appr_btn_batal'.tr())),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('admin_auto_a80accd5f7'.tr())),
        ],
      ),
    );
    final t = title.text;
    final x = extra.text.trim();
    final a = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', ''));
    title.dispose();
    extra.dispose();
    amount.dispose();
    if (ok != true) return;
    if (!_isPlatform || _busy) return;
    setState(() => _busy = true);
    try {
      String? body;
      if (x.isNotEmpty) {
        final tpl = await supabase.rpc('rekasa_contract_template', params: {
          'p_display_name': _name,
          'p_legal_name': widget.tenant['legal_name'],
          'p_slug': widget.tenant['slug'],
          'p_plan_label': widget.tenant['plan_label'] ?? widget.tenant['plan_key'],
          'p_amount_idr': a ?? widget.tenant['plan_price_idr'] ?? 0,
        });
        body = '${tpl ?? ''}\n\nPasal tambahan:\n$x';
      }
      final res = await supabase.rpc('platform_create_contract', params: {
        'p_tenant_id': _tenantId,
        'p_title': t,
        'p_body': body,
        'p_amount_idr': a,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal buat kontrak';
      final token = '${map['public_token'] ?? ''}';
      if (token.isNotEmpty) {
        final url = TenantBilling.publicSignUrl(token);
        await Clipboard.setData(ClipboardData(text: url));
        _snack('admin_gl_row_ab42f34873'.tr(), OptikAdminTokens.success);
      }
      await _boot();
    } catch (e) {
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink(String token) async {
    final url = TenantBilling.publicSignUrl(token);
    await Clipboard.setData(ClipboardData(text: url));
    _snack('admin_gl_row_6e51e7fc18'.tr(), OptikAdminTokens.success);
  }

  @override
  Widget build(BuildContext context) {
    final status = '${widget.tenant['status'] ?? 'aktif'}';
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: Text('admin_auto_7b68f68832'.tr(namedArgs: {'name': _name})),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                Text(
                  'Status $status'
                  '${widget.tenant['suspend_reason'] != null ? ' · ${widget.tenant['suspend_reason']}' : ''}. '
                  'Hari H lewat & belum bayar → akses UMKM mati. Data tidak dihapus. '
                  'Kontrak ditandatangani online (centang + ketik nama).',
                  style: TextStyle(
                    color: OptikAdminTokens.navy.withOpacity(0.75),
                    height: 1.35,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: OptikAdminTokens.danger)),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy || !_isPlatform ? null : _createInvoice,
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: Text('admin_auto_36e943f02f'.tr()),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || !_isPlatform ? null : _createContract,
                      icon: const Icon(Icons.draw_rounded),
                      label: Text('admin_auto_60da1788eb'.tr()),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !_isPlatform
                          ? null
                          : () => _rpc(
                                'enforce_tenant_billing',
                                const {},
                                'Tagihan jatuh tempo ditandai. UMKM menunggak dimatikan.',
                              ),
                      child: Text('admin_auto_074e2b8a70'.tr()),
                    ),
                    if (status != 'suspend')
                      OutlinedButton(
                        onPressed: _busy || !_isPlatform
                            ? null
                            : () => _rpc(
                                  'platform_set_tenant_status',
                                  {
                                    'p_tenant_id': _tenantId,
                                    'p_status': 'suspend',
                                    'p_reason': 'manual',
                                    'p_force': false,
                                  },
                                  'Sistem UMKM dimatikan (manual).',
                                ),
                        child: Text('admin_auto_f48b11dcae'.tr()),
                      )
                    else
                      OutlinedButton(
                        onPressed: _busy || !_isPlatform
                            ? null
                            : () => _rpc(
                                  'platform_set_tenant_status',
                                  {
                                    'p_tenant_id': _tenantId,
                                    'p_status': 'aktif',
                                    'p_force': true,
                                  },
                                  'Sistem dinyalakan lagi.',
                                ),
                        child: Text('admin_auto_877a60543f'.tr()),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                PremiumSectionHeader(label: 'admin_auto_50a3a70af9'.tr()),
                const SizedBox(height: 8),
                if (_invoices.isEmpty) Text('admin_auto_4f740f09b8'.tr()),
                for (final i in _invoices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${i['invoice_no']} · ${i['period']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${TenantBilling.formatRp(i['amount_idr'])} · '
                          '${i['status']} · jatuh ${i['due_at'] ?? '-'}',
                        ),
                        trailing: !_isPlatform ||
                                i['status'] == 'paid' ||
                                i['status'] == 'void'
                            ? null
                            : PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'paid') {
                                    _rpc(
                                      'platform_mark_invoice_paid',
                                      {
                                        'p_invoice_id': i['id'],
                                        'p_method': 'transfer',
                                      },
                                      'Lunas. Sistem nyala lagi jika tidak ada tunggakan.',
                                    );
                                  } else if (v == 'void') {
                                    _rpc(
                                      'platform_void_invoice',
                                      {'p_invoice_id': i['id']},
                                      'Tagihan dibatalkan.',
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'paid', child: Text('admin_auto_91c6fd7d72'.tr())),
                                  PopupMenuItem(value: 'void', child: Text('pengajuan_btn_batal'.tr())),
                                ],
                              ),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                PremiumSectionHeader(label: 'admin_auto_fb6e235f71'.tr()),
                const SizedBox(height: 8),
                if (_contracts.isEmpty) Text('admin_auto_7c3b3356af'.tr()),
                for (final c in _contracts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${c['contract_no']} · ${c['status']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${c['title'] ?? ''}\n'
                          '${c['signer_name'] != null ? 'Ditandatangani ${c['signer_name']}' : 'Belum ditandatangani'}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'admin_auto_a4d4c9981c'.tr(),
                              onPressed: () => _copyLink('${c['public_token']}'),
                              icon: const Icon(Icons.link_rounded),
                            ),
                            IconButton(
                              tooltip: 'admin_auto_de56c4f710'.tr(),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TenantContractSignPage(
                                      token: '${c['public_token']}',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.visibility_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Klien buka ${Uri.base.origin}/?kontrak=… di browser — tanpa login Rekasa.',
                    style: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.9),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
