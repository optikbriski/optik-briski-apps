import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/bootstrap.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Admin Pusat / Owner Utama: run payroll period + post saldo pusat↔toko.
/// RPCs: admin_run_payroll_period, admin_post_saldo_movement.
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
      _snack('Hanya Admin Pusat / Owner Utama.', OptikAdminTokens.danger);
      return;
    }
    final toko = _tokoId;
    final ym = _periode.text.trim();
    if (toko == null || toko.isEmpty) {
      _snack('Pilih cabang.', OptikAdminTokens.warning);
      return;
    }
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(ym)) {
      _snack('Periode harus YYYY-MM.', OptikAdminTokens.warning);
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
      _snack('Hanya Admin Pusat / Owner Utama.', OptikAdminTokens.danger);
      return;
    }
    final toko = _tokoId;
    final amount = int.tryParse(_amount.text.trim().replaceAll('.', ''));
    if (toko == null || toko.isEmpty) {
      _snack('Pilih cabang.', OptikAdminTokens.warning);
      return;
    }
    if (amount == null || amount <= 0) {
      _snack('Nominal harus > 0.', OptikAdminTokens.warning);
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
      _snack('Mutasi saldo tercatat.', OptikAdminTokens.success);
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
        title: const Text('Payroll & Saldo Owner'),
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
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _tokoId,
                      decoration: const InputDecoration(
                        labelText: 'Cabang',
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
                    const PremiumSectionHeader(label: 'Run payroll period'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _periode,
                      decoration: const InputDecoration(
                        labelText: 'Periode (YYYY-MM)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kunci period setelah run'),
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
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: OptikAdminTokens.snow,
                              ),
                            )
                          : const Text('Jalankan payroll'),
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
                    const PremiumSectionHeader(label: 'Post mutasi saldo'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _direction,
                      decoration: const InputDecoration(
                        labelText: 'Arah',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pusat_ke_toko',
                          child: Text('Pusat → Toko'),
                        ),
                        DropdownMenuItem(
                          value: 'toko_ke_pusat',
                          child: Text('Toko → Pusat'),
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
                      decoration: const InputDecoration(
                        labelText: 'Nominal (Rp)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _note,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
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
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: OptikAdminTokens.snow,
                              ),
                            )
                          : const Text('Post mutasi saldo'),
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
