import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_ui.dart';

class OwnerCabangPage extends StatefulWidget {
  const OwnerCabangPage({super.key});

  @override
  State<OwnerCabangPage> createState() => _OwnerCabangPageState();
}

class _OwnerCabangPageState extends State<OwnerCabangPage> {
  final _svc = OwnerService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _ledger = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _svc.listCabang();
      final ledger = await _svc.listSaldoLedger(limit: 30);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _ledger = ledger;
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

  @override
  Widget build(BuildContext context) {
    return OwnerPageFrame(
      title: 'Cabang',
      subtitle: 'Scope kepemilikan & saldo pusat ↔ toko',
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy))
          : _error != null
              ? OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
              : _rows.isEmpty
                  ? const OwnerEmptyState('Belum ada cabang di scope Anda.')
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      children: [
                        for (final r in _rows) ...[
                          _CabangCard(row: r),
                          const SizedBox(height: 12),
                        ],
                        const OwnerSectionLabel('Mutasi saldo'),
                        if (_ledger.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: OwnerUi.panel(),
                            child: Text(
                              'Belum ada mutasi. Admin / Owner Utama dapat post saldo.',
                              style: OwnerUi.label(),
                            ),
                          )
                        else
                          for (final l in _ledger)
                            OwnerListCard(
                              accent: (l['direction'] ?? '') == 'pusat_ke_toko'
                                  ? OptikAdminTokens.success
                                  : OptikAdminTokens.warning,
                              title:
                                  '${(l['direction'] ?? '') == 'pusat_ke_toko' ? 'Pusat → Toko' : 'Toko → Pusat'} · ${OwnerService.formatRp(l['amount'])}',
                              subtitle:
                                  '${l['toko_id'] ?? '-'} · ${l['note'] ?? '-'}\n${l['created_at'] ?? ''}',
                            ),
                      ],
                    ),
    );
  }
}

class _CabangCard extends StatelessWidget {
  const _CabangCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final toko = (row['toko_id'] ?? '').toString();
    final nama = (row['nama'] ?? toko).toString();
    final primary = row['is_primary'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: OwnerUi.panel(elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: OptikAdminTokens.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  toko.isNotEmpty ? toko.substring(0, 1) : '?',
                  style: OwnerUi.body(
                    color: OptikAdminTokens.navy,
                    weight: FontWeight.w800,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nama,
                      style: OwnerUi.body(
                        color: OptikAdminTokens.navy,
                        weight: FontWeight.w800,
                        size: 15,
                      ),
                    ),
                    Text(toko, style: OwnerUi.label()),
                  ],
                ),
              ),
              if (primary)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.navy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Primary',
                    style: OwnerUi.label(color: OptikAdminTokens.snow),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SaldoChip(
                  label: 'Split',
                  value: '${row['pct_owner_utama']}% / ${row['pct_owner_toko']}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SaldoChip(
                  label: 'Pusat → Toko',
                  value: OwnerService.formatRp(row['saldo_pusat_ke_toko']),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SaldoChip(
                  label: 'Toko → Pusat',
                  value: OwnerService.formatRp(row['saldo_toko_ke_pusat']),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaldoChip extends StatelessWidget {
  const _SaldoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: OwnerUi.label()),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OwnerUi.body(
              color: OptikAdminTokens.navy,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
