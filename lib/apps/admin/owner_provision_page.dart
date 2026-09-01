import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../shared/bootstrap.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Admin Pusat / Owner Utama: buat akun Owner + assign toko + split % (default 50/50).
class OwnerProvisionPage extends StatefulWidget {
  const OwnerProvisionPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OwnerProvisionPage> createState() => _OwnerProvisionPageState();
}

class _OwnerProvisionPageState extends State<OwnerProvisionPage> {
  final _nama = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _pctUtama = TextEditingController(text: '50');
  final _pctToko = TextEditingController(text: '50');

  String _ownerType = 'toko';
  final Set<String> _selectedToko = {};
  List<Map<String, dynamic>> _tokoMaster = [];
  List<Map<String, dynamic>> _owners = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _canProvision {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return role == 'owner' ||
        role == 'admin_pusat' ||
        role == 'super_admin';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _nama.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _pctUtama.dispose();
    _pctToko.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final toko = await supabase.from('toko_id').select('id, toko_id').order('id');
      List<Map<String, dynamic>> owners = [];
      try {
        final raw = await supabase.rpc('admin_list_owners');
        if (raw is List) {
          owners = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        // Table may not exist yet on old deploys.
      }
      if (!mounted) return;
      setState(() {
        _tokoMaster = (toko as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _owners = owners;
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

  Future<void> _submit() async {
    if (!_canProvision) {
      _snack('admin_gl_row_cffde148d9'.tr(), OptikAdminTokens.danger);
      return;
    }
    final nama = _nama.text.trim();
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (nama.isEmpty || email.isEmpty || password.length < 6) {
      _snack('admin_gl_row_82e43f80b5'.tr(), OptikAdminTokens.warning);
      return;
    }
    if (_ownerType == 'toko' && _selectedToko.isEmpty) {
      _snack('admin_gl_row_4f4418f374'.tr(), OptikAdminTokens.warning);
      return;
    }
    final pctU = num.tryParse(_pctUtama.text.trim()) ?? 50;
    final pctT = num.tryParse(_pctToko.text.trim()) ?? 50;
    if ((pctU + pctT).round() != 100) {
      _snack('admin_gl_row_b019116111'.tr(), OptikAdminTokens.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      // Prefer edge function (service role creates auth user without hijacking session).
      String? userId;
      try {
        final fn = await supabase.functions.invoke(
          'provision-owner',
          body: {
            'email': email,
            'password': password,
            'nama': nama,
            'owner_type': _ownerType,
            'toko_ids': _ownerType == 'utama'
                ? _selectedToko.toList()
                : _selectedToko.toList(),
            'pct_utama': pctU,
            'pct_toko': pctT,
            'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            'primary_toko':
                _selectedToko.isEmpty ? null : _selectedToko.first,
          },
        );
        final data = fn.data;
        if (fn.status >= 400) {
          throw 'provision-owner HTTP ${fn.status}: $data';
        }
        if (data is Map && data['user_id'] != null) {
          userId = data['user_id'].toString();
        } else if (data is Map && data['ok'] == true) {
          userId = data['user_id']?.toString();
        }
      } catch (e) {
        debugPrint('provision-owner function: $e — fallback signUp attach');
        userId = await _fallbackCreateAndAttach(
          email: email,
          password: password,
          nama: nama,
          pctU: pctU,
          pctT: pctT,
        );
      }

      if (userId == null || userId.isEmpty) {
        throw 'Gagal membuat user Owner';
      }

      if (!mounted) return;
      _snack('admin_auto_81f331c156'.tr(namedArgs: {'email': email}), OptikAdminTokens.success);
      _nama.clear();
      _email.clear();
      _password.clear();
      _phone.clear();
      _selectedToko.clear();
      await _boot();
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fallback: signUp (may switch session) then restore admin session via re-login prompt.
  /// Prefer deploying provision-owner edge function.
  Future<String> _fallbackCreateAndAttach({
    required String email,
    required String password,
    required String nama,
    required num pctU,
    required num pctT,
  }) async {
    final adminSession = supabase.auth.currentSession;
    final adminEmail = adminSession?.user.email;
    if (adminEmail == null) throw 'Sesi Admin hilang';

    final created = await supabase.auth.signUp(
      email: email,
      password: password,
    );
    final uid = created.user?.id;
    if (uid == null) throw 'signUp Owner gagal';

    // Attach while still on new user session (RPC needs provisioner — will fail).
    // So restore admin: we cannot without password. Call RPC as service via function only.
    // Instead: sign out new user and ask admin to re-login, then call attach with known uid.
    await supabase.auth.signOut();

    throw 'Edge function provision-owner belum tersedia. '
        'Buat user Auth manual untuk $email (uid $uid), login ulang Admin, '
        'lalu jalankan attach. Atau deploy supabase/functions/provision-owner.';
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      appBar: AppBar(
        title: Text('admin_auto_99c0cdbfe4'.tr()),
        backgroundColor: OptikAdminTokens.bg,
        foregroundColor: OptikAdminTokens.navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    PremiumSectionHeader(label: 'admin_auto_d3b6571884'.tr()),
                    const SizedBox(height: 8),
                    Text(
                      'Owner masuk APK Karyawan → shell Owner. '
                      'Bukan jabatan self-register. Default bagi hasil 50/50.',
                      style: TextStyle(color: OptikAdminTokens.slate),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nama,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_c6e88f1b17'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_4bcaf1b235'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_df434e759f'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_6f56f62cac'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _ownerType,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_6b969aac32'.tr(),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'utama',
                          child: Text('admin_auto_c7551fb865'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'toko',
                          child: Text('admin_auto_3c95140888'.tr()),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _ownerType = v ?? 'toko'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pctUtama,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'admin_auto_cc2646a93e'.tr(),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _pctToko,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'admin_auto_a34a275a47'.tr(),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _ownerType == 'utama'
                          ? 'Cabang opsional (Owner Utama melihat semua by default):'
                          : 'Cabang wajib (Owner Toko):',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _tokoMaster)
                          FilterChip(
                            label: Text((t['id'] ?? '').toString()),
                            selected: _selectedToko.contains(t['id']),
                            onSelected: (sel) {
                              setState(() {
                                final id = (t['id'] ?? '').toString();
                                if (sel) {
                                  _selectedToko.add(id);
                                } else {
                                  _selectedToko.remove(id);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikAdminTokens.navy,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: OptikAdminTokens.snow,
                              ),
                            )
                          : Text('admin_auto_99c0cdbfe4'.tr()),
                    ),
                    const SizedBox(height: 28),
                    PremiumSectionHeader(label: 'admin_auto_7f2374b056'.tr()),
                    const SizedBox(height: 8),
                    if (_owners.isEmpty)
                      Text('admin_auto_33b1303c07'.tr())
                    else
                      ..._owners.map((o) {
                        final tokoIds = o['toko_ids'];
                        final tokoStr = tokoIds is List
                            ? tokoIds.join(', ')
                            : '-';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${o['nama']} (${o['owner_type']})',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: OptikAdminTokens.navy,
                            ),
                          ),
                          subtitle: Text('${o['email']}\n$tokoStr'),
                          isThreeLine: true,
                        );
                      }),
                  ],
                ),
    );
  }
}
