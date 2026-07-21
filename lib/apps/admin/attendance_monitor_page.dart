import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jadwal_kerja_page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

/// Monitor absensi untuk Admin (bukan clock-in).
class AttendanceMonitorPage extends StatefulWidget {
  const AttendanceMonitorPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<AttendanceMonitorPage> createState() => _AttendanceMonitorPageState();
}

class _AttendanceMonitorPageState extends State<AttendanceMonitorPage> {
  bool _loading = true;
  DateTime _date = DateTime.now();
  String? _tokoFilter;
  List<String> _tokoOptions = [];
  List<Map<String, dynamic>> _shifts = [];
  String? _error;

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
    _tokoFilter = _isPusat ? null : widget.profile['toko_id']?.toString();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (_isPusat) {
        final rows =
            await Supabase.instance.client.from('toko_id').select('id').order('id');
        _tokoOptions = [
          for (final r in rows) r['id']?.toString() ?? '',
        ].where((e) => e.isNotEmpty).toList();
      }
      await _load();
    } catch (e) {
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
      final day = DateFormat('yyyy-MM-dd').format(_date);
      final start = '${day}T00:00:00';
      final end = '${day}T23:59:59';

      final toko = _tokoFilter?.isNotEmpty == true
          ? _tokoFilter
          : (_isPusat
              ? null
              : widget.profile['toko_id']?.toString() ?? 'KOSONG');

      final filter = Supabase.instance.client
          .from('attendance_shifts')
          .select(
              'id, karyawan_id, toko_id, status, masuk_at, pulang_at, karyawan:karyawan_id(nama, jabatan)')
          .gte('masuk_at', start)
          .lte('masuk_at', end);

      final rows = await (toko == null
              ? filter
              : filter.eq('toko_id', toko))
          .order('masuk_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _shifts = List<Map<String, dynamic>>.from(rows);
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _load();
    }
  }

  String _fmtDistance(dynamic v) {
    if (v is num) return v.toStringAsFixed(0);
    return v?.toString() ?? '-';
  }

  Future<void> _showLogs(Map<String, dynamic> shift) async {
    final logs = await Supabase.instance.client
        .from('attendance_logs')
        .select()
        .eq('shift_id', shift['id'])
        .order('created_at');

    if (!mounted) return;
    final df = DateFormat('HH:mm:ss');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: OptikAdminTokens.card,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Log: ${shift['karyawan']?['nama'] ?? shift['karyawan_id']}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...List<Map<String, dynamic>>.from(logs).map((log) {
              final at =
                  DateTime.tryParse(log['created_at']?.toString() ?? '');
              return Card(
                color: OptikAdminTokens.bgMid,
                child: ListTile(
                  title: Text(
                    '${log['tipe']} • skor ${log['match_score'] ?? '-'}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${at != null ? df.format(at.toLocal()) : '-'}'
                    ' • GPS ${_fmtDistance(log['distance_meters'])} m'
                    ' • liveness ${log['liveness_ok'] == true ? 'OK' : '-'}'
                    '${log['liveness_provider'] != null ? ' (${log['liveness_provider']}' : ''}'
                    '${log['liveness_confidence'] != null ? ' ${log['liveness_confidence']}%' : ''}'
                    '${log['liveness_provider'] != null ? ')' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: log['photo_url'] != null
                      ? IconButton(
                          icon: const Icon(Icons.image, color: Colors.blueAccent),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                child: InteractiveViewer(
                                  child: Image.network(
                                      log['photo_url'].toString()),
                                ),
                              ),
                            );
                          },
                        )
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy', 'id_ID');
    final timeFmt = DateFormat('HH:mm');

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Monitor Absensi',
        actions: [
          IconButton(
            tooltip: 'Atur jadwal kerja',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => JadwalKerjaPage(profile: widget.profile),
              ),
            ),
            icon: const Icon(Icons.edit_calendar_rounded),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 480;
                final dateBtn = OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(df.format(_date),
                      overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: Size(stacked ? double.infinity : 0, 44),
                  ),
                );
                final tokoDrop = !_isPusat
                    ? null
                    : DropdownButtonFormField<String?>(
                        isExpanded: true,
                        value: _tokoFilter,
                        dropdownColor: OptikAdminTokens.card,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: OptikAdminTokens.card,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        hint: const Text('Semua toko',
                            style: TextStyle(color: Colors.white54)),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Semua toko',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white)),
                          ),
                          ..._tokoOptions.map(
                            (t) => DropdownMenuItem<String?>(
                              value: t,
                              child: Text(t,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _tokoFilter = v);
                          _load();
                        },
                      );

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      dateBtn,
                      if (tokoDrop != null) ...[
                        const SizedBox(height: 8),
                        tokoDrop,
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: dateBtn),
                    if (tokoDrop != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: tokoDrop),
                    ],
                  ],
                );
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
                : _shifts.isEmpty
                    ? const Center(
                        child: Text('Tidak ada absensi pada tanggal ini.',
                            style: TextStyle(color: Colors.white54)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _shifts.length,
                          itemBuilder: (context, i) {
                            final s = _shifts[i];
                            final nama =
                                s['karyawan']?['nama']?.toString() ?? '-';
                            final jabatan =
                                s['karyawan']?['jabatan']?.toString() ?? '';
                            final masuk = DateTime.tryParse(
                                s['masuk_at']?.toString() ?? '');
                            final pulang = DateTime.tryParse(
                                s['pulang_at']?.toString() ?? '');
                            final open = s['status'] == 'OPEN';
                            return Card(
                              color: OptikAdminTokens.card,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                onTap: () => _showLogs(s),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                title: Text(
                                  nama,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  '$jabatan • ${s['toko_id']}\n'
                                  'Masuk ${masuk != null ? timeFmt.format(masuk.toLocal()) : '-'}'
                                  ' • Pulang ${pulang != null ? timeFmt.format(pulang.toLocal()) : '-'}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, height: 1.35),
                                ),
                                isThreeLine: true,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: open
                                        ? Colors.teal.withOpacity(0.25)
                                        : Colors.grey.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    open ? 'OPEN' : 'CLOSED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: open
                                          ? Colors.tealAccent
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
