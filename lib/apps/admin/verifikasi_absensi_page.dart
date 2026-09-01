import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/attendance/attendance_verification_config.dart';
import '../../shared/attendance/attendance_verification_service.dart';
import '../../shared/admin/admin_format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/zoomable_network_image.dart';
import 'tinjauan_mencurigakan_page.dart';

/// Admin: bandingkan foto capture absen (kiri) vs foto terdaftar (kanan).
/// admin_pusat: cabang saja. Owner: termasuk Pusat. Cabang: tidak dipakai (kiosk saja).
class VerifikasiAbsensiPage extends StatefulWidget {
  const VerifikasiAbsensiPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<VerifikasiAbsensiPage> createState() => _VerifikasiAbsensiPageState();
}

class _VerifikasiAbsensiPageState extends State<VerifikasiAbsensiPage> {
  final _svc = AttendanceVerificationService();
  DateFormat get _dayFmt => AdminFormat.date(context, 'd MMM yyyy HH:mm');

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

  String? get _tenantId =>
      AttendanceAdminScope.tenantIdOf(widget.profile);

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
        statuses: [AttendanceVerificationStatus.pendingReview],
        tokoId: toko,
        tokoIds: toko == null ? _tokoOptions : null,
        tenantId: _tenantId,
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

  Future<void> _markValid() async {
    final row = _selected;
    if (row == null || _acting) return;
    if (!AttendanceAdminScope.canAccessTokoAttendance(
        widget.profile,
        row['toko_id']?.toString(),
        rowTenantId: row['tenant_id']?.toString(),
      )) {
      _snack('admin_gl_row_d7705cfa27'.tr(), OptikAdminTokens.danger);
      return;
    }
    final ok = await _confirm(
      title: 'admin_auto_be4b2cf189'.tr(),
      body:
          'Absensi wajah hari ini akan ditandai AMAN dan karyawan mendapat '
          '+${AttendanceVerificationConfig.validDayPoints} poin ABSEN.\n\n'
          'Ini verifikasi wajah — bukan penilaian keterlambatan.',
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

  Future<void> _markMencurigakan() async {
    final row = _selected;
    if (row == null || _acting) return;
    if (!AttendanceAdminScope.canAccessTokoAttendance(
        widget.profile,
        row['toko_id']?.toString(),
        rowTenantId: row['tenant_id']?.toString(),
      )) {
      _snack('admin_gl_row_d7705cfa27'.tr(), OptikAdminTokens.danger);
      return;
    }
    final ok = await _confirm(
      title: 'admin_auto_1e27415c59'.tr(),
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
      _snack('admin_gl_row_37ea28bca7'.tr(), OptikAdminTokens.warning);
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
          side: BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: Text(title,
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontWeight: FontWeight.w800,
            )),
        content: Text(body,
            style: TextStyle(
              color: OptikAdminTokens.slate,
              height: 1.4,
            )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: OptikAdminTokens.slate),
            child: Text('appr_btn_batal'.tr()),
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
      title: 'admin_auto_78058947dd'.tr(),
      subtitle: 'admin_auto_6ba7225956'.tr(),
      headerIcon: Icons.storefront_rounded,
      searchHint: 'Cari kode toko…',
      clearLabel: _allStores ? 'admin_lbl_semua_toko'.tr() : null,
      clearSubtitle: _allStores ? 'admin_lbl_tampilkan_seluruh_antrean'.tr() : null,
      clearIcon: Icons.apps_rounded,
      selected: _tokoFilter,
      options: [
        for (final t in _tokoOptions)
          AdminPickerOption(
            value: t,
            label: t,
            subtitle: AttendanceAdminScope.isPusatTokoId(t) ? 'admin_lbl_pusat'.tr() : 'admin_lbl_cabang'.tr(),
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

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: TextStyle(
            color: OptikAdminTokens.snow,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'appr_verifikasi_absensi'.tr(),
        actions: [
          IconButton(
            tooltip: 'appr_tinjauan_mencurigakan'.tr(),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TinjauanMencurigakanPage(profile: widget.profile),
              ),
            ).then((_) => _load()),
            icon: const Icon(Icons.warning_amber_rounded,
                color: OptikAdminTokens.warning),
          ),
          IconButton(
            tooltip: 'admin_btn_refresh'.tr(),
            onPressed: _load,
            icon: Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
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
              borderColor: OptikAdminTokens.ice.withOpacity(0.55),
              child: Text(
                'Bandingkan foto capture absen (kiri) dengan foto wajah '
                'terdaftar (kanan). Valid = aman + poin. Mencurigakan = '
                'antrean tinjauan. Bukan untuk keterlambatan.',
                style: TextStyle(
                  color: OptikAdminTokens.slate,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (_canMonitor)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AdminPickerField(
                label: 'admin_auto_78058947dd'.tr(),
                valueText: _tokoFilterLabel,
                icon: Icons.storefront_rounded,
                onTap: _pickTokoFilter,
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
                ? Center(child: CircularProgressIndicator(color: OptikAdminTokens.ice))
                : _rows.isEmpty
                    ? PremiumEmptyState(
                        message:
                            'Tidak ada absensi menunggu verifikasi wajah.',
                        icon: Icons.verified_user_outlined,
                      )
                    : wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 320, child: _buildList()),
                              VerticalDivider(width: 1, color: OptikAdminTokens.line),
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
                                      icon: const Icon(Icons.arrow_back_rounded),
                                      label: Text('admin_btn_daftar'.tr()),
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
            borderColor:
                selected ? OptikAdminTokens.ice.withOpacity(0.7) : null,
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
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${r['toko_id'] ?? '-'}'
                        '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        at != null ? _dayFmt.format(at.toLocal()) : '-',
                        style: TextStyle(
                          color: OptikAdminTokens.slate,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: OptikAdminTokens.slate),
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
      return PremiumEmptyState(
        message: 'admin_auto_2f76cbe621'.tr(),
        icon: Icons.compare_rounded,
      );
    }
    final capture = (r['capture_photo_url'] ?? '').toString();
    final enrolled = _svc.enrolledUrlOf(r);
    final score = r['match_score'];
    final at = DateTime.tryParse(r['created_at']?.toString() ?? '');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _svc.namaOf(r),
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${r['toko_id'] ?? '-'}'
          '${_svc.jabatanOf(r).isNotEmpty ? ' · ${_svc.jabatanOf(r)}' : ''}'
          '${at != null ? ' · ${_dayFmt.format(at.toLocal())}' : ''}',
          style: TextStyle(color: OptikAdminTokens.slate, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Skor match: ${score ?? '-'}'
          ' · Liveness: ${r['liveness_ok'] == true ? 'OK' : '-'}'
          '${r['liveness_provider'] != null ? ' (${r['liveness_provider']})' : ''}',
          style: TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 560;
            final left = _photoPane(
              label: 'admin_auto_7187985eb2'.tr(),
              subtitle: 'admin_auto_fcaaddc7ab'.tr(),
              url: capture,
              accent: OptikAdminTokens.navy,
            );
            final right = _photoPane(
              label: 'admin_auto_e8847690d4'.tr(),
              subtitle: 'admin_auto_92b69be5ad'.tr(),
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
                label: 'admin_auto_3ac705f2ac'.tr(),
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
                label: 'admin_auto_a62e01bd59'.tr(),
                icon: Icons.warning_amber_rounded,
                loading: _acting,
                onPressed: _acting ? null : _markMencurigakan,
                gradient: const LinearGradient(
                  colors: [OptikAdminTokens.warning, OptikAdminTokens.warning],
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
            style: TextStyle(color: OptikAdminTokens.slate, fontSize: 11),
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
        child: Icon(Icons.person, color: OptikAdminTokens.slate, size: 22),
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
        child: Icon(Icons.broken_image, color: OptikAdminTokens.slate, size: 18),
      ),
    );
  }
}
