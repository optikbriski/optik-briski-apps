import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/karyawan/karyawan_i18n_display.dart';
import '../../shared/theme.dart';

/// Daftar pengumuman cabang + ack dibaca (lokal per perangkat).
class PengumumanListPage extends StatefulWidget {
  const PengumumanListPage({
    super.key,
    required this.items,
    this.tokoId,
  });

  final List<Map<String, dynamic>> items;
  final String? tokoId;

  @override
  State<PengumumanListPage> createState() => _PengumumanListPageState();
}

class _PengumumanListPageState extends State<PengumumanListPage> {
  static const _prefsKey = 'pengumuman_ack_ids_v1';
  final _acked = <String>{};
  late List<Map<String, dynamic>> _items;
  bool _ready = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.items);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadAck(), _refreshRemote()]);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadAck() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).map((e) => '$e').toSet();
        _acked.addAll(list);
      } catch (_) {}
    }
  }

  Future<void> _refreshRemote() async {
    setState(() => _loading = true);
    try {
      final tokoId = (widget.tokoId ?? '').trim();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final tokoFilter = tokoId.isEmpty
          ? 'toko_id.is.null,toko_id.eq.PUSAT'
          : 'toko_id.is.null,toko_id.eq.PUSAT,toko_id.eq.$tokoId';
      final rows = await Supabase.instance.client
          .from('pengumuman_cabang')
          .select('id, judul, isi, created_at, toko_id')
          .eq('aktif', true)
          .or('tampil_sampai.is.null,tampil_sampai.gte.$nowIso')
          .or(tokoFilter)
          .order('created_at', ascending: false)
          .limit(60);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isNotEmpty) _items = list;
    } catch (_) {
      // Tetap pakai seed dari home.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ack(String id) async {
    if (id.isEmpty || _acked.contains(id)) return;
    setState(() => _acked.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_acked.toList()));
  }

  Future<void> _ackAll() async {
    for (final m in _items) {
      final id = (m['id'] ?? '').toString();
      if (id.isNotEmpty) _acked.add(id);
    }
    setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_acked.toList()));
  }

  int get _unreadCount => _items
      .where((m) => !_acked.contains((m['id'] ?? '').toString()))
      .length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.bg,
      appBar: AppBar(
        backgroundColor: OptikKaryawanTokens.snow,
        foregroundColor: OptikKaryawanTokens.ink,
        title: Text(
          'pengumuman_list_title'.tr(),
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_unreadCount > 0)
            TextButton(
              onPressed: _ackAll,
              child: Text('pengumuman_ack_semua'.tr()),
            ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text('pengumuman_list_empty'.tr()))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = _items[i];
                    final id = (m['id'] ?? '').toString();
                    final read = _acked.contains(id);
                    final when =
                        DateTime.tryParse((m['created_at'] ?? '').toString());
                    return Material(
                      color: OptikKaryawanTokens.snow,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _ack(id),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: read
                                  ? OptikKaryawanTokens.border
                                  : OptikKaryawanTokens.cyan.withOpacity(0.45),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      KaryawanI18nDisplay.pengumumanJudul(
                                        m['judul']?.toString(),
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    read
                                        ? 'pengumuman_status_dibaca'.tr()
                                        : 'pengumuman_status_baru'.tr(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: read
                                          ? OptikKaryawanTokens.muted
                                          : OptikKaryawanTokens.cyan,
                                    ),
                                  ),
                                ],
                              ),
                              if (when != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('d MMM yyyy · HH:mm')
                                      .format(when.toLocal()),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: OptikKaryawanTokens.muted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                KaryawanI18nDisplay.pengumumanIsi(
                                  m['isi']?.toString(),
                                ),
                                style: const TextStyle(height: 1.4, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
