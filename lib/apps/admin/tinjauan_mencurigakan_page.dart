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

/// Admin: tinjauan lanjut hasil yang di-flag mencurigakan.
/// Aman = poin + status aman. Curang = -200 poin + SP1 (bukan keterlambatan).
/// admin_pusat: cabang saja (tanpa Pusat). Owner: termasuk Pusat.
class TinjauanMencurigakanPage extends StatefulWidget {
  const TinjauanMencurigakanPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<TinjauanMencurigakanPage> createState() =>
      _TinjauanMencurigakanPageState();
}

class _TinjauanMencurigakanPageState extends State<TinjauanMencurigakanPage> {
  final _svc = AttendanceVerificationService();
  final _dayFmt = DateFormat('d MMM yyyy HH:mm', 'id_ID');

  bool _loading = true;
  bool _acting = false;
  String? _error;
  String? _tokoFilter;
  List<String> _tokoOptions = [];
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _selected;

  bool get _canMonitor =>
      AttendanceAdminScope.canOpenStoreMonitor(widget.profile);

  bool get _allStores =>
      AttendanceAdminScope.canViewAllStores(widget.profile);

  @override
  void initState() {
    super.initState();
    _tokoFilter =
        _allStores ? null : widget.profile['toko_id']?.toString();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (_canMonitor) {
        final rows = await Supabase.instance.client
            .from('toko_id')
            .select('id')
            .order('id');
        final all = [
          for (final r in rows) r['id']?.toString() ?? '',
        ].where((e) => e.isNotEmpty).toList();
        _tokoOptions =
            AttendanceAdminScope.filterTokoForMonitor(all, widget.profile);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tokoFilter != null &&
          !AttendanceAdminScope.canAccessTokoAttendance(
              widget.profile, _tokoFilter)) {
        throw 'Tidak berhak melihat absensi toko ini.';
      }

      final toko = _tokoFilter?.isNotEmpty == true
          ? _tokoFilter
          : (_allStores ? null : widget.profile['toko_id']?.toString());

      final rows = await _svc.listByStatus(
        statuses: [AttendanceVerificationStatus.mencurigakan],
        tokoId: toko,
      );
      final filtered =
          AttendanceAdminScope.filterVerificationRows(rows, widget.profile);
      if (!mounted) return;

      Map<String, dynamic>? nextSelected;
      if (_selected != null) {
        final id = _selected!['id'];
        for (final r in filtered) {
          if (r['id'] == id) {
            nextSelected = r;
            break;
          }
        }
      }
      nextSelected ??= filtered.isNotEmpty ? filtered.first : null;

      setState(() {
        _rows = filtered;
        _selected = nextSelected;
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

  Future<void> _markAman() async {
    final row = _selected;
    if (row == null || _acting) return;
    if (!AttendanceAdminScope.canAccessTokoAttendance(
        widget.profile, row['toko_id']?.toString())) {
      _snack('Tidak berhak menilai absensi toko ini.', OptikAdminTokens.danger);
      return;
    }
    final ok = await _confirm(
      title: 'Tandai Aman?',
      body:
          'Sama seperti Valid: absensi ditandai AMAN dan karyawan mendapat '
          '+${AttendanceVerificationConfig.validDayPoints} poin ABSEN.\n\n'
          'Bukan penilaian keterlambatan.',
      confirmLabel: 'Aman',
      danger: false,
    );
    if (!ok) return;
    setState(() => _acting = true);
    try {
      await _svc.markAman(
        verificationId: row['id'].toString(),
        karyawanId: row['karyawan_id'].toString(),
        notes: 'Aman setelah tinjauan lanjut',
      );
      if (!mounted) return;
      _snack(
        'Ditandai aman. Poin +${AttendanceVerificationConfig.validDayPoints}.',
        OptikAdminTokens.success,
      );
      _selected = null;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _markCurang() async {
    final row = _selected;
    if (row == null || _acting) return;
    if (!AttendanceAdminScope.canAccessTokoAttendance(
        widget.profile, row['toko_id']?.toString())) {
      _snack('Tidak berhak menilai absensi toko ini.', OptikAdminTokens.danger);
      return;
    }
    final ok = await _confirm(
      title: 'Terbukti salah / curang?',
      body:
          'Hanya untuk kecurangan verifikasi wajah yang terbukti.\n'
          'Efek: ${AttendanceVerificationConfig.cheatingPenaltyPoints} poin '
          '+ SP ${AttendanceVerificationConfig.cheatingSpTingkat}.\n\n'
          'JANGAN dipakai untuk keterlambatan absensi.',
      confirmLabel: 'Terbukti curang',
      danger: true,
    );
    if (!ok) return;
    setState(() => _acting = true);
    try {
      await _svc.markCurang(
        verificationId: row['id'].toString(),
        karyawanId: row['karyawan_id'].toString(),
        tokoId: (row['toko_id'] ?? '').toString(),
        notes: 'Terbukti curang pada verifikasi wajah absensi',
      );
      if (!mounted) return;
      _snack(
        'Curang: ${AttendanceVerificationConfig.cheatingPenaltyPoints} poin '
        '+ SP ${AttendanceVerificationConfig.cheatingSpTingkat}.',
        OptikAdminTokens.danger,
      );
      _selected = null;
      await _load();
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
        title: Text(
          title,
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(
            color: OptikAdminTokens.slate,
            height: 1.4,
          ),
        ),
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

  String get _tokoFilterLabel {
    if (_tokoFilter != null && _tokoFilter!.isNotEmpty) return _tokoFilter!;
    if (!_allStores) {
      final own = widget.profile['toko_id']?.toString() ?? '';
      return own.isEmpty ? 'Toko sendiri' : own;
    }
    return 'Semua toko';
  }

  Future<void> _pickTokoFilter() async {
    if (!_canMonitor) return;

    final sel = await showAdminPicker<String>(
      context: context,
      title: 'Filter toko',
      subtitle: 'Pilih cabang untuk antrean tinjauan',
      headerIcon: Icons.storefront_rounded,
      searchHint: 'Cari kode toko…',
      clearLabel: _allStores ? 'Semua toko' : null,
      clearSubtitle: _allStores ? 'Tampilkan seluruh antrean' : null,
      clearIcon: Icons.apps_rounded,
      selected: _tokoFilter,
      options: [
        for (final t in _tokoOptions)
          AdminPickerOption(
            value: t,
            label: t,
            subtitle: AttendanceAdminScope.isPusatTokoId(t) ? 'Pusat' : 'Cabang',
            icon: AttendanceAdminScope.isPusatTokoId(t)
                ? Icons.apartment_rounded
                : Icons.storefront_rounded,
          ),
      ],
    );
    if (!mounted || sel == null) return;
    final next = sel.isClear ? null : sel.value;
    if (next == _tokoFilter) return;
    setState(() {
      _tokoFilter = next;
      _selected = null;
    });
    await _load();
  }

  Widget _statusChip({bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: OptikAdminTokens.warning.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OptikAdminTokens.warning.withOpacity(0.45)),
      ),
      child: Text(
        compact ? 'FLAG' : 'Mencurigakan',
        style: TextStyle(
          color: OptikAdminTokens.warning,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
          letterSpacing: compact ? 0.4 : 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final queueCount = _rows.length;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'dash_menu_tinjauan_mencurigakan'.tr(),
        subtitle: queueCount > 0
            ? '$queueCount menunggu tinjauan'
            : 'Antrean kosong',
        actions: [
          if (queueCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.warning,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$queueCount',
                    style: const TextStyle(
                      color: OptikAdminTokens.snow,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            // Callout semantik warning — bukan PremiumPanel (sheen ice).
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OptikAdminTokens.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: OptikAdminTokens.warning.withOpacity(0.7),
                  width: 1.2,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PremiumIconBadge(
                    icon: Icons.warning_amber_rounded,
                    color: OptikAdminTokens.warning,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Antrean hasil yang di-flag mencurigakan. '
                      'Aman = +${AttendanceVerificationConfig.validDayPoints} poin. '
                      'Terbukti curang = ${AttendanceVerificationConfig.cheatingPenaltyPoints} poin '
                      '+ SP ${AttendanceVerificationConfig.cheatingSpTingkat}. '
                      'Bukan untuk keterlambatan.',
                      style: const TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_canMonitor)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AdminPickerField(
                label: 'Filter toko',
                valueText: _tokoFilterLabel,
                icon: Icons.storefront_rounded,
                onTap: _pickTokoFilter,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OptikAdminTokens.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: OptikAdminTokens.danger.withOpacity(0.7),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: OptikAdminTokens.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: OptikAdminTokens.danger,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: OptikAdminTokens.ice),
                  )
                : _rows.isEmpty
                    ? PremiumEmptyState(
                        message:
                            'Tidak ada kasus mencurigakan menunggu tinjauan.',
                        icon: Icons.fact_check_outlined,
                        accent: OptikAdminTokens.ice,
                        action: TextButton.icon(
                          onPressed: _load,
                          style: TextButton.styleFrom(
                            foregroundColor: OptikAdminTokens.navy,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Muat ulang'),
                        ),
                      )
                    : wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 340, child: _buildList()),
                              const VerticalDivider(
                                width: 1,
                                color: OptikAdminTokens.line,
                              ),
                              Expanded(child: _buildDetail()),
                            ],
                          )
                        : _selected == null
                            ? _buildList()
                            : Column(
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          setState(() => _selected = null),
                                      style: TextButton.styleFrom(
                                        foregroundColor: OptikAdminTokens.navy,
                                      ),
                                      icon: const Icon(
                                          Icons.arrow_back_rounded),
                                      label: const Text('Daftar'),
                                    ),
                                  ),
                                  Expanded(child: _buildDetail()),
                                ],
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      color: OptikAdminTokens.ice,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final r = _rows[i];
          final selected = _selected?['id'] == r['id'];
          final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
          return PremiumPanel(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: 14,
            borderColor: selected
                ? OptikAdminTokens.warning.withOpacity(0.65)
                : OptikAdminTokens.lineStrong,
            onTap: () => setState(() => _selected = r),
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
                      const SizedBox(height: 2),
                      Text(
                        '${r['toko_id'] ?? '-'}'
                        '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        at != null ? _dayFmt.format(at.toLocal()) : '-',
                        style: const TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(compact: true),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: selected
                      ? OptikAdminTokens.warning
                      : OptikAdminTokens.slate,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetail() {
    final r = _selected;
    if (r == null) {
      return const PremiumEmptyState(
        message: 'Pilih kasus untuk meninjau foto capture vs terdaftar.',
        icon: Icons.compare_rounded,
      );
    }
    final capture = (r['capture_photo_url'] ?? '').toString();
    final enrolled = _svc.enrolledUrlOf(r);
    final score = r['match_score'];
    final at = DateTime.tryParse(r['created_at']?.toString() ?? '');
    final notes = (r['notes'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _svc.namaOf(r),
                style: const TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${r['toko_id'] ?? '-'}'
          '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}'
          '${at != null ? ' · ${_dayFmt.format(at.toLocal())}' : ''}',
          style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Skor match: ${score ?? '-'}'
          ' · Liveness: ${r['liveness_ok'] == true ? 'OK' : '-'}'
          '${r['liveness_provider'] != null ? ' (${r['liveness_provider']})' : ''}',
          style: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          PremiumPanel(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            borderColor: OptikAdminTokens.warning.withOpacity(0.45),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  color: OptikAdminTokens.warning,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notes,
                    style: const TextStyle(
                      color: OptikAdminTokens.slate,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 560;
            final left = _photoPane(
              label: 'Capture absen (hari itu)',
              subtitle: 'Hasil liveness / face match saat masuk',
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
                children: [left, const SizedBox(height: 12), right],
              );
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
        Row(
          children: [
            Expanded(
              child: PremiumPrimaryButton(
                label: 'Aman',
                icon: Icons.verified_rounded,
                loading: _acting,
                onPressed: _acting ? null : _markAman,
                gradient: const LinearGradient(
                  colors: [OptikAdminTokens.success, OptikAdminTokens.success],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PremiumPrimaryButton(
                label: 'Terbukti curang',
                icon: Icons.gavel_rounded,
                loading: _acting,
                onPressed: _acting ? null : _markCurang,
                gradient: const LinearGradient(
                  colors: [OptikAdminTokens.danger, OptikAdminTokens.danger],
                ),
              ),
            ),
          ],
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
        child: const Icon(
          Icons.broken_image,
          color: OptikAdminTokens.slate,
          size: 18,
        ),
      ),
    );
  }
}
