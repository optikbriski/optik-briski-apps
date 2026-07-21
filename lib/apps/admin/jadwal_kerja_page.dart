import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  bool get _isPusat {
    final toko = (widget.profile['toko_id'] ?? '').toString();
    final role = (widget.profile['role'] ?? '').toString();
    return toko == 'PUSAT' ||
        toko == 'CABANG-PUSAT' ||
        role == 'owner' ||
        role == 'admin_pusat';
  }

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: OptikAdminTokens.textPrimary),
        title: Text(_selectedTokoId == null
            ? 'Jadwal Kerja — Pilih Cabang'
            : 'Jadwal Kerja'),
        actions: [
          if (_selectedTokoId != null && _isPusat)
            IconButton(
              tooltip: 'Ganti cabang',
              onPressed: () => setState(() => _selectedTokoId = null),
              icon: const Icon(Icons.store_mall_directory_rounded),
            ),
          IconButton(
            tooltip: 'Approval ijin / tukar',
            onPressed: () => _openApproval(
              tokoId: _selectedTokoId ??
                  (_isPusat ? null : widget.profile['toko_id']?.toString()),
            ),
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
          IconButton(
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center),
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
            style: TextStyle(color: Colors.white54)),
      );
    }
    final list = _filteredCabang;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Cari nama / kode toko…',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white54),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear, color: Colors.white38),
                    ),
              filled: true,
              fillColor: OptikAdminTokens.card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
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
            iconColor: Colors.tealAccent,
            leading: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: PremiumIconBadge(
                icon: Icons.fact_check_outlined,
                color: Colors.tealAccent,
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
                      style: TextStyle(color: Colors.white38)),
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
                      iconColor: Colors.purpleAccent,
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
      text: isLibur ? '' : _fmtTime(existing?['jam_masuk']).replaceAll('--:--', '09:00'),
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
            title: Text(
              '${karyawan['nama']}\n${_hari[day.weekday - 1]}, ${_dayFmt.format(day)}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Libur',
                      style: TextStyle(color: Colors.white70)),
                  value: isLibur,
                  onChanged: (v) => setModal(() => isLibur = v),
                ),
                if (!isLibur) ...[
                  TextField(
                    controller: masukCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Jam masuk (HH:mm)',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                  TextField(
                    controller: pulangCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Jam pulang (HH:mm)',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                ],
                TextField(
                  controller: catatanCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    labelStyle: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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
                        SnackBar(content: Text('Gagal hapus: $e')),
                      );
                    }
                  },
                  child: const Text('Hapus',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ElevatedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!isLibur) {
                    final m = masukCtrl.text.trim();
                    final p = pulangCtrl.text.trim();
                    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(m) ||
                        !RegExp(r'^\d{2}:\d{2}$').hasMatch(p)) {
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Format jam harus HH:mm')),
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
                      SnackBar(content: Text('Gagal simpan: $e')),
                    );
                  }
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        );
      },
    );

    if (saved == true) await _load();
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
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: const Text('Setting shift cabang',
              style: TextStyle(color: Colors.white, fontSize: 17)),
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
                        color: Colors.white54, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  const Text('Shift 1',
                      style: TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold)),
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
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold)),
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
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
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
        const SnackBar(content: Text('Format jam harus HH:mm')),
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
          content: Text(
            'Setting tersimpan. Kuota harian: ${next.totalKuotaHarian} '
            '(S1 ${next.shift1Kuota} + S2 ${next.shift2Kuota}).',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan setting: $e'), backgroundColor: Colors.red),
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
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          filled: true,
          fillColor: OptikAdminTokens.bgMid,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.tealAccent, width: 1.4),
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
        title: const Text('Auto random shift?'),
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
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Jalankan')),
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
          content: Text(
            'Selesai: ${result.daysProcessed} hari, '
            '${result.rowsWritten} baris jadwal.$warn',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal auto-random: $e\n'
            'Pastikan migration toko_shift_settings sudah dijalankan.',
          ),
          backgroundColor: Colors.red,
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
        title: Text('Isi default $periode?'),
        content: Text(
          'Isi ${_daysInRange.length} hari kerja untuk ${karyawan['nama']} '
          '(${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Masuk}'
          '–${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Pulang}). '
          'Toko buka tiap hari; libur Lebaran atur manual.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya')),
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
        const SnackBar(
          content: Text('Jadwal default tersimpan.'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
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
        title: Text('Isi default semua ($periode)?'),
        content: Text(
          'Cabang ${widget.tokoLabel}: isi default '
          '${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Masuk}'
          '–${(_shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId)).shift1Pulang} '
          'setiap hari untuk ${_karyawan.length} karyawan × '
          '${_daysInRange.length} hari. Toko buka tiap hari; '
          'libur Lebaran atur manual.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, isi semua')),
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
        const SnackBar(
          content: Text('Jadwal default semua karyawan tersimpan.'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }

    final s = _shiftSettings ?? TokoShiftSettings.defaults(widget.tokoId);

    return Stack(
      children: [
        Column(
          children: [
            Material(
              color: OptikAdminTokens.bgMid,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 420;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.tokoLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: OptikAdminTokens.spaceMd),
                        PremiumStatGrid(
                          spacing: OptikAdminTokens.spaceSm,
                          items: [
                            PremiumStatItem(
                              label: s.shift1Label,
                              value: '${s.shift1Kuota} org',
                              color: Colors.tealAccent,
                            ),
                            PremiumStatItem(
                              label: s.shift2Label,
                              value: '${s.shift2Kuota} org',
                              color: Colors.orangeAccent,
                            ),
                            PremiumStatItem(
                              label: 'Kuota/hari',
                              value: '${s.totalKuotaHarian}',
                              color: Colors.blueAccent,
                            ),
                            PremiumStatItem(
                              label: 'Karyawan',
                              value: '${_karyawan.length}',
                              color: Colors.white70,
                            ),
                          ],
                        ),
                        if (s.totalKuotaHarian > _karyawan.length)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: OptikAdminTokens.spaceSm),
                            child: Text(
                              'Kuota harian melebihi jumlah karyawan — cek setting shift.',
                              style: TextStyle(
                                color: Colors.orangeAccent.withOpacity(0.9),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        const SizedBox(height: OptikAdminTokens.spaceMd),
                        SegmentedButton<_JadwalMode>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: _JadwalMode.minggu,
                              label: Text(narrow ? 'Minggu' : 'Per minggu'),
                              icon: const Icon(Icons.view_week_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: _JadwalMode.bulan,
                              label: Text(narrow ? 'Bulan' : 'Per bulan'),
                              icon: const Icon(Icons.calendar_view_month_rounded,
                                  size: 16),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (sel) => _setMode(sel.first),
                          style: ButtonStyle(
                            foregroundColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white;
                              }
                              return Colors.white70;
                            }),
                            backgroundColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.indigoAccent.withOpacity(0.45);
                              }
                              return OptikAdminTokens.card;
                            }),
                          ),
                        ),
                        const SizedBox(height: OptikAdminTokens.spaceMd),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _shiftPeriod(-1),
                              icon: const Icon(Icons.chevron_left,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: PremiumDateRangeTrigger(
                                label: _rangeLabel,
                                onTap: _openPeriodPicker,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => _shiftPeriod(1),
                              icon: const Icon(Icons.chevron_right,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: OptikAdminTokens.spaceMd),
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
                              icon: Icons.playlist_add_check,
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
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: _karyawan.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada karyawan di cabang ini.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _karyawan.length,
                        itemBuilder: (context, i) {
                          final k = _karyawan[i];
                          final kid = k['id']?.toString() ?? '';
                          final expanded = _expandedId == kid;
                          final days = _daysInRange;
                          final layer = layerLabel(
                              officeLayerOf(k['jabatan']?.toString()));
                          return Card(
                            color: OptikAdminTokens.card,
                            margin: const EdgeInsets.only(bottom: 10),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 2),
                                  title: Text(
                                    k['nama']?.toString() ?? '-',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${k['jabatan'] ?? '-'} • $layer • ${days.length} hari',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Isi default periode',
                                        onPressed: () => _isiDefaultPeriode(k),
                                        icon: const Icon(Icons.auto_awesome,
                                            color: Colors.tealAccent, size: 20),
                                      ),
                                      Icon(
                                        expanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: Colors.white54,
                                      ),
                                    ],
                                  ),
                                  onTap: () => setState(() {
                                    _expandedId = expanded ? null : kid;
                                  }),
                                ),
                                if (expanded)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        4, 0, 4, 8),
                                    child: Column(
                                      children: [
                                        for (final day in days)
                                          _dayRow(k, day),
                                      ],
                                    ),
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
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
        if (_busy)
          const Center(child: CircularProgressIndicator()),
      ],
    );
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
                ? 'Libur • $catatan'
                : 'Libur')
            : '${_fmtTime(row['jam_masuk'])}–${_fmtTime(row['jam_pulang'])}'
                '${catatan != null && catatan.isNotEmpty ? ' • $catatan' : ''}';

    final color = row == null
        ? Colors.orangeAccent
        : libur
            ? Colors.redAccent
            : Colors.tealAccent;

    return InkWell(
      onTap: () => _editDay(karyawan: karyawan, day: day),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(
                '${_hari[day.weekday - 1]} • ${_dayFmt.format(day)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }
}
