import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../owner_service.dart';
import '../owner_ui.dart';

class OwnerTimPage extends StatefulWidget {
  const OwnerTimPage({super.key});

  @override
  State<OwnerTimPage> createState() => _OwnerTimPageState();
}

class _OwnerTimPageState extends State<OwnerTimPage> {
  final _svc = OwnerService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tim = [];
  Map<String, dynamic>? _payroll;
  List<Map<String, dynamic>> _payrollLines = [];
  String? _jabatanFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _maps(dynamic res) {
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tim = await _svc.listTim();
      final payroll = await _svc.payrollMonitor();
      if (!mounted) return;
      setState(() {
        _tim = tim;
        _payroll = payroll;
        _payrollLines = _maps(payroll['lines']);
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

  List<String> get _jabatans {
    final set = <String>{};
    for (final k in _tim) {
      final j = (k['jabatan'] ?? '').toString().trim();
      if (j.isNotEmpty) set.add(j);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> get _filtered {
    if (_jabatanFilter == null) return _tim;
    return _tim
        .where((k) => (k['jabatan'] ?? '').toString() == _jabatanFilter)
        .toList();
  }

  int get _aktifCount =>
      _tim.where((k) => (k['status_approval'] ?? '') == 'Aktif').length;

  int get _pendingCount => _tim
      .where((k) => (k['status_approval'] ?? '').toString().toLowerCase().contains('pending'))
      .length;

  @override
  Widget build(BuildContext context) {
    final status = (_payroll?['status'] ?? '-').toString();
    final periode = (_payroll?['periode_ym'] ?? '-').toString();
    final nett = _payroll?['total_nett'] ?? _payroll?['total_gaji_pokok'];
    final filtered = _filtered;

    return OwnerPageFrame(
      title: 'Tim',
      subtitle: '${_tim.length} orang · $_aktifCount aktif',
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.navy))
          : _error != null
              ? OwnerEmptyState(_error!, icon: Icons.error_outline_rounded)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    // KPI strip
                    Row(
                      children: [
                        Expanded(
                          child: _MiniKpi(
                            label: 'Payroll',
                            value: OwnerService.formatRp(nett is num ? nett : 0),
                            hint: '$periode · $status',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniKpi(
                            label: 'Pending',
                            value: '$_pendingCount',
                            hint: 'menunggu approve',
                            emphasize: _pendingCount > 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Jabatan chips
                    if (_jabatans.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Semua',
                              selected: _jabatanFilter == null,
                              onTap: () => setState(() => _jabatanFilter = null),
                            ),
                            for (final j in _jabatans) ...[
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: j,
                                selected: _jabatanFilter == j,
                                onTap: () => setState(() => _jabatanFilter = j),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_payrollLines.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const OwnerSectionLabel('Slip periode ini'),
                      Container(
                        decoration: OwnerUi.panel(),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < _payrollLines.length; i++) ...[
                              _DensePayRow(line: _payrollLines[i]),
                              if (i < _payrollLines.length - 1)
                                const Divider(height: 1, color: OptikAdminTokens.line),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    OwnerSectionLabel(
                      _jabatanFilter == null
                          ? 'Karyawan (${filtered.length})'
                          : '$_jabatanFilter (${filtered.length})',
                    ),
                    if (filtered.isEmpty)
                      const OwnerEmptyState('Tidak ada karyawan di filter ini.')
                    else
                      Container(
                        decoration: OwnerUi.panel(elevated: true),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < filtered.length; i++) ...[
                              _DenseStaffRow(row: filtered[i]),
                              if (i < filtered.length - 1)
                                const Divider(height: 1, color: OptikAdminTokens.line),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({
    required this.label,
    required this.value,
    required this.hint,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String hint;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: emphasize
            ? LinearGradient(
                colors: [
                  OptikAdminTokens.warning.withOpacity(0.12),
                  OptikAdminTokens.panel,
                ],
              )
            : OptikAdminTokens.cardSheen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasize
              ? OptikAdminTokens.warning.withOpacity(0.35)
              : OptikAdminTokens.line,
        ),
        boxShadow: OptikAdminTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: OwnerUi.label()),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OwnerUi.display(18),
          ),
          const SizedBox(height: 4),
          Text(hint, style: OwnerUi.label()),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? OptikAdminTokens.navy : OptikAdminTokens.panel,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? OptikAdminTokens.navy : OptikAdminTokens.line,
            ),
          ),
          child: Text(
            label,
            style: OwnerUi.label(
              color: selected ? OptikAdminTokens.snow : OptikAdminTokens.navy,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _DenseStaffRow extends StatelessWidget {
  const _DenseStaffRow({required this.row});
  final Map<String, dynamic> row;

  String get _initials {
    final n = (row['nama'] ?? '?').toString().trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Color get _statusColor {
    final s = (row['status_approval'] ?? '').toString();
    if (s == 'Aktif') return OptikAdminTokens.success;
    if (s.toLowerCase().contains('tolak')) return OptikAdminTokens.danger;
    return OptikAdminTokens.warning;
  }

  @override
  Widget build(BuildContext context) {
    final status = (row['status_approval'] ?? '-').toString();
    final jabatan = (row['jabatan'] ?? '-').toString();
    final gaji = OwnerService.formatRp(row['gaji_pokok']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: OptikAdminTokens.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _initials,
              style: OwnerUi.body(
                color: OptikAdminTokens.navy,
                weight: FontWeight.w800,
                size: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row['nama'] ?? '-').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OwnerUi.body(
                    color: OptikAdminTokens.navy,
                    weight: FontWeight.w700,
                    size: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  jabatan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OwnerUi.label(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                gaji,
                style: OwnerUi.body(
                  color: OptikAdminTokens.navy,
                  weight: FontWeight.w800,
                  size: 13,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: OwnerUi.label(color: _statusColor).copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DensePayRow extends StatelessWidget {
  const _DensePayRow({required this.line});
  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (line['nama'] ?? '-').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OwnerUi.body(
                color: OptikAdminTokens.navy,
                weight: FontWeight.w700,
                size: 13,
              ),
            ),
          ),
          Text(
            OwnerService.formatRp(line['nett'] ?? line['gaji_pokok']),
            style: OwnerUi.body(
              color: OptikAdminTokens.navy,
              weight: FontWeight.w800,
              size: 13,
            ),
          ),
        ],
      ),
    );
  }
}
