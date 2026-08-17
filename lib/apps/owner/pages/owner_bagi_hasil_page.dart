import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_session.dart';
import '../owner_ui.dart';

class OwnerBagiHasilPage extends StatefulWidget {
  const OwnerBagiHasilPage({super.key});

  @override
  State<OwnerBagiHasilPage> createState() => _OwnerBagiHasilPageState();
}

class _OwnerBagiHasilPageState extends State<OwnerBagiHasilPage> {
  final _svc = OwnerService();
  bool _loading = true;
  bool _computing = false;
  String? _error;
  List<Map<String, dynamic>> _periods = [];
  String? _selectedToko;
  late String _periodeYm;

  @override
  void initState() {
    super.initState();
    _periodeYm = OwnerService.currentPeriodeYm();
    final ids = OwnerSession.instance.tokoIds;
    _selectedToko = ids.isEmpty ? null : ids.first;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _svc.listBagiHasil();
      if (!mounted) return;
      setState(() {
        _periods = rows;
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

  Future<void> _compute({bool lock = false}) async {
    final toko = _selectedToko;
    if (toko == null || toko.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cabang dulu.')),
      );
      return;
    }
    setState(() => _computing = true);
    try {
      final row = await _svc.computeBagiHasil(
        tokoId: toko,
        periodeYm: _periodeYm,
        lock: lock,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bagi hasil $toko $_periodeYm: '
            'bersih ${OwnerService.formatRp(row['laba_bersih'])} → '
            'Utama ${OwnerService.formatRp(row['bagi_owner_utama'])} / '
            'Toko ${OwnerService.formatRp(row['bagi_owner_toko'])}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _computing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokoIds = OwnerSession.instance.tokoIds;

    return OwnerPageFrame(
      title: 'Bagi hasil',
      subtitle: 'Omzet − beban = bersih → 50/50',
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: OwnerUi.panel(elevated: true),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hitung periode',
                  style: OwnerUi.body(
                    color: OptikAdminTokens.navy,
                    weight: FontWeight.w800,
                    size: 15,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedToko != null && tokoIds.contains(_selectedToko)
                      ? _selectedToko
                      : (tokoIds.isEmpty ? null : tokoIds.first),
                  decoration: InputDecoration(
                    labelText: 'Cabang',
                    filled: true,
                    fillColor: OptikAdminTokens.bgMid,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: OptikAdminTokens.line),
                    ),
                  ),
                  items: [
                    for (final t in tokoIds)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _selectedToko = v),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: _periodeYm,
                  decoration: InputDecoration(
                    labelText: 'Periode (YYYY-MM)',
                    filled: true,
                    fillColor: OptikAdminTokens.bgMid,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: (v) => _periodeYm = v.trim(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _computing ? null : () => _compute(),
                        style: FilledButton.styleFrom(
                          backgroundColor: OptikAdminTokens.navy,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _computing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: OptikAdminTokens.snow,
                                ),
                              )
                            : const Text('Hitung draft'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _computing ? null : () => _compute(lock: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OptikAdminTokens.navy,
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: OptikAdminTokens.navy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Kunci'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const OwnerSectionLabel('Riwayat periode'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy)),
            )
          else if (_error != null)
            OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
          else if (_periods.isEmpty)
            const OwnerEmptyState('Belum ada periode bagi hasil.')
          else
            for (final p in _periods)
              OwnerListCard(
                accent: (p['status'] ?? '') == 'locked'
                    ? OptikAdminTokens.success
                    : OptikAdminTokens.accentDeep,
                title: '${p['toko_id']} · ${p['periode_ym']}',
                subtitle:
                    'Status ${p['status']} · bersih ${OwnerService.formatRp(p['laba_bersih'])}\n'
                    'Utama ${OwnerService.formatRp(p['bagi_owner_utama'])} (${p['pct_owner_utama']}%) · '
                    'Toko ${OwnerService.formatRp(p['bagi_owner_toko'])} (${p['pct_owner_toko']}%)',
              ),
        ],
      ),
    );
  }
}
