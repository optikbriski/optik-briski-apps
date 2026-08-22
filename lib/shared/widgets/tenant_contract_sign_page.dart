import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../bootstrap.dart';
import '../tenant/tenant_billing.dart';
import '../theme.dart';
import 'admin/admin_premium.dart';

/// Tanda tangan kontrak Rekasa di web (tautan `?kontrak=`).
/// Klik-setuju + ketik nama + stempel waktu. Bukan API pihak ketiga.
class TenantContractSignPage extends StatefulWidget {
  const TenantContractSignPage({super.key, required this.token});

  final String token;

  @override
  State<TenantContractSignPage> createState() => _TenantContractSignPageState();
}

class _TenantContractSignPageState extends State<TenantContractSignPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _agree = false;
  String? _error;
  Map<String, dynamic> _doc = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await supabase.rpc(
        'get_contract_by_token',
        params: {'p_token': widget.token},
      );
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (map['ok'] != true) {
        throw map['error'] ?? 'Kontrak tidak ditemukan';
      }
      if (!mounted) return;
      setState(() {
        _doc = map;
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

  Future<void> _sign() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final raw = await supabase.rpc('sign_tenant_contract', params: {
        'p_token': widget.token,
        'p_signer_name': _name.text,
        'p_agree': _agree,
        'p_signer_email': _email.text,
        'p_user_agent': kIsWeb ? 'web' : 'app',
      });
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (map['ok'] != true) throw map['error'] ?? 'Gagal menandatangani';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tertandatangani ${map['signer_name'] ?? _name.text}. '
            'Salinan tetap di tautan ini.',
          ),
          backgroundColor: OptikAdminTokens.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signed = _doc['status'] == 'signed';
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: const Text('Kontrak online'),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: OptikAdminTokens.danger)),
                if (_error == null) ...[
                  Text(
                    '${_doc['title'] ?? 'Perjanjian langganan'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: OptikAdminTokens.navy,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_doc['contract_no'] ?? ''} · ${_doc['provider'] ?? 'REKASA KARYA INDONESIA'}\n'
                    '${_doc['display_name'] ?? ''} · kode ${_doc['slug'] ?? ''}',
                    style: const TextStyle(
                      color: OptikAdminTokens.slate,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nilai acuan ${TenantBilling.formatRp(_doc['amount_idr'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  PremiumPanel(
                    child: SelectableText(
                      '${_doc['body'] ?? ''}',
                      style: const TextStyle(height: 1.45, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (signed) ...[
                    Text(
                      'Sudah ditandatangani ${_doc['signer_name'] ?? ''} '
                      'pada ${_doc['signed_at'] ?? ''}.',
                      style: const TextStyle(
                        color: OptikAdminTokens.success,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nama lengkap penandatangan',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email (opsional)',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _agree,
                      onChanged: (v) => setState(() => _agree = v == true),
                      title: const Text(
                        'Saya sudah membaca dan menyetujui seluruh pasal. '
                        'Persetujuan elektronik ini mengikat.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    PremiumPrimaryButton(
                      label: _saving ? 'Menyimpan…' : 'Tandatangani kontrak',
                      onPressed: _saving ? null : _sign,
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}
