import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/karyawan/jadwal_pengajuan_service.dart';
import '../../shared/responsive.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Admin Pusat: approval ijin / cuti / tukar — dikelompok per toko
/// (hanya toko yang punya pengajuan pending).
class JadwalPengajuanApprovalPage extends StatefulWidget {
  const JadwalPengajuanApprovalPage({
    super.key,
    required this.profile,
    this.initialTokoId,
  });

  final Map<String, dynamic> profile;
  final String? initialTokoId;

  @override
  State<JadwalPengajuanApprovalPage> createState() =>
      _JadwalPengajuanApprovalPageState();
}

class _JadwalPengajuanApprovalPageState
    extends State<JadwalPengajuanApprovalPage> {
  final _svc = JadwalPengajuanService();
  final _dayFmt = DateFormat('EEE, d MMM yyyy', 'id_ID');

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  /// tokoId → daftar pengajuan pending
  Map<String, List<Map<String, dynamic>>> _byToko = {};

  bool get _isPusat =>
      AttendanceAdminScope.canViewAllStores(widget.profile);

  String get _scopeToko =>
      widget.initialTokoId ?? widget.profile['toko_id']?.toString() ?? '';

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
      // Admin pusat: lihat semua cabang yang ada pengajuan.
      // Admin cabang / filter cabang: hanya toko itu.
      final allPusat = _isPusat &&
          (widget.initialTokoId == null || widget.initialTokoId!.isEmpty);
      _items = await _svc.listPending(
        tokoId: _scopeToko,
        allToko: allPusat,
      );
      if (!allPusat &&
          widget.initialTokoId != null &&
          widget.initialTokoId!.isNotEmpty) {
        _items = _items
            .where((e) => e['toko_id']?.toString() == widget.initialTokoId)
            .toList();
      }
      _byToko = _groupByToko(_items);
    } catch (e) {
      _error = '$e';
      _byToko = {};
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByToko(
      List<Map<String, dynamic>> items) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final toko = (item['toko_id'] ?? 'TANPA-TOKO').toString();
      map.putIfAbsent(toko, () => []).add(item);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in keys) k: map[k]!};
  }

  String _tipeLabel(String? t) {
    switch ((t ?? '').toUpperCase()) {
      case 'IJIN':
        return 'Ijin';
      case 'CUTI':
        return 'Cuti';
      case 'TUKAR':
        return 'Tukar';
      default:
        return t ?? '-';
    }
  }

  Color _tipeColor(String? t) {
    switch ((t ?? '').toUpperCase()) {
      case 'IJIN':
        return OptikAdminTokens.warning;
      case 'CUTI':
        return OptikAdminTokens.slate;
      case 'TUKAR':
        return OptikAdminTokens.navy;
      default:
        return OptikAdminTokens.slate;
    }
  }

  String _nama(dynamic nested, [String fallback = '-']) {
    if (nested is Map) return nested['nama']?.toString() ?? fallback;
    return fallback;
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '-';
    final s = v.toString();
    final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
    return d == null ? s : _dayFmt.format(d);
  }

  String _dateKey(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// Hari yang punya ≥2 ijin/cuti di toko yang sama (peringatan bentrok).
  List<String> _clashDays(List<Map<String, dynamic>> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      final tipe = (r['tipe'] ?? '').toString().toUpperCase();
      if (tipe != 'IJIN' && tipe != 'CUTI') continue;
      final key = _dateKey(r['tanggal']);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries
        .where((e) => e.value >= 2)
        .map((e) => e.key)
        .toList()
      ..sort();
  }

  Future<void> _decide(Map<String, dynamic> item, bool approve) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: Text(
          approve ? 'Setujui pengajuan?' : 'Tolak pengajuan?',
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: R.constrainedDialog(
          context: context,
          preferWidth: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approve
                    ? 'Jadwal akan langsung diubah sesuai pengajuan.'
                    : 'Pengajuan akan ditolak tanpa mengubah jadwal.',
                style: const TextStyle(
                  color: OptikAdminTokens.slate,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: OptikAdminTokens.navy),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Catatan admin (opsional)',
                  labelStyle: const TextStyle(color: OptikAdminTokens.slate),
                  filled: true,
                  fillColor: OptikAdminTokens.bgMid,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(OptikAdminTokens.radiusSm),
                    borderSide:
                        const BorderSide(color: OptikAdminTokens.lineStrong),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(OptikAdminTokens.radiusSm),
                    borderSide:
                        const BorderSide(color: OptikAdminTokens.lineStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(OptikAdminTokens.radiusSm),
                    borderSide: const BorderSide(
                      color: OptikAdminTokens.navy,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: OptikAdminTokens.slate),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  approve ? OptikAdminTokens.navy : OptikAdminTokens.danger,
              foregroundColor: OptikAdminTokens.snow,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Setujui' : 'Tolak'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _svc.decide(
        id: item['id'].toString(),
        approve: approve,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              approve ? OptikAdminTokens.success : OptikAdminTokens.warning,
          content: Text(
            approve ? 'Pengajuan disetujui.' : 'Pengajuan ditolak.',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.danger,
          content: Text(
            'Gagal: $e\nPastikan migration jadwal_pengajuan sudah dijalankan.',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
  }

  void _showDetail(Map<String, dynamic> item,
      {required List<Map<String, dynamic>> siblings}) {
    final tipe = item['tipe']?.toString();
    final color = _tipeColor(tipe);
    final nama = _nama(item['karyawan']);
    final partner = _nama(item['partner'], '');
    final jabatan = item['karyawan'] is Map
        ? item['karyawan']['jabatan']?.toString()
        : null;
    final myDay = _dateKey(item['tanggal']);
    final sameDayCount = siblings.where((s) {
      final t = (s['tipe'] ?? '').toString().toUpperCase();
      return (t == 'IJIN' || t == 'CUTI') && _dateKey(s['tanggal']) == myDay;
    }).length;
    final bentrok =
        (tipe == 'IJIN' || tipe == 'CUTI') && sameDayCount >= 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: OptikAdminTokens.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.lineStrong,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _tipeLabel(tipe),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['toko_id']?.toString() ?? '-',
                          style: const TextStyle(
                              color: OptikAdminTokens.slate, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(nama,
                      style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  if (jabatan != null && jabatan.isNotEmpty)
                    Text(jabatan,
                        style: const TextStyle(
                            color: OptikAdminTokens.slate, fontSize: 13)),
                  const SizedBox(height: 14),
                  _detailRow('Tanggal', _fmtDate(item['tanggal'])),
                  if ((tipe ?? '').toUpperCase() == 'TUKAR') ...[
                    _detailRow(
                        'Tukar dengan', partner.isEmpty ? '-' : partner),
                    _detailRow(
                        'Hari partner', _fmtDate(item['tanggal_tukar'])),
                  ],
                  const SizedBox(height: 8),
                  const Text('Alasan',
                      style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    item['alasan']?.toString() ?? '-',
                    style: const TextStyle(
                        color: OptikAdminTokens.slate, fontSize: 14, height: 1.4),
                  ),
                  if (bentrok) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: OptikAdminTokens.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: OptikAdminTokens.warning.withOpacity(0.4)),
                      ),
                      child: Text(
                        'Peringatan: ada $sameDayCount pengajuan ijin/cuti '
                        'di cabang ini untuk hari yang sama. '
                        'Pertimbangkan agar tidak terlalu banyak yang kosong barengan.',
                        style: const TextStyle(
                            color: OptikAdminTokens.warning,
                            fontSize: 12,
                            height: 1.35),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _decide(item, false);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: OptikAdminTokens.danger,
                            side: const BorderSide(color: OptikAdminTokens.danger),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Tolak'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _decide(item, true);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: OptikAdminTokens.navy,
                            foregroundColor: OptikAdminTokens.snow,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Setujui'),
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
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: OptikAdminTokens.navy, fontSize: 13, height: 1.3)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokoKeys = _byToko.keys.toList();
    final totalPending =
        _byToko.values.fold<int>(0, (sum, rows) => sum + rows.length);
    final clashTokoCount = tokoKeys
        .where((toko) => _clashDays(_byToko[toko]!).isNotEmpty)
        .length;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: widget.initialTokoId == null || widget.initialTokoId!.isEmpty
            ? 'Approval Jadwal'
            : 'Approval — ${widget.initialTokoId}',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: OptikAdminTokens.danger),
                        ),
                        const SizedBox(height: 12),
                        PremiumPrimaryButton(
                          label: 'Coba lagi',
                          onPressed: _load,
                          expand: false,
                        ),
                      ],
                    ),
                  ),
                )
              : tokoKeys.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Tidak ada pengajuan menunggu.\n'
                          'Toko hanya muncul di sini jika ada anak toko yang mengajukan dari APK Karyawan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: OptikAdminTokens.slate, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: tokoKeys.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return PremiumStatGrid(
                            padding: const EdgeInsets.only(bottom: 12),
                            items: [
                              PremiumStatItem(
                                label: 'Pengajuan',
                                value: '$totalPending',
                                color: OptikAdminTokens.slate,
                              ),
                              PremiumStatItem(
                                label: 'Cabang',
                                value: '${tokoKeys.length}',
                                color: OptikAdminTokens.navy,
                              ),
                              PremiumStatItem(
                                label: 'Bentrok hari',
                                value: '$clashTokoCount',
                                color: clashTokoCount > 0
                                    ? OptikAdminTokens.warning
                                    : OptikAdminTokens.slate,
                              ),
                            ],
                          );
                        }
                        if (index == 1) {
                          return const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: Text(
                              'Dikelompok per cabang yang ada pengajuan. '
                              'Cek dulu kalau beberapa orang ijin di hari yang sama.',
                              style: TextStyle(
                                  color: OptikAdminTokens.slate,
                                  fontSize: 12,
                                  height: 1.35),
                            ),
                          );
                        }
                        final toko = tokoKeys[index - 2];
                        final rows = _byToko[toko]!;
                        final clash = _clashDays(rows);
                        return _tokoSection(toko, rows, clash);
                      },
                    ),
    );
  }

  Widget _tokoSection(
    String toko,
    List<Map<String, dynamic>> rows,
    List<String> clashDays,
  ) {
    return PremiumPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      borderRadius: 14,
      borderColor: clashDays.isNotEmpty
          ? OptikAdminTokens.warning.withOpacity(0.45)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: OptikAdminTokens.navy.withOpacity(0.1),
                  child: const Icon(Icons.storefront_rounded,
                      color: OptikAdminTokens.navy, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        toko,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${rows.length} pengajuan menunggu',
                        style: const TextStyle(
                            color: OptikAdminTokens.slate, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (clashDays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: OptikAdminTokens.warning.withOpacity(0.12),
                  borderRadius:
                      BorderRadius.circular(OptikAdminTokens.radiusSm),
                  border: Border.all(
                    color: OptikAdminTokens.warning.withOpacity(0.4),
                  ),
                ),
                child: Text(
                  '${clashDays.length} hari punya ≥2 ijin/cuti barengan — '
                  'cek sebelum setujui semua.',
                  style: const TextStyle(
                    color: OptikAdminTokens.warning,
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const Divider(height: 1, color: OptikAdminTokens.line),
          ...rows.map((item) {
            final tipe = item['tipe']?.toString();
            final color = _tipeColor(tipe);
            final nama = _nama(item['karyawan']);
            final dayKey = _dateKey(item['tanggal']);
            final bentrok = (tipe == 'IJIN' || tipe == 'CUTI') &&
                clashDays.contains(dayKey);

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              title: Text(
                nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: OptikAdminTokens.navy, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${_tipeLabel(tipe)} • ${_fmtDate(item['tanggal'])}'
                '${bentrok ? ' • bentrok?' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bentrok ? OptikAdminTokens.warning : OptikAdminTokens.slate,
                  fontSize: 11,
                ),
              ),
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              trailing: TextButton(
                onPressed: () => _showDetail(item, siblings: rows),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.navy,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Detail',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              onTap: () => _showDetail(item, siblings: rows),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
