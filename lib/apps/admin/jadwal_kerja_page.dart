import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/karyawan/jadwal_pengajuan_service.dart';
import '../../shared/karyawan/shift_auto_assign.dart';
import '../../shared/responsive.dart';
import 'jadwal_pengajuan_approval_page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';
import '../../shared/widgets/premium_date_range_picker.dart';

/// Admin Pusat: list cabang → atur jadwal_kerja karyawan cabang tersebut.
/// Admin toko: langsung ke cabangnya sendiri.
class JadwalKerjaPage extends StatefulWidget {
  const JadwalKerjaPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<JadwalKerjaPage> createState() => _JadwalKerjaPageState();
}

class _JadwalKerjaPageState extends State<JadwalKerjaPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cabang = [];
  String? _selectedTokoId;
  final _searchCtrl = TextEditingController();
  String _query = '';
  int _pendingCount = 0;

  bool get _isPusat =>
      AttendanceAdminScope.canViewAllStores(widget.profile);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isPusat) {
        final rows = await Supabase.instance.client
            .from('toko_id')
            .select('id, toko_id')
            .order('id');
        _cabang = List<Map<String, dynamic>>.from(rows);
      } else {
        final tokoId = widget.profile['toko_id']?.toString() ?? '';
        final row = await Supabase.instance.client
            .from('toko_id')
            .select('id, toko_id')
            .eq('id', tokoId)
            .maybeSingle();
        _cabang = row != null
            ? [row]
            : [
                {'id': tokoId, 'toko_id': tokoId},
              ];
        _selectedTokoId = tokoId;
      }
      try {
        _pendingCount = await JadwalPengajuanService().countPending(
          tokoId: widget.profile['toko_id']?.toString(),
          allToko: _isPusat,
        );
      } catch (_) {
        _pendingCount = 0;
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _namaCabang(Map<String, dynamic> t) {
    final nama = t['toko_id']?.toString() ?? '';
    final id = t['id']?.toString() ?? '';
    if (nama.isEmpty || nama == id) return id;
    return '$nama ($id)';
  }

  List<Map<String, dynamic>> get _filteredCabang {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _cabang;
    return _cabang.where((t) {
      final id = (t['id'] ?? '').toString().toLowerCase();
      final nama = (t['toko_id'] ?? '').toString().toLowerCase();
      return id.contains(q) || nama.contains(q);
    }).toList();
  }

  void _openApproval({String? tokoId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JadwalPengajuanApprovalPage(
          profile: widget.profile,
          initialTokoId: tokoId,
        ),
      ),
    ).then((_) => _bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: _selectedTokoId == null
            ? 'Jadwal Kerja — Pilih Cabang'
            : 'Jadwal Kerja',
        actions: [
          if (_selectedTokoId != null && _isPusat)
            IconButton(
              tooltip: 'Ganti cabang',
              onPressed: () => setState(() => _selectedTokoId = null),
              icon: const Icon(Icons.store_mall_directory_rounded,
                  color: OptikAdminTokens.navy),
            ),
          IconButton(
            tooltip: 'Approval ijin / tukar',
            onPressed: () => _openApproval(
              tokoId: _selectedTokoId ??
                  (_isPusat ? null : widget.profile['toko_id']?.toString()),
            ),
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text(
                '$_pendingCount',
                style: const TextStyle(color: OptikAdminTokens.snow, fontSize: 10),
              ),
              backgroundColor: OptikAdminTokens.danger,
              child: const Icon(Icons.fact_check_outlined,
                  color: OptikAdminTokens.navy),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _bootstrap,
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
                          style: const TextStyle(color: OptikAdminTokens.danger),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        PremiumPrimaryButton(
                          label: 'Coba lagi',
                          onPressed: _bootstrap,
                          expand: false,
                        ),
                      ],
                    ),
                  ),
                )
              : _selectedTokoId == null
                  ? _buildCabangList()
                  : _JadwalCabangEditor(
                      tokoId: _selectedTokoId!,
                      tokoLabel: _namaCabang(
                        _cabang.firstWhere(
                          (c) => c['id'] == _selectedTokoId,
                          orElse: () => {
                            'id': _selectedTokoId,
                            'toko_id': _selectedTokoId,
                          },
                        ),
                      ),
                      onOpenApproval: () =>
                          _openApproval(tokoId: _selectedTokoId),
                    ),
    );
  }

  Widget _buildCabangList() {
    if (_cabang.isEmpty) {
      return const Center(
        child: Text('Belum ada data cabang di toko_id.',
            style: TextStyle(color: OptikAdminTokens.slate)),
      );
    }
    final list = _filteredCabang;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: OptikAdminTokens.navy),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Cari nama / kode toko…',
              hintStyle: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.75),
              ),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: OptikAdminTokens.slate),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear, color: OptikAdminTokens.slate),
                    ),
              filled: true,
              fillColor: OptikAdminTokens.bgMid,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
                borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
                borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
                borderSide: const BorderSide(
                  color: OptikAdminTokens.navy,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: PremiumListTile(
            title: 'Approval ijin / tukar jadwal',
            subtitle: _pendingCount == 0
                ? 'Tidak ada pengajuan menunggu'
                : '$_pendingCount menunggu approval',
            icon: Icons.fact_check_outlined,
            iconColor: OptikAdminTokens.navy,
            leading: Badge(
              isLabelVisible: _pendingCount > 0,
              backgroundColor: OptikAdminTokens.danger,
              label: Text(
                '$_pendingCount',
                style: const TextStyle(
                  color: OptikAdminTokens.snow,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const PremiumIconBadge(
                icon: Icons.fact_check_outlined,
                color: OptikAdminTokens.navy,
                size: 44,
              ),
            ),
            margin: EdgeInsets.zero,
            onTap: () => _openApproval(),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('Tidak ada cabang cocok.',
                      style: TextStyle(color: OptikAdminTokens.slate)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final t = list[i];
                    final id = t['id']?.toString() ?? '-';
                    return PremiumListTile(
                      title: _namaCabang(t),
                      subtitle: 'Kode: $id',
                      icon: Icons.storefront_rounded,
                      iconColor: OptikAdminTokens.slate,
                      onTap: () => setState(() => _selectedTokoId = id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _JadwalCabangEditor extends StatefulWidget {
  const _JadwalCabangEditor({
    required this.tokoId,
    required this.tokoLabel,
    this.onOpenApproval,
  });

  final String tokoId;
  final String tokoLabel;
  final VoidCallback? onOpenApproval;

  @override
  State<_JadwalCabangEditor> createState() => _JadwalCabangEditorState();
}

enum _JadwalMode { minggu, bulan }

class _JadwalCabangEditorState extends State<_JadwalCabangEditor> {
  final _assignService = ShiftAutoAssignService();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  _JadwalMode _mode = _JadwalMode.minggu;
  /// Senin minggu aktif, atau tanggal 1 bulan aktif.
  DateTime _anchor = _mondayOf(DateTime.now());
  List<Map<String, dynamic>> _karyawan = [];
  /// key: karyawanId -> dateKey -> row
  Map<String, Map<String, Map<String, dynamic>>> _jadwal = {};
  String? _expandedId;
  TokoShiftSettings? _shiftSettings;

  static final _dateKey = DateFormat('yyyy-MM-dd');
  static final _dayFmt = DateFormat('EEE d MMM', 'id_ID');
  static const _hari = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static DateTime _mondayOf(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - 1));
  }

  DateTime get _rangeStart {
    if (_mode == _JadwalMode.minggu) return _mondayOf(_anchor);
    return DateTime(_anchor.year, _anchor.month, 1);
  }

  DateTime get _rangeEnd {
    if (_mode == _JadwalMode.minggu) {
      return _rangeStart.add(const Duration(days: 6));
    }
    return DateTime(_anchor.year, _anchor.month + 1, 0);
  }

  List<DateTime> get _daysInRange {
    final start = _rangeStart;
    final end = _rangeEnd;
    final out = <DateTime>[];
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

  String get _rangeLabel {
    if (_mode == _JadwalMode.minggu) {
      return '${DateFormat('d MMM', 'id_ID').format(_rangeStart)} – '
          '${DateFormat('d MMM yyyy', 'id_ID').format(_rangeEnd)}';
    }
    return DateFormat('MMMM yyyy', 'id_ID').format(_rangeStart);
  }

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
      final karyawanRows = await Supabase.instance.client
          .from('karyawan')
          .select('id, nama, jabatan, toko_id, status_approval')
          .eq('toko_id', widget.tokoId)
          .order('nama');

      final list = List<Map<String, dynamic>>.from(karyawanRows)
          .where((k) {
            final st = (k['status_approval'] ?? '').toString().toLowerCase();
            return st.isEmpty || st == 'approved' || st == 'aktif' || st == 'active';
          })
          .toList();

      // Jika filter approval kosongkan semua, tampilkan semua karyawan cabang
      final karyawan =
          list.isEmpty ? List<Map<String, dynamic>>.from(karyawanRows) : list;

      final start = _dateKey.format(_rangeStart);
      final end = _dateKey.format(_rangeEnd);

      final jadwalRows = await Supabase.instance.client
          .from('jadwal_kerja')
          .select()
          .eq('toko_id', widget.tokoId)
          .gte('tanggal', start)
          .lte('tanggal', end);

      final map = <String, Map<String, Map<String, dynamic>>>{};
      for (final r in jadwalRows) {
        final kid = r['karyawan_id']?.toString() ?? '';
        final tgl = r['tanggal']?.toString() ?? '';
        map.putIfAbsent(kid, () => {});
        map[kid]![tgl] = Map<String, dynamic>.from(r);
      }

      final settings = await _assignService.fetchSettings(widget.tokoId);

      if (!mounted) return;
      setState(() {
        _karyawan = karyawan;
        _jadwal = map;
        _shiftSettings = settings;
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

  void _setMode(_JadwalMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      if (mode == _JadwalMode.minggu) {
        _anchor = _mondayOf(DateTime.now());
      } else {
        final now = DateTime.now();
        _anchor = DateTime(now.year, now.month, 1);
      }
    });
    _load();
  }

  void _shiftPeriod(int delta) {
    setState(() {
      if (_mode == _JadwalMode.minggu) {
        _anchor = _rangeStart.add(Duration(days: 7 * delta));
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
      }
    });
    _load();
  }

  Future<void> _openPeriodPicker() async {
    final result = await showPremiumDateRangePicker(
      context: context,
      initialStart: _rangeStart,
      initialEnd: _rangeEnd,
      initialPresetId: 'custom',
    );
    if (result == null) return;
    final start = DateTime(result.start.year, result.start.month, result.start.day);
    final end = DateTime(result.end.year, result.end.month, result.end.day);
    final span = end.difference(start).inDays;
    setState(() {
      if (span <= 10) {
        _mode = _JadwalMode.minggu;
        _anchor = _mondayOf(start);
      } else {
        _mode = _JadwalMode.bulan;
        _anchor = DateTime(start.year, start.month, 1);
      }
    });
    await _load();
  }

  List<Map<String, dynamic>> _defaultRowsForKaryawan(String kid) {
    final s = _shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId);
    final rows = <Map<String, dynamic>>[];
    // Toko buka tiap hari (termasuk Minggu). Tutup khusus Lebaran → atur manual.
    for (final day in _daysInRange) {
      rows.add({
        'karyawan_id': kid,
        'toko_id': widget.tokoId,
        'tanggal': _dateKey.format(day),
        'jam_masuk': '${s.shift1Masuk}:00',
        'jam_pulang': '${s.shift1Pulang}:00',
        'is_libur': false,
      });
    }
    return rows;
  }

  String _fmtTime(dynamic v) {
    if (v == null) return '--:--';
    final s = v.toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  Future<void> _editDay({
    required Map<String, dynamic> karyawan,
    required DateTime day,
  }) async {
    final kid = karyawan['id']?.toString() ?? '';
    final key = _dateKey.format(day);
    final existing = _jadwal[kid]?[key];

    var isLibur = existing?['is_libur'] == true;
    final masukCtrl = TextEditingController(
      text: isLibur ? '' : _fmtTime(existing?['jam_masuk']).replaceAll('--:--', '08:30'),
    );
    final pulangCtrl = TextEditingController(
      text: isLibur
          ? ''
          : _fmtTime(existing?['jam_pulang']).replaceAll('--:--', '17:00'),
    );
    final catatanCtrl = TextEditingController(
      text: existing?['catatan']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => AlertDialog(
            backgroundColor: OptikAdminTokens.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
              side: const BorderSide(color: OptikAdminTokens.lineStrong),
            ),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: OptikAdminTokens.ice.withOpacity(0.32),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: OptikAdminTokens.ice.withOpacity(0.95),
                    ),
                  ),
                  child: Text(
                    '${day.day}',
                    style: const TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        karyawan['nama']?.toString() ?? '-',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_hari[day.weekday - 1]} · ${_dayFmt.format(day)}',
                        style: TextStyle(
                          color: OptikAdminTokens.slate.withOpacity(0.95),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: R.constrainedDialog(
              context: context,
              preferWidth: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setModal(() => isLibur = !isLibur),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isLibur
                              ? OptikAdminTokens.danger.withOpacity(0.08)
                              : OptikAdminTokens.bgMid,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isLibur
                                ? OptikAdminTokens.danger.withOpacity(0.45)
                                : OptikAdminTokens.lineStrong,
                          ),
                        ),
                        child: Row(
                          children: [
                            PremiumIconBadge(
                              icon: isLibur
                                  ? Icons.beach_access_rounded
                                  : Icons.work_outline_rounded,
                              color: isLibur
                                  ? OptikAdminTokens.danger
                                  : OptikAdminTokens.ice,
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isLibur ? 'Hari libur' : 'Hari kerja',
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    isLibur
                                        ? 'Tidak ada jam masuk/pulang'
                                        : 'Isi jam operasional di bawah',
                                    style: TextStyle(
                                      color: OptikAdminTokens.slate
                                          .withOpacity(0.95),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: isLibur,
                              activeColor: OptikAdminTokens.danger,
                              activeTrackColor:
                                  OptikAdminTokens.danger.withOpacity(0.35),
                              onChanged: (v) => setModal(() => isLibur = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isLibur) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _editDayField(
                            controller: masukCtrl,
                            label: 'Jam masuk',
                            hint: '08:30',
                            icon: Icons.login_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _editDayField(
                            controller: pulangCtrl,
                            label: 'Jam pulang',
                            hint: '17:00',
                            icon: Icons.logout_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _editDayField(
                    controller: catatanCtrl,
                    label: 'Catatan',
                    hint: 'Opsional',
                    icon: Icons.notes_rounded,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.slate,
                ),
                child: const Text('Batal'),
              ),
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await Supabase.instance.client
                          .from('jadwal_kerja')
                          .delete()
                          .eq('karyawan_id', kid)
                          .eq('tanggal', key);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: OptikAdminTokens.danger,
                          content: Text(
                            'Gagal hapus: $e',
                            style: const TextStyle(
                              color: OptikAdminTokens.snow,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: OptikAdminTokens.danger,
                  ),
                  child: const Text('Hapus'),
                ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: OptikAdminTokens.navy,
                  foregroundColor: OptikAdminTokens.snow,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(OptikAdminTokens.radiusSm),
                  ),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!isLibur) {
                    final m = masukCtrl.text.trim();
                    final p = pulangCtrl.text.trim();
                    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(m) ||
                        !RegExp(r'^\d{2}:\d{2}$').hasMatch(p)) {
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: OptikAdminTokens.warning,
                          content: Text(
                            'Format jam harus HH:mm',
                            style: const TextStyle(
                              color: OptikAdminTokens.snow,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                  }
                  try {
                    await Supabase.instance.client.from('jadwal_kerja').upsert({
                      'karyawan_id': kid,
                      'toko_id': widget.tokoId,
                      'tanggal': key,
                      'jam_masuk':
                          isLibur ? null : '${masukCtrl.text.trim()}:00',
                      'jam_pulang':
                          isLibur ? null : '${pulangCtrl.text.trim()}:00',
                      'is_libur': isLibur,
                      'catatan': catatanCtrl.text.trim().isEmpty
                          ? null
                          : catatanCtrl.text.trim(),
                    }, onConflict: 'karyawan_id,tanggal');
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: OptikAdminTokens.danger,
                        content: Text(
                          'Gagal simpan: $e',
                          style: const TextStyle(
                            color: OptikAdminTokens.snow,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }
                },
                child: const Text(
                  'Simpan',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );

    masukCtrl.dispose();
    pulangCtrl.dispose();
    catatanCtrl.dispose();

    if (saved == true) await _load();
  }

  Widget _editDayField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: OptikAdminTokens.navy,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: OptikAdminTokens.slate,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: OptikAdminTokens.slate.withOpacity(0.65),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: OptikAdminTokens.slate, size: 18),
        filled: true,
        fillColor: OptikAdminTokens.bgMid,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
          borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
          borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
          borderSide: const BorderSide(
            color: OptikAdminTokens.navy,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Future<void> _editShiftSettings() async {
    final current = _shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId);
    final s1Label = TextEditingController(text: current.shift1Label);
    final s1Masuk = TextEditingController(text: current.shift1Masuk);
    final s1Pulang = TextEditingController(text: current.shift1Pulang);
    final s1Kuota = TextEditingController(text: '${current.shift1Kuota}');
    final s2Label = TextEditingController(text: current.shift2Label);
    final s2Masuk = TextEditingController(text: current.shift2Masuk);
    final s2Pulang = TextEditingController(text: current.shift2Pulang);
    final s2Kuota = TextEditingController(text: '${current.shift2Kuota}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
          backgroundColor: OptikAdminTokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
            side: const BorderSide(color: OptikAdminTokens.lineStrong),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: const Text(
            'Setting shift cabang',
            style: TextStyle(
              color: OptikAdminTokens.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: R.constrainedDialog(
            context: context,
            preferWidth: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kuota = berapa orang per shift per hari. '
                    'Total ideal ≈ Shift1 + Shift2.\n'
                    'Karyawan cabang sekarang: ${_karyawan.length}.\n\n'
                    'Toko buka tiap hari (termasuk Minggu). '
                    'Tutup khusus Lebaran atur manual di kalender. '
                    'Auto-random hanya menggilir libur karyawan '
                    '(1 hari/minggu), bukan tutup toko.',
                    style: const TextStyle(
                        color: OptikAdminTokens.slate, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  const Text('Shift 1',
                      style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _settingField(s1Label, 'Nama (mis. Shift Pagi)'),
                  Row(children: [
                    Expanded(child: _settingField(s1Masuk, 'Masuk HH:mm')),
                    const SizedBox(width: 10),
                    Expanded(child: _settingField(s1Pulang, 'Pulang HH:mm')),
                  ]),
                  _settingField(s1Kuota, 'Kuota orang', number: true),
                  const SizedBox(height: 8),
                  const Text('Shift 2',
                      style: TextStyle(
                          color: OptikAdminTokens.navy,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _settingField(s2Label, 'Nama (mis. Shift Sore)'),
                  Row(children: [
                    Expanded(child: _settingField(s2Masuk, 'Masuk HH:mm')),
                    const SizedBox(width: 10),
                    Expanded(child: _settingField(s2Pulang, 'Pulang HH:mm')),
                  ]),
                  _settingField(s2Kuota, 'Kuota orang', number: true),
                ],
              ),
            ),
          ),
          actionsPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: OptikAdminTokens.slate),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: OptikAdminTokens.navy,
                foregroundColor: OptikAdminTokens.snow,
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
    );
    if (ok != true) return;
    if (!mounted) return;

    bool validTime(String t) => RegExp(r'^\d{2}:\d{2}$').hasMatch(t.trim());
    if (!validTime(s1Masuk.text) ||
        !validTime(s1Pulang.text) ||
        !validTime(s2Masuk.text) ||
        !validTime(s2Pulang.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.warning,
          content: Text(
            'Format jam harus HH:mm',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      return;
    }

    final next = TokoShiftSettings(
      tokoId: widget.tokoId,
      shift1Label: s1Label.text.trim().isEmpty ? 'Shift Pagi' : s1Label.text.trim(),
      shift1Masuk: s1Masuk.text.trim(),
      shift1Pulang: s1Pulang.text.trim(),
      shift1Kuota: int.tryParse(s1Kuota.text.trim()) ?? 0,
      shift2Label: s2Label.text.trim().isEmpty ? 'Shift Sore' : s2Label.text.trim(),
      shift2Masuk: s2Masuk.text.trim(),
      shift2Pulang: s2Pulang.text.trim(),
      shift2Kuota: int.tryParse(s2Kuota.text.trim()) ?? 0,
      // Toko tidak tutup Minggu — kolom DB tetap false.
      mingguLibur: false,
    );

    try {
      await _assignService.saveSettings(next);
      setState(() => _shiftSettings = next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.success,
          content: Text(
            'Setting tersimpan. Kuota harian: ${next.totalKuotaHarian} '
            '(S1 ${next.shift1Kuota} + S2 ${next.shift2Kuota}).',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.danger,
          content: Text(
            'Gagal simpan setting: $e',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
  }

  Widget _settingField(TextEditingController c, String label, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: const TextStyle(color: OptikAdminTokens.navy, fontSize: 14, height: 1.3),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          filled: true,
          fillColor: OptikAdminTokens.bgMid,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: OptikAdminTokens.navy, width: 1.4),
          ),
        ),
      ),
    );
  }

  Future<void> _autoRandomPeriod() async {
    final settings = _shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId);
    final periode =
        _mode == _JadwalMode.minggu ? 'minggu ini' : 'bulan $_rangeLabel';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: const Text(
          'Auto random shift?',
          style: TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              'Cabang ${widget.tokoLabel}\n'
              'Periode: $periode (${_daysInRange.length} hari)\n'
              'Karyawan: ${_karyawan.length}\n\n'
              '${settings.shift1Label}: ${settings.shift1Kuota} orang '
              '(${settings.shift1Masuk}–${settings.shift1Pulang})\n'
              '${settings.shift2Label}: ${settings.shift2Kuota} orang '
              '(${settings.shift2Masuk}–${settings.shift2Pulang})\n'
              'Total kuota/hari: ${settings.totalKuotaHarian}\n'
              'Toko buka tiap hari. Libur karyawan digilir 1 hari/minggu '
              'per layer (bukan tutup toko).\n'
              'Tutup Lebaran atur manual.\n\n'
              'Front & Back office digilir terpisah — tidak boleh semua '
              'back office libur di hari yang sama (jika ≥2 orang).\n'
              'Jadwal periode ini akan ditimpa.',
              style: const TextStyle(
                color: OptikAdminTokens.slate,
                height: 1.4,
              ),
            ),
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
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            child: const Text('Jalankan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final result = await _assignService.autoRandom(
        tokoId: widget.tokoId,
        karyawan: _karyawan,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
        settings: settings,
      );
      if (!mounted) return;
      final warn = result.warnings.isEmpty
          ? ''
          : '\n${result.warnings.join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.success,
          duration: const Duration(seconds: 5),
          content: Text(
            'Selesai: ${result.daysProcessed} hari, '
            '${result.rowsWritten} baris jadwal.$warn',
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
            'Gagal auto-random: $e\n'
            'Pastikan migration toko_shift_settings sudah dijalankan.',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _isiDefaultPeriode(Map<String, dynamic> karyawan) async {
    final kid = karyawan['id']?.toString() ?? '';
    final periode =
        _mode == _JadwalMode.minggu ? 'minggu ini' : 'bulan $_rangeLabel';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: Text(
          'Isi default $periode?',
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Isi ${_daysInRange.length} hari kerja untuk ${karyawan['nama']} '
          '(${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Masuk}'
          '–${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Pulang}). '
          'Toko buka tiap hari; libur Lebaran atur manual.',
          style: const TextStyle(color: OptikAdminTokens.slate, height: 1.4),
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
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('jadwal_kerja').upsert(
            _defaultRowsForKaryawan(kid),
            onConflict: 'karyawan_id,tanggal',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.success,
          content: Text(
            'Jadwal default tersimpan.',
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
            'Gagal: $e',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _isiDefaultSemua() async {
    if (_karyawan.isEmpty) return;
    final periode =
        _mode == _JadwalMode.minggu ? 'minggu ini' : 'bulan $_rangeLabel';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OptikAdminTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
          side: const BorderSide(color: OptikAdminTokens.lineStrong),
        ),
        title: Text(
          'Isi default semua ($periode)?',
          style: const TextStyle(
            color: OptikAdminTokens.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Cabang ${widget.tokoLabel}: isi default '
          '${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Masuk}'
          '–${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Pulang} '
          'setiap hari untuk ${_karyawan.length} karyawan × '
          '${_daysInRange.length} hari. Toko buka tiap hari; '
          'libur Lebaran atur manual.',
          style: const TextStyle(color: OptikAdminTokens.slate, height: 1.4),
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
              backgroundColor: OptikAdminTokens.navy,
              foregroundColor: OptikAdminTokens.snow,
            ),
            child: const Text('Ya, isi semua'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final rows = <Map<String, dynamic>>[];
      for (final k in _karyawan) {
        rows.addAll(_defaultRowsForKaryawan(k['id']?.toString() ?? ''));
      }
      await Supabase.instance.client
          .from('jadwal_kerja')
          .upsert(rows, onConflict: 'karyawan_id,tanggal');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: OptikAdminTokens.success,
          content: Text(
            'Jadwal default semua karyawan tersimpan.',
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
            'Gagal: $e',
            style: const TextStyle(
              color: OptikAdminTokens.snow,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: OptikAdminTokens.ice));
    }
    if (_error != null) {
      return Center(
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
      );
    }

    final s = _shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId);

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 420;
                  return PremiumPanel(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    borderRadius: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const PremiumIconBadge(
                              icon: Icons.storefront_rounded,
                              color: OptikAdminTokens.ice,
                              size: 46,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.tokoLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: OptikAdminTokens.navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16.5,
                                      height: 1.2,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_karyawan.length} karyawan · $_rangeLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: OptikAdminTokens.slate
                                          .withOpacity(0.95),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        PremiumStatGrid(
                          spacing: OptikAdminTokens.spaceSm,
                          items: [
                            PremiumStatItem(
                              label: s.shift1Label,
                              value: '${s.shift1Kuota} org',
                              color: OptikAdminTokens.navy,
                            ),
                            PremiumStatItem(
                              label: s.shift2Label,
                              value: '${s.shift2Kuota} org',
                              color: OptikAdminTokens.slate,
                            ),
                            PremiumStatItem(
                              label: 'Kuota/hari',
                              value: '${s.totalKuotaHarian}',
                              color: OptikAdminTokens.navy,
                            ),
                            PremiumStatItem(
                              label: 'Karyawan',
                              value: '${_karyawan.length}',
                              color: OptikAdminTokens.slate,
                            ),
                          ],
                        ),
                        if (s.totalKuotaHarian > _karyawan.length) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  OptikAdminTokens.warning.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: OptikAdminTokens.warning
                                    .withOpacity(0.65),
                                width: 1.1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const PremiumIconBadge(
                                  icon: Icons.warning_amber_rounded,
                                  color: OptikAdminTokens.warning,
                                  size: 36,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Kuota melebihi karyawan',
                                        style: TextStyle(
                                          color: OptikAdminTokens.navy,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Kuota harian ${s.totalKuotaHarian} > '
                                        '${_karyawan.length} orang. '
                                        'Buka Kuota & jam untuk menyesuaikan.',
                                        style: TextStyle(
                                          color: OptikAdminTokens.slate
                                              .withOpacity(0.95),
                                          fontSize: 11.5,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        const PremiumSectionHeader(
                          label: 'Periode',
                          padding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        AdminPickerField(
                          label: 'Tampilan jadwal',
                          valueText: _mode == _JadwalMode.minggu
                              ? (narrow ? 'Minggu' : 'Per minggu')
                              : (narrow ? 'Bulan' : 'Per bulan'),
                          icon: _mode == _JadwalMode.minggu
                              ? Icons.view_week_rounded
                              : Icons.calendar_view_month_rounded,
                          onTap: () async {
                            final sel = await showAdminPicker<_JadwalMode>(
                              context: context,
                              title: 'Tampilan jadwal',
                              searchable: false,
                              selected: _mode,
                              headerIcon: Icons.calendar_month_outlined,
                              options: [
                                AdminPickerOption(
                                  value: _JadwalMode.minggu,
                                  label: narrow ? 'Minggu' : 'Per minggu',
                                  icon: Icons.view_week_rounded,
                                ),
                                AdminPickerOption(
                                  value: _JadwalMode.bulan,
                                  label: narrow ? 'Bulan' : 'Per bulan',
                                  icon: Icons.calendar_view_month_rounded,
                                ),
                              ],
                            );
                            if (sel == null || sel.isClear) return;
                            _setMode(sel.value!);
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _periodNavBtn(
                              icon: Icons.chevron_left_rounded,
                              onTap: () => _shiftPeriod(-1),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PremiumDateRangeTrigger(
                                label: _rangeLabel,
                                onTap: _openPeriodPicker,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _periodNavBtn(
                              icon: Icons.chevron_right_rounded,
                              onTap: () => _shiftPeriod(1),
                            ),
                          ],
                        ),
                        const PremiumSectionHeader(
                          label: 'Aksi cepat',
                          padding: EdgeInsets.only(top: 14, bottom: 10),
                        ),
                        PremiumChipWrap(
                          children: [
                            PremiumActionChip(
                              icon: Icons.tune_rounded,
                              label: 'Kuota & jam',
                              onPressed: _busy ? null : _editShiftSettings,
                            ),
                            PremiumActionChip(
                              icon: Icons.casino_rounded,
                              label: 'Auto random',
                              onPressed: _busy ? null : _autoRandomPeriod,
                            ),
                            PremiumActionChip(
                              icon: Icons.playlist_add_check_rounded,
                              label: 'Default sama',
                              onPressed: _busy ? null : _isiDefaultSemua,
                            ),
                            PremiumActionChip(
                              icon: Icons.fact_check_outlined,
                              label: 'Approval ijin',
                              onPressed: widget.onOpenApproval,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: PremiumSectionHeader(
                label: 'Karyawan',
                padding: EdgeInsets.zero,
                trailing: Text(
                  '${_karyawan.length}',
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _karyawan.isEmpty
                  ? const PremiumEmptyState(
                      message: 'Belum ada karyawan di cabang ini.',
                      icon: Icons.groups_rounded,
                    )
                  : RefreshIndicator(
                      color: OptikAdminTokens.ice,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        itemCount: _karyawan.length,
                        itemBuilder: (context, i) {
                          final k = _karyawan[i];
                          final kid = k['id']?.toString() ?? '';
                          final expanded = _expandedId == kid;
                          final days = _daysInRange;
                          final layer = layerLabel(
                              officeLayerOf(k['jabatan']?.toString()));
                          final counts = _dayCounts(kid);
                          return PremiumPanel(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.zero,
                            borderRadius: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      _expandedId = expanded ? null : kid;
                                    }),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 12, 8, 12),
                                      child: Row(
                                        children: [
                                          _avatarChip(
                                            k['nama']?.toString() ?? '-',
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  k['nama']?.toString() ??
                                                      '-',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color:
                                                        OptikAdminTokens.navy,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    fontSize: 14,
                                                    letterSpacing: -0.15,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${k['jabatan'] ?? '-'} · $layer',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: OptikAdminTokens
                                                        .slate
                                                        .withOpacity(0.95),
                                                    fontSize: 11.5,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 6,
                                                  children: [
                                                    _miniStat(
                                                      '${counts.jadwal}',
                                                      'jadwal',
                                                      OptikAdminTokens.navy,
                                                    ),
                                                    _miniStat(
                                                      '${counts.libur}',
                                                      'libur',
                                                      OptikAdminTokens.danger,
                                                    ),
                                                    _miniStat(
                                                      '${counts.kosong}',
                                                      'kosong',
                                                      counts.kosong > 0
                                                          ? OptikAdminTokens
                                                              .warning
                                                          : OptikAdminTokens
                                                              .slate,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Isi default periode',
                                            onPressed: () =>
                                                _isiDefaultPeriode(k),
                                            icon: const Icon(
                                              Icons.auto_awesome_rounded,
                                              color: OptikAdminTokens.navy,
                                              size: 20,
                                            ),
                                          ),
                                          AnimatedRotation(
                                            turns: expanded ? 0.5 : 0,
                                            duration: const Duration(
                                                milliseconds: 180),
                                            child: const Icon(
                                              Icons.expand_more_rounded,
                                              color: OptikAdminTokens.slate,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                AnimatedCrossFade(
                                  firstChild: const SizedBox.shrink(),
                                  secondChild: Column(
                                    children: [
                                      const Divider(
                                        height: 1,
                                        color: OptikAdminTokens.line,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 6, 8, 10),
                                        child: Column(
                                          children: [
                                            for (var di = 0;
                                                di < days.length;
                                                di++) ...[
                                              _dayRow(k, days[di]),
                                              if (di < days.length - 1)
                                                Divider(
                                                  height: 1,
                                                  indent: 48,
                                                  color: OptikAdminTokens.line
                                                      .withOpacity(0.65),
                                                ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  crossFadeState: expanded
                                      ? CrossFadeState.showSecond
                                      : CrossFadeState.showFirst,
                                  duration:
                                      const Duration(milliseconds: 180),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
        if (_busy)
          ModalBarrier(
            dismissible: false,
            color: OptikAdminTokens.bg.withOpacity(0.4),
          ),
        if (_busy)
          const Center(
              child: CircularProgressIndicator(color: OptikAdminTokens.ice)),
      ],
    );
  }

  Widget _periodNavBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: OptikAdminTokens.card,
      borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
            border: Border.all(color: OptikAdminTokens.lineStrong),
          ),
          child: Icon(icon, color: OptikAdminTokens.navy, size: 22),
        ),
      ),
    );
  }

  Widget _avatarChip(String nama) {
    final parts = nama
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
                .toUpperCase();
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            OptikAdminTokens.navy,
            OptikAdminTokens.navy.withOpacity(0.82),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: OptikAdminTokens.navy.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        initials,
        style: const TextStyle(
          color: OptikAdminTokens.snow,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _miniStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  ({int jadwal, int libur, int kosong}) _dayCounts(String kid) {
    var jadwal = 0;
    var libur = 0;
    var kosong = 0;
    for (final day in _daysInRange) {
      final row = _jadwal[kid]?[_dateKey.format(day)];
      if (row == null) {
        kosong++;
      } else if (row['is_libur'] == true) {
        libur++;
      } else {
        jadwal++;
      }
    }
    return (jadwal: jadwal, libur: libur, kosong: kosong);
  }

  Widget _dayRow(Map<String, dynamic> karyawan, DateTime day) {
    final kid = karyawan['id']?.toString() ?? '';
    final key = _dateKey.format(day);
    final row = _jadwal[kid]?[key];
    final libur = row?['is_libur'] == true;
    final catatan = row?['catatan']?.toString();
    final label = row == null
        ? 'Belum dijadwalkan'
        : libur
            ? (catatan != null && catatan.isNotEmpty
                ? 'Libur · $catatan'
                : 'Libur')
            : '${_fmtTime(row['jam_masuk'])}–${_fmtTime(row['jam_pulang'])}'
                '${catatan != null && catatan.isNotEmpty ? ' · $catatan' : ''}';

    // Wash semantik; teks jadwal aktif selalu navy (bukan ice).
    final wash = row == null
        ? OptikAdminTokens.warning
        : libur
            ? OptikAdminTokens.danger
            : OptikAdminTokens.ice;
    final fg = row == null
        ? OptikAdminTokens.warning
        : libur
            ? OptikAdminTokens.danger
            : OptikAdminTokens.navy;
    final isIceWash = wash == OptikAdminTokens.ice;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editDay(karyawan: karyawan, day: day),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OptikAdminTokens.navy.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: OptikAdminTokens.lineStrong),
                ),
                child: Text(
                  '${day.day}',
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hari[day.weekday - 1],
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _dayFmt.format(day),
                      style: TextStyle(
                        color: OptikAdminTokens.slate.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: wash.withOpacity(isIceWash ? 0.28 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: wash.withOpacity(isIceWash ? 0.95 : 0.45),
                    ),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: OptikAdminTokens.slate.withOpacity(0.75),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
