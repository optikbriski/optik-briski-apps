import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/theme.dart';

/// Inbox Admin: balas pengaduan karyawan (tutup loop).
class PengaduanInboxPage extends StatefulWidget {
  const PengaduanInboxPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<PengaduanInboxPage> createState() => _PengaduanInboxPageState();
}

class _PengaduanInboxPageState extends State<PengaduanInboxPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String? _busyId;

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
      final isPusat = AttendanceAdminScope.isPusatTokoId(toko) ||
          AttendanceAdminScope.isPusatOperator(widget.profile);
      final keys = AttendanceAdminScope.storeIdAliases(toko);
      var q = _db.from('pengaduan').select(
            'id, karyawan_id, toko_id, kategori, isi, foto_url, status, '
            'balasan, dibalas_at, dibalas_oleh, created_at, '
            'karyawan:karyawan_id(nama, nik)',
          );
      if (!isPusat && toko.isNotEmpty) {
        q = q.inFilter('toko_id', keys.isEmpty ? [toko] : keys);
      }
      final rows = await q.order('created_at', ascending: false).limit(80);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reply(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ctrl = TextEditingController(text: (row['balasan'] ?? '').toString());
    var status = ((row['status'] ?? 'OPEN').toString().toUpperCase() == 'DONE')
        ? 'DONE'
        : 'DONE';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('pengaduan_admin_balas_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              (row['isi'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'pengaduan_admin_balasan'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: status,
              decoration: InputDecoration(
                labelText: 'pengaduan_admin_status'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'IN_PROGRESS',
                  child: Text('pengaduan_status_progress'.tr()),
                ),
                DropdownMenuItem(
                  value: 'DONE',
                  child: Text('pengaduan_status_done'.tr()),
                ),
                DropdownMenuItem(
                  value: 'OPEN',
                  child: Text('pengaduan_status_open'.tr()),
                ),
              ],
              onChanged: (v) {
                if (v != null) status = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('pengaduan_admin_batal'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('pengaduan_admin_kirim'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final body = ctrl.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('pengaduan_admin_balasan_wajib'.tr())),
      );
      return;
    }

    setState(() => _busyId = id);
    try {
      final res = await _db.rpc('reply_pengaduan', params: {
        'p_id': id,
        'p_balasan': body,
        'p_status': status,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : {};
      if (map['ok'] != true) {
        throw map['error'] ?? 'Gagal membalas';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('pengaduan_admin_ok'.tr())),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.snow,
      appBar: AppBar(
        title: Text('pengaduan_admin_title'.tr()),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.orange)),
                  if (_rows.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        'pengaduan_admin_empty'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: OptikAdminTokens.textMuted),
                      ),
                    ),
                  ..._rows.map(_card),
                ],
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final busy = _busyId == id;
    final st = (row['status'] ?? 'OPEN').toString().toUpperCase();
    final kary = row['karyawan'];
    String nama = '-';
    if (kary is Map) {
      nama = (kary['nama'] ?? '-').toString();
    }
    final when = DateTime.tryParse((row['created_at'] ?? '').toString());
    final balasan = (row['balasan'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : () => _reply(row),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row['kategori'] ?? '-'} · $nama',
                        style: GoogleFonts.fraunces(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      st,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: st == 'DONE'
                            ? OptikAdminTokens.navy
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${row['toko_id'] ?? '-'}'
                  '${when == null ? '' : ' · ${DateFormat('d MMM · HH:mm').format(when.toLocal())}'}',
                  style: TextStyle(
                    color: OptikAdminTokens.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (row['isi'] ?? '').toString(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.35, fontSize: 13.5),
                ),
                if (balasan.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'pengaduan_admin_sudah_balas'.tr(namedArgs: {
                      'oleh': (row['dibalas_oleh'] ?? 'Admin').toString(),
                    }),
                    style: TextStyle(
                      color: OptikAdminTokens.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    balasan,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          balasan.isEmpty
                              ? 'pengaduan_admin_tap_balas'.tr()
                              : 'pengaduan_admin_tap_edit'.tr(),
                          style: TextStyle(
                            color: OptikAdminTokens.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
