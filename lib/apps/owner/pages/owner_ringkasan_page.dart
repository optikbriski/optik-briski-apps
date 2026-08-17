import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_session.dart';
import '../owner_ui.dart';

class OwnerRingkasanPage extends StatefulWidget {
  const OwnerRingkasanPage({super.key});

  @override
  State<OwnerRingkasanPage> createState() => _OwnerRingkasanPageState();
}

class _OwnerRingkasanPageState extends State<OwnerRingkasanPage> {
  final _svc = OwnerService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  String? _tokoFilter;

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
      final data = await _svc.ringkasan(
        tokoId: _tokoFilter,
        periodeYm: OwnerService.currentPeriodeYm(),
      );
      if (!mounted) return;
      setState(() {
        _data = data;
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

  num _n(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final session = OwnerSession.instance;
    final tokoIds = session.tokoIds;
    final periode = (_data?['periode_ym'] ?? OwnerService.currentPeriodeYm()).toString();
    final role = session.isUtama ? 'Owner Utama' : 'Owner Toko';

    return OwnerPageFrame(
      title: 'Ringkasan',
      subtitle: '${session.nama} · $role',
      onRefresh: _load,
      actions: [
        if (tokoIds.length > 1)
          PopupMenuButton<String?>(
            tooltip: 'Filter cabang',
            initialValue: _tokoFilter,
            onSelected: (v) {
              setState(() => _tokoFilter = v);
              _load();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Semua cabang')),
              ...tokoIds.map((t) => PopupMenuItem(value: t, child: Text(t))),
            ],
            child: Container(
              margin: const EdgeInsets.only(right: 8, top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OptikAdminTokens.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: const Icon(Icons.tune_rounded, size: 18, color: OptikAdminTokens.navy),
            ),
          ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy))
          : _error != null
              ? OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      decoration: OwnerUi.hero(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Periode $periode',
                                style: OwnerUi.label(color: OptikAdminTokens.ice),
                              ),
                              const Spacer(),
                              if (_tokoFilter != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _tokoFilter!,
                                    style: OwnerUi.label(color: OptikAdminTokens.snow),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Omzet',
                            style: OwnerUi.label(color: OptikAdminTokens.ice.withOpacity(0.9)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            OwnerService.formatRp(_data?['omzet']),
                            style: OwnerUi.display(34, color: OptikAdminTokens.snow),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.12)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _HeroMini(
                                    label: 'Laba bersih',
                                    value: OwnerService.formatRp(_data?['laba_bersih_est']),
                                    negative: _n(_data?['laba_bersih_est']) < 0,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 36,
                                  color: Colors.white.withOpacity(0.18),
                                ),
                                Expanded(
                                  child: _HeroMini(
                                    label: 'Invoice',
                                    value: '${_data?['invoice_count'] ?? 0}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const OwnerSectionLabel('Bagi hasil (estimasi)'),
                    Row(
                      children: [
                        Expanded(
                          child: _ShareTile(
                            label: 'Owner Utama',
                            value: _n(_data?['bagi_utama_est']),
                            pct: '50%',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ShareTile(
                            label: 'Owner Toko',
                            value: _n(_data?['bagi_toko_est']),
                            pct: '50%',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const OwnerSectionLabel('Beban periode'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      decoration: OwnerUi.panel(),
                      child: Column(
                        children: [
                          _ExpenseRow('HPP', _n(_data?['hpp'])),
                          _ExpenseRow('Opex', _n(_data?['opex'])),
                          _ExpenseRow('Gaji', _n(_data?['gaji']), last: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const OwnerSectionLabel('Tim'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: OwnerUi.panel(),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: OptikAdminTokens.accentSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.groups_rounded,
                              color: OptikAdminTokens.navy,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_data?['karyawan_aktif'] ?? 0} karyawan aktif',
                                  style: OwnerUi.body(
                                    color: OptikAdminTokens.navy,
                                    weight: FontWeight.w700,
                                    size: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pending: ${_data?['karyawan_pending'] ?? 0}',
                                  style: OwnerUi.label(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _HeroMini extends StatelessWidget {
  const _HeroMini({
    required this.label,
    required this.value,
    this.negative = false,
  });

  final String label;
  final String value;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: OwnerUi.label(color: OptikAdminTokens.ice.withOpacity(0.85))),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OwnerUi.display(
              18,
              color: negative ? const Color(0xFFFFB4B4) : OptikAdminTokens.snow,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({
    required this.label,
    required this.value,
    required this.pct,
  });

  final String label;
  final num value;
  final String pct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: OwnerUi.panel(elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: OwnerUi.label())),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: OptikAdminTokens.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(pct, style: OwnerUi.label(color: OptikAdminTokens.navy)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OwnerUi.moneyText(value, size: 20),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow(this.label, this.value, {this.last = false});
  final String label;
  final num value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: OptikAdminTokens.line)),
      ),
      child: Row(
        children: [
          Text(label, style: OwnerUi.body(weight: FontWeight.w600)),
          const Spacer(),
          Text(
            OwnerService.formatRp(value),
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
