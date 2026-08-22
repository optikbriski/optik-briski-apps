import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/attendance/attendance_verification_config.dart';
import '../../shared/attendance/attendance_verification_service.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/zoomable_network_image.dart';
import 'tinjauan_mencurigakan_page.dart';

/// Monitor Absensi (owner / admin_pusat): toko → karyawan hari ini → detail Valid/Mencurigakan.
/// admin_pusat: cabang saja (tanpa PUSAT / CABANG-PUSAT). Owner: semua termasuk Pusat.
class AttendanceMonitorPage extends StatefulWidget {
  const AttendanceMonitorPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<AttendanceMonitorPage> createState() => _AttendanceMonitorPageState();
}

enum _MonitorLevel { tokoList, karyawanList, detail }

class _AttendanceMonitorPageState extends State<AttendanceMonitorPage> {
  final _svc = AttendanceVerificationService();
  final _dayFmt = DateFormat('d MMM yyyy', 'id_ID');
  final _timeFmt = DateFormat('HH:mm', 'id_ID');
  final _dateTimeFmt = DateFormat('d MMM yyyy HH:mm', 'id_ID');

  _MonitorLevel _level = _MonitorLevel.tokoList;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  DateTime _day = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  List<String> _tokoOptions = [];
  Map<String, int> _tokoCounts = {};
  String? _selectedToko;
  List<Map<String, dynamic>> _karyawanRows = [];
  Map<String, dynamic>? _selectedRow;

  String? get _tenantId =>
      AttendanceAdminScope.tenantIdOf(widget.profile);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await Supabase.instance.client.from('toko_id').select('id').order('id');
      final all = [
        for (final r in rows) r['id']?.toString() ?? '',
      ].where((e) => e.isNotEmpty).toList();
      _tokoOptions =
          AttendanceAdminScope.filterTokoForMonitor(all, widget.profile);
      if (_tokoOptions.length == 1) {
        await _loadKaryawanForToko(_tokoOptions.first);
        return;
      }
      await _loadTokoCounts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  DateTime get _dayStart => _day;
  DateTime get _dayEnd =>
      DateTime(_day.year, _day.month, _day.day, 23, 59, 59, 999);

  Future<void> _loadTokoCounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tokoOptions.isEmpty) {
        if (!mounted) return;
        setState(() {
          _tokoCounts = {};
          _loading = false;
        });
        return;
      }
      final rows = await _svc.listByStatus(
        statuses: const [
          AttendanceVerificationStatus.pendingReview,
          AttendanceVerificationStatus.aman,
          AttendanceVerificationStatus.mencurigakan,
          AttendanceVerificationStatus.curang,
        ],
        tokoIds: _tokoOptions,
        tenantId: _tenantId,
        dayStart: _dayStart,
        dayEnd: _dayEnd,
        limit: 500,
      );
      final filtered =
          AttendanceAdminScope.filterVerificationRows(rows, widget.profile);
      final counts = <String, int>{};
      for (final r in filtered) {
        final t = (r['toko_id'] ?? '').toString();
        if (t.isEmpty) continue;
        counts[t] = (counts[t] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _tokoCounts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadKaryawanForToko(String tokoId) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedToko = tokoId;
      _level = _MonitorLevel.karyawanList;
      _selectedRow = null;
    });
    try {
      if (!AttendanceAdminScope.canAccessTokoAttendance(
          widget.profile, tokoId)) {
        throw 'Tidak berhak melihat absensi toko ini.';
      }
      final rows = await _svc.listByStatus(
        statuses: const [
          AttendanceVerificationStatus.pendingReview,
          AttendanceVerificationStatus.aman,
          AttendanceVerificationStatus.mencurigakan,
          AttendanceVerificationStatus.curang,
        ],
        tokoId: tokoId,
        tenantId: _tenantId,
        dayStart: _dayStart,
        dayEnd: _dayEnd,
        limit: 200,
      );
      final filtered =
          AttendanceAdminScope.filterVerificationRows(rows, widget.profile);
      if (!mounted) return;
      setState(() {
        _karyawanRows = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _day = DateTime(picked.year, picked.month, picked.day);
      _selectedRow = null;
      if (_level == _MonitorLevel.detail) {
        _level = _MonitorLevel.karyawanList;
      }
    });
    if (_level == _MonitorLevel.karyawanList && _selectedToko != null) {
      await _loadKaryawanForToko(_selectedToko!);
    } else {
      await _loadTokoCounts();
    }
  }

  void _back() {
    if (_level == _MonitorLevel.detail) {
      setState(() {
        _level = _MonitorLevel.karyawanList;
        _selectedRow = null;
      });
      return;
    }
    if (_level == _MonitorLevel.karyawanList) {
      setState(() {
        _level = _MonitorLevel.tokoList;
        _selectedToko = null;
        _karyawanRows = [];
        _selectedRow = null;
      });
      _loadTokoCounts();
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _markValid() async {
    final row = _selectedRow;
    if (row == null || _acting) return;
    if (row['status'] != AttendanceVerificationStatus.pendingReview) return;
    if (!AttendanceAdminScope.canAccessTokoAttendance(
        widget.profile,
        row['toko_id']?.toString(),
        rowTenantId: row['tenant_id']?.toString(),
      )) {
      _snack('Tidak berhak menilai absensi toko ini.', OptikAdminTokens.danger);
      return;
    }
    final ok = await _confirm(
      title: 'Tandai Valid?',
      body:
          'Wajah disetujui. Poin baru dihitung sekarang:\n'
          '• Ontime → +${AttendanceVerificationConfig.validDayPoints}\n'
          '• Telat → hanya penalti telat (tanpa poin ontime)\n\n'
          'Sebelum Valid, belum ada poin absensi.',
      confirmLabel: 'Valid',
      danger: false,
    );
    if (!ok) return;
    setState(() => _acting = true);
    try {
      await _svc.markAman(
        verificationId: row['id'].toString(),
        karyawanId: row['karyawan_id'].toString(),
        tokoId: (row['toko_id'] ?? '').toString(),
        tenantId: _tenantId,
        notes: 'Valid — cocok dengan foto terdaftar',
      );
      if (!mounted) return;
      _snack(
        'Ditandai aman. Poin absensi sudah diproses (ontime atau telat).',
        OptikAdminTokens.success,
      );
      await _loadKaryawanForToko(_selectedToko!);
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _markMencurigakan() async {
    final row = _selectedRow;
    if (row == null || _acting) return;
    if (row['status'] != AttendanceVerificationStatus.pendingReview) return;
    if (!AttendanceAdminScope.canAccessTokoAttendance(
        widget.profile,
        row['toko_id']?.toString(),
        rowTenantId: row['tenant_id']?.toString(),
      )) {
      _snack('Tidak berhak menilai absensi toko ini.', OptikAdminTokens.danger);
      return;
    }
    final ok = await _confirm(
      title: 'Tandai Mencurigakan?',
      body:
          'Masuk ke antrean Tinjauan Mencurigakan untuk keputusan lanjut.\n'
          'Belum ada potongan poin / SP pada langkah ini.',
      confirmLabel: 'Mencurigakan',
      danger: true,
    );
    if (!ok) return;
    setState(() => _acting = true);
    try {
      await _svc.markMencurigakan(
        verificationId: row['id'].toString(),
        tokoId: (row['toko_id'] ?? '').toString(),
        tenantId: _tenantId,
        notes: 'Perlu tinjauan lanjut',
      );
      if (!mounted) return;
      _snack('Masuk antrean tinjauan mencurigakan.', OptikAdminTokens.warning);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TinjauanMencurigakanPage(profile: widget.profile),
        ),
      );
      if (!mounted) return;
      await _loadKaryawanForToko(_selectedToko!);
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    required bool danger,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: Text(title,
            style: const TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
            )),
        content: Text(body,
            style: const TextStyle(
              color: OptikAdminTokens.slate,
              height: 1.4,
            )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: OptikAdminTokens.slate),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  danger ? OptikAdminTokens.danger : OptikAdminTokens.success,
              foregroundColor: OptikAdminTokens.snow,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: const TextStyle(
            color: OptikAdminTokens.snow,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (_level) {
      case _MonitorLevel.tokoList:
        return 'appr_monitor_absensi'.tr();
      case _MonitorLevel.karyawanList:
        return _selectedToko ?? 'appr_monitor_absensi'.tr();
      case _MonitorLevel.detail:
        return _svc.namaOf(_selectedRow ?? const {});
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case AttendanceVerificationStatus.pendingReview:
        return 'Menunggu';
      case AttendanceVerificationStatus.aman:
        return 'Valid / Aman';
      case AttendanceVerificationStatus.mencurigakan:
        return 'Mencurigakan';
      case AttendanceVerificationStatus.curang:
        return 'Curang';
      default:
        return status ?? '-';
    }
  }

  /// Warna aksen status (wash chip / border).
  Color _statusColor(String? status) {
    switch (status) {
      case AttendanceVerificationStatus.pendingReview:
        return OptikAdminTokens.ice;
      case AttendanceVerificationStatus.aman:
        return OptikAdminTokens.success;
      case AttendanceVerificationStatus.mencurigakan:
        return OptikAdminTokens.warning;
      case AttendanceVerificationStatus.curang:
        return OptikAdminTokens.danger;
      default:
        return OptikAdminTokens.slate;
    }
  }

  /// Teks status di permukaan terang — ice terlalu muda, pakai navy.
  Color _statusFg(String? status) {
    if (status == AttendanceVerificationStatus.pendingReview) {
      return OptikAdminTokens.navy;
    }
    return _statusColor(status);
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: _title,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: OptikAdminTokens.navy),
          onPressed: _back,
        ),
        actions: [
          IconButton(
            tooltip: 'Pilih tanggal',
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_today_rounded,
                color: OptikAdminTokens.navy),
          ),
          IconButton(
            tooltip: 'dash_menu_tinjauan_mencurigakan'.tr(),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TinjauanMencurigakanPage(profile: widget.profile),
              ),
            ).then((_) {
              if (_level == _MonitorLevel.karyawanList &&
                  _selectedToko != null) {
                return _loadKaryawanForToko(_selectedToko!);
              }
              return _loadTokoCounts();
            }),
            icon: const Icon(Icons.warning_amber_rounded,
                color: OptikAdminTokens.warning),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              if (_level == _MonitorLevel.karyawanList &&
                  _selectedToko != null) {
                _loadKaryawanForToko(_selectedToko!);
              } else if (_level == _MonitorLevel.detail &&
                  _selectedToko != null) {
                _loadKaryawanForToko(_selectedToko!);
              } else {
                _loadTokoCounts();
              }
            },
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: PremiumPanel(
              padding: const EdgeInsets.all(12),
              borderRadius: 14,
              child: Text(
                'Hari ${_dayFmt.format(_day)} · '
                    '${AttendanceAdminScope.monitorBannerHint(widget.profile)}',
                style: const TextStyle(
                  color: OptikAdminTokens.slate,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: const TextStyle(color: OptikAdminTokens.danger)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.ice))
                : switch (_level) {
                    _MonitorLevel.tokoList => _buildTokoList(),
                    _MonitorLevel.karyawanList => _buildKaryawanList(),
                    _MonitorLevel.detail => _buildDetail(),
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildTokoList() {
    if (_tokoOptions.isEmpty) {
      return const PremiumEmptyState(
        message: 'Tidak ada toko untuk dipantau.',
        icon: Icons.store_outlined,
      );
    }
    return RefreshIndicator(
      color: OptikAdminTokens.ice,
      onRefresh: _loadTokoCounts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tokoOptions.length,
        itemBuilder: (context, i) {
          final toko = _tokoOptions[i];
          final count = _tokoCounts[toko] ?? 0;
          final isPusat = AttendanceAdminScope.isPusatTokoId(toko);
          return PremiumPanel(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            borderRadius: 14,
            onTap: () => _loadKaryawanForToko(toko),
            child: Row(
              children: [
                Icon(
                  isPusat ? Icons.apartment_rounded : Icons.storefront_rounded,
                  color: OptikAdminTokens.navy,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        toko,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        count == 0
                            ? 'Belum ada absen masuk hari ini'
                            : '$count karyawan sudah absen masuk',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: OptikAdminTokens.ice.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: OptikAdminTokens.slate),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKaryawanList() {
    if (_karyawanRows.isEmpty) {
      return PremiumEmptyState(
        message:
            'Belum ada karyawan absen masuk di ${_selectedToko ?? '-'} pada ${_dayFmt.format(_day)}.',
        icon: Icons.person_off_outlined,
      );
    }
    return RefreshIndicator(
      color: OptikAdminTokens.ice,
      onRefresh: () => _loadKaryawanForToko(_selectedToko!),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _karyawanRows.length,
        itemBuilder: (context, i) {
          final r = _karyawanRows[i];
          final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
          final status = r['status']?.toString();
          return PremiumPanel(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: 14,
            onTap: () => setState(() {
              _selectedRow = r;
              _level = _MonitorLevel.detail;
            }),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _thumb(r['capture_photo_url']?.toString(), 48),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _svc.namaOf(r),
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _svc.jabatanOf(r).isNotEmpty
                            ? _svc.jabatanOf(r)
                            : 'Karyawan',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Masuk ${at != null ? _timeFmt.format(at.toLocal()) : '-'}',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusFg(status),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: OptikAdminTokens.slate),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetail() {
    final r = _selectedRow;
    if (r == null) {
      return const PremiumEmptyState(
        message: 'Pilih karyawan untuk melihat detail.',
        icon: Icons.compare_rounded,
      );
    }
    final capture = (r['capture_photo_url'] ?? '').toString();
    final enrolled = _svc.enrolledUrlOf(r);
    final score = r['match_score'];
    final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
    final status = r['status']?.toString();
    final pending = status == AttendanceVerificationStatus.pendingReview;
    final mencurigakan = status == AttendanceVerificationStatus.mencurigakan;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _svc.namaOf(r),
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${r['toko_id'] ?? '-'}'
          '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}',
          style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Jam detect/masuk: ${at != null ? _dateTimeFmt.format(at.toLocal()) : '-'}',
          style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'Status: ${_statusLabel(status)}'
          ' · Skor match: ${score ?? '-'}'
          ' · Liveness: ${r['liveness_ok'] == true ? 'OK' : '-'}',
          style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 560;
            final left = _photoPane(
              label: 'Capture absen (hari ini)',
              subtitle: 'Foto liveness saat masuk (tinjauan Admin)',
              url: capture,
              accent: OptikAdminTokens.navy,
            );
            final right = _photoPane(
              label: 'Foto terdaftar',
              subtitle: 'face_photo_url / enroll karyawan',
              url: enrolled,
              accent: OptikAdminTokens.success,
            );
            if (stacked) {
              return Column(
                  children: [left, const SizedBox(height: 12), right]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 12),
                Expanded(child: right),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (pending)
          Row(
            children: [
              Expanded(
                child: PremiumPrimaryButton(
                  label: 'Valid',
                  icon: Icons.verified_rounded,
                  loading: _acting,
                  onPressed: _acting ? null : _markValid,
                  gradient: const LinearGradient(
                    colors: [OptikAdminTokens.success, OptikAdminTokens.success],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PremiumPrimaryButton(
                  label: 'Mencurigakan',
                  icon: Icons.warning_amber_rounded,
                  loading: _acting,
                  onPressed: _acting ? null : _markMencurigakan,
                  gradient: const LinearGradient(
                    colors: [OptikAdminTokens.warning, OptikAdminTokens.warning],
                  ),
                ),
              ),
            ],
          )
        else if (mencurigakan)
          PremiumPrimaryButton(
            label: 'Buka Tinjauan Mencurigakan',
            icon: Icons.warning_amber_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TinjauanMencurigakanPage(profile: widget.profile),
              ),
            ).then((_) {
              if (_selectedToko != null) {
                return _loadKaryawanForToko(_selectedToko!);
              }
            }),
            gradient: const LinearGradient(
              colors: [OptikAdminTokens.warning, OptikAdminTokens.warning],
            ),
          )
        else
          PremiumPanel(
            padding: const EdgeInsets.all(14),
            borderRadius: 14,
            borderColor: _statusColor(status).withOpacity(0.4),
            child: Text(
              'Sudah dinilai: ${_statusLabel(status)}',
              style: TextStyle(
                color: _statusFg(status),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _photoPane({
    required String label,
    required String subtitle,
    required String url,
    required Color accent,
  }) {
    return PremiumPanel(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      borderColor: accent.withOpacity(0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 11),
          ),
          const SizedBox(height: 10),
          ZoomableNetworkImagePane(url: url),
        ],
      ),
    );
  }

  Widget _thumb(String? url, double size) {
    if (url == null || url.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        color: OptikAdminTokens.bgMid,
        child: const Icon(Icons.person, color: OptikAdminTokens.slate, size: 22),
      );
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: OptikAdminTokens.bgMid,
        child: const Icon(Icons.broken_image, color: OptikAdminTokens.slate, size: 18),
      ),
    );
  }
}
