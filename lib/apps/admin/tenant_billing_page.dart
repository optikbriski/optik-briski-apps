import 'package:flutter/foundation.dart';
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
        title: const Text('Buat tagihan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: period,
                decoration: const InputDecoration(
                  labelText: 'Periode (YYYY-MM)',
                ),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
              ),
              TextField(
                controller: due,
                decoration: const InputDecoration(
                  labelText: 'Jatuh tempo (YYYY-MM-DD)',
                ),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Catatan'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
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
        title: const Text('Buat kontrak online'),
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
                decoration: const InputDecoration(
                  labelText: 'Judul (opsional)',
                ),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nilai acuan (Rp)'),
              ),
              TextField(
                controller: extra,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Pasal tambahan (opsional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buat tautan')),
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
        _snack('Tautan disalin. Kirim via WA/email.', OptikAdminTokens.success);
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
    _snack('Tautan kontrak disalin', OptikAdminTokens.success);
  }

  @override
  Widget build(BuildContext context) {
    final status = '${widget.tenant['status'] ?? 'aktif'}';
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: Text('Tagihan · $_name'),
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
                      label: const Text('Buat tagihan'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || !_isPlatform ? null : _createContract,
                      icon: const Icon(Icons.draw_rounded),
                      label: const Text('Buat kontrak'),
                    ),
                    OutlinedButton(
                      onPressed: _busy || !_isPlatform
                          ? null
                          : () => _rpc(
                                'enforce_tenant_billing',
                                const {},
                                'Tagihan jatuh tempo ditandai. UMKM menunggak dimatikan.',
                              ),
                      child: const Text('Tegakkan hari H'),
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
                        child: const Text('Matikan sekarang'),
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
                        child: const Text('Nyalakan (force)'),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const PremiumSectionHeader(label: 'Tagihan'),
                const SizedBox(height: 8),
                if (_invoices.isEmpty) const Text('Belum ada tagihan.'),
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
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'paid', child: Text('Tandai lunas')),
                                  PopupMenuItem(value: 'void', child: Text('Batalkan')),
                                ],
                              ),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                const PremiumSectionHeader(label: 'Kontrak online'),
                const SizedBox(height: 8),
                if (_contracts.isEmpty) const Text('Belum ada kontrak.'),
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
                              tooltip: 'Salin tautan',
                              onPressed: () => _copyLink('${c['public_token']}'),
                              icon: const Icon(Icons.link_rounded),
                            ),
                            IconButton(
                              tooltip: 'Lihat',
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
