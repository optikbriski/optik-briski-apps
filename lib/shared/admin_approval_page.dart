import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../apps/admin/attendance_monitor_page.dart';
import '../apps/admin/jadwal_kerja_page.dart';
import '../apps/admin/tinjauan_mencurigakan_page.dart';
import '../apps/karyawan/register_karyawan_page.dart';
import 'attendance/attendance_admin_scope.dart';
import 'attendance/attendance_dinas.dart';
import 'karyawan/shift_auto_assign.dart';
import 'formatters.dart';
import 'ktp/ktp_approval_review_page.dart';
import 'responsive.dart';
import 'brand/brand_service.dart';
import 'connectivity/connectivity_reload.dart';
import 'theme.dart';
import 'admin/admin_nav_badge_service.dart';
import 'widgets/admin/admin_nav_badge.dart';
import 'widgets/admin/admin_premium.dart';

/// Tone nilai di baris info profil — warna semantik, bukan dekorasi.
enum _InfoTone { normal, success, danger, warning, sensitive }

class AdminApprovalPage extends StatefulWidget {
  final String roleAdmin;
  final String cabangAdmin;

  /// Profil admin untuk scope toko / tenant / pintasan pantau.
  final Map<String, dynamic>? profile;

  const AdminApprovalPage({
    super.key,
    this.roleAdmin = '',
    this.cabangAdmin = '',
    this.profile,
  });

  @override
  State<AdminApprovalPage> createState() => _AdminApprovalPageState();
}

class _AdminApprovalPageState extends State<AdminApprovalPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final Object _reloadOwner = Object();
  late final TabController _tabs;
  static const int _pageSize = 50;
  static const List<String> _statusAktif = ['Aktif', 'aktif', 'AKTIF'];

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _search = '';
  String _filterToko = '';
  List<String> _tokoOptions = [];
  static const int _tabCount = 4;
  final List<int> _page = [0, 0, 0, 0];
  final List<bool> _more = [false, false, false, false];
  final List<List<Map<String, dynamic>>> _lists = [[], [], [], []];
  Map<String, String> _leaveToday = {};
  int _leaveWindow = 0;
  final List<bool> _serverFull = [false, false, false, false];
  int _totalStaff = 0;
  bool _isLoading = true;
  bool _busy = false;
  bool _openingReview = false;
  String? _actingId;

  Map<String, dynamic> get _scopeProfile =>
      widget.profile ??
      <String, dynamic>{
        'role': widget.roleAdmin,
        'toko_id': widget.cabangAdmin,
      };

  /// Semua cabang: owner / admin_pusat / super_admin.
  /// admin_toko (meski assigned PUSAT) hanya toko sendiri.
  bool get _isPusat => AttendanceAdminScope.canViewAllStores(_scopeProfile);

  String get _scopeTokoLabel {
    final raw = AttendanceAdminScope.workSummaryTokoLabel(widget.cabangAdmin);
    return raw.isEmpty ? widget.cabangAdmin : raw;
  }

  String _staffTokoLabel(Map data) {
    final raw = (data['toko_id'] ?? data['cabang'] ?? '').toString();
    final label = AttendanceAdminScope.workSummaryTokoLabel(raw);
    return label.isEmpty ? '-' : label;
  }

  bool _isPendingStatus(String? raw) => isKtpReviewPendingStatus(raw);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    ConnectivityReload.bind(_reloadOwner, _tarikDataKaryawan);
    _tarikDataKaryawan();
  }

  @override
  void didUpdateWidget(AdminApprovalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldToko = (oldWidget.profile?['toko_id'] ?? oldWidget.cabangAdmin)
        .toString();
    final newToko = (widget.profile?['toko_id'] ?? widget.cabangAdmin).toString();
    final oldTenant = (oldWidget.profile?['tenant_id'] ?? '').toString();
    final newTenant = (widget.profile?['tenant_id'] ?? '').toString();
    if (oldWidget.roleAdmin != widget.roleAdmin ||
        oldToko != newToko ||
        oldTenant != newTenant) {
      _tarikDataKaryawan();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    ConnectivityReload.unbind(_reloadOwner);
    _tabs.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final next = raw.trim();
      if (!mounted || next == _search) return;
      _search = next;
      for (var i = 0; i < _tabCount; i++) {
        _page[i] = 0;
      }
      _tarikDataKaryawan();
    });
  }

  List<String>? _storeKeys() {
    if (!_isPusat) {
      final raw = widget.cabangAdmin.trim().isNotEmpty
          ? widget.cabangAdmin.trim()
          : AttendanceAdminScope.tokoOf(_scopeProfile).trim();
      if (raw.isEmpty) return const ['__tidak-ada-cabang__'];
      final keys = AttendanceAdminScope.storeIdAliases(raw);
      return keys.isEmpty ? [raw] : keys;
    }
    if (_filterToko.isEmpty) return null;
    final keys = AttendanceAdminScope.storeIdAliases(_filterToko);
    return keys.isEmpty ? [_filterToko] : keys;
  }

  String _tokoOptionLabel(String id) {
    final label = AttendanceAdminScope.workSummaryTokoLabel(id);
    return label.isEmpty ? id : label;
  }

  Map<String, dynamic> _asStaff(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  String _genderLabel(dynamic raw) {
    final g = (raw ?? '').toString().trim();
    if (g.isEmpty) return '-';
    final lower = g.toLowerCase();
    if (g == 'L' || lower == 'laki-laki' || lower == 'male') {
      return 'gender_l'.tr();
    }
    if (g == 'P' || lower == 'perempuan' || lower == 'female') {
      return 'gender_p'.tr();
    }
    return g;
  }

  String _gajiLabel(dynamic raw) {
    if (raw == null) return '-';
    if (raw is num) return formatRupiah(raw.round());
    final digits = raw.toString().replaceAll(RegExp(r'[^0-9-]'), '');
    if (digits.isEmpty) return '-';
    final n = int.tryParse(digits);
    return n == null ? '-' : formatRupiah(n);
  }

  void _snackLoadFail() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('appr_err_umum'.tr()),
        backgroundColor: OptikAdminTokens.danger,
      ),
    );
  }

  String get _searchNeedle =>
      _search.replaceAll(RegExp(r'''[%_,()'"]'''), '').trim();

  bool _needsReview(String? raw) {
    if (isKtpReviewPendingStatus(raw)) return true;
    final s = (raw ?? '').trim();
    return kKtpReviewPendingStatuses.contains(s);
  }

  bool _isInactiveStatus(String? raw) {
    final s = (raw ?? '').toLowerCase();
    return s.contains('tolak') ||
        s.contains('reject') ||
        s.contains('nonaktif');
  }

  bool _isLeaveStatus(String? raw) {
    final s = (raw ?? '').toLowerCase();
    return s.contains('cuti') || s.contains('izin') || s.contains('ijin');
  }

  bool _onLeave(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    return _leaveToday.containsKey(id) ||
        _isLeaveStatus(row['status_approval']?.toString());
  }

  List<String> _storeIdsMatching(String needle) {
    final n = needle.toLowerCase();
    if (n.isEmpty) return const [];
    return [
      for (final id in _tokoOptions)
        if (id.toLowerCase().contains(n) ||
            _tokoOptionLabel(id).toLowerCase().contains(n))
          id,
    ];
  }

  dynamic _applyScopeAndSearch(dynamic query) {
    final keys = _storeKeys();
    if (keys != null) {
      query = query.inFilter('toko_id', keys);
    }
    final needle = _searchNeedle;
    if (needle.isEmpty) return query;
    final parts = <String>[
      'nama.ilike.%$needle%',
      'nik.ilike.%$needle%',
      'wa.ilike.%$needle%',
      'toko_id.ilike.%$needle%',
    ];
    for (final id in _storeIdsMatching(needle)) {
      final safe = id.replaceAll(RegExp(r'''[,%()]'''), '');
      if (safe.isNotEmpty) parts.add('toko_id.eq.$safe');
    }
    return query.or(parts.join(','));
  }

  Future<List<Map<String, dynamic>>> _fetchStaffPage({
    required String tenant,
    required int bucket,
    required int page,
  }) async {
    if (bucket == 2) {
      return _fetchLeavePage(tenant: tenant, page: page);
    }

    var query = supabase.from('karyawan').select().eq('tenant_id', tenant);
    if (bucket == 0) {
      query = query.inFilter('status_approval', kKtpReviewPendingStatuses);
    } else if (bucket == 1) {
      query = query.inFilter('status_approval', _statusAktif);
    } else if (bucket == 3) {
      query = query.or(
        'status_approval.ilike.%ditolak%,'
        'status_approval.ilike.%nonaktif%,'
        'status_approval.ilike.%reject%',
      );
    }
    query = _applyScopeAndSearch(query);

    final from = page * _pageSize;
    final to = (page + 1) * _pageSize - 1;
    final data = await query
        .order('created_at', ascending: false)
        .range(from, to)
        .timeout(const Duration(seconds: 15));
    final rows = data.map(_asStaff).toList();
    final rawCount = rows.length;
    if (bucket == 1 && _leaveToday.isNotEmpty) {
      rows.removeWhere(
        (row) => _leaveToday.containsKey((row['id'] ?? '').toString()),
      );
    }
    _serverFull[bucket] = rawCount == _pageSize;
    return rows;
  }

  Future<List<Map<String, dynamic>>> _fetchLeavePage({
    required String tenant,
    required int page,
  }) async {
    final merged = <String, Map<String, dynamic>>{};
    final ids = _leaveToday.keys.toList();
    if (ids.isNotEmpty) {
      var byId = supabase
          .from('karyawan')
          .select()
          .eq('tenant_id', tenant)
          .inFilter('id', ids.take(200).toList());
      byId = _applyScopeAndSearch(byId);
      final rows = await byId.timeout(const Duration(seconds: 15));
      for (final row in rows.map(_asStaff)) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) merged[id] = row;
      }
    }

    var byStatus = supabase.from('karyawan').select().eq('tenant_id', tenant).or(
          'status_approval.ilike.%cuti%,'
          'status_approval.ilike.%izin%,'
          'status_approval.ilike.%ijin%',
        );
    byStatus = _applyScopeAndSearch(byStatus);
    final statusRows = await byStatus
        .order('created_at', ascending: false)
        .limit(200)
        .timeout(const Duration(seconds: 15));
    for (final row in statusRows.map(_asStaff)) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) merged[id] = row;
    }

    final all = merged.values.toList();
    _leaveWindow = all.length;
    final start = page * _pageSize;
    if (start >= all.length) return [];
    final end = start + _pageSize;
    return all.sublist(start, end > all.length ? all.length : end);
  }

  Future<Map<String, String>> _loadLeaveToday() async {
    final today = AttendanceDinas.todayKey();
    try {
      var q = supabase
          .from('jadwal_pengajuan')
          .select('karyawan_id, tipe')
          .eq('status', 'APPROVED')
          .inFilter('tipe', const ['IJIN', 'CUTI'])
          .eq('tanggal', today);
      final keys = _storeKeys();
      if (keys != null) q = q.inFilter('toko_id', keys);
      final rows = await q.limit(500).timeout(const Duration(seconds: 15));
      final map = <String, String>{};
      for (final row in rows) {
        final id = row['karyawan_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        map[id] = (row['tipe'] ?? 'CUTI').toString();
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<int> _countStaff(String tenant) async {
    try {
      var q = supabase.from('karyawan').select('id').eq('tenant_id', tenant);
      q = _applyScopeAndSearch(q);
      final counted = await q.count(CountOption.exact);
      return counted.count;
    } catch (_) {
      return _lists.fold<int>(0, (n, list) => n + list.length);
    }
  }

  Future<void> _tarikDataKaryawan({int? bucket}) async {
    if (!mounted || _busy) return;
    _busy = true;
    final firstPaint = _isLoading && _lists.every((list) => list.isEmpty);
    setState(() {
      if (firstPaint) _isLoading = true;
    });

    try {
      final tenant = AttendanceAdminScope.tenantIdOf(_scopeProfile);
      if (tenant == null || tenant.isEmpty) {
        if (!mounted) {
          _busy = false;
          return;
        }
        setState(() {
          for (final list in _lists) {
            list.clear();
          }
          _totalStaff = 0;
          _isLoading = false;
          _busy = false;
        });
        _snackLoadFail();
        return;
      }

      if (_isPusat) {
        final tokoRows = await supabase
            .from('toko_id')
            .select('id')
            .eq('tenant_id', tenant)
            .order('id')
            .limit(2000)
            .timeout(const Duration(seconds: 15));
        _tokoOptions = [
          for (final row in tokoRows) row['id']?.toString() ?? '',
        ].where((id) => id.isNotEmpty).toList();
        if (_filterToko.isNotEmpty && !_tokoOptions.contains(_filterToko)) {
          _filterToko = '';
        }
      }

      _leaveToday = await _loadLeaveToday();
      final indexes = bucket == null
          ? List<int>.generate(_tabCount, (i) => i)
          : <int>[bucket];
      final fetched = <int, List<Map<String, dynamic>>>{};
      for (final i in indexes) {
        fetched[i] = await _fetchStaffPage(
          tenant: tenant,
          bucket: i,
          page: _page[i],
        );
      }
      final total = bucket == null ? await _countStaff(tenant) : _totalStaff;

      if (!mounted) {
        _busy = false;
        return;
      }
      setState(() {
        for (final entry in fetched.entries) {
          _lists[entry.key] = entry.value;
          _more[entry.key] = entry.key == 2
              ? (_page[2] + 1) * _pageSize < _leaveWindow
              : _serverFull[entry.key];
        }
        _totalStaff = total;
        _isLoading = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _busy = false;
      });
      _snackLoadFail();
    }
  }

  String _initials(String nama) {
    final parts = nama
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && p != '-')
        .toList();
    if (parts.isEmpty) return '?';
    String ch(String s) => s.isEmpty ? '' : s.substring(0, 1).toUpperCase();
    if (parts.length == 1) return ch(parts.first);
    return '${ch(parts.first)}${ch(parts.last)}';
  }

  String _leaveChipLabel(Map<String, dynamic> k) {
    final tipe = (_leaveToday[(k['id'] ?? '').toString()] ?? '').toUpperCase();
    if (tipe == 'IJIN' || tipe == 'IZIN') return 'appr_leave_izin'.tr();
    if (tipe == 'CUTI' || _isLeaveStatus(k['status_approval']?.toString())) {
      return 'appr_leave_cuti'.tr();
    }
    return 'appr_leave_izin'.tr();
  }

  (Color, String) _statusPill(Map<String, dynamic> k) {
    final raw = k['status_approval']?.toString();
    if (_onLeave(k) && !_isInactiveStatus(raw) && !_needsReview(raw)) {
      return (OptikAdminTokens.warning, _leaveChipLabel(k));
    }
    if (_needsReview(raw)) {
      return (OptikAdminTokens.warning, _statusLabel(raw));
    }
    if (_isInactiveStatus(raw)) {
      return (OptikAdminTokens.danger, 'appr_tab_nonaktif'.tr());
    }
    if (_statusTone(raw) == _InfoTone.success) {
      return (OptikAdminTokens.success, 'appr_status_aktif'.tr());
    }
    return (OptikAdminTokens.warning, _statusLabel(raw));
  }

  Widget _statusPillWidget(Map<String, dynamic> k) {
    final (color, label) = _statusPill(k);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.22),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: OptikAdminTokens.bgMid,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: OptikAdminTokens.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: OptikAdminTokens.slate),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: OptikAdminTokens.slate,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardButton(
    String label,
    VoidCallback? onPressed, {
    bool danger = false,
    bool primary = false,
  }) {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: primary
            ? OptikAdminTokens.snow
            : (danger ? OptikAdminTokens.danger : OptikAdminTokens.navy),
      ),
    );
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: OptikAdminTokens.navy,
          foregroundColor: OptikAdminTokens.snow,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
          ),
        ),
        child: text,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            danger ? OptikAdminTokens.danger : OptikAdminTokens.navy,
        side: BorderSide(
          color: danger
              ? OptikAdminTokens.danger.withOpacity(0.45)
              : OptikAdminTokens.slate,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        ),
      ),
      child: text,
    );
  }

  void _bukaJadwal() {
    if (!AttendanceAdminScope.canManageJadwal(_scopeProfile)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JadwalKerjaPage(profile: _scopeProfile),
      ),
    );
  }

  void _bukaRiwayat() {
    if (!AttendanceAdminScope.canOpenStoreMonitor(_scopeProfile)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceMonitorPage(profile: _scopeProfile),
      ),
    );
  }

  void _bukaTambah() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterKaryawanPage()),
    );
  }

  Widget _buildCardKaryawanAktif(Map<String, dynamic> k) {
    final nama = (k['nama'] ?? '-').toString();
    final jabatan = (k['jabatan'] ?? '').toString().trim();
    final toko = _staffTokoLabel(k);
    final phone = (k['wa'] ?? '').toString().trim();
    final meta = [
      if (jabatan.isNotEmpty) jabatan,
      if (toko.isNotEmpty && toko != '-') toko,
      if (phone.isNotEmpty) phone,
    ].join(' · ');
    final kid = (k['id'] ?? '').toString();
    final pending = _needsReview(k['status_approval']?.toString());
    final inactive = _isInactiveStatus(k['status_approval']?.toString());
    final unread = kid.isNotEmpty &&
        pending &&
        AdminNavBadgeService.instance.isEntityUnread('karyawan', kid);
    final mulai = (k['tanggal_mulai'] ?? '').toString().split('T').first.trim();
    final onLeave = _onLeave(k);

    return GestureDetector(
      onLongPress: !pending || kid.isEmpty
          ? null
          : () {
              unawaited(
                AdminNavBadgeService.instance.markEntityUnread('karyawan', kid),
              );
            },
      child: PremiumPanel(
        showAccentBar: true,
        padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
        onTap: () {
          if (pending) {
            _bukaReviewVerifikasi(Map<String, dynamic>.from(k));
          } else {
            _tampilkanDetailKaryawan(k);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminNavBadgeOverlay(
                  count: unread ? 1 : 0,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          OptikAdminTokens.ice.withOpacity(0.55),
                          OptikAdminTokens.ice.withOpacity(0.18),
                        ],
                      ),
                      border: Border.all(
                        color: OptikAdminTokens.ice.withOpacity(0.7),
                      ),
                    ),
                    child: Text(
                      _initials(nama),
                      style: TextStyle(
                        color: OptikAdminTokens.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: OptikAdminTokens.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusPillWidget(k),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (onLeave)
                  _metaChip(Icons.event_busy_rounded, _leaveChipLabel(k))
                else if (mulai.isNotEmpty)
                  _metaChip(
                    Icons.schedule_rounded,
                    'appr_chip_mulai'.tr(namedArgs: {'date': mulai}),
                  ),
                if (jabatan.isNotEmpty)
                  _metaChip(Icons.badge_outlined, jabatan),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (pending) ...[
                  _cardButton(
                    'appr_btn_tolak'.tr(),
                    _actingId == null ? () => _tolakKaryawan(k) : null,
                    danger: true,
                  ),
                  _cardButton(
                    'appr_btn_setuju'.tr(),
                    _actingId == null ? () => _setujuiKaryawan(k) : null,
                    primary: true,
                  ),
                ] else if (inactive) ...[
                  if (AttendanceAdminScope.canOpenStoreMonitor(_scopeProfile))
                    _cardButton('appr_btn_riwayat'.tr(), _bukaRiwayat),
                  _cardButton(
                    'appr_btn_aktifkan'.tr(),
                    _actingId == null ? () => _aktifkanKembali(k) : null,
                    primary: true,
                  ),
                  _cardButton(
                    'appr_btn_edit'.tr(),
                    () => _tampilkanDetailKaryawan(k),
                  ),
                ] else ...[
                  if (AttendanceAdminScope.canManageJadwal(_scopeProfile))
                    _cardButton('appr_btn_jadwal'.tr(), _bukaJadwal),
                  if (AttendanceAdminScope.canOpenStoreMonitor(_scopeProfile))
                    _cardButton('appr_btn_riwayat'.tr(), _bukaRiwayat),
                  _cardButton(
                    'appr_btn_edit'.tr(),
                    () => _tampilkanDetailKaryawan(k),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // UI PREMIUM & RESPONSIVE POP-UP (tanpa Flexible di scroll — hindari crash)
  void _tampilkanDetailKaryawan(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.9;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: R.dialogMaxWidth(ctx, 950),
              maxHeight: maxH,
            ),
            child: Material(
              color: OptikAdminTokens.card,
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_rounded,
                            color: OptikAdminTokens.navy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "appr_detail_title".tr(),
                            style: TextStyle(
                                color: OptikAdminTokens.navy,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'admin_btn_close'.tr(),
                          icon: Icon(Icons.close_rounded,
                              color: OptikAdminTokens.slate),
                          onPressed: () => Navigator.pop(ctx),
                        )
                      ],
                    ),
                    const SizedBox(height: 25),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 750;
                        final detailBlocks = _buildDetailDataBlocks(data, isMobile);

                        if (isMobile) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildVirtualIDCard(data),
                              const SizedBox(height: 30),
                              detailBlocks,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildVirtualIDCard(data),
                            const SizedBox(width: 40),
                            Expanded(child: detailBlocks),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailDataBlocks(Map<String, dynamic> data, bool isMobile) {
    final pribadi = _buildDataSection("hr_data_pribadi".tr(), [
      _buildInfoRow("profil_label_nik".tr(), data['nik'] ?? '-'),
      _buildInfoRow("appr_email".tr(), data['email'] ?? '-'),
      _buildInfoRow("appr_nomor_wa".tr(), data['wa'] ?? '-'),
      _buildInfoRow("appr_gender".tr(), _genderLabel(data['gender'])),
      _buildInfoRow(
          "profil_label_umur".tr(),
          "appr_tahun".tr(args: [(data['umur'] ?? '-').toString()])),
      _buildInfoRow("appr_alamat".tr(), data['alamat_lengkap'] ?? '-'),
    ]);
    final kepegawaian = _buildDataSection("hr_kepegawaian".tr(), [
      _buildInfoRow(
          "appr_tgl_mulai".tr(),
          data['tanggal_mulai'] != null
              ? data['tanggal_mulai'].toString().split('T')[0]
              : '-'),
      _buildInfoRow("appr_pin_absensi".tr(),
          data['pin_absensi']?.toString() ?? '-',
          tone: _InfoTone.sensitive),
      _buildInfoRow(
        "appr_status".tr(),
        _statusLabel(data['status_approval']?.toString()),
        tone: _statusTone(data['status_approval']?.toString()),
      ),
    ]);
    final payroll = _buildDataSection("appr_data_payroll".tr(), [
      _buildInfoRow("hr_reg_bank".tr(), data['nama_bank'] ?? '-'),
      _buildInfoRow("appr_no_rekening".tr(), data['no_rekening'] ?? '-'),
      _buildInfoRow('appr_gaji_pokok'.tr(), _gajiLabel(data['gaji_pokok'])),
    ]);
    final darurat = _buildDataSection("hr_kontak_darurat".tr(), [
      _buildInfoRow("appr_nama_kontak".tr(), data['darurat_nama'] ?? '-'),
      _buildInfoRow("hr_reg_wa_darurat".tr(), data['darurat_wa'] ?? '-'),
    ]);

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pribadi,
          const SizedBox(height: 16),
          kepegawaian,
          const SizedBox(height: 16),
          payroll,
          const SizedBox(height: 16),
          darurat,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pribadi),
            const SizedBox(width: 20),
            Expanded(child: kepegawaian),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: payroll),
            const SizedBox(width: 20),
            Expanded(child: darurat),
          ],
        ),
      ],
    );
  }

  /// Fungsi warna teks Frozen Lake (dialog profil):
  /// - Navy → judul & nilai data
  /// - Slate → label / meta
  /// - Ice → aksen UI (border, badge), bukan body text
  /// - Success / Danger / Warning → hanya status semantik
  String _statusLabel(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '-';
    final lower = s.toLowerCase();
    if (lower == 'aktif') return 'appr_status_aktif'.tr();
    if (lower == 'pending') return 'appr_status_pending'.tr();
    if (lower == 'menunggu otp') return 'appr_status_otp'.tr();
    if (lower == 'menunggu persetujuan') return 'appr_status_tunggu'.tr();
    if (lower.startsWith('ditolak')) {
      final i = s.indexOf(':');
      final alasan = i < 0 ? '' : s.substring(i + 1).trim();
      return alasan.isEmpty
          ? 'appr_status_tolak'.tr()
          : 'appr_status_tolak_alasan'.tr(namedArgs: {'alasan': alasan});
    }
    return s;
  }

  _InfoTone _statusTone(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('aktif') || s.contains('approved') || s.contains('setuju')) {
      return _InfoTone.success;
    }
    if (s.contains('tolak') || s.contains('reject') || s.contains('nonaktif')) {
      return _InfoTone.danger;
    }
    if (s.contains('pending') || s.contains('tunggu')) {
      return _InfoTone.warning;
    }
    return _InfoTone.normal;
  }

  Color _toneColor(_InfoTone tone) {
    switch (tone) {
      case _InfoTone.success:
        return OptikAdminTokens.success;
      case _InfoTone.danger:
        return OptikAdminTokens.danger;
      case _InfoTone.warning:
        return OptikAdminTokens.warning;
      case _InfoTone.sensitive:
        return OptikAdminTokens.danger;
      case _InfoTone.normal:
        return OptikAdminTokens.navy;
    }
  }

  // WIDGET HELPER: ID CARD VIRTUAL
  Widget _buildVirtualIDCard(Map<String, dynamic> data) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        color: OptikAdminTokens.snow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OptikAdminTokens.ice, width: 1.5),
        boxShadow: OptikAdminTokens.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.remove_red_eye,
                  color: OptikAdminTokens.navy, size: 24),
              const SizedBox(width: 8),
              Text(
                BrandService.name,
                style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            "appr_id_card_pos".tr(),
            style: TextStyle(
                color: OptikAdminTokens.slate, fontSize: 8, letterSpacing: 2),
          ),
          const SizedBox(height: 15),
          Divider(color: OptikAdminTokens.line, thickness: 1),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: OptikAdminTokens.ice, width: 2),
            ),
            child: CircleAvatar(
              radius: 45,
              backgroundColor: OptikAdminTokens.cardElevated,
              child:
                  Icon(Icons.person, size: 50, color: OptikAdminTokens.slate),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            data['nama'] ?? '-',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            (data['jabatan'] ?? 'default_karyawan'.tr())
                .toString()
                .toUpperCase(),
            style: TextStyle(
                color: OptikAdminTokens.slate,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: OptikAdminTokens.accentSoft.withOpacity(0.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: OptikAdminTokens.ice),
            ),
            child: Text(
              "${'hr_cabang'.tr()} ${_staffTokoLabel(data)}",
              style: TextStyle(
                  color: OptikAdminTokens.navy,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: OptikAdminTokens.navy,
                borderRadius: BorderRadius.circular(10)),
            child: _LanyardQr(karyawanId: (data['id'] ?? '').toString()),
          ),
          const SizedBox(height: 15),
          Text(
            "appr_scan_barcode".tr(),
            style: TextStyle(
                color: OptikAdminTokens.slate,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: OptikAdminTokens.ice,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Divider(color: OptikAdminTokens.line, thickness: 1),
        const SizedBox(height: 10),
        ...rows,
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    _InfoTone tone = _InfoTone.normal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                  color: OptikAdminTokens.slate, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _toneColor(tone),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String key, Color bg, {List<String>? args}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(args == null ? key.tr() : key.tr(args: args)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _setujuiKaryawan(Map<String, dynamic> k) async {
    final kid = (k['id'] ?? '').toString();
    if (kid.isEmpty || _actingId != null) return;
    final tenant = AttendanceAdminScope.tenantIdOf(_scopeProfile);
    if (tenant == null || tenant.isEmpty) {
      _snack('ktprev_approve_fail', OptikAdminTokens.danger);
      return;
    }
    setState(() => _actingId = kid);
    try {
      final admin = supabase.auth.currentUser;
      final email = (admin?.email ?? '').trim();
      final updated = await supabase
          .from('karyawan')
          .update({
            'status_approval': 'Aktif',
            if (admin?.id != null) 'approved_by': admin!.id,
            if (email.isNotEmpty) 'approved_by_name': email,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', kid)
          .eq('tenant_id', tenant)
          .inFilter('status_approval', kKtpReviewPendingStatuses)
          .select('id')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (updated.isEmpty) {
        _snack('ktprev_sudah_diputus', OptikAdminTokens.warning);
        await _tarikDataKaryawan();
        return;
      }
      try {
        final tokoId = (k['toko_id'] ?? '').toString().trim();
        if (tokoId.isNotEmpty) {
          await ShiftAutoAssignService().ensureDefaultWeekIfEmpty(
            karyawanId: kid,
            tokoId: tokoId,
          );
        }
      } catch (e) {
        debugPrint('seed jadwal after approve: $e');
      }
      unawaited(AdminNavBadgeService.instance.markEntitySeen('karyawan', kid));
      unawaited(AdminNavBadgeService.instance.refresh());
      _snack(
        'appr_sukses_setuju',
        OptikAdminTokens.success,
        args: [(k['nama'] ?? '-').toString()],
      );
      await _tarikDataKaryawan();
    } catch (e, st) {
      debugPrint('approve karyawan: $e\n$st');
      if (!mounted) return;
      _snack('ktprev_approve_fail', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _actingId = null);
    }
  }

  Future<void> _tolakKaryawan(Map<String, dynamic> k) async {
    final kid = (k['id'] ?? '').toString();
    if (kid.isEmpty || _actingId != null) return;
    final tenant = AttendanceAdminScope.tenantIdOf(_scopeProfile);
    if (tenant == null || tenant.isEmpty) {
      _snack('ktprev_reject_fail', OptikAdminTokens.danger);
      return;
    }
    final alasanCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('appr_tanya_tolak'.tr()),
          content: TextField(
            controller: alasanCtrl,
            maxLines: 3,
            maxLength: 160,
            onChanged: (_) => setLocal(() {}),
            decoration: InputDecoration(
              hintText: 'appr_hint_tolak'.tr(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('appr_btn_batal'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.danger,
                foregroundColor: OptikAdminTokens.snow,
                elevation: 0,
              ),
              onPressed: alasanCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('appr_btn_tolak_kirim'.tr()),
            ),
          ],
        ),
      ),
    );
    final alasan = alasanCtrl.text.trim();
    alasanCtrl.dispose();
    if (ok != true || alasan.isEmpty || !mounted) return;
    final alasanSimpan =
        alasan.length > 160 ? alasan.substring(0, 160) : alasan;

    setState(() => _actingId = kid);
    try {
      final updated = await supabase
          .from('karyawan')
          .update({'status_approval': 'Ditolak: $alasanSimpan'})
          .eq('id', kid)
          .eq('tenant_id', tenant)
          .inFilter('status_approval', kKtpReviewPendingStatuses)
          .select('id')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (updated.isEmpty) {
        _snack('ktprev_sudah_diputus', OptikAdminTokens.warning);
        await _tarikDataKaryawan();
        return;
      }
      unawaited(AdminNavBadgeService.instance.markEntitySeen('karyawan', kid));
      unawaited(AdminNavBadgeService.instance.refresh());
      _snack(
        'appr_sukses_tolak',
        OptikAdminTokens.danger,
        args: [(k['nama'] ?? '-').toString()],
      );
      await _tarikDataKaryawan();
    } catch (e, st) {
      debugPrint('reject karyawan: $e\n$st');
      if (!mounted) return;
      _snack('ktprev_reject_fail', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _actingId = null);
    }
  }

  Future<void> _aktifkanKembali(Map<String, dynamic> k) async {
    final kid = (k['id'] ?? '').toString();
    if (kid.isEmpty || _actingId != null) return;
    final tenant = AttendanceAdminScope.tenantIdOf(_scopeProfile);
    if (tenant == null || tenant.isEmpty) {
      _snack('appr_aktifkan_fail', OptikAdminTokens.danger);
      return;
    }
    setState(() => _actingId = kid);
    try {
      final updated = await supabase
          .from('karyawan')
          .update({'status_approval': 'Aktif'})
          .eq('id', kid)
          .eq('tenant_id', tenant)
          .select('id')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (updated.isEmpty) {
        _snack('appr_aktifkan_fail', OptikAdminTokens.danger);
        return;
      }
      _snack(
        'appr_sukses_aktifkan',
        OptikAdminTokens.success,
        args: [(k['nama'] ?? '-').toString()],
      );
      await _tarikDataKaryawan();
    } catch (e, st) {
      debugPrint('reaktivasi karyawan: $e\n$st');
      if (!mounted) return;
      _snack('appr_aktifkan_fail', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _actingId = null);
    }
  }

  /// Satu pintu: buka halaman detail → pilih data valid → baru Tolak/Setujui.
  Future<void> _bukaReviewVerifikasi(Map karyawan) async {
    if (_openingReview) return;
    _openingReview = true;
    final kid = karyawan['id']?.toString() ?? '';
    try {
      final tenant = AttendanceAdminScope.tenantIdOf(_scopeProfile);
      if (tenant == null || tenant.isEmpty || kid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('appr_review_fail'.tr()),
          backgroundColor: OptikAdminTokens.danger,
        ));
        return;
      }

      final fresh = await supabase
          .from('karyawan')
          .select()
          .eq('id', kid)
          .eq('tenant_id', tenant)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (fresh == null ||
          !_isPendingStatus(fresh['status_approval']?.toString())) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ktprev_sudah_diputus'.tr()),
          backgroundColor: OptikAdminTokens.warning,
        ));
        await _tarikDataKaryawan();
        return;
      }
      final data = _asStaff(fresh);
      unawaited(AdminNavBadgeService.instance.markEntitySeen('karyawan', kid));

      final result = await Navigator.push<KtpReviewResult>(
        context,
        MaterialPageRoute(
          builder: (_) => KtpApprovalReviewPage(karyawan: data),
        ),
      );
      if (!mounted) return;
      if (result == KtpReviewResult.stale) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ktprev_sudah_diputus'.tr()),
          backgroundColor: OptikAdminTokens.warning,
        ));
        await _tarikDataKaryawan();
        return;
      }
      if (result == null || result == KtpReviewResult.cancelled) {
        await _tarikDataKaryawan();
        return;
      }
      final nama = (data['nama'] ?? data['nama_ocr'] ?? '-').toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          result == KtpReviewResult.approved
              ? "appr_sukses_setuju".tr(args: [nama])
              : "appr_sukses_tolak".tr(args: [nama]),
        ),
        backgroundColor:
            result == KtpReviewResult.approved ? OptikAdminTokens.success : OptikAdminTokens.danger,
      ));
      await _tarikDataKaryawan();
    } catch (e, st) {
      debugPrint('Review verifikasi error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('appr_review_fail'.tr()),
        backgroundColor: OptikAdminTokens.danger,
      ));
    } finally {
      _openingReview = false;
    }
  }

  void _pindahHalaman(int bucket, int page) {
    if (page < 0 || bucket < 0 || bucket >= _tabCount || _busy) return;
    setState(() => _page[bucket] = page);
    _tarikDataKaryawan(bucket: bucket);
  }

  Widget _pager(int bucket) {
    final page = _page[bucket];
    final more = _more[bucket];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: page > 0 && !_busy
                ? () => _pindahHalaman(bucket, page - 1)
                : null,
            child: Text('appr_pager_prev'.tr()),
          ),
          Text(
            '${'appr_pager_page'.tr()} ${page + 1}',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextButton(
            onPressed: more && !_busy
                ? () => _pindahHalaman(bucket, page + 1)
                : null,
            child: Text('appr_pager_next'.tr()),
          ),
        ],
      ),
    );
  }

  String _emptyMessage(int bucket) {
    switch (bucket) {
      case 1:
        return 'appr_aktif_kosong'.tr();
      case 2:
        return 'appr_empty_cuti'.tr();
      case 3:
        return 'appr_empty_nonaktif'.tr();
      default:
        return 'appr_verifikasi_kosong'.tr();
    }
  }

  IconData _emptyIcon(int bucket) {
    switch (bucket) {
      case 1:
        return Icons.verified_rounded;
      case 2:
        return Icons.event_busy_rounded;
      case 3:
        return Icons.person_off_rounded;
      default:
        return Icons.how_to_reg_rounded;
    }
  }

  Widget _staffListPane(int bucket) {
    final items = _lists[bucket];
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _tarikDataKaryawan,
            color: OptikAdminTokens.navy,
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      PremiumEmptyState(
                        title: 'appr_empty_title'.tr(),
                        message: _emptyMessage(bucket),
                        icon: _emptyIcon(bucket),
                        action: OutlinedButton.icon(
                          onPressed: _busy ? null : _tarikDataKaryawan,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            'appr_tooltip_refresh'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildCardKaryawanAktif(items[index]),
                  ),
          ),
        ),
        if (items.isNotEmpty || _page[bucket] > 0) _pager(bucket),
      ],
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'appr_search_hint'.tr(),
          prefixIcon: Icon(Icons.search_rounded, color: OptikAdminTokens.slate),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  String _subtitle() {
    final scope = _isPusat ? 'appr_semua_cabang'.tr() : _scopeTokoLabel;
    if (_totalStaff <= 0) return scope;
    return 'appr_scope_count'.tr();
  }

  PreferredSizeWidget _segmentedTabs(int verifBadge) {
    final items = <(IconData, String)>[
      (Icons.how_to_reg_rounded, 'appr_tab_menunggu'.tr()),
      (Icons.verified_rounded, 'appr_status_aktif'.tr()),
      (Icons.event_busy_rounded, 'appr_tab_cuti'.tr()),
      (Icons.person_off_rounded, 'appr_tab_ditolak'.tr()),
    ];
    return PreferredSize(
      preferredSize: const Size.fromHeight(66),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: OptikAdminTokens.snow.withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OptikAdminTokens.ice.withOpacity(0.55)),
            boxShadow: OptikAdminTokens.cardShadow,
          ),
          child: TabBar(
            controller: _tabs,
            isScrollable: false,
            padding: const EdgeInsets.all(4),
            labelPadding: EdgeInsets.zero,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  OptikAdminTokens.navy,
                  OptikAdminTokens.navy.withOpacity(0.88),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: OptikAdminTokens.navy.withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            labelColor: OptikAdminTokens.snow,
            unselectedLabelColor: OptikAdminTokens.slate,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            tabs: [
              for (var i = 0; i < items.length; i++)
                Tab(
                  height: 48,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(items[i].$1, size: 16),
                          const SizedBox(width: 5),
                          Text(items[i].$2),
                          if (i == 0 && verifBadge > 0) ...[
                            const SizedBox(width: 6),
                            AdminNavBadge(count: verifBadge, compact: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminNavBadgeService.instance,
      builder: (context, _) {
        final verifBadge =
            AdminNavBadgeService.instance.displayCount('karyawan');
        return PremiumScaffold(
          appBar: PremiumAppBar(
            title: 'appr_title'.tr(),
            subtitle: _subtitle(),
            actions: [
              IconButton(
                tooltip: 'appr_btn_tambah'.tr(),
                icon: Icon(Icons.person_add_alt_1_rounded,
                    color: OptikAdminTokens.navy),
                onPressed: _bukaTambah,
              ),
              if (AttendanceAdminScope.canOpenStoreMonitor(_scopeProfile))
                IconButton(
                  tooltip: 'dash_menu_monitor_absensi'.tr(),
                  icon: Icon(Icons.fact_check_rounded,
                      color: OptikAdminTokens.navy),
                  onPressed: _bukaRiwayat,
                ),
              if (AttendanceAdminScope.canOpenStoreMonitor(_scopeProfile))
                IconButton(
                  tooltip: 'appr_tinjauan_mencurigakan'.tr(),
                  icon: const Icon(Icons.warning_amber_rounded,
                      color: OptikAdminTokens.warning),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TinjauanMencurigakanPage(profile: _scopeProfile),
                      ),
                    );
                  },
                ),
              IconButton(
                tooltip: 'appr_tooltip_refresh'.tr(),
                icon: Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
                onPressed: _isLoading || _busy ? null : _tarikDataKaryawan,
              ),
            ],
            bottom: _segmentedTabs(verifBadge),
          ),
          body: Column(
            children: [
              _searchField(),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: OptikAdminTokens.navy,
                        ),
                      )
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          for (var i = 0; i < _tabCount; i++) _staffListPane(i),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanyardQr extends StatefulWidget {
  const _LanyardQr({required this.karyawanId});

  final String karyawanId;

  @override
  State<_LanyardQr> createState() => _LanyardQrState();
}

class _LanyardQrState extends State<_LanyardQr> {
  String? _kode;
  bool _gagal = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final id = widget.karyawanId.trim();
    if (id.isEmpty) {
      if (mounted) setState(() => _gagal = true);
      return;
    }
    try {
      final raw = await Supabase.instance.client.rpc(
        'barcode_lanyard',
        params: {'p_karyawan': id},
      );
      final kode = (raw ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _kode = kode.startsWith('OBRKARY|v2|') ? kode : null;
        _gagal = !kode.startsWith('OBRKARY|v2|');
      });
    } catch (_) {
      if (mounted) setState(() => _gagal = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kode = _kode;
    if (kode != null) {
      return SizedBox(
        height: 100,
        width: 100,
        child: BarcodeWidget(
          barcode: Barcode.qrCode(),
          data: kode,
          color: OptikAdminTokens.snow,
          drawText: false,
        ),
      );
    }
    if (_gagal) {
      return SizedBox(
        height: 100,
        width: 100,
        child: Center(
          child: Text(
            'QR badge belum siap',
            textAlign: TextAlign.center,
            style: TextStyle(color: OptikAdminTokens.snow, fontSize: 10),
          ),
        ),
      );
    }
    return const SizedBox(
      height: 100,
      width: 100,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
