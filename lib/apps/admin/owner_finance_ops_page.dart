import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

import '../../shared/bootstrap.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import 'payroll_workspace_page.dart';

/// Admin Pusat / Owner Utama: run payroll period + post saldo pusat↔toko.
/// RPCs: admin_run_payroll_period, admin_post_saldo_movement.
/// Prefer [PayrollWorkspacePage] for flexible bonus/OT/PPh.
class OwnerFinanceOpsPage extends StatefulWidget {
  const OwnerFinanceOpsPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<OwnerFinanceOpsPage> createState() => _OwnerFinanceOpsPageState();
}

class _OwnerFinanceOpsPageState extends State<OwnerFinanceOpsPage> {
  final _periode = TextEditingController(
    text: _ym(DateTime.now()),
  );
  final _amount = TextEditingController();
  final _note = TextEditingController();

  List<Map<String, dynamic>> _tokoMaster = [];
  String? _tokoId;
  String _direction = 'pusat_ke_toko';
  bool _lockPayroll = true;
  bool _loading = true;
  bool _busyPayroll = false;
  bool _busySaldo = false;
  String? _error;
  Map<String, dynamic>? _lastPayroll;
  Map<String, dynamic>? _lastSaldo;

  bool get _canRun {
    final role = (widget.profile['role'] ?? '').toString().toLowerCase();
    return role == 'owner' ||
        role == 'admin_pusat' ||
        role == 'super_admin';
  }

  static String _ym(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _periode.dispose();
    _amount.dispose();
    _note.dispose();
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
      if (!mounted) return;
      final list = (toko as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) {
            final id = (t['id'] ?? '').toString();
            return id.isNotEmpty && id != 'PUSAT' && id != 'CABANG-PUSAT';
          })
          .toList();
      setState(() {
        _tokoMaster = list;
        _tokoId = list.isEmpty ? null : list.first['id']?.toString();
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

  Future<void> _runPayroll() async {
    if (!_canRun) {
      _snack('admin_gl_row_cffde148d9'.tr(), OptikAdminTokens.danger);
      return;
    }
    final toko = _tokoId;
    final ym = _periode.text.trim();
    if (toko == null || toko.isEmpty) {
      _snack('admin_gl_row_fdae65f210'.tr(), OptikAdminTokens.warning);
      return;
    }
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(ym)) {
      _snack('admin_gl_row_7b53b8eadd'.tr(), OptikAdminTokens.warning);
      return;
    }
    setState(() => _busyPayroll = true);
    try {
      final raw = await supabase.rpc(
        'admin_run_payroll_period',
        params: {
          'p_toko_id': toko,
          'p_periode_ym': ym,
          'p_lock': _lockPayroll,
        },
      );
      if (!mounted) return;
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'raw': raw};
      setState(() => _lastPayroll = map);
      _snack(
        'Payroll $toko $ym · ${map['status'] ?? '-'} · '
        'nett ${map['total_nett'] ?? 0}',
        OptikAdminTokens.success,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _busyPayroll = false);
    }
  }

  Future<void> _postSaldo() async {
    if (!_canRun) {
      _snack('admin_gl_row_cffde148d9'.tr(), OptikAdminTokens.danger);
      return;
    }
    final toko = _tokoId;
    final amount = int.tryParse(_amount.text.trim().replaceAll('.', ''));
    if (toko == null || toko.isEmpty) {
      _snack('admin_gl_row_fdae65f210'.tr(), OptikAdminTokens.warning);
      return;
    }
    if (amount == null || amount <= 0) {
      _snack('admin_gl_row_6c55d78035'.tr(), OptikAdminTokens.warning);
      return;
    }
    setState(() => _busySaldo = true);
    try {
      final raw = await supabase.rpc(
        'admin_post_saldo_movement',
        params: {
          'p_toko_id': toko,
          'p_direction': _direction,
          'p_amount': amount,
          'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          'p_ref_type': 'admin_ui',
          'p_ref_id': null,
        },
      );
      if (!mounted) return;
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'raw': raw};
      setState(() => _lastSaldo = map);
      _snack('admin_gl_row_c98c868185'.tr(), OptikAdminTokens.success);
      _amount.clear();
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _busySaldo = false);
    }
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
        title: Text('admin_auto_bb2f026863'.tr()),
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
                    Text(
                      'Sinkron ke Owner APK: owner_payroll_monitor + '
                      'owner_list_cabang / owner_list_saldo_ledger.',
                      style: TextStyle(color: OptikAdminTokens.slate),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PayrollWorkspacePage(
                              profile: widget.profile,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.payments_rounded),
                      label: Text('admin_auto_5cb45ecd54'.tr()),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _tokoId,
                      decoration: InputDecoration(
                        labelText: 'work_sum_toko'.tr(),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final t in _tokoMaster)
                          DropdownMenuItem(
                            value: t['id']?.toString(),
                            child: Text((t['id'] ?? '').toString()),
                          ),
                      ],
                      onChanged: (v) => setState(() => _tokoId = v),
                    ),
                    const SizedBox(height: 24),
                    PremiumSectionHeader(label: 'admin_auto_7e24f15ee9'.tr()),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _periode,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_9562db598e'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('admin_auto_b9b697e972'.tr()),
                      value: _lockPayroll,
                      onChanged: (v) => setState(() => _lockPayroll = v),
                    ),
                    FilledButton(
                      onPressed: _busyPayroll ? null : _runPayroll,
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikAdminTokens.navy,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _busyPayroll
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: OptikAdminTokens.snow,
                              ),
                            )
                          : Text('admin_auto_cd5c55776d'.tr()),
                    ),
                    if (_lastPayroll != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last: ${_lastPayroll!['periode_ym']} · '
                        '${_lastPayroll!['status']} · '
                        'nett ${_lastPayroll!['total_nett']} · '
                        'lines ${_lastPayroll!['line_count']}',
                        style: TextStyle(color: OptikAdminTokens.slate),
                      ),
                    ],
                    const SizedBox(height: 28),
                    PremiumSectionHeader(label: 'admin_auto_10bf5cc5be'.tr()),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _direction,
                      decoration: InputDecoration(
                        labelText: 'admin_auto_2b20ac2df6'.tr(),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'pusat_ke_toko',
                          child: Text('admin_auto_e8d57ef9d1'.tr()),
                        ),
                        DropdownMenuItem(
                          value: 'toko_ke_pusat',
                          child: Text('admin_auto_5b806fbc42'.tr()),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _direction = v ?? 'pusat_ke_toko'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: 'admin_lbl_nominal_rp'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _note,
                      decoration: InputDecoration(
                        labelText: 'ops_reimburse_catatan_admin'.tr(),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busySaldo ? null : _postSaldo,
                      style: FilledButton.styleFrom(
                        backgroundColor: OptikAdminTokens.navy,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _busySaldo
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: OptikAdminTokens.snow,
                              ),
                            )
                          : Text('admin_auto_10bf5cc5be'.tr()),
                    ),
                    if (_lastSaldo != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'OK: ${_lastSaldo!['ok'] == true}',
                        style: TextStyle(color: OptikAdminTokens.slate),
                      ),
                    ],
                  ],
                ),
    );
  }
}
