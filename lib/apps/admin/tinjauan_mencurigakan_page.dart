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

  @override
  void initState() {
    super.initState();
    _tokoFilter = _canMonitor ? null : widget.profile['toko_id']?.toString();
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
          : (_canMonitor ? null : widget.profile['toko_id']?.toString());

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
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  danger ? OptikAdminTokens.danger : OptikAdminTokens.success,
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
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Tinjauan Mencurigakan',
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: PremiumPanel(
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              borderColor: OptikAdminTokens.warning.withOpacity(0.45),
              child: Text(
                'Antrean hasil yang di-flag mencurigakan. '
                'Aman = +${AttendanceVerificationConfig.validDayPoints} poin. '
                'Terbukti curang = ${AttendanceVerificationConfig.cheatingPenaltyPoints} poin '
                '+ SP ${AttendanceVerificationConfig.cheatingSpTingkat}. '
                'Bukan untuk keterlambatan.',
                style: const TextStyle(
                  color: OptikAdminTokens.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (_canMonitor)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                value: _tokoFilter,
                dropdownColor: OptikAdminTokens.card,
                decoration: const InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: OptikAdminTokens.card,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                hint: const Text('Semua toko',
                    style: TextStyle(color: Colors.white54)),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua toko',
                        style: TextStyle(color: Colors.white)),
                  ),
                  ..._tokoOptions.map(
                    (t) => DropdownMenuItem<String?>(
                      value: t,
                      child:
                          Text(t, style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _tokoFilter = v;
                    _selected = null;
                  });
                  _load();
                },
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const PremiumEmptyState(
                        message: 'Tidak ada kasus mencurigakan menunggu tinjauan.',
                        icon: Icons.fact_check_outlined,
                      )
                    : wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 320, child: _buildList()),
                              const VerticalDivider(width: 1),
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
                                      icon: const Icon(Icons.arrow_back),
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
            borderColor:
                selected ? OptikAdminTokens.warning.withOpacity(0.55) : null,
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
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${r['toko_id'] ?? '-'}'
                        '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        at != null ? _dayFmt.format(at.toLocal()) : '-',
                        style: const TextStyle(
                          color: Colors.white38,
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
                    color: OptikAdminTokens.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'FLAG',
                    style: TextStyle(
                      color: OptikAdminTokens.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
        Text(
          _svc.namaOf(r),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${r['toko_id'] ?? '-'}'
          '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}'
          '${at != null ? ' · ${_dayFmt.format(at.toLocal())}' : ''}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Skor match: ${score ?? '-'}'
          ' · Liveness: ${r['liveness_ok'] == true ? 'OK' : '-'}'
          '${r['liveness_provider'] != null ? ' (${r['liveness_provider']})' : ''}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Catatan: $notes',
            style: const TextStyle(color: OptikAdminTokens.warning, fontSize: 12),
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
              accent: OptikAdminTokens.accentSoft,
            );
            final right = _photoPane(
              label: 'Foto terdaftar',
              subtitle: 'face_photo_url / enroll karyawan',
              url: enrolled,
              accent: OptikAdminTokens.success,
            );
            if (stacked) {
              return Column(children: [left, const SizedBox(height: 12), right]);
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
                  colors: [Color(0xFF34D399), Color(0xFF059669)],
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
                  colors: [Color(0xFFF87171), Color(0xFFDC2626)],
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
            style: const TextStyle(color: Colors.white38, fontSize: 11),
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
        child: const Icon(Icons.person, color: Colors.white24, size: 22),
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
        child: const Icon(Icons.broken_image, color: Colors.white24, size: 18),
      ),
    );
  }
}
