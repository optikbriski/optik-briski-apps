import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/admin/admin_nav_badge_service.dart';
import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/payroll/payroll_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_nav_badge.dart';
import '../../shared/widgets/admin/admin_premium.dart';

class LemburInboxPage extends StatefulWidget {
  const LemburInboxPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<LemburInboxPage> createState() => _LemburInboxPageState();
}

class _LemburInboxPageState extends State<LemburInboxPage> {
  final _svc = PayrollService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  bool get _allToko => AttendanceAdminScope.canViewAllStores(widget.profile);

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
      final toko = AttendanceAdminScope.tokoOf(widget.profile);
      _rows = await _svc.listOvertimeDrafts(
        tokoId: toko,
        allToko: _allToko,
      );
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

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    unawaited(AdminNavBadgeService.instance.markEntitySeen('lembur', id));
    var rate = 0;
    try {
      final kid = row['karyawan_id']?.toString();
      if (kid != null && kid.isNotEmpty) {
        rate = await _svc.overtimeRateFor(kid);
      }
    } catch (_) {}
    if (!mounted) return;
    final rateCtrl = TextEditingController(text: rate > 0 ? '$rate' : '');
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        title: Text(
          approve ? 'ops_lembur_setuju'.tr() : 'ops_lembur_tolak'.tr(),
          style: TextStyle(color: OptikAdminTokens.navy),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (approve)
              TextField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'ops_lembur_rate'.tr(),
                ),
              ),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'ops_reimburse_catatan_admin'.tr(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('pengaduan_admin_batal'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'ops_lembur_setuju'.tr() : 'ops_lembur_tolak'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final parsedRate =
        int.tryParse(rateCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (approve && parsedRate <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ops_lembur_rate'.tr()),
          backgroundColor: OptikAdminTokens.danger,
        ),
      );
      return;
    }
    setState(() => _busyId = id);
    try {
      await _svc.decideOvertime(
        id: id,
        approve: approve,
        rateRp: parsedRate,
        note: noteCtrl.text,
      );
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
        final pending =
            AdminNavBadgeService.instance.displayCount('lembur');
        return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'ops_lembur_admin_title'.tr(),
        subtitle: pending > 0
            ? '${'ops_lembur_admin_sub'.tr()} · $pending menunggu'
            : 'ops_lembur_admin_sub'.tr(),
        actions: [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: AdminNavBadge(count: pending),
              ),
            ),
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? Center(child: Text('ops_lembur_admin_empty'.tr()))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final row = _rows[i];
                        final id = (row['id'] ?? '').toString();
                        final kary = row['karyawan'];
                        final nama =
                            kary is Map ? (kary['nama'] ?? '-').toString() : '-';
                        final meta = row['meta'];
                        final alasan = meta is Map
                            ? (meta['alasan'] ?? '').toString()
                            : '';
                        final busy = _busyId == id;
                        final unread = id.isNotEmpty &&
                            AdminNavBadgeService.instance
                                .isEntityUnread('lembur', id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onLongPress: id.isNotEmpty
                                ? () => unawaited(AdminNavBadgeService
                                    .instance
                                    .markEntityUnread('lembur', id))
                                : null,
                            child: PremiumPanel(
                            padding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            borderRadius: 20,
                            showAccentBar: true,
                            onTap: () => unawaited(AdminNavBadgeService
                                .instance
                                .markEntitySeen('lembur', id)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    AdminNavBadgeOverlay(
                                      count: unread ? 1 : 0,
                                      child: Icon(Icons.more_time_rounded,
                                          color: OptikAdminTokens.navy,
                                          size: 22),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        nama,
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
                                  '${row['toko_id'] ?? '-'} · ${row['tanggal'] ?? '-'} · ${row['jam']} jam',
                                  style: TextStyle(
                                    color: OptikAdminTokens.slate,
                                    fontSize: 12,
                                  ),
                                ),
                                if (alasan.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(alasan),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => _decide(row, false),
                                        child: Text('ops_lembur_tolak'.tr()),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: busy
                                            ? null
                                            : () => _decide(row, true),
                                        child: Text('ops_lembur_setuju'.tr()),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    ),
    );
      },
    );
  }
}
