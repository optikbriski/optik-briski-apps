import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/karyawan/reimburse_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_nav_badge.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/zoomable_network_image.dart';

class ReimburseInboxPage extends StatefulWidget {
  const ReimburseInboxPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<ReimburseInboxPage> createState() => _ReimburseInboxPageState();
}

class _ReimburseInboxPageState extends State<ReimburseInboxPage> {
  final _svc = ReimburseService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String? _busyId;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await _svc.listInbox(profile: widget.profile);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    final f = _statusFilter;
    if (f == null) return _rows;
    return _rows
        .where((r) => (r['status'] ?? 'OPEN').toString().toUpperCase() == f)
        .toList();
  }

  int _count(String status) => _rows
      .where((r) => (r['status'] ?? 'OPEN').toString().toUpperCase() == status)
      .length;

  String _label(String s) {
    switch (s) {
      case 'OPEN':
        return 'ops_reimburse_st_open'.tr();
      case 'APPROVED':
        return 'ops_reimburse_st_ok'.tr();
      case 'REJECTED':
        return 'ops_reimburse_st_tolak'.tr();
      default:
        return s;
    }
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    unawaited(AdminNavBadgeService.instance.markEntitySeen('reimburse', id));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text(
          approve ? 'ops_reimburse_setuju'.tr() : 'ops_reimburse_tolak'.tr(),
          style: TextStyle(color: OptikAdminTokens.navy),
        ),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: InputDecoration(labelText: 'ops_reimburse_catatan_admin'.tr()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('pengaduan_admin_batal'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'ops_reimburse_setuju'.tr() : 'ops_reimburse_tolak'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = id);
    try {
      await _svc.decide(id: id, approve: approve, note: note.text);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('admin_auto_564b2dc6f1'.tr(namedArgs: {'error': '$e'})), backgroundColor: OptikAdminTokens.danger),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminNavBadgeService.instance,
      builder: (context, _) {
        final visible = _visible;
        return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'ops_reimburse_admin_title'.tr(),
        subtitle: 'ops_reimburse_admin_sub'.tr(),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in <(String?, String)>[
                  (null, 'pengaduan_admin_filter_all'.tr()),
                  ('OPEN', _label('OPEN')),
                  ('APPROVED', _label('APPROVED')),
                  ('REJECTED', _label('REJECTED')),
                ])
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.$1 == null
                              ? '${e.$2} (${_rows.length})'
                              : e.$1 == 'OPEN'
                                  ? e.$2
                                  : '${e.$2} (${_count(e.$1!)})',
                        ),
                        if (e.$1 == 'OPEN') ...[
                          const SizedBox(width: 6),
                          AdminNavBadge(
                            count: AdminNavBadgeService.instance
                                .displayCount('reimburse'),
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    selected: _statusFilter == e.$1,
                    onSelected: (_) => setState(() => _statusFilter = e.$1),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : visible.isEmpty
                        ? Center(child: Text('ops_reimburse_admin_empty'.tr()))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: visible.length,
                            itemBuilder: (context, i) => _card(visible[i]),
                          ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final busy = _busyId == id;
    final st = (row['status'] ?? 'OPEN').toString().toUpperCase();
    final kary = row['karyawan'];
    final nama = kary is Map ? (kary['nama'] ?? '-').toString() : '-';
    final when = DateTime.tryParse('${row['created_at']}');
    final foto = (row['foto_url'] ?? '').toString().trim();
    final unread = st == 'OPEN' &&
        id.isNotEmpty &&
        AdminNavBadgeService.instance.isEntityUnread('reimburse', id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: st == 'OPEN' && id.isNotEmpty
            ? () => unawaited(AdminNavBadgeService.instance
                .markEntityUnread('reimburse', id))
            : null,
        child: PremiumPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          borderRadius: 20,
          showAccentBar: st == 'OPEN',
          onTap: st == 'OPEN'
              ? () => unawaited(
                  AdminNavBadgeService.instance.markEntitySeen('reimburse', id))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AdminNavBadgeOverlay(
                    count: unread ? 1 : 0,
                    child: Icon(Icons.receipt_long_rounded,
                        color: OptikAdminTokens.navy, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${row['kategori'] ?? '-'} · Rp ${row['jumlah_rp']}',
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Text(
              '$nama · ${row['toko_id'] ?? '-'} · ${_label(st)}'
              '${when == null ? '' : ' · ${DateFormat('d MMM HH:mm').format(when.toLocal())}'}',
              style: TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text('${row['catatan'] ?? ''}'),
            if (foto.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 140,
                child: ZoomableNetworkImagePane(url: foto, aspectRatio: 16 / 9),
              ),
            ],
            if (st == 'OPEN') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _decide(row, false),
                      child: Text('ops_reimburse_tolak'.tr()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => _decide(row, true),
                      child: Text('ops_reimburse_setuju'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}
